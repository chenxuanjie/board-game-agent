#!/bin/sh
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
if [ ! -f docker-compose.yml ]; then
    printf '%s\n' 'Missing docker-compose.yml; copy the matching release configuration.' >&2
    exit 1
fi
command -v docker >/dev/null 2>&1 || { printf '%s\n' 'Docker is required on the NAS.' >&2; exit 1; }
docker compose version >/dev/null
sha256sum -c checksums.sha256
IFS= read -r release_platform < image-platform.txt
IFS= read -r release_tag < image-tag.txt
case "$release_tag" in ''|*[!A-Za-z0-9_.-]*) printf '%s\n' 'Invalid release tag.' >&2; exit 1;; esac
case "$(uname -s)/$(uname -m):$release_platform" in
    Linux/x86_64:linux/amd64|Linux/aarch64:linux/arm64|Linux/arm64:linux/arm64) ;;
    *) printf '%s\n' 'This image bundle does not match the NAS CPU architecture.' >&2; exit 1;;
esac
# The delivered YAML pins both image refs and all settings. No .env is needed.
docker compose -p "${COMPOSE_PROJECT_NAME:-board-game-agent}" -f docker-compose.yml config --quiet
docker image load --input "${1:-images.tar}"
docker compose -p "${COMPOSE_PROJECT_NAME:-board-game-agent}" -f docker-compose.yml up -d --no-build --pull never
printf '%s\n' 'Containers started. Verify logs, HTTPS login and mounted-library access before accepting the release.'
