"""Bounded public comment snapshots; writes use the current user's DSM session.

The mount is read-only. Never writes as the container user, changes permissions,
or creates the administrator-managed public root.
"""
import json
import asyncio
import os
from pathlib import Path
import re
from datetime import datetime
from contextlib import ExitStack

ACCOUNT = re.compile(r"u[1-9][0-9]*")
DEVICE = re.compile(r"d[0-9a-f]{32}\.json")
ID = re.compile(r"c[0-9a-f]{32}")
MAX_BYTES = 512 * 1024


class Comments:
    def __init__(self, root, nas_root, failure):
        self.root, self.nas_root, self.failure = Path(root), nas_root, failure

    def parts(self, relative, *, file=False):
        parts = relative.split("/") if relative else []
        if (len(parts) > 2 or (parts and not ACCOUNT.fullmatch(parts[0]))
                or (len(parts) == 2 and not DEVICE.fullmatch(parts[1]))
                or (file and len(parts) != 2)):
            raise self.failure("missing", 404)
        return parts

    def path(self, relative):
        parts = self.parts(relative)
        path = self.root
        try:
            root = self.root.resolve(strict=True)
            for part in parts:
                path /= part
                if path.is_symlink():
                    raise self.failure("accountDenied", 403)
            if not path.resolve(strict=True).is_relative_to(root):
                raise self.failure("accountDenied", 403)
            return path
        except FileNotFoundError:
            raise self.failure("missing", 404) from None
        except OSError:
            raise self.failure("accountDenied", 403) from None

    def entries(self, relative):
        parts = self.parts(relative)
        if len(parts) > 1:
            raise self.failure("missing", 404)
        directory = self.path(relative)
        result = []
        for child in directory.iterdir():
            if not (DEVICE if parts else ACCOUNT).fullmatch(child.name):
                continue
            if child.is_symlink() or child.is_dir() != (not parts):
                raise self.failure("accountDenied", 403)
            uid = child.stat().st_uid
            if parts and uid != int(parts[0][1:]):
                raise self.failure("accountDenied", 403)
            result.append({"name": child.name, "directory": not parts, "ownerUid": uid})
            if len(result) > (128 if parts else 1000):
                raise self.failure("providerUnavailable")
        return sorted(result, key=lambda entry: entry["name"])

    def read(self, relative):
        parts = self.parts(relative, file=True)
        path = self.path(relative)
        with ExitStack() as stack:
            if os.open in os.supports_dir_fd:
                # Open every path component without following symlinks, including
                # when an account directory is replaced between stat and open.
                flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
                directory = os.open(self.root, flags)
                stack.callback(os.close, directory)
                directory = os.open(parts[0], flags, dir_fd=directory)
                stack.callback(os.close, directory)
                stream = stack.enter_context(os.fdopen(os.open(parts[1], os.O_RDONLY | os.O_NOFOLLOW,
                                                                dir_fd=directory), "rb"))
            else:
                stream = stack.enter_context(path.open("rb"))
            stat = os.fstat(stream.fileno())
            if stat.st_uid != int(parts[0][1:]) or stat.st_size > MAX_BYTES:
                raise self.failure("accountDenied", 403)
            content = stream.read(MAX_BYTES + 1)
        if len(content) > MAX_BYTES:
            raise self.failure("providerUnavailable")
        try:
            text = content.decode("utf-8")
            self.validate(relative, text, int(parts[0][1:]))
            return text
        except (ValueError, TypeError, KeyError, UnicodeError):
            raise self.failure("providerUnavailable") from None

    def validate(self, relative, content, uid):
        parts = self.parts(relative, file=True)
        if parts[0] != f"u{uid}" or not isinstance(content, str) or len(content.encode()) > MAX_BYTES:
            raise ValueError("Own bounded snapshot required")
        data = json.loads(content)
        if (not isinstance(data, dict) or type(data.get("version")) is not int or data["version"] != 1
                or type(data.get("uid")) is not int or data["uid"] != uid
                or data.get("device") != parts[1][:-5] or not isinstance(data.get("operations"), list)
                or len(data["operations"]) > 20000):
            raise ValueError("Invalid snapshot")
        seen = set()
        for op in data["operations"]:
            if (not isinstance(op, dict) or type(op.get("uid")) is not int or op["uid"] != uid
                    or not isinstance(op.get("id"), str) or not ID.fullmatch(op["id"]) or op["id"] in seen
                    or not isinstance(op.get("game"), str) or not re.fullmatch(r"[a-z0-9][a-z0-9_-]{0,127}", op["game"])
                    or type(op.get("revision")) is not int or not 1 <= op["revision"] <= 9007199254740991
                    or not isinstance(op.get("author"), str) or len(op["author"]) > 80
                    or not isinstance(op.get("text"), str) or len(op["text"]) > 1000
                    or type(op.get("liked")) is not bool
                    or (op.get("rating") is not None and (type(op["rating"]) is not int or not 1 <= op["rating"] <= 10))
                    or any(v is not None and (not isinstance(v, str) or not ID.fullmatch(v))
                           for v in (op.get("root"), op.get("replyTo"), op.get("target")))):
                raise ValueError("Invalid operation")
            if not isinstance(op.get("at"), str):
                raise ValueError("Invalid date")
            at = datetime.fromisoformat(op["at"].replace("Z", "+00:00"))
            if not 2020 <= at.year <= 2100:
                raise ValueError("Invalid date")
            if op.get("action") == "publish":
                if (not op["text"].strip() or not op["author"].strip() or op.get("target") is not None
                        or (op.get("root") is None) != (op.get("replyTo") is None)
                        or (op.get("root") is not None and op.get("rating") is not None)):
                    raise ValueError("Invalid comment")
            elif op.get("action") not in ("like", "delete") or (op.get("target") is None or op["text"]
                    or any(op.get(key) is not None for key in ("rating", "root", "replyTo"))):
                raise ValueError("Invalid reaction")
            seen.add(op["id"])

    async def replace(self, dsm, nas, relative, content):
        self.validate(relative, content, nas.uid)
        folder = f"{self.nas_root}/u{nas.uid}"

        async def stat(path):
            data = await dsm.file_api(nas, "SYNO.FileStation.List", "getinfo",
                                      {"path": json.dumps([path]), "additional": '["owner"]'})
            entries = data.get("files")
            if not isinstance(entries, list) or len(entries) != 1:
                raise self.failure("providerUnavailable")
            entry = entries[0]
            if entry.get("code") == 408:
                return None
            if entry.get("code") or entry.get("path") != path:
                raise self.failure("accountDenied", 403)
            return entry

        # Only an explicit 408 on this user's directory permits initialization.
        root = await stat(self.nas_root)
        if not root or root.get("isdir") is not True:
            raise self.failure("missing", 404)
        directory = await stat(folder)
        if directory is None:
            try:
                await dsm.file_api(nas, "SYNO.FileStation.CreateFolder", "create",
                                   {"folder_path": json.dumps([self.nas_root]), "name": json.dumps([f"u{nas.uid}"]),
                                    "force_parent": "false"})
            except self.failure as failure:
                if failure.code != "providerUnavailable" or await stat(folder) is None:
                    raise
            directory = await stat(folder)
        if not directory or directory.get("isdir") is not True:
            raise self.failure("accountDenied", 403)
        existing = await stat(f"{self.nas_root}/{relative}")
        if existing and (existing.get("isdir") is not False
                         or existing.get("additional", {}).get("owner", {}).get("uid") != nas.uid):
            raise self.failure("accountDenied", 403)
        await dsm.file_api(nas, "SYNO.FileStation.Upload", "upload",
                           {"path": folder, "create_parents": "false", "overwrite": "true"},
                           file=(relative.split("/")[1], content.encode(), "application/json"))
        # Re-read the actual mount, verifying owner and the exact saved content.
        if await asyncio.to_thread(self.read, relative) != content:
            raise self.failure("providerUnavailable")
