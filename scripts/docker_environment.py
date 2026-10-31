"""Wait for actual Docker readiness and start only known local WSL services."""
import argparse
from pathlib import Path
import subprocess
import time
import urllib.parse
import urllib.request


def command(*args, timeout=30):
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout)


def ensure_service(name):
    state = command('systemctl', 'is-active', name).stdout.strip()
    if state in ('inactive', 'failed'):
        print(f'RECOVER starting local service {name}', flush=True)
        if command('sudo', '-n', 'systemctl', 'start', name, timeout=180).returncode:
            raise RuntimeError(f'SERVICE_START_FAILED: {name}; inspect local permissions/journal')
    elif state not in ('active', 'activating', 'reloading'):
        raise RuntimeError(f'SERVICE_UNAVAILABLE: {name} ({state or "no response"})')
    deadline = time.monotonic() + 180
    while command('systemctl', 'is-active', name).stdout.strip() != 'active':
        if time.monotonic() >= deadline:
            raise RuntimeError(f'SERVICE_NOT_READY: {name}')
        time.sleep(1)
    print(f'READY service {name}', flush=True)


def prepare():
    release = Path('/proc/sys/kernel/osrelease')
    wsl = release.exists() and 'microsoft' in release.read_text().lower()
    if wsl:
        ensure_service('docker')
    deadline = time.monotonic() + 180
    while True:
        result = command('docker', 'info', '--format', '{{.OSType}}')
        if result.returncode == 0 and result.stdout.strip() == 'linux':
            break
        if time.monotonic() >= deadline:
            raise RuntimeError('DOCKER_API_NOT_READY: service start did not produce a working Linux engine')
        time.sleep(1)
    print('READY Linux Docker API', flush=True)
    proxy = urllib.parse.urlsplit(urllib.request.getproxies().get('https', ''))
    if wsl and proxy.hostname in ('127.0.0.1', 'localhost') and proxy.port == 18080:
        ensure_service('bga-docker-proxy')


if __name__ == '__main__':
    argparse.ArgumentParser(description=__doc__).parse_args()
    try:
        prepare()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f'Environment preparation failed: {type(error).__name__}: {error}', flush=True)
        raise SystemExit(1) from None
