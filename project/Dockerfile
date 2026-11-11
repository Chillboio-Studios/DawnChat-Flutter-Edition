# ============================================
# Stage 1: Build the Flutter web client
# ============================================
FROM ghcr.io/cirruslabs/flutter:stable AS builder

WORKDIR /app

# Dependencies first for layer caching
COPY pubspec.yaml pubspec.lock ./
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
