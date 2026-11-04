"""Retired account-gateway image builder. Never generates current releases."""
import sys

RETIRED_MESSAGE = 'Legacy Web account-gateway delivery is retired and cannot serve the current SQL/API protocol. Use .github/workflows/web-ghcr.yml and packaging/docker/docker-compose.ghcr.yml; see docs/web-ghcr.md. No images or deployment files were changed.'


class ReleaseError(RuntimeError):
    pass


def build_release(*args, **kwargs):
    raise ReleaseError(RETIRED_MESSAGE)


def main():
    print(RETIRED_MESSAGE, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
