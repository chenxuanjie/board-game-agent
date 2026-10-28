# Build context: parent directory containing board-game-agent and shared_packages.
FROM --platform=$BUILDPLATFORM ubuntu:22.04 AS builder
ARG FLUTTER_VERSION=3.41.9
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git unzip xz-utils zip libglu1-mesa python3 \
    && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch "${FLUTTER_VERSION}" \
    https://github.com/flutter/flutter.git /opt/flutter
ENV PATH="/opt/flutter/bin:${PATH}"
# Match the existing lockfile's package source; do not silently re-resolve it
# against another registry while producing a release.
ENV PUB_HOSTED_URL=https://pub.flutter-io.cn
RUN flutter config --no-analytics --enable-web && flutter precache --web
WORKDIR /workspace
COPY shared_packages ./shared_packages
COPY board-game-agent ./board-game-agent
WORKDIR /workspace/board-game-agent
RUN python3 scripts/prepare-web-assets.py pubspec.yaml --apply \
    && flutter pub get --enforce-lockfile && flutter build web --release --no-wasm-dry-run --no-pub --base-href=/

FROM nginx:1.28-alpine AS runtime
COPY board-game-agent/packaging/docker/nginx-main.conf /etc/nginx/nginx.conf
COPY board-game-agent/packaging/docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /workspace/board-game-agent/build/web /usr/share/nginx/html
USER 65532:65532
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1
ENTRYPOINT ["nginx"]
CMD ["-g", "daemon off;"]
