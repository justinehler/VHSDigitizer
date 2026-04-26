#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/.build/VHS Digitizer.app"
BIN="$ROOT/.build/release/VHSDigitizer"

cd "$ROOT"
swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/VHSDigitizer"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"

codesign --force --deep --sign - "$APP"

echo "$APP"
