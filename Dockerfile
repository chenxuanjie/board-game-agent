# Build context: parent directory containing board-game-agent and shared_packages.
FROM --platform=$BUILDPLATFORM ubuntu:22.04 AS flutter-sdk
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

FROM flutter-sdk AS dependencies
# Includes pubspecs/lockfiles of the complete path-dependency closure only.
COPY dependency-manifests/ ./
WORKDIR /workspace/board-game-agent
RUN flutter pub get --enforce-lockfile

FROM dependencies AS builder
WORKDIR /workspace
COPY shared_packages ./shared_packages
WORKDIR /workspace/board-game-agent
COPY board-game-agent/pubspec.yaml board-game-agent/pubspec.lock ./
COPY board-game-agent/lib ./lib
COPY board-game-agent/web ./web
COPY board-game-agent/assets ./assets
COPY board-game-agent/branding ./branding
COPY board-game-agent/packages ./packages
COPY board-game-agent/scripts/prepare-web-assets.py ./scripts/
RUN python3 scripts/prepare-web-assets.py pubspec.yaml --apply \
    && flutter build web --release --no-wasm-dry-run --no-web-resources-cdn --no-pub --base-href=/
COPY board-game-agent/scripts/prepare-web-layers.py ./scripts/
RUN python3 scripts/prepare-web-layers.py build/web build/web-layers

FROM nginx:1.28-alpine@sha256:a8b39bd9cf0f83869a2162827a0caf6137ddf759d50a171451b335cecc87d236 AS runtime
COPY board-game-agent/packaging/docker/nginx-main.conf /etc/nginx/nginx.conf
COPY board-game-agent/packaging/docker/nginx.conf /opt/board-game-agent/nginx.conf.template
COPY board-game-agent/packaging/docker/start-web.sh /opt/board-game-agent/start-web.sh
# Keep large, rarely changed resources independent from the application bundle.
COPY --link --from=builder /workspace/board-game-agent/build/web-layers/engine/ /usr/share/nginx/html/
COPY --link --from=builder /workspace/board-game-agent/build/web-layers/sync/ /usr/share/nginx/html/
COPY --link --from=builder /workspace/board-game-agent/build/web-layers/pdf/ /usr/share/nginx/html/
COPY --link --from=builder /workspace/board-game-agent/build/web-layers/fonts/ /usr/share/nginx/html/
COPY --link --from=builder /workspace/board-game-agent/build/web-layers/media/ /usr/share/nginx/html/
COPY --link --from=builder /workspace/board-game-agent/build/web-layers/app/ /usr/share/nginx/html/
COPY --link --from=builder /workspace/board-game-agent/build/web-layers/web-etags.map /opt/board-game-agent/web-etags.map
USER 65532:65532
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1
ENTRYPOINT ["/bin/sh", "/opt/board-game-agent/start-web.sh"]
