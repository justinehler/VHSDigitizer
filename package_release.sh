#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/.build/VHS Digitizer.app"
DIST="$ROOT/.build/dist"
ZIP="$DIST/VHS-Digitizer-macOS.zip"

cd "$ROOT"
"$ROOT/build_app.sh" >/dev/null

rm -rf "$DIST"
mkdir -p "$DIST"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "$ZIP"
