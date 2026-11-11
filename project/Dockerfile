# ============================================
# Stage 1: Build the Flutter web client
# ============================================
FROM debian:bookworm-slim AS builder

# Flutter toolchain + the GTK/X11 stack the cnativeapi (tray_manager)
# native-assets hook needs even for `flutter pub get` on Linux — same
# package set the GitHub workflow installs on ubuntu-latest.
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash curl ca-certificates git unzip zip xz-utils file \
    clang cmake ninja-build pkg-config \
    libgtk-3-dev libx11-dev libxi-dev libxext-dev libxfixes-dev libxrandr-dev \
    libxrender-dev libxcursor-dev libxdamage-dev libxtst-dev libxss-dev \
    libxcb1-dev libasound2-dev libsecret-1-dev libayatana-appindicator3-dev \
    libcurl4-openssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Pinned to match CI (FLUTTER_VERSION in .github/workflows/build.yml) —
# pubspec requires Dart ^3.13.7.
ARG FLUTTER_VERSION=3.47.9
RUN curl -fsSL \
    "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    | tar -xJ -C /opt
ENV PATH="/opt/flutter/bin:${PATH}" FLUTTER_ROOT=/opt/flutter
# The tarball preserves archive uids, so git flags /opt/flutter as
# "dubious ownership" when the flutter tool shells out to it.
RUN git config --global --add safe.directory /opt/flutter

WORKDIR /app

# Dependencies first for layer caching. rust_builder is a path
# dependency, so its pubspec must exist for version solving.
COPY pubspec.yaml pubspec.lock ./
COPY rust_builder/pubspec.yaml rust_builder/pubspec.yaml
RUN flutter pub get

COPY . .

# Optional build-time configuration (same dart-defines the CI uses).
# Web-specific *_WEB variants take precedence inside the app when set.
ARG KLIPY_API_KEY=""
ARG FIREBASE_API_KEY=""
ARG FIREBASE_API_KEY_WEB=""
ARG FIREBASE_APP_ID=""
ARG FIREBASE_APP_ID_WEB=""
ARG FIREBASE_SENDER_ID=""
ARG FIREBASE_PROJECT_ID=""

RUN flutter build web --release \
    --pwa-strategy=none \
    --no-wasm-dry-run \
    --dart-define=KLIPY_API_KEY=${KLIPY_API_KEY} \
    --dart-define=FIREBASE_API_KEY=${FIREBASE_API_KEY} \
    --dart-define=FIREBASE_API_KEY_WEB=${FIREBASE_API_KEY_WEB} \
    --dart-define=FIREBASE_APP_ID=${FIREBASE_APP_ID} \
    --dart-define=FIREBASE_APP_ID_WEB=${FIREBASE_APP_ID_WEB} \
    --dart-define=FIREBASE_SENDER_ID=${FIREBASE_SENDER_ID} \
    --dart-define=FIREBASE_PROJECT_ID=${FIREBASE_PROJECT_ID}

# ============================================
# Stage 2: Serve static assets
# ============================================
FROM nginx:1.27-alpine

COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/build/web /usr/share/nginx/html

EXPOSE 5000
