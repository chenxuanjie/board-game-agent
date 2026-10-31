"""Partition a Flutter Web build into deterministic, independently reusable layers."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil

GROUPS = ("engine", "sync", "pdf", "fonts", "media", "app")
GENERATED_ASSETS = {"AssetManifest.bin", "AssetManifest.bin.json", "AssetManifest.json",
                    "FontManifest.json", "NOTICES"}


def group_for(path):
    parts = path.parts
    if parts[0] == "canvaskit":
        return "engine"
    if parts[0] == "powersync":
        return "sync"
    if parts[:3] == ("assets", "packages", "pdfrx"):
        return "pdf"
    if path.suffix.lower() in {".ttf", ".otf", ".woff", ".woff2"} or "fonts" in parts:
        return "fonts"
    if ((parts[0] == "assets" and path.name not in GENERATED_ASSETS)
            or parts[0] == "icons" or path.name == "favicon.png"):
        return "media"
    return "app"


def prepare(source, destination):
    source, destination = source.resolve(), destination.resolve()
    if destination.exists() or destination.is_relative_to(source):
        raise ValueError("Use a new output directory outside the Web build")
    if not all((source / name).is_file() for name in ("index.html", "main.dart.js")):
        raise ValueError("A complete JavaScript Flutter Web build is required")
    files = sorted(source.rglob("*"))
    if any(path.is_symlink() or not (path.is_file() or path.is_dir()) for path in files):
        raise ValueError("Web build cannot contain symbolic links or special files")
    inventory = {name: {"bytes": 0, "files": {}} for name in GROUPS}
    for name in GROUPS:
        (destination / name).mkdir(parents=True)
    for path in files:
        if not path.is_file():
            continue
        relative = path.relative_to(source)
        group = group_for(relative)
        target = destination / group / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
        target.chmod(0o644)
        os.utime(target, (0, 0))
        entry = inventory[group]
        entry["bytes"] += target.stat().st_size
        entry["files"][relative.as_posix()] = hashlib.sha256(target.read_bytes()).hexdigest()
    # Rebuilds otherwise give identical fonts/images different layer timestamps.
    for path in sorted(destination.rglob("*"), reverse=True):
        if path.is_dir():
            path.chmod(0o755)
            os.utime(path, (0, 0))
    etags = {}
    for value in inventory.values():
        for name, digest in value["files"].items():
            if any(character in name for character in ('$','\\','"','\r','\n')):
                raise ValueError("Unsupported characters in a static resource path")
            etags["/" + name] = '"sha256:' + digest + '"'
    etags["/"] = etags["/index.html"]
    mapping = destination / "web-etags.map"
    # Nginx map string keys ignore case; resource URLs must keep filesystem case.
    mapping.write_text("".join(json.dumps("~^" + re.escape(name) + "$", ensure_ascii=False) + " " + json.dumps(value) + ";\n"
                               for name, value in sorted(etags.items())), encoding="utf-8", newline="\n")
    mapping.chmod(0o644)
    os.utime(mapping, (0, 0))
    (destination / "layer-inventory.json").write_text(
        json.dumps({"schemaVersion": 1, "groups": inventory}, indent=2) + "\n", encoding="utf-8")
    return inventory


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    record = prepare(args.source, args.destination)
    print(json.dumps({group: {"bytes": value["bytes"], "files": len(value["files"])}
                      for group, value in record.items()}))
