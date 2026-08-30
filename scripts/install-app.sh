#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_APP="$ROOT_DIR/dist/EPEX MenuBar.app"
TARGET_APP="/Applications/Frank Energie Tarieven.app"

if [[ ! -d "$SOURCE_APP" ]]; then
  "$ROOT_DIR/scripts/package-app.sh"
fi

rm -rf "$TARGET_APP"
ditto "$SOURCE_APP" "$TARGET_APP"
codesign --force --deep --sign - "$TARGET_APP"

echo "$TARGET_APP"
