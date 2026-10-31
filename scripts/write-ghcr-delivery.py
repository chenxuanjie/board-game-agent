"""Record pushed image identities and generate the matching immutable Compose."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

from ghcr_web_release import LOCK, ROOT, ai_input_digest, compose, git, nas_compose


def published(image, *, relay=False, reused=False):
    info = json.loads(subprocess.check_output(["docker", "image", "inspect", image], text=True))[0]
    repository = image.rsplit(":", 1)[0]
    reference = next((ref for ref in info.get("RepoDigests", []) if ref.startswith(repository + "@sha256:")), None)
    if reference is None:
        raise ValueError("Pushed image has no matching registry digest")
    if info["Os"] != "linux" or info["Architecture"] != "amd64":
        raise ValueError("Unexpected image platform")
    labels = info["Config"].get("Labels") or {}
    source = labels.get("org.opencontainers.image.revision", "")
    if relay and (labels.get("io.board-game-agent.build-inputs") != ai_input_digest()
                  or re.fullmatch(r"[a-f0-9]{40}", source) is None):
        raise ValueError("Relay image does not match its declared source inputs")
    if not reused and source != git(ROOT, "rev-parse", "HEAD"):
        raise ValueError("Image source differs from the checked-out commit")
    return {"tag": image, "reference": reference, "imageId": info["Id"], "sourceRevision": source,
            **({"inputDigest": ai_input_digest(), "reused": reused} if relay else {})}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--web-image", required=True)
    parser.add_argument("--ai-image", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--reuse-ai", action="store_true")
    parser.add_argument("--nas-channel", action="store_true")
    args = parser.parse_args()
    if git(ROOT, "status", "--porcelain"):
        raise ValueError("Sources changed during image construction")
    web, ai = published(args.web_image), published(args.ai_image, relay=True, reused=args.reuse_ai)
    args.output.mkdir(parents=True, exist_ok=True)
    configuration = args.output / "docker-compose.yml"
    configuration.write_text(compose(web["reference"], ai["reference"]), encoding="utf-8")
    subprocess.run(["docker", "compose", "-f", str(configuration), "config", "--quiet"], check=True)
    if args.nas_channel:
        reusable = args.output / "docker-compose.nas.yml"
        reusable.write_text(nas_compose(), encoding="utf-8")
        subprocess.run(["docker", "compose", "-f", str(reusable), "config", "--quiet"], check=True)
    dependencies = json.loads((ROOT / LOCK).read_text(encoding="utf-8"))
    record = {"schemaVersion": 1, "sourceRevision": git(ROOT, "rev-parse", "HEAD"),
              "dirtySource": False, "platform": "linux/amd64", "images": {"web": web, "webAi": ai},
              "dependencies": dependencies["packages"], "published": True, "realNasDeployed": False,
              "httpPort": 8083, "httpsPort": 8084, "browserOrigin": "https://cznas.pp.ua:8084",
              "apiRequiresBrowserOriginConfiguration": True, "applicationVersion":
                  json.loads(subprocess.check_output(["docker", "image", "inspect", args.web_image], text=True))[0]["Config"]["Labels"]["org.opencontainers.image.version"]}
    record["nasChannelPublished"] = args.nas_channel
    (args.output / "release.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    checksums = "".join(hashlib.sha256(path.read_bytes()).hexdigest() + "  " + path.name + "\n"
                        for path in sorted(args.output.iterdir()) if path.is_file() and path.name != "checksums.sha256")
    (args.output / "checksums.sha256").write_text(checksums, encoding="utf-8")
    print(json.dumps(record, indent=2))


if __name__ == "__main__":
    main()
