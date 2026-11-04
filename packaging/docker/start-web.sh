#!/bin/sh
set -eu
APP_SERVICE_UPSTREAM="${APP_SERVICE_UPSTREAM:-http://192.168.1.55:18280}"
if ! printf '%s' "$APP_SERVICE_UPSTREAM" | grep -Eq '^https?://([A-Za-z0-9.-]+|\[[0-9A-Fa-f:]+\])(:[0-9]{1,5})?$'; then
    echo 'APP_SERVICE_UPSTREAM must be an HTTP(S) origin without credentials or path.' >&2
    exit 1
fi
export APP_SERVICE_UPSTREAM
LIBRARY_ACCELERATION="${LIBRARY_ACCELERATION:-0}"
case "$LIBRARY_ACCELERATION" in 0|1) ;; *) echo 'LIBRARY_ACCELERATION must be 0 or 1.' >&2; exit 1 ;; esac
if [ "$LIBRARY_ACCELERATION" = 1 ] && [ ! -d /data/board-library/blobs ]; then
    echo 'NAS acceleration requires the existing library store mounted read-only.' >&2
    exit 1
fi
export LIBRARY_ACCELERATION

# Only explicitly configured ingress peers may supply a forwarded client IP.
set -f
printf '%s\n' 'real_ip_header X-Forwarded-For;' 'real_ip_recursive on;' > /tmp/bga-trusted-proxies.conf
proxy_count=0
proxy_ifs=$IFS
IFS=,
for proxy in ${BGA_TRUSTED_PROXIES:-}; do
    case "$proxy" in ''|*[!0-9a-fA-F:./]*) echo 'BGA_TRUSTED_PROXIES requires numeric IPs/CIDRs.' >&2; exit 1;; esac
    case "$proxy" in *:*) ;; *[!0-9./]*) echo 'Proxy hostnames are not allowed.' >&2; exit 1;; esac
    case "$proxy" in */*)
        prefix=${proxy##*/}
        case "$prefix" in ''|*[!0-9]*) echo 'Invalid proxy CIDR prefix.' >&2; exit 1;; esac
        if [ "$prefix" -eq 0 ]; then echo 'Trust specific proxies, never all addresses.' >&2; exit 1; fi;;
    esac
    proxy_count=$((proxy_count + 1))
    if [ "$proxy_count" -gt 32 ]; then echo 'Too many trusted proxies.' >&2; exit 1; fi
    printf 'set_real_ip_from %s;\n' "$proxy" >> /tmp/bga-trusted-proxies.conf
done
IFS=$proxy_ifs
envsubst '${APP_SERVICE_UPSTREAM} ${LIBRARY_ACCELERATION}' < /opt/board-game-agent/nginx.conf.template > /tmp/board-game-agent.conf
exec nginx -g 'daemon off;'
