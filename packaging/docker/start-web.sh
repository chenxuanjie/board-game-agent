#!/bin/sh
set -eu
APP_SERVICE_UPSTREAM="${APP_SERVICE_UPSTREAM:-http://192.168.1.55:18280}"
if ! printf '%s' "$APP_SERVICE_UPSTREAM" | grep -Eq '^https?://([A-Za-z0-9.-]+|\[[0-9A-Fa-f:]+\])(:[0-9]{1,5})?$'; then
    echo 'APP_SERVICE_UPSTREAM must be an HTTP(S) origin without credentials or path.' >&2
    exit 1
fi
export APP_SERVICE_UPSTREAM
envsubst '${APP_SERVICE_UPSTREAM}' < /opt/board-game-agent/nginx.conf.template > /tmp/board-game-agent.conf
exec nginx -g 'daemon off;'
