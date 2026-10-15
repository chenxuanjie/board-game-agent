"""Read-only published-library index; never discovers arbitrary NAS folders."""
import json
from pathlib import Path, PurePosixPath
import re


class LibraryError(Exception):
    def __init__(self, status):
        self.status = status


def logical_path(value):
    if (not isinstance(value, str) or not 1 <= len(value) <= 1024
            or any(c in value for c in "\\%?#:\x00\r\n")
            or re.search(r"[\x00-\x1f\x7f]", value)
            or any(part in ("", ".", "..") or part.startswith(".") for part in value.split("/"))
            or not value.startswith("assets/")
            or "docs/others" in value.lower()):
        raise LibraryError(404)
    return value


class Library:
    def __init__(self, root):
        self.root = Path(root)
        self._signature = None
        self._allowed = frozenset()

    def file(self, logical):
        logical_path(logical)
        candidate = self.root / logical
        try:
            root = self.root.resolve(strict=True)
            if not candidate.resolve(strict=True).is_relative_to(root):
                raise LibraryError(404)
            cursor = self.root
            for part in PurePosixPath(logical).parts:
                cursor /= part
                if cursor.is_symlink():
                    raise LibraryError(404)
            if not candidate.is_file():
                raise LibraryError(404)
            return candidate
        except (OSError, RuntimeError):
            raise LibraryError(404) from None

    def _json(self, path):
        file = self.file(path)
        if file.stat().st_size > 4 * 1024 * 1024:
            raise LibraryError(503)
        try:
            value = json.loads(file.read_bytes())
            if not isinstance(value, dict):
                raise ValueError()
            return value
        except (ValueError, OSError):
            raise LibraryError(503) from None

    def paths(self):
        catalog = self._json("assets/catalog.json")
        games = catalog.get("games")
        if not isinstance(games, list) or len(games) > 1000:
            raise LibraryError(503)
        slugs = []
        for item in games:
            if (not isinstance(item, dict) or not isinstance(item.get("slug"), str)
                    or not re.fullmatch(r"[a-z0-9][a-z0-9_-]{0,99}", item["slug"])):
                raise LibraryError(503)
            if item.get("enabled", False) is True:
                slugs.append(item["slug"])
        metadata = ["assets/catalog.json"] + [f"assets/games/{s}/{name}" for s in slugs for name in ("game.json", "manifest.json")]
        signature = []
        for path in metadata:
            try:
                stat = self.file(path).stat()
                signature.append((path, stat.st_mtime_ns, stat.st_size))
            except LibraryError:
                signature.append((path, None, None))
        signature = tuple(signature)
        if signature == self._signature:
            return self._allowed
        allowed = {"assets/catalog.json"}
        for slug in slugs:
            base = f"assets/games/{slug}/"
            allowed.update(base + name for name in ("game.json", "manifest.json"))
            try:
                game = self._json(base + "game.json")
                gallery = game.get("galleryAssets") or []
                if not isinstance(gallery, list):
                    raise LibraryError(503)
                images = [game.get("coverAsset"), game.get("bannerAsset"), *gallery]
                for path in images:
                    if isinstance(path, str) and path:
                        full = path if path.startswith("assets/") else base + path
                        try:
                            logical_path(full)
                        except LibraryError:
                            continue
                        if full.startswith(base + "images/"):
                            allowed.add(full)
                            if len(allowed) > 20000:
                                raise LibraryError(503)
                manifest = self._json(base + "manifest.json")
                resources = manifest.get("resources", [])
                if not isinstance(resources, list):
                    raise LibraryError(503)
                for resource in resources:
                    if (not isinstance(resource, dict) or resource.get("enabled", False) is not True
                            or resource.get("status") != "available"):
                        continue
                    path = resource.get("path")
                    if isinstance(path, str):
                        full = path if path.startswith("assets/") else base + path
                        try:
                            logical_path(full)
                        except LibraryError:
                            continue
                        if full.startswith(base):
                            allowed.add(full)
                    if len(allowed) > 20000:
                        raise LibraryError(503)
            except LibraryError as error:
                if error.status != 404:
                    raise
            except (TypeError, ValueError):
                raise LibraryError(503) from None
        self._signature, self._allowed = signature, frozenset(allowed)
        return self._allowed

    def resolve(self, path):
        logical_path(path)
        if path not in self.paths():
            raise LibraryError(404)
        return self.file(path)

    def entries(self, directory, max_depth, max_entries):
        if directory != "assets":
            logical_path(directory)
        prefix = directory.rstrip("/") + "/"
        values = []
        for path in sorted(self.paths()):
            if not path.startswith(prefix) or path[len(prefix):].count("/") > max_depth:
                continue
            try:
                stat = self.file(path).stat()
            except LibraryError:
                continue
            values.append({"path": path, "name": PurePosixPath(path).name,
                           "etag": f'"{stat.st_mtime_ns:x}-{stat.st_size:x}"'})
            if len(values) >= max_entries:
                break
        return values

    def versions(self):
        values = []
        for path in sorted(self.paths()):
            try:
                stat = self.file(path).stat()
                values.append({"path": path, "version": f"{stat.st_mtime_ns:x}-{stat.st_size:x}", "exists": True})
            except LibraryError:
                values.append({"path": path, "exists": False})
        return values
