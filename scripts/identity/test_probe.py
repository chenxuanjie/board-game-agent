"""Offline contract/fault tests. No live NAS, Supabase, user tokens or passwords."""

import base64
import contextlib
import copy
import io
import json
import os
from pathlib import Path
import ssl
import tempfile
import unittest
from unittest.mock import patch
import urllib.error

import probe


def config():
    return {"issuer": "https://nas.test/webman/sso",
            "discoveryUrl": "https://nas.test/custom/well-known",
            "supabaseUrl": "https://auth.test",
            "clientId": "private-client-identifier", "clientSecret": "private-client-secret",
            "adminKey": "private-admin-key"}


def discovery():
    return {"issuer": config()["issuer"],
            "authorization_endpoint": "https://nas.test/webman/sso/authorize",
            "token_endpoint": "https://nas.test/webman/sso/token",
            "jwks_uri": "https://nas.test/webman/sso/jwks",
            "scopes_supported": ["openid", "profile", "email"],
            "response_types_supported": ["code"],
            "grant_types_supported": ["authorization_code"],
            "token_endpoint_auth_methods_supported": ["client_secret_basic"],
            "code_challenge_methods_supported": ["S256"],
            "id_token_signing_alg_values_supported": ["RS256"],
            "subject_types_supported": ["public"]}


def jwks():
    # Test fixture only, not an actual usable RSA key; no signatures are tested.
    modulus = base64.urlsafe_b64encode(b"\x80" + b"\x01" * 255).decode().rstrip("=")
    return {"keys": [{"kty": "RSA", "use": "sig", "kid": "fixture-only",
                      "alg": "RS256", "n": modulus, "e": "AQAB"}]}


class FakeTransport:
    def __init__(self, responses):
        self.responses = list(responses)
        self.calls = []

    def request(self, url, *, method="GET", headers=None, body=None):
        self.calls.append({"url": url, "method": method, "headers": headers, "body": body})
        if not self.responses:
            raise AssertionError("Unexpected network call")
        result = self.responses.pop(0)
        if isinstance(result, Exception):
            raise result
        return copy.deepcopy(result)


class Response:
    def __init__(self, body=b"{}", headers=None, status=200):
        self.body = io.BytesIO(body)
        self.headers = headers or {}
        self.status = status
        self.reads = 0

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.body.close()

    def read(self, length):
        self.reads += 1
        return self.body.read(length)


class FakeOpener:
    def __init__(self, response):
        self.response = response
        self.calls = []

    def open(self, request, timeout):
        self.calls.append((request, timeout))
        if isinstance(self.response, Exception):
            raise self.response
        return self.response


class ConfigTests(unittest.TestCase):
    def test_exact_fields_no_values_in_error(self):
        for data in [None, [], {**config(), "password": "do-not-print"},
                     {k: v for k, v in config().items() if k != "issuer"}]:
            with self.subTest(data_type=type(data)):
                with self.assertRaisesRegex(probe.ProbeError, "CONFIG_FIELDS_MUST_MATCH"):
                    probe.validate_config(data)

    def test_https_urls_reject_unsafe_forms(self):
        for url in ["http://nas.test", "https://user:secret@nas.test", "https://nas.test/#x",
                    "https://nas.test/?token=secret", "https://nas.test?", "https://nas.test#",
                    "https://nas.test:99999", "https://nas.test:0", "https://nas.test/\n",
                    "https://nas.test\\evil.test", "https://[bad", "https://", None]:
            with self.subTest(url=url):
                with self.assertRaises(probe.ProbeError):
                    probe.https_url(url)

    def test_no_trailing_slash_normalization(self):
        data = config()
        data["issuer"] += "/"
        self.assertEqual(probe.validate_config(data)["issuer"], data["issuer"])

    def test_examples_never_make_requests(self):
        path = Path(__file__).with_name("private-config.example.json")
        fake = FakeTransport([])
        report = probe.run_probe(json.loads(path.read_text()), fake, apply=True)
        self.assertEqual(fake.calls, [])
        self.assertEqual(report["checks"][0]["code"], "CONFIG_PLACEHOLDER")

    def test_supabase_url_not_auth_base(self):
        data = config()
        data["supabaseUrl"] += "/auth/v1/"
        with self.assertRaisesRegex(probe.ProbeError, "CONFIG_SUPABASE_URL_IS_AUTH_URL"):
            probe.validate_config(data)

    def test_config_file_limits_duplicate_keys_and_private_permissions(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "config.private.json"
            path.write_bytes(json.dumps(config()).encode())
            if os.name != "nt":
                path.chmod(0o600)
            self.assertEqual(probe.load_config(path), config())
            path.write_bytes(b" " * (probe.MAX_CONFIG_BYTES + 1))
            with self.assertRaisesRegex(probe.ProbeError, "CONFIG_TOO_LARGE"):
                probe.load_config(path)
            path.write_bytes(b'{"issuer":"secret","issuer":"second"}')
            with self.assertRaisesRegex(probe.ProbeError, "JSON_DUPLICATE_KEY"):
                probe.load_config(path)
            if os.name != "nt":
                path.chmod(0o644)
                with self.assertRaisesRegex(probe.ProbeError, "CONFIG_PERMISSIONS_REQUIRE_0600"):
                    probe.load_config(path)

    def test_json_validation_does_not_echo_input(self):
        for raw in [b'{"secret":', b'\xffsecret', b'{"v":NaN}', b'{"v":Infinity}']:
            with self.assertRaises(probe.ProbeError) as caught:
                probe.parse_json(raw)
            self.assertNotIn("secret", str(caught.exception))


class ProbeTests(unittest.TestCase):
    def run_metadata(self, document=None, keys=None, admin=None, data=None, **kwargs):
        data = config() if data is None else data
        responses = [discovery() if document is None else document,
                     jwks() if keys is None else keys]
        if data["adminKey"]:
            responses.append({"providers": []} if admin is None else admin)
        fake = FakeTransport(responses)
        return probe.run_probe(data, fake, **kwargs), fake

    def test_read_only_exact_url_no_nas_credentials_and_redaction(self):
        document = discovery()
        document.update({"vendorSecret": config()["clientSecret"]})
        keys = jwks()
        keys["keys"][0]["kid"] = config()["adminKey"]
        admin = {"providers": [{"identifier": "custom:other", "client_secret": "remote-secret",
                                "authorization_params": {"password": "remote-password"}}]}
        report, fake = self.run_metadata(document=document, keys=keys, admin=admin)
        self.assertEqual(report["status"], "metadata_compatible")
        self.assertEqual(report["apply"]["state"], "not_attempted")
        self.assertEqual([c["method"] for c in fake.calls], ["GET"] * 3)
        self.assertEqual(fake.calls[0]["url"], config()["discoveryUrl"])
        self.assertTrue(report["discovery"]["usesExplicitOverride"])
        self.assertIsNone(fake.calls[0]["headers"])
        self.assertIsNone(fake.calls[1]["headers"])
        self.assertEqual(fake.calls[2]["headers"], {"apikey": config()["adminKey"]})
        encoded = json.dumps(report)
        for secret in [*config().values(), "remote-secret", "remote-password", "vendorSecret"]:
            self.assertNotIn(secret, encoded)

    def test_issuer_mismatch_stops_before_jwks_and_admin(self):
        for issuer in [config()["issuer"] + "/", "https://evil.test", "HTTPS://nas.test/webman/sso"]:
            doc = discovery()
            doc["issuer"] = issuer
            report, fake = self.run_metadata(document=doc)
            self.assertEqual(len(fake.calls), 1)
            self.assertEqual(report["checks"][-1]["code"], "ISSUER_EXACT_MISMATCH")

    def test_explicit_discovery_override_other_origin_allowed_issuer_still_exact(self):
        data = config()
        data["discoveryUrl"] = "https://metadata.test/well-known"
        report, fake = self.run_metadata(data=data)
        self.assertEqual(report["status"], "metadata_compatible")
        self.assertFalse(report["discovery"]["sameOriginAsIssuer"])
        self.assertEqual(fake.calls[0]["url"], data["discoveryUrl"])

    def test_invalid_metadata_endpoints_never_fetched(self):
        for field in ["authorization_endpoint", "token_endpoint", "jwks_uri"]:
            for url in ["http://nas.test", "https://user:secret@nas.test", "https://nas.test/?key=secret"]:
                with self.subTest(field=field, url=url):
                    doc = discovery()
                    doc[field] = url
                    report, fake = self.run_metadata(document=doc)
                    self.assertEqual(report["status"], "blocked")
                    self.assertEqual(len(fake.calls), 1)

    def test_capability_failures_block_apply(self):
        changes = [
            {"response_types_supported": ["token", "code id_token"]},
            {"grant_types_supported": ["client_credentials"]},
            {"scopes_supported": ["openid"]},
            {"token_endpoint_auth_methods_supported": ["private_key_jwt", "none"]},
            {"code_challenge_methods_supported": ["plain"]},
            {"id_token_signing_alg_values_supported": ["none", "HS256"]},
            {"subject_types_supported": []},
        ]
        for change in changes:
            with self.subTest(change=change):
                document = {**discovery(), **change}
                report, fake = self.run_metadata(document=document, apply=True)
                self.assertEqual(report["status"], "blocked")
                self.assertFalse(any(c["method"] != "GET" for c in fake.calls))

    def test_absent_refresh_public_client_flags_are_unknown_not_false_or_guaranteed(self):
        doc = discovery()
        del doc["grant_types_supported"]
        del doc["token_endpoint_auth_methods_supported"]
        del doc["code_challenge_methods_supported"]
        report, _ = self.run_metadata(document=doc)
        flags = report["advertised"]
        self.assertIsNone(flags["refreshTokenGrant"])
        self.assertIsNone(flags["publicClientTokenAuthNone"])
        self.assertIsNone(flags["pkceS256"])
        self.assertFalse(report["assurance"]["nasRefreshOperationallyVerified"])
        self.assertFalse(report["assurance"]["publicClientRegistrationVerified"])
        self.assertEqual(report["status"], "blocked")

    def test_advertised_refresh_and_public_client_not_operational_guarantees(self):
        doc = discovery()
        doc["grant_types_supported"].append("refresh_token")
        doc["scopes_supported"].append("offline_access")
        doc["token_endpoint_auth_methods_supported"].append("none")
        report, _ = self.run_metadata(document=doc)
        self.assertTrue(report["advertised"]["refreshTokenGrant"])
        self.assertTrue(report["advertised"]["offlineAccessScope"])
        self.assertTrue(report["advertised"]["publicClientTokenAuthNone"])
        self.assertFalse(report["assurance"]["nasRefreshOperationallyVerified"])
        self.assertFalse(report["assurance"]["credentialsValidated"])

    def test_missing_optional_grant_metadata_not_falsely_unsupported(self):
        doc = discovery()
        del doc["grant_types_supported"]
        report, _ = self.run_metadata(document=doc)
        self.assertEqual(report["status"], "metadata_compatible")
        self.assertIsNone(report["advertised"]["authorizationCodeGrant"])

    def test_malformed_metadata_list(self):
        for bad in ["code", ["code", "code"], [123], None, [{}]]:
            doc = discovery()
            doc["response_types_supported"] = bad
            report, fake = self.run_metadata(document=doc)
            self.assertEqual(report["checks"][-1]["code"], "DISCOVERY_INVALID_LIST")
            self.assertEqual(len(fake.calls), 1)

    def test_incomplete_credentials_probe_only(self):
        data = config()
        for name in ["clientId", "clientSecret", "adminKey"]:
            data[name] = ""
        report, fake = self.run_metadata(data=data)
        self.assertEqual(report["status"], "metadata_compatible")
        self.assertEqual(len(fake.calls), 2)
        self.assertFalse(report["supabaseAdmin"]["checked"])
        report, fake = self.run_metadata(data=data, apply=True)
        self.assertEqual(report["checks"][-1]["code"], "APPLY_REQUIRES_COMPLETE_PRIVATE_CONFIG")
        self.assertTrue(all(c["method"] == "GET" for c in fake.calls))

    def test_explicit_email_optional_policy_and_scope_subset(self):
        doc = discovery()
        doc["scopes_supported"] = ["openid", "profile"]
        report, _ = self.run_metadata(document=doc, scopes=["openid", "profile"], email_optional=True)
        self.assertEqual(report["status"], "metadata_compatible")
        self.assertTrue(report["configuration"]["emailOptional"])

    def test_unexpected_admin_response_and_failures_never_create(self):
        for admin in [[], {"data": []}, {"providers": [{}]},
                      {"providers": [{"identifier": "x"}, {"identifier": "x"}]},
                      probe.ProbeError("HTTP_STATUS", 401), probe.ProbeError("HTTP_STATUS", 404)]:
            report, fake = self.run_metadata(admin=admin, apply=True)
            self.assertEqual(report["status"], "blocked")
            self.assertTrue(all(c["method"] == "GET" for c in fake.calls))

    def test_existing_provider_never_overwritten(self):
        report, fake = self.run_metadata(admin={"providers": [{"identifier": probe.PROVIDER,
                                                               "client_secret": "secret"}]}, apply=True)
        self.assertEqual(report["checks"][-1]["code"], "PROVIDER_EXISTS_NO_OVERWRITE")
        self.assertTrue(all(c["method"] == "GET" for c in fake.calls))

    def test_create_and_verify_official_payload_no_token_auth_field(self):
        expected = probe.provider_payload(config(), ["openid", "profile", "email"], False)
        saved = {k: v for k, v in expected.items() if k != "client_secret"}
        fake = FakeTransport([discovery(), jwks(), {"providers": []},
                              {**saved, "client_secret": "remote-echo-secret"}, {"providers": [saved]}])
        report = probe.run_probe(config(), fake, apply=True)
        self.assertEqual([c["method"] for c in fake.calls], ["GET", "GET", "GET", "POST", "GET"])
        self.assertEqual(fake.calls[3]["url"], "https://auth.test/auth/v1/admin/custom-providers")
        self.assertEqual(fake.calls[3]["body"], expected)
        self.assertNotIn("token_endpoint_auth_method", expected)
        self.assertEqual(report["status"], "registered_login_unverified")
        self.assertEqual(report["apply"]["state"], "created_verified_configuration_only")
        self.assertNotIn("remote-echo-secret", json.dumps(report))

    def test_create_errors_no_retry_or_automatic_rollback(self):
        for error, state in [(probe.ProbeError("TLS_OR_NETWORK_FAILURE"), "outcome_unknown"),
                             (probe.ProbeError("HTTP_STATUS", 500), "outcome_unknown"),
                             (probe.ProbeError("HTTP_STATUS", 400), "rejected")]:
            fake = FakeTransport([discovery(), jwks(), {"providers": []}, error])
            report = probe.run_probe(config(), fake, apply=True)
            self.assertEqual(len(fake.calls), 4)
            self.assertEqual(report["apply"]["state"], state)

    def test_verification_failure_keeps_created_state(self):
        fake = FakeTransport([discovery(), jwks(), {"providers": []},
                              {"identifier": probe.PROVIDER}, {"providers": []}])
        report = probe.run_probe(config(), fake, apply=True)
        self.assertEqual(report["apply"]["state"], "created_verification_pending")
        self.assertEqual(report["checks"][-1]["code"], "CREATE_NOT_VERIFIED")
        self.assertEqual(len(fake.calls), 5)

    def test_jwks_malformed_weak_private_and_mismatched_keys(self):
        bad_values = [[], {}, {"keys": []}, {"keys": [123]}, {"keys": [{"kty": []}]}]
        for change in [{"d": "DO_NOT_PRINT_PRIVATE_KEY"}, {"k": "secret"},
                       {"n": "AQAB"}, {"e": "Ag"}, {"n": "not base64!"},
                       {"alg": "HS256"}, {"use": "enc"}, {"key_ops": ["encrypt"]},
                       {"kty": "oct"}, {"key_ops": "verify"}]:
            value = jwks()
            value["keys"][0].update(change)
            bad_values.append(value)
        for value in bad_values:
            with self.subTest(value_type=type(value)):
                report, fake = self.run_metadata(keys=value, apply=True)
                self.assertEqual(report["status"], "blocked")
                self.assertTrue(all(c["method"] == "GET" for c in fake.calls))
                self.assertNotIn("DO_NOT_PRINT_PRIVATE_KEY", json.dumps(report))

    def test_scope_validation_before_network(self):
        for scopes in [[], ["email"], ["openid", "openid"], ["openid", "secret\n"], ["openid", {}]]:
            fake = FakeTransport([])
            report = probe.run_probe(config(), fake, scopes=scopes)
            self.assertEqual(fake.calls, [])
            self.assertEqual(report["checks"][0]["code"], "INVALID_REQUESTED_SCOPES")

    def test_secrets_cannot_leak_through_requested_scope_names(self):
        data = config()
        doc = discovery()
        doc["scopes_supported"].append(data["clientSecret"])
        report, _ = self.run_metadata(data=data, document=doc,
                                     scopes=["openid", data["clientSecret"]])
        self.assertEqual(report["status"], "metadata_compatible")
        self.assertNotIn(data["clientSecret"], json.dumps(report))
        self.assertTrue(report["advertised"]["requestedScopes"]["[REDACTED_SCOPE_1]"])


class TransportTests(unittest.TestCase):
    def make_transport(self, response):
        transport = probe.JsonTransport()
        transport.opener = FakeOpener(response)
        return transport

    def test_tls_verification_required_and_environment_proxy_disabled(self):
        with patch.object(probe.urllib.request, "build_opener") as build:
            probe.JsonTransport()
        proxy, https, redirect = build.call_args.args
        self.assertEqual(proxy.proxies, {})
        self.assertTrue(https._context.check_hostname)
        self.assertEqual(https._context.verify_mode, ssl.CERT_REQUIRED)
        self.assertEqual(https._context.minimum_version, ssl.TLSVersion.TLSv1_2)
        self.assertIsInstance(redirect, probe.NoRedirect)

    def test_redirect_rejected_even_same_origin(self):
        with self.assertRaisesRegex(probe.ProbeError, "HTTP_REDIRECT_REFUSED"):
            probe.NoRedirect().redirect_request(None, None, 302, "secret", {}, "http://evil.test")

    def test_no_error_body_exception_or_headers_echo(self):
        error = urllib.error.HTTPError("https://secret.test", 401, "secret-admin-key",
                                       {"Secret": "secret"}, io.BytesIO(b"secret response"))
        transport = self.make_transport(error)
        with self.assertRaises(probe.ProbeError) as caught:
            transport.request("https://nas.test")
        self.assertEqual(str(caught.exception), "HTTP_STATUS")
        self.assertEqual(caught.exception.http_status, 401)
        self.assertTrue(error.fp.closed)
        for error in [ssl.SSLError("secret"), urllib.error.URLError("secret"), TimeoutError("secret")]:
            transport = self.make_transport(error)
            with self.assertRaisesRegex(probe.ProbeError, "TLS_OR_NETWORK_FAILURE"):
                transport.request("https://nas.test")

    def test_response_size_cap_declared_and_chunked(self):
        for response in [Response(headers={"Content-Length": str(probe.MAX_RESPONSE_BYTES + 1)}),
                         Response(b" " * (probe.MAX_RESPONSE_BYTES + 1))]:
            transport = self.make_transport(response)
            with self.assertRaisesRegex(probe.ProbeError, "HTTP_RESPONSE_TOO_LARGE"):
                transport.request("https://nas.test")

    def test_compression_and_bad_lengths_refused(self):
        for headers in [{"Content-Encoding": "gzip"}, {"Content-Length": "secret"},
                        {"Content-Length": "-1"}]:
            with self.assertRaises(probe.ProbeError):
                self.make_transport(Response(headers=headers)).request("https://nas.test")

    def test_per_request_timeout_and_request_budget(self):
        transport = self.make_transport(Response())
        self.assertEqual(transport.request("https://nas.test"), {})
        request, timeout = transport.opener.calls[0]
        self.assertEqual(timeout, probe.REQUEST_TIMEOUT_SECONDS)
        self.assertEqual(request.get_header("Accept-encoding"), "identity")
        transport.requests = probe.MAX_REQUESTS
        with self.assertRaisesRegex(probe.ProbeError, "REQUEST_BUDGET_EXCEEDED"):
            transport.request("https://nas.test")
        self.assertEqual(len(transport.opener.calls), 1)

    def test_expired_read_deadline(self):
        transport = self.make_transport(Response())
        with patch.object(probe.time, "monotonic", side_effect=[0, 9]):
            with self.assertRaisesRegex(probe.ProbeError, "REQUEST_DEADLINE"):
                transport.request("https://nas.test")


class FakeProcess:
    def __init__(self, *args, **kwargs):
        self.pid = None
        self.live = False
        self.terminated = False
        self.killed = False
        self.closed = False

    def start(self):
        self.pid = 123
        self.live = True

    def is_alive(self):
        return self.live

    def terminate(self):
        self.terminated = True
        # Simulate a non-cooperating process: must escalate to kill.

    def kill(self):
        self.killed = True
        self.live = False

    def join(self, timeout):
        pass

    def close(self):
        self.closed = True


class ProcessAndCliTests(unittest.TestCase):
    def test_real_spawn_roundtrip_with_network_rejected_placeholder_config(self):
        # Exercises Windows spawn / pipe behavior without any live network work.
        data = config()
        data["issuer"] = "https://nas.example.invalid/webman/sso"
        report = probe.bounded_probe(data, wall_timeout=10)
        self.assertEqual(report["status"], "blocked")
        self.assertEqual(report["checks"][0]["code"], "CONFIG_PLACEHOLDER")

    def test_watchdog_kills_stuck_worker_and_reports_ambiguous_apply(self):
        from unittest.mock import Mock
        receiver, sender = Mock(), Mock()
        receiver.poll.return_value = False
        process = FakeProcess()
        context = Mock()
        context.Pipe.return_value = receiver, sender
        context.Process.return_value = process
        with patch.object(probe.multiprocessing, "get_context", return_value=context):
            report = probe.bounded_probe(config(), apply=True, wall_timeout=0.01)
        receiver.poll.assert_called_once_with(0.01)
        self.assertTrue(process.terminated)
        self.assertTrue(process.killed)
        self.assertTrue(process.closed)
        self.assertEqual(report["checks"][0]["code"], "PROCESS_WALL_DEADLINE")
        self.assertEqual(report["apply"]["state"], "outcome_unknown")

    def test_worker_catches_unsanitized_unexpected_exception(self):
        from unittest.mock import Mock
        pipe = Mock()
        with patch.object(probe, "JsonTransport", side_effect=RuntimeError("private-client-secret")):
            probe._worker(config(), True, None, False, None, pipe)
        report = pipe.send.call_args.args[0]
        self.assertNotIn("private-client-secret", json.dumps(report))
        self.assertEqual(report["apply"]["state"], "outcome_unknown")

    def test_cli_error_output_is_json_and_does_not_echo_args_or_config_path(self):
        for argv in [["--client-secret", "SECRET_DO_NOT_PRINT"],
                     ["--config", "SECRET_PRIVATE_PATH_DO_NOT_PRINT"]]:
            output, errors = io.StringIO(), io.StringIO()
            with contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
                code = probe.main(argv)
            self.assertEqual(code, 2)
            self.assertEqual(json.loads(output.getvalue())["status"], "blocked")
            self.assertNotIn("DO_NOT_PRINT", output.getvalue() + errors.getvalue())
            self.assertEqual(errors.getvalue(), "")


if __name__ == "__main__":
    unittest.main()
