# Build context: parent directory containing board-game-agent and shared_packages.
FROM ubuntu:22.04 AS builder
ARG FLUTTER_VERSION=3.41.9
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git unzip xz-utils zip libglu1-mesa \
    && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch "${FLUTTER_VERSION}" \
    https://github.com/flutter/flutter.git /opt/flutter
ENV PATH="/opt/flutter/bin:${PATH}"
RUN flutter config --no-analytics --enable-web && flutter precache --web
WORKDIR /workspace
COPY shared_packages ./shared_packages
COPY board-game-agent ./board-game-agent
WORKDIR /workspace/board-game-agent
RUN flutter pub get && flutter build web --release --base-href=/

FROM nginx:1.28-alpine AS runtime
COPY board-game-agent/packaging/docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /workspace/board-game-agent/build/web /usr/share/nginx/html
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD wget -q -O /dev/null http://127.0.0.1/healthz || exit 1
CMD ["nginx", "-g", "daemon off;"]
