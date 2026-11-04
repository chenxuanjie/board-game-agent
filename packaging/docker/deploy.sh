#!/bin/sh
printf '%s\n' 'Legacy Web account-gateway delivery is retired and cannot serve the current SQL/API protocol. Use .github/workflows/web-ghcr.yml and packaging/docker/docker-compose.ghcr.yml; see docs/web-ghcr.md. No images or deployment files were changed.' >&2
exit 2
