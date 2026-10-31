"""Check this build process's HTTPS proxy; never print proxy URLs or tokens."""
import sys
import urllib.request


def main():
    if not urllib.request.getproxies().get('https'):
        print('No HTTPS proxy configured for the build process.')
        return 0
    try:
        with urllib.request.urlopen(
            'https://auth.docker.io/token?service=registry.docker.io&scope=repository:library/nginx:pull',
            timeout=60,
        ) as response:
            if response.status != 200:
                raise RuntimeError('Registry authentication unavailable')
        print('Configured HTTPS proxy / registry authentication endpoint passed.')
        return 0
    except Exception as error:
        print(f'Proxy preflight failed: {type(error).__name__}; check local proxy and WSL relay.')
        return 1


if __name__ == '__main__':
    sys.exit(main())
