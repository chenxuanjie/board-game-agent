"""Allowlisted inputs shared by the supported Web image workflow."""
import importlib.util
import re
import shutil


class ReleaseError(ValueError):
    pass


def stage_build_context(root, destination):
    ignored = {".git", ".dart_tool", "build", "node_modules", ".idea", ".pub-cache", ".pub",
               "coverage", "test", "tests", "example", "examples", ".gradle", "keystore", "__pycache__"}
    private = {".env", "pubspec_overrides.yaml", "key.properties", "local.properties", "webdav.local.json"}
    def copy(source, target, *, package_root=False):
        if source.is_symlink():
            raise ReleaseError(f"Build input cannot be a symbolic link: {source}")
        if (source.name in ignored and not package_root) or source.name in private or source.suffix in {".jks", ".keystore", ".p12", ".pfx", ".pyc", ".log"}:
            return
        if source.is_dir():
            target.mkdir(parents=True, exist_ok=True)
            for child in source.iterdir():
                copy(child, target / child.name)
        else:
            if source.suffix.lower() == ".pdf" or ("games" in source.parts and "docs" in source.parts):
                raise ReleaseError("Game documents cannot enter the Web build context")
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
    project = destination / "board-game-agent"
    for name in ("Dockerfile", "Dockerfile.dockerignore", "pubspec.yaml", "pubspec.lock", "lib", "web",
                 "scripts/prepare-web-assets.py", "services/web_account", "packaging/docker/nginx.conf", "packaging/docker/nginx-main.conf"):
        copy(root / name, project / name)
    for name in ("packaging/docker/start-web.sh", "packaging/docker/Dockerfile.ai", "packaging/docker/ai-requirements.lock", "scripts/prepare-web-layers.py"):
        if (root / name).is_file():
            copy(root / name, project / name)
    spec = importlib.util.spec_from_file_location("web_asset_plan", root / "scripts/prepare-web-assets.py")
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    plan = helper.plan((root / "pubspec.yaml").read_text(encoding="utf-8-sig"))
    for name in plan["paths"]:
        copy(root / name, project / name)
    pending, visited = [root], set()
    while pending:
        package = pending.pop().resolve()
        if package in visited:
            continue
        if not package.is_relative_to(root.parent):
            raise ReleaseError("Path dependency escaped the workspace")
        visited.add(package)
        if package != root:
            copy(package, destination / package.relative_to(root.parent), package_root=True)
        for match in re.finditer(r"(?m)^\s+path:\s*[\"']?((?:\.{1,2}/|packages/)[^\s\"'#]+)",
                                 (package / "pubspec.yaml").read_text(encoding="utf-8-sig")):
            pending.append(package / match[1])
    # Resolve packages before copying frequently changing sources into the image.
    # All paths keep the same relationship as in the final /workspace tree.
    for package in sorted(visited):
        relative = package.relative_to(root.parent)
        for name in ("pubspec.yaml", "pubspec.lock"):
            source = package / name
            if source.is_file():
                target = destination / "dependency-manifests" / relative / name
                target.parent.mkdir(parents=True, exist_ok=True)
                text = source.read_text(encoding="utf-8-sig")
                if package == root and name == "pubspec.yaml":
                    text = plan["manifest"]
                    # The application's own version does not affect dependency
                    # solving. Only this cache descriptor is normalized; the
                    # real pubspec is copied back before Flutter compilation.
                    text = re.sub(r"(?m)^version:[^\n]*", "version: 0.0.0", text)
                target.write_text(text, encoding="utf-8", newline="\n")
    startup = project / "packaging/docker/start-web.sh"
    if startup.is_file():
        startup.write_text(startup.read_text(encoding="utf-8-sig"), encoding="utf-8", newline="\n")
    print(f"Prepared allowlisted build context: {sum(p.stat().st_size for p in destination.rglob('*') if p.is_file()) / 1024**2:.1f} MiB", flush=True)
