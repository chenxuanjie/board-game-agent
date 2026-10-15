"""Prepare the source-only Web deployment manifest, without copying game docs.

Supports this project's explicit four-space Flutter asset list. Unknown asset
syntax fails closed rather than accidentally shipping a broad resource tree.
Only the deployment copy of pubspec.yaml is rewritten, never the native one.
"""
import argparse
import json
from pathlib import Path
import re


def plan(text):
    lines = text.splitlines(keepends=True)
    result, paths = [], []
    in_assets = False
    index = 0
    while index < len(lines):
        line = lines[index]
        if line.rstrip() == "  assets:":
            in_assets = True
            result.append(line)
            index += 1
            continue
        if in_assets and line.strip() and not line.startswith("    "):
            in_assets = False
        if in_assets and re.match(r"^    - ", line):
            block = [line]
            index += 1
            while index < len(lines) and lines[index].startswith("      "):
                block.append(lines[index])
                index += 1
            match = re.fullmatch(r"    - (?:path: )?([\w./-]+)\s*", line)
            if not match:
                raise ValueError("Unsupported Flutter asset declaration")
            path = match[1]
            platforms = None
            for option in block[1:]:
                value = re.fullmatch(r"      platforms: \[([a-z, ]+)\]\s*", option)
                if not value:
                    raise ValueError("Unsupported asset options")
                platforms = [part.strip() for part in value[1].split(",")]
            if platforms is not None and "web" not in platforms:
                continue
            if (".." in path.split("/") or "/docs/" in path or path.endswith(".pdf")
                    or path in ("assets/", "assets/games/")
                    or re.fullmatch(r"assets/games/[^/]+/", path)):
                raise ValueError("Web cannot bundle game documents or broad game directories: " + path)
            result.extend(block)
            paths.append(path)
            continue
        # Font declarations precede the asset section in this project's schema.
        font = re.fullmatch(r"\s+- asset: ([\w./-]+)\s*", line)
        if font:
            paths.append(font[1])
        result.append(line)
        index += 1
    if not paths or "assets/catalog.json" not in paths:
        raise ValueError("Missing Web catalog/assets")
    return {"manifest": "".join(result), "paths": list(dict.fromkeys(paths))}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    value = plan(args.manifest.read_text(encoding="utf-8-sig"))
    if args.apply:
        args.manifest.write_text(value["manifest"], encoding="utf-8", newline="\n")
    else:
        print(json.dumps(value, ensure_ascii=True))
