"""Retired account-gateway TAR verifier; not a current image acceptance."""
import sys


def main():
    print('Legacy Web account-gateway delivery is retired and cannot serve the current SQL/API protocol. Use .github/workflows/web-ghcr.yml and packaging/docker/docker-compose.ghcr.yml; see docs/web-ghcr.md. No images or deployment files were changed.', file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
