FROM debian:bookworm-slim AS build

ARG FLUTTER_VERSION=3.47.7

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl ca-certificates git unzip xz-utils zip \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL \
        "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
        -o /tmp/flutter.tar.xz \
    && tar -xf /tmp/flutter.tar.xz -C /opt \
    && rm /tmp/flutter.tar.xz

ENV PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:${PATH}"

RUN git config --global --add safe.directory /opt/flutter \
    && flutter config --no-analytics \
    && flutter precache --web

WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .
# No service worker: an internal tool must always run the bundle that nginx
# just serves, never a copy cached by a previously installed worker. Flutter
# does not copy a worker from web/, so the stub below is written straight into
# the build output: it takes over, drops every cache and unregisters itself.
RUN flutter build web --release \
        --pwa-strategy=none \
        --dart-define=API_BASE_URL=/api \
        --dart-define=BUILD_ID=$(date -u +%Y%m%d-%H%M%S) \
    && printf '%s\n' \
        "self.addEventListener('install', () => self.skipWaiting());" \
        "self.addEventListener('fetch', () => {});" \
        "self.addEventListener('activate', (event) => {" \
        "  event.waitUntil(self.registration.unregister().then(() => self.caches.keys())" \
        "    .then((keys) => Promise.all(keys.map((key) => self.caches.delete(key)))));" \
        "});" \
        > /app/build/web/flutter_service_worker.js

FROM nginx:alpine
COPY --from=build /app/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
