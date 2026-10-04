#!/usr/bin/env python3
"""Metadata inspection and opt-in creation; never implements an auth protocol.

Python 3.10+ standard library only. CLI isolates network work in a process so
DNS and slow-drip responses cannot defeat the wall deadline. No server-supplied
strings, URLs, keys, bodies, headers or exception messages enter the report.
"""

from __future__ import annotations

import argparse
import base64
import binascii
import json
import multiprocessing
import os
from pathlib import Path
import re
import ssl
import stat
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


PROVIDER = "custom:synology"
CONFIG_FIELDS = frozenset(
    {"issuer", "discoveryUrl", "supabaseUrl", "clientId", "clientSecret", "adminKey"}
)
MAX_CONFIG_BYTES = 16384
MAX_RESPONSE_BYTES = 524288
MAX_REQUESTS = 5  # discovery, JWKS, list, create, verification list
REQUEST_TIMEOUT_SECONDS = 8
WALL_TIMEOUT_SECONDS = 45
SUPPORTED_TOKEN_AUTH = frozenset({"client_secret_basic", "client_secret_post"})
SIGNING_ALGORITHMS = {
    "RSA": frozenset({"RS256", "RS384", "RS512", "PS256", "PS384", "PS512"}),
    "EC": frozenset({"ES256", "ES384", "ES512"}),
    "OKP": frozenset({"EdDSA"}),
}


class ProbeError(Exception):
    """Only fixed local error codes and numeric HTTP statuses are reportable."""

    def __init__(self, code: str, http_status: int | None = None):
        super().__init__(code)
        self.code = code
        self.http_status = http_status


def _object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ProbeError("JSON_DUPLICATE_KEY")
        result[key] = value
    return result


def _reject_constant(value):
    raise ProbeError("JSON_NONFINITE_NUMBER")


def parse_json(raw: bytes):
    try:
        return json.loads(raw.decode("utf-8-sig"), object_pairs_hook=_object,
                          parse_constant=_reject_constant)
    except (UnicodeError, ValueError, RecursionError):
        raise ProbeError("INVALID_JSON") from None


def https_url(value):
    """Validate without normalization: issuer equality is byte-for-byte."""
    if not isinstance(value, str) or not value or len(value) > 4096:
        raise ProbeError("INVALID_HTTPS_URL")
    if any(ord(c) <= 32 or ord(c) == 127 for c in value) or "\\" in value:
        raise ProbeError("INVALID_HTTPS_URL")
    try:
        parsed = urllib.parse.urlsplit(value)
        port = parsed.port
        if (parsed.scheme != "https" or not parsed.hostname or
                parsed.username is not None or parsed.password is not None or
                parsed.query or parsed.fragment or "?" in value or "#" in value or
                (port is not None and not 1 <= port <= 65535)):
            raise ProbeError("INVALID_HTTPS_URL")
        parsed.hostname.encode("ascii")
    except (ValueError, UnicodeError):
        raise ProbeError("INVALID_HTTPS_URL") from None
    return parsed


def origin(url):
    parsed = https_url(url)
    return parsed.hostname.lower(), parsed.port or 443


def validate_config(data):
    if not isinstance(data, dict) or set(data) != CONFIG_FIELDS:
        raise ProbeError("CONFIG_FIELDS_MUST_MATCH")
    for field in CONFIG_FIELDS:
        value = data[field]
        if not isinstance(value, str) or len(value) > 4096:
            raise ProbeError("CONFIG_INVALID_VALUE")
        if any(ord(c) < 32 or ord(c) == 127 for c in value):
            raise ProbeError("CONFIG_INVALID_VALUE")
    for field in ("issuer", "discoveryUrl", "supabaseUrl"):
        parsed = https_url(data[field])
        host = parsed.hostname.lower()
        if (host.endswith((".invalid", ".example")) or
                host in {"example.com", "example.org", "example.net"} or
                "REPLACE_" in data[field]):
            raise ProbeError("CONFIG_PLACEHOLDER")
    # A project origin / gateway prefix, never an already suffixed Auth URL.
    if data["supabaseUrl"].rstrip("/").endswith("/auth/v1"):
        raise ProbeError("CONFIG_SUPABASE_URL_IS_AUTH_URL")
    return dict(data)


def load_config(path):
    try:
        with Path(path).open("rb") as source:
            file_stat = os.fstat(source.fileno())
            if not stat.S_ISREG(file_stat.st_mode):
                raise ProbeError("CONFIG_NOT_REGULAR_FILE")
            if os.name != "nt" and file_stat.st_mode & 0o077:
                raise ProbeError("CONFIG_PERMISSIONS_REQUIRE_0600")
            raw = source.read(MAX_CONFIG_BYTES + 1)
    except OSError:
        raise ProbeError("CONFIG_READ_FAILED") from None
    if len(raw) > MAX_CONFIG_BYTES:
        raise ProbeError("CONFIG_TOO_LARGE")
    return validate_config(parse_json(raw))


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # Never forward admin credentials or silently change discovery location.
        raise ProbeError("HTTP_REDIRECT_REFUSED", code)


class JsonTransport:
    def __init__(self, ca_file=None):
        context = ssl.create_default_context(cafile=ca_file)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        # Explicit direct connections; no environment proxy/netrc credentials.
        self.opener = urllib.request.build_opener(
            urllib.request.ProxyHandler({}),
            urllib.request.HTTPSHandler(context=context), NoRedirect())
        self.requests = 0

    def request(self, url, *, method="GET", headers=None, body=None):
        https_url(url)
        self.requests += 1
        if self.requests > MAX_REQUESTS:
            raise ProbeError("REQUEST_BUDGET_EXCEEDED")
        request_headers = {"Accept": "application/json", "Accept-Encoding": "identity"}
        request_headers.update(headers or {})
        raw_body = None
        if body is not None:
            raw_body = json.dumps(body, allow_nan=False).encode("utf-8")
            request_headers["Content-Type"] = "application/json"
        req = urllib.request.Request(url, data=raw_body, headers=request_headers, method=method)
        try:
            with self.opener.open(req, timeout=REQUEST_TIMEOUT_SECONDS) as response:
                if not 200 <= response.status < 300:
                    raise ProbeError("HTTP_STATUS", response.status)
                if response.headers.get("Content-Encoding", "identity").lower() != "identity":
                    raise ProbeError("HTTP_CONTENT_ENCODING_REFUSED")
                length = response.headers.get("Content-Length")
                if length is not None:
                    try:
                        size = int(length)
                    except ValueError:
                        raise ProbeError("HTTP_INVALID_LENGTH") from None
                    if not 0 <= size <= MAX_RESPONSE_BYTES:
                        raise ProbeError("HTTP_RESPONSE_TOO_LARGE")
                chunks = []
                count = 0
                deadline = time.monotonic() + REQUEST_TIMEOUT_SECONDS
                while True:
                    if time.monotonic() >= deadline:
                        raise ProbeError("REQUEST_DEADLINE")
                    chunk = response.read(min(65536, MAX_RESPONSE_BYTES + 1 - count))
                    count += len(chunk)
                    if count > MAX_RESPONSE_BYTES:
                        raise ProbeError("HTTP_RESPONSE_TOO_LARGE")
                    if not chunk:
                        break
                    chunks.append(chunk)
                return parse_json(b"".join(chunks))
        except urllib.error.HTTPError as exc:
            status = exc.code
            exc.close()  # Do not read or report error bodies, reason or headers.
            raise ProbeError("HTTP_STATUS", status) from None
        except (ssl.SSLError, urllib.error.URLError, OSError):
            raise ProbeError("TLS_OR_NETWORK_FAILURE") from None


def add_check(report, name, status, code=None):
    check = {"name": name, "status": status}
    if code:
        check["code"] = code
    report["checks"].append(check)


def string_list(document, key):
    if key not in document:
        return None
    value = document[key]
    if (not isinstance(value, list) or len(value) > 256 or
            any(not isinstance(v, str) or not v or len(v) > 256 for v in value) or
            len(set(value)) != len(value)):
        raise ProbeError("DISCOVERY_INVALID_LIST")
    return value


def advertised(values, item):
    return None if values is None else item in values


def validate_discovery(config, discovery, scopes, report):
    if not isinstance(discovery, dict):
        raise ProbeError("DISCOVERY_NOT_OBJECT")
    if discovery.get("issuer") != config["issuer"]:
        raise ProbeError("ISSUER_EXACT_MISMATCH")
    https_url(discovery["issuer"])
    add_check(report, "issuerExactMatch", "pass")
    default_url = config["issuer"].rstrip("/") + "/.well-known/openid-configuration"
    report["discovery"] = {
        "exactConfiguredUrlFetched": True,
        "usesExplicitOverride": config["discoveryUrl"] != default_url,
        "sameOriginAsIssuer": origin(config["discoveryUrl"]) == origin(config["issuer"]),
    }
    for field in ("authorization_endpoint", "token_endpoint", "jwks_uri"):
        https_url(discovery.get(field))
    if discovery.get("userinfo_endpoint"):
        https_url(discovery["userinfo_endpoint"])
    add_check(report, "endpointHttps", "pass")

    responses = string_list(discovery, "response_types_supported")
    grants = string_list(discovery, "grant_types_supported")
    supported_scopes = string_list(discovery, "scopes_supported")
    auth = string_list(discovery, "token_endpoint_auth_methods_supported")
    pkce = string_list(discovery, "code_challenge_methods_supported")
    signing = string_list(discovery, "id_token_signing_alg_values_supported")
    subjects = string_list(discovery, "subject_types_supported")
    auth_overlap = sorted(SUPPORTED_TOKEN_AUTH.intersection(auth or []))
    report["advertised"] = {
        "authorizationCodeResponse": advertised(responses, "code"),
        "authorizationCodeGrant": advertised(grants, "authorization_code"),
        "requestedScopes": {
            (f"[REDACTED_SCOPE_{index}]" if any(
                config[field] and config[field] in scope
                for field in ("clientId", "clientSecret", "adminKey")) else scope):
            advertised(supported_scopes, scope)
            for index, scope in enumerate(scopes)
        },
        "supportedConfidentialTokenAuth": auth_overlap,
        "tokenAuthMethodsPresent": auth is not None,
        "refreshTokenGrant": advertised(grants, "refresh_token"),
        "offlineAccessScope": advertised(supported_scopes, "offline_access"),
        "publicClientTokenAuthNone": advertised(auth, "none"),
        "pkceS256": advertised(pkce, "S256"),
        "supportedSigningAlgorithms": sorted(
            set(signing or []).intersection(set().union(*SIGNING_ALGORITHMS.values()))),
        "publicSubjectType": advertised(subjects, "public"),
        "pairwiseSubjectType": advertised(subjects, "pairwise"),
    }
    # Omitted optional metadata is unknown, never evidence of unsupported refresh
    # or an operational guarantee. Fail closed on apply prerequisites.
    for name, values, required in (
            ("codeResponse", responses, {"code"}),
            ("scopes", supported_scopes, set(scopes)),
            ("pkceS256", pkce, {"S256"})):
        status = "unknown" if values is None else (
            "pass" if required.issubset(values) else "fail")
        add_check(report, name, status)
    add_check(report, "authorizationCodeGrant", "unknown" if grants is None else (
        "pass" if "authorization_code" in grants else "fail"))
    add_check(report, "confidentialTokenAuth", "unknown" if auth is None else (
        "pass" if auth_overlap else "fail"))
    add_check(report, "signingAlgorithms", "unknown" if signing is None else (
        "pass" if report["advertised"]["supportedSigningAlgorithms"] else "fail"))
    add_check(report, "subjectTypes", "unknown" if subjects is None else (
        "pass" if {"public", "pairwise"}.intersection(subjects) else "fail"))
    report["assurance"] = {
        "metadataOnly": True,
        "loginTested": False,
        "credentialsValidated": False,
        "idTokenSignatureVerified": False,
        "nasRefreshOperationallyVerified": False,
        "publicClientRegistrationVerified": False,
        "supabaseSessionRevocationVerified": False,
        "bffDeployed": False,
    }
    return discovery["jwks_uri"], signing or []


def _b64(value):
    if (not isinstance(value, str) or not value or len(value) > 2048 or
            re.fullmatch(r"[A-Za-z0-9_-]+", value) is None):
        raise ProbeError("JWKS_INVALID_PUBLIC_KEY")
    try:
        return base64.b64decode(value + "=" * (-len(value) % 4), altchars=b"-_", validate=True)
    except (ValueError, binascii.Error):
        raise ProbeError("JWKS_INVALID_PUBLIC_KEY") from None


def validate_jwks(jwks, signing, report):
    if not isinstance(jwks, dict) or not isinstance(jwks.get("keys"), list):
        raise ProbeError("JWKS_INVALID_KEYS")
    keys = jwks["keys"]
    if not 1 <= len(keys) <= 64:
        raise ProbeError("JWKS_INVALID_KEYS")
    usable = 0
    for key in keys:
        if not isinstance(key, dict):
            raise ProbeError("JWKS_INVALID_KEYS")
        if set(key).intersection({"d", "p", "q", "dp", "dq", "qi", "oth", "k"}):
            raise ProbeError("JWKS_CONTAINS_PRIVATE_MATERIAL")
        if key.get("use", "sig") != "sig":
            continue
        if "key_ops" in key:
            ops = key["key_ops"]
            if not isinstance(ops, list) or any(not isinstance(op, str) for op in ops):
                raise ProbeError("JWKS_INVALID_PUBLIC_KEY")
            if "verify" not in ops:
                continue
        family = key.get("kty")
        if not isinstance(family, str):
            raise ProbeError("JWKS_INVALID_PUBLIC_KEY")
        algorithms = set(SIGNING_ALGORITHMS.get(family, []))
        if family == "RSA":
            modulus, exponent = _b64(key.get("n")), _b64(key.get("e"))
            if not 2048 <= int.from_bytes(modulus, "big").bit_length() <= 8192:
                raise ProbeError("JWKS_INVALID_RSA_SIZE")
            if len(exponent) > 8 or int.from_bytes(exponent, "big") < 3 or exponent[-1] % 2 != 1:
                raise ProbeError("JWKS_INVALID_PUBLIC_KEY")
        elif family == "EC":
            curves = {"P-256": (32, "ES256"), "P-384": (48, "ES384"), "P-521": (66, "ES512")}
            curve = key.get("crv")
            if not isinstance(curve, str) or curve not in curves:
                raise ProbeError("JWKS_INVALID_PUBLIC_KEY")
            size, algorithm = curves[curve]
            if len(_b64(key.get("x"))) != size or len(_b64(key.get("y"))) != size:
                raise ProbeError("JWKS_INVALID_PUBLIC_KEY")
            algorithms = {algorithm}
        elif family == "OKP":
            if key.get("crv") != "Ed25519" or len(_b64(key.get("x"))) != 32:
                raise ProbeError("JWKS_INVALID_PUBLIC_KEY")
        if "alg" in key:
            if not isinstance(key["alg"], str):
                raise ProbeError("JWKS_INVALID_PUBLIC_KEY")
            algorithms.intersection_update({key["alg"]})
        if algorithms.intersection(signing):
            usable += 1
    report["jwks"] = {"keyCount": len(keys), "usableSigningKeyCount": usable,
                      "structuralValidationOnly": True}
    add_check(report, "jwksSigningKey", "pass" if usable else "fail")


def provider_payload(config, scopes, email_optional):
    return {
        "provider_type": "oidc", "identifier": PROVIDER, "name": "Synology SSO",
        "client_id": config["clientId"], "client_secret": config["clientSecret"],
        "issuer": config["issuer"], "discovery_url": config["discoveryUrl"],
        "scopes": scopes, "pkce_enabled": True, "skip_nonce_check": False,
        "email_optional": email_optional, "enabled": True,
    }


def list_providers(transport, url, headers):
    response = transport.request(url, headers=headers)
    if not isinstance(response, dict) or not isinstance(response.get("providers"), list):
        raise ProbeError("ADMIN_UNEXPECTED_RESPONSE")
    result = response["providers"]
    identifiers = []
    for provider in result:
        if not isinstance(provider, dict) or not isinstance(provider.get("identifier"), str):
            raise ProbeError("ADMIN_UNEXPECTED_RESPONSE")
        identifiers.append(provider["identifier"])
    if len(set(identifiers)) != len(identifiers):
        raise ProbeError("ADMIN_UNEXPECTED_RESPONSE")
    return result


def base_report(apply=False):
    return {"schemaVersion": 1, "provider": PROVIDER, "status": "blocked",
            "checks": [], "apply": {"requested": apply, "state": "not_attempted"}}


def error_check(report, stage, error):
    add_check(report, stage, "fail", error.code)
    if error.http_status is not None:
        report["checks"][-1]["httpStatus"] = error.http_status


def run_probe(config, transport, *, apply=False, scopes=None, email_optional=False):
    report = base_report(apply)
    scopes = scopes if scopes is not None else ["openid", "profile", "email"]
    stage = "configuration"
    try:
        config = validate_config(config)
        if (not isinstance(scopes, list) or not 1 <= len(scopes) <= 32 or
                any(not isinstance(s, str) or re.fullmatch(r"[a-zA-Z0-9_:.-]{1,128}", s) is None
                    for s in scopes) or len(set(scopes)) != len(scopes) or "openid" not in scopes):
            raise ProbeError("INVALID_REQUESTED_SCOPES")
        report["configuration"] = {
            "clientId": "[REDACTED]" if config["clientId"] else "[ABSENT]",
            "clientSecret": "[REDACTED]" if config["clientSecret"] else "[ABSENT]",
            "adminKey": "[REDACTED]" if config["adminKey"] else "[ABSENT]",
            "emailOptional": email_optional,
        }
        stage = "discovery"
        discovery = transport.request(config["discoveryUrl"])
        jwks_url, signing = validate_discovery(config, discovery, scopes, report)
        stage = "jwks"
        jwks = transport.request(jwks_url)
        validate_jwks(jwks, signing, report)
        report["supabaseAdmin"] = {"checked": False, "providerExists": None}
        url = config["supabaseUrl"].rstrip("/") + "/auth/v1/admin/custom-providers"
        # Official gateway API supports both modern secret keys and legacy service
        # role JWTs via apikey. Do not use a publishable/anon key or invent a bearer.
        headers = {"apikey": config["adminKey"]}
        if config["adminKey"]:
            stage = "supabaseAdmin"
            providers = list_providers(transport, url, headers)
            exists = any(p["identifier"] == PROVIDER for p in providers)
            report["supabaseAdmin"] = {"checked": True, "providerExists": exists}
            add_check(report, "supabaseCustomProviderAdminApi", "pass")
        else:
            add_check(report, "supabaseCustomProviderAdminApi", "unknown")
            exists = None
        # grant_types is optional in Discovery; absent defaults are not rendered
        # as advertised support, and do not override an explicit negative value.
        required_checks = [c for c in report["checks"]
                           if c["name"] not in {"authorizationCodeGrant", "supabaseCustomProviderAdminApi"}]
        metadata_ok = (all(c["status"] == "pass" for c in required_checks) and
                       not any(c["status"] == "fail" for c in report["checks"]))
        report["status"] = "metadata_compatible" if metadata_ok else "blocked"
        if not apply:
            return report
        stage = "applyPreflight"
        if not all(config[k] and not config[k].startswith("REPLACE_")
                   for k in ("clientId", "clientSecret", "adminKey")):
            raise ProbeError("APPLY_REQUIRES_COMPLETE_PRIVATE_CONFIG")
        if exists:
            raise ProbeError("PROVIDER_EXISTS_NO_OVERWRITE")
        if not metadata_ok or exists is None:
            raise ProbeError("APPLY_PREREQUISITES_NOT_PASSED")
        payload = provider_payload(config, scopes, email_optional)
        stage = "providerCreate"
        report["apply"]["state"] = "outcome_unknown"
        # Exactly one POST. No mutation retries, PUT, PATCH, DELETE or rollback.
        created = transport.request(url, method="POST", headers=headers, body=payload)
        if not isinstance(created, dict) or created.get("identifier") != PROVIDER:
            raise ProbeError("CREATE_UNEXPECTED_RESPONSE")
        report["apply"]["state"] = "created_verification_pending"
        stage = "providerVerification"
        providers = list_providers(transport, url, headers)
        saved = next((p for p in providers if p["identifier"] == PROVIDER), None)
        fields = ("provider_type", "client_id", "issuer", "discovery_url", "scopes",
                  "pkce_enabled", "skip_nonce_check", "email_optional", "enabled")
        if saved is None or any(saved.get(k) != payload[k] for k in fields):
            raise ProbeError("CREATE_NOT_VERIFIED")
        report["apply"]["state"] = "created_verified_configuration_only"
        report["supabaseAdmin"]["providerExists"] = True
        report["status"] = "registered_login_unverified"
        return report
    except ProbeError as error:
        report["status"] = "blocked"
        error_check(report, stage, error)
        if stage == "providerCreate" and error.http_status is not None and 400 <= error.http_status < 500:
            report["apply"]["state"] = "rejected"
        return report


def _worker(config, apply, scopes, email_optional, ca_file, pipe):
    try:
        result = run_probe(config, JsonTransport(ca_file), apply=apply,
                           scopes=scopes, email_optional=email_optional)
    except (Exception, KeyboardInterrupt) as error:
        result = base_report(apply)
        error_check(result, "worker", ProbeError("CANCELLED" if isinstance(error, KeyboardInterrupt)
                                                else "UNEXPECTED_FAILURE_DETAILS_SUPPRESSED"))
        if apply:
            result["apply"]["state"] = "outcome_unknown"
    try:
        pipe.send(result)
    finally:
        pipe.close()


def bounded_probe(config, *, apply=False, scopes=None, email_optional=False,
                  ca_file=None, wall_timeout=WALL_TIMEOUT_SECONDS):
    context = multiprocessing.get_context("spawn")
    receiver, sender = context.Pipe(duplex=False)
    process = context.Process(target=_worker, args=(
        config, apply, scopes, email_optional, ca_file, sender), daemon=True)
    result = base_report(apply)
    try:
        process.start()
        sender.close()
        if receiver.poll(wall_timeout):
            result = receiver.recv()
        else:
            raise ProbeError("PROCESS_WALL_DEADLINE")
    except KeyboardInterrupt:
        error_check(result, "worker", ProbeError("CANCELLED"))
        if apply:
            result["apply"]["state"] = "outcome_unknown"
    except (OSError, EOFError, ProbeError) as error:
        error_check(result, "worker", error if isinstance(error, ProbeError)
                    else ProbeError("WORKER_FAILED_DETAILS_SUPPRESSED"))
        if apply:
            result["apply"]["state"] = "outcome_unknown"
    finally:
        if process.pid is not None:
            if process.is_alive():
                process.terminate()
            process.join(timeout=1)
            if process.is_alive():
                process.kill()
                process.join(timeout=1)
            process.close()
        receiver.close()
        sender.close()
    return result


class SafeParser(argparse.ArgumentParser):
    def error(self, message):
        # argparse normally echoes offending arguments, potentially credentials.
        raise ProbeError("CLI_INVALID_ARGUMENTS")


def main(argv=None):
    parser = SafeParser(description=__doc__)
    parser.add_argument("--config", required=True, help="Explicit private JSON path; never inline credentials")
    parser.add_argument("--apply", action="store_true", help="Create an absent custom:synology provider once")
    parser.add_argument("--scopes", nargs="+", default=["openid", "profile", "email"])
    parser.add_argument("--email-optional", action="store_true", help="Explicitly permit accounts without email")
    parser.add_argument("--ca-file", help="Optional trusted PEM CA bundle; verification remains mandatory")
    apply = False
    try:
        args = parser.parse_args(argv)
        apply = args.apply
        config = load_config(args.config)
        report = bounded_probe(config, apply=apply, scopes=args.scopes,
                               email_optional=args.email_optional, ca_file=args.ca_file)
    except ProbeError as error:
        report = base_report(apply)
        error_check(report, "configuration", error)
    except KeyboardInterrupt:
        report = base_report(apply)
        error_check(report, "cli", ProbeError("CANCELLED"))
    except Exception:
        report = base_report(apply)
        error_check(report, "cli", ProbeError("UNEXPECTED_FAILURE_DETAILS_SUPPRESSED"))
    print(json.dumps(report, indent=2, ensure_ascii=True, allow_nan=False))
    return 2 if report["status"] == "blocked" else 0


if __name__ == "__main__":
    multiprocessing.freeze_support()
    sys.exit(main())
