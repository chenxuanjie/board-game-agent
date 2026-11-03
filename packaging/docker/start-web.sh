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
envsubst '${APP_SERVICE_UPSTREAM} ${LIBRARY_ACCELERATION}' < /opt/board-game-agent/nginx.conf.template > /tmp/board-game-agent.conf
exec nginx -g 'daemon off;'
