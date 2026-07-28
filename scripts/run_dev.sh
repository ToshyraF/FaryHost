#!/usr/bin/env bash
# Starts the Go backend, then runs the Flutter app against it. Run this from
# a machine with both the Go and Flutter/Dart SDKs installed (this repo's
# sandbox has neither — see backend/README.md and app/README.md).
#
# Usage: scripts/run_dev.sh [flutter run args...]
#   scripts/run_dev.sh                # launch on whatever device flutter picks
#   scripts/run_dev.sh -d chrome      # launch in Chrome
#   scripts/run_dev.sh -d emulator-5554
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/backend"
APP_DIR="$ROOT_DIR/app"
ADDR="${ADDR:-:8080}"
HEALTH_URL="http://localhost${ADDR}/api/vendors"

echo "==> Starting backend on $ADDR"
(cd "$BACKEND_DIR" && ADDR="$ADDR" go run ./cmd/api) &
BACKEND_PID=$!
trap 'echo "==> Stopping backend (pid $BACKEND_PID)"; kill "$BACKEND_PID" 2>/dev/null || true' EXIT

echo "==> Waiting for backend to come up..."
for _ in $(seq 1 30); do
  if curl -sf "$HEALTH_URL" > /dev/null; then
    echo "==> Backend is up at http://localhost${ADDR}"
    break
  fi
  sleep 1
done

if [ ! -d "$APP_DIR/android" ] && [ ! -d "$APP_DIR/ios" ] && [ ! -d "$APP_DIR/web" ]; then
  echo "==> No platform folders yet, running flutter create ."
  (cd "$APP_DIR" && flutter create . --project-name faryhost_app)
fi

echo "==> flutter pub get"
(cd "$APP_DIR" && flutter pub get)

echo "==> flutter run $*"
echo "    Targeting the Android emulator? localhost inside it is the emulator"
echo "    itself, not your machine — pass baseUrl: 'http://10.0.2.2:8080/api'"
echo "    to the ApiClient() call in app/lib/main.dart first."
(cd "$APP_DIR" && flutter run "$@")
