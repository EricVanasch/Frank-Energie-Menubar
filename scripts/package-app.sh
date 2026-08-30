#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="arm64"
BUILD_DIR="$ROOT_DIR/.build/arm64-apple-macosx/release"
APP_DIR="$ROOT_DIR/dist/EPEX MenuBar.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

swift build -c release --arch "$ARCH" --package-path "$ROOT_DIR"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BUILD_DIR/EpexMenuBar" "$MACOS_DIR/EpexMenuBar"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Resources/FrankEnergyIcon.icns" "$RESOURCES_DIR/FrankEnergyIcon.icns"

if ! lipo -archs "$MACOS_DIR/EpexMenuBar" | grep -q "$ARCH"; then
  echo "Expected $ARCH binary, got: $(lipo -archs "$MACOS_DIR/EpexMenuBar")" >&2
  exit 1
fi

codesign --force --deep --sign - "$APP_DIR"

echo "$APP_DIR"
