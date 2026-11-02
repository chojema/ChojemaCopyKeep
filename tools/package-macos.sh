#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/build/macos/Chojema CopyKeep.app"
DIST_DIR="$ROOT_DIR/dist/macos-v0.1.3"
STAGE_DIR="$DIST_DIR/package"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")" = "0.1.3"
ARCHS="$(xcrun lipo -archs "$APP_BUNDLE/Contents/MacOS/ChojemaCopyKeep")"
[[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]]
codesign --verify --deep --strict "$APP_BUNDLE"
mkdir -p "$STAGE_DIR/docs"
ditto "$APP_BUNDLE" "$STAGE_DIR/Chojema CopyKeep.app"
cp "$ROOT_DIR/README.md" "$ROOT_DIR/README.en.md" "$STAGE_DIR/"
cp "$ROOT_DIR/docs/BUILD.ko.md" "$ROOT_DIR/docs/BUILD.en.md" \
  "$ROOT_DIR/docs/PRIVACY.ko.md" "$ROOT_DIR/docs/PRIVACY.en.md" "$STAGE_DIR/docs/"
ditto -c -k --keepParent --norsrc "$STAGE_DIR" "$DIST_DIR/ChojemaCopyKeep-macos-universal-0.1.3.zip"
cd "$DIST_DIR"
shasum -a 256 ChojemaCopyKeep-macos-universal-0.1.3.zip > SHA256SUMS-macos.txt
echo "$DIST_DIR/ChojemaCopyKeep-macos-universal-0.1.3.zip"
