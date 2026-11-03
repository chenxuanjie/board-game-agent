"""Measure compressed missing layers between OCI archives or registry manifests."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import tarfile


def load_image(path):
    if path.suffix == ".json":
        value = json.loads(path.read_text(encoding="utf-8"))
        if "layers" not in value:
            raise ValueError("Expected a resolved platform image manifest")
        return value
    with tarfile.open(path) as archive:
        def blob(descriptor):
            algorithm, digest = descriptor["digest"].split(":", 1)
            if algorithm != "sha256" or not re.fullmatch("[a-f0-9]{64}", digest):
                raise ValueError("Invalid OCI digest")
            data = archive.extractfile("blobs/sha256/" + digest).read()
            if len(data) != descriptor["size"] or hashlib.sha256(data).hexdigest() != digest:
                raise ValueError("OCI metadata digest mismatch")
            return json.loads(data)
        index = json.load(archive.extractfile("index.json"))
        descriptors = index["manifests"]
        if len(descriptors) != 1:
            descriptors = [item for item in descriptors
                           if item.get("platform", {}).get("architecture") == "amd64"
                           and item["platform"].get("os") == "linux"]
        if len(descriptors) != 1:
            raise ValueError("Expected exactly one Linux amd64 image")
        manifest = blob(descriptors[0])
        config = blob(manifest["config"])
        history = [item for item in config.get("history", []) if not item.get("empty_layer")]
        for index, layer in enumerate(manifest["layers"]):
            digest = layer["digest"].split(":", 1)[1]
            if archive.getmember("blobs/sha256/" + digest).size != layer["size"]:
                raise ValueError("OCI layer size mismatch")
            created_by = history[index].get("created_by", "") if index < len(history) else ""
            match = re.search(r"web-layers/(engine|sync|pdf|fonts|media|app)/?", created_by)
            layer["group"] = match[1] if match else (
                "metadata" if "web-etags.map" in created_by else
                "monolithic-web" if "COPY" in created_by and "/usr/share/nginx/html" in created_by else "base/config")
        return manifest


def compare(previous, current):
    existing = {item["digest"] for item in previous["layers"]}
    layers = {item["digest"]: item for item in current["layers"]}
    missing = [item for digest, item in layers.items() if digest not in existing]
    total = sum(item["size"] for item in layers.values())
    download = sum(item["size"] for item in missing)
    return {"compressedImageBytes": total, "downloadBytes": download,
            "reusedBytes": total - download, "downloadLayers": missing,
            "assumption": "Previous layers remain cached; registry metadata and transport overhead excluded"}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("previous", type=Path)
    parser.add_argument("current", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    record = compare(load_image(args.previous), load_image(args.current))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"downloadMiB": round(record["downloadBytes"] / 1024**2, 3),
                      "reusedMiB": round(record["reusedBytes"] / 1024**2, 3),
                      "newLayers": len(record["downloadLayers"])}))
