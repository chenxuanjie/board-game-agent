"""Existing account-sync wire format over the current DSM user's FileStation.

No host-home mount, service credentials, ACL changes, deletes or arbitrary paths.
Private operation conflict resolution remains in webdav_sync on the client.
"""
import hashlib
import json
import re

DEVICE = r"d[0-9a-f]{32}"
PRIVATE_FILE = re.compile(rf"operations/({DEVICE})\.([0-9]{{16}})\.json")
LEGACY_FILE = re.compile(rf"operations/({DEVICE})/([0-9]{{16}})\.json")
PUBLIC_FILE = re.compile(rf"u([1-9][0-9]*)/({DEVICE})\.json")
MAX_PRIVATE = 8 * 1024 * 1024
MAX_PUBLIC = 512 * 1024


class AccountFiles:
    def __init__(self, settings, failure):
        self.settings, self.failure = settings, failure
        self.environment = hashlib.sha256(f"synology-direct-v1|{settings.identity_origin}".encode()).hexdigest()
        self.private_root = f"/home/Apps/board_game_agent/sync/v1/{self.environment}"
        self.public_root = f"/{settings.shared_folder}/apps/board_game_agent/public/v1"

    def scope(self, uid):
        user = hashlib.sha256(f"synology-direct-v1|{self.settings.identity_origin}|{uid}".encode()).hexdigest()
        return hashlib.sha256(f"{self.environment}|{user}".encode()).hexdigest()

    def path(self, lane, relative, *, listing=False, writing=False):
        if not isinstance(relative, str):
            raise self.failure("accountDenied", 400)
        if lane == "private":
            allowed = (relative == "operations" or re.fullmatch(rf"operations/{DEVICE}", relative)) if listing else (
                PRIVATE_FILE.fullmatch(relative) or (not writing and LEGACY_FILE.fullmatch(relative)))
            root = self.private_root
        elif lane == "public":
            allowed = (relative == "" or re.fullmatch(r"u[1-9][0-9]*", relative)) if listing else PUBLIC_FILE.fullmatch(relative)
            root = self.public_root
        else:
            allowed, root = False, ""
        if not allowed:
            raise self.failure("accountDenied", 400)
        return root + ("/" + relative if relative else "")

    async def stat(self, call, path):
        data = await call("SYNO.FileStation.List", "getinfo", {"path": json.dumps([path]), "additional": '["owner"]'})
        files = data.get("files")
        if not isinstance(files, list) or len(files) != 1 or not isinstance(files[0], dict):
            raise self.failure("providerUnavailable")
        value = files[0]
        if value.get("code") == 408:
            return None
        if value.get("code") or value.get("path") != path or type(value.get("isdir")) is not bool:
            raise self.failure("accountDenied", 403)
        return value

    async def directory(self, call, path, allowed):
        value = await self.stat(call, path)
        if value is None:
            if path not in allowed:
                raise self.failure("missing", 404)
            parent, name = path.rsplit("/", 1)
            try:
                await call("SYNO.FileStation.CreateFolder", "create", {
                    "folder_path": json.dumps([parent]), "name": json.dumps([name]), "force_parent": "false"})
            except self.failure as error:
                if error.code != "providerUnavailable" or await self.stat(call, path) is None:
                    raise
            value = await self.stat(call, path)
        if value is None or value["isdir"] is not True:
            raise self.failure("accountDenied", 403)

    async def entries(self, call, lane, relative):
        path = self.path(lane, relative, listing=True)
        result = []
        for offset in range(0, 10000 if lane == "private" else 2000, 100):
            fields = {"folder_path": path, "offset": str(offset), "limit": "100", "sort_by": "name", "additional": '["owner"]'}
            try:
                data = await call("SYNO.FileStation.List", "list", fields)
            except self.failure as error:
                if offset or lane != "private" or relative != "operations" or error.code != "missing":
                    raise
                chain = ["/home/Apps", "/home/Apps/board_game_agent", "/home/Apps/board_game_agent/sync",
                         "/home/Apps/board_game_agent/sync/v1", self.private_root, self.private_root + "/operations"]
                for directory in chain:
                    await self.directory(call, directory, chain)
                data = await call("SYNO.FileStation.List", "list", fields)
            files, total = data.get("files"), data.get("total")
            maximum = 10000 if lane == "private" else 2000
            if not isinstance(files, list) or type(total) is not int or not 0 <= total <= maximum or len(files) > 100:
                raise self.failure("providerUnavailable")
            for file in files:
                if (not isinstance(file, dict) or not isinstance(file.get("name"), str)
                        or file.get("path") != path + "/" + file["name"] or type(file.get("isdir")) is not bool):
                    raise self.failure("accountDenied", 403)
                name, directory = file["name"], file["isdir"]
                child = relative + "/" + name if relative else name
                self.path(lane, child, listing=directory)
                entry = {"name": name, "directory": directory}
                if lane == "public":
                    uid = file.get("additional", {}).get("owner", {}).get("uid")
                    if type(uid) is not int or uid <= 0 or (not directory and uid != int(relative[1:])):
                        raise self.failure("accountDenied", 403)
                    entry["ownerUid"] = uid
                result.append(entry)
            if offset + len(files) >= total:
                return result
            if not files:
                raise self.failure("providerUnavailable")
        raise self.failure("providerUnavailable")

    async def read(self, call, lane, relative):
        path = self.path(lane, relative)
        expected_uid = int(relative.split("/")[0][1:]) if lane == "public" else None
        async def owner_check():
            value = await self.stat(call, path)
            if value is None:
                raise self.failure("missing", 404)
            if value["isdir"] or value.get("additional", {}).get("owner", {}).get("uid") != expected_uid:
                raise self.failure("accountDenied", 403)
        if expected_uid is not None:
            await owner_check()
        raw = await call("SYNO.FileStation.Download", "download", {"path": json.dumps([path]), "mode": "download"},
                         raw_limit=MAX_PUBLIC if lane == "public" else MAX_PRIVATE)
        try:
            text = raw.decode("utf-8")
            json.loads(text)
        except (ValueError, UnicodeError):
            raise self.failure("providerUnavailable") from None
        if expected_uid is not None:
            await owner_check()
        return text

    def validate(self, lane, relative, content, uid):
        self.path(lane, relative, writing=True)
        maximum = MAX_PRIVATE if lane == "private" else MAX_PUBLIC
        if not isinstance(content, str) or len(content.encode()) > maximum:
            raise self.failure("accountDenied", 413)
        try:
            value = json.loads(content)
            if lane == "private":
                match = PRIVATE_FILE.fullmatch(relative)
                self.operation(value, self.scope(uid))
                if (value["deviceId"] != match[1] or value["sequence"] != int(match[2])
                        or value["operationId"] != f'{match[1]}_{int(match[2])}'):
                    raise ValueError()
            else:
                match = PUBLIC_FILE.fullmatch(relative)
                if (int(match[1]) != uid or type(value.get("uid")) is not int or value["uid"] != uid
                        or value.get("device") != match[2] or type(value.get("version")) is not int or value["version"] != 1
                        or not isinstance(value.get("operations"), list) or len(value["operations"]) > 20000):
                    raise ValueError()
                for op in value["operations"]:
                    self.operation(op, self.scope(uid))
                    if op["entityType"] not in ("favorite", "vote"):
                        raise ValueError()
        except (ValueError, TypeError, KeyError, AttributeError):
            raise self.failure("accountDenied", 400) from None

    @staticmethod
    def operation(value, scope):
        if (not isinstance(value, dict) or value.get("datasetId") != scope or type(value.get("protocolVersion")) is not int
                or value["protocolVersion"] != 1 or not isinstance(value.get("deviceId"), str)
                or not re.fullmatch(DEVICE, value["deviceId"]) or type(value.get("sequence")) is not int
                or not 1 <= value["sequence"] <= 9007199254740991 or value.get("operation") not in ("upsert", "delete")
                or (value["operation"] == "upsert" and not isinstance(value.get("payload"), dict))
                or (value["operation"] == "delete" and value.get("payload") is not None)):
            raise ValueError()

    async def write(self, call, lane, relative, content, uid):
        self.validate(lane, relative, content, uid)
        path = self.path(lane, relative, writing=True)
        if lane == "public":
            await self.directory(call, self.public_root, ())
            await self.directory(call, f"{self.public_root}/u{uid}", (f"{self.public_root}/u{uid}",))
            existing = await self.stat(call, path)
            if existing and (existing["isdir"] or existing.get("additional", {}).get("owner", {}).get("uid") != uid):
                raise self.failure("accountDenied", 403)
        await call("SYNO.FileStation.Upload", "upload", {
            "path": path.rsplit("/", 1)[0], "create_parents": "false", "overwrite": "true" if lane == "public" else "false"},
            file=(path.rsplit("/", 1)[1], content.encode(), "application/json"))
        if await self.read(call, lane, relative) != content:
            raise self.failure("syncConflict", 409)
