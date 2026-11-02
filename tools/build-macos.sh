#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-universal}"
BUILD_DIR="$ROOT_DIR/build/macos"
APP_BUNDLE="$BUILD_DIR/Chojema CopyKeep.app"
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_DIR/module-cache"
mkdir -p "$BUILD_DIR"
case "$MODE" in
  test)
    swift test --disable-xctest --enable-swift-testing --cache-path "$BUILD_DIR/cache" --config-path "$BUILD_DIR/config" --security-path "$BUILD_DIR/security" --manifest-cache local --package-path "$ROOT_DIR/macos" --scratch-path "$BUILD_DIR/swift" --disable-sandbox
    exit
    ;;
  native) ARCHS=("$(uname -m)") ;;
  universal) ARCHS=(arm64 x86_64) ;;
  *) echo "Usage: $0 [universal|native|test]" >&2; exit 2 ;;
esac
BINARIES=()
for ARCH in "${ARCHS[@]}"; do
  TRIPLE="$ARCH-apple-macosx13.0"
  swift build --cache-path "$BUILD_DIR/cache" --config-path "$BUILD_DIR/config" --security-path "$BUILD_DIR/security" --manifest-cache local --package-path "$ROOT_DIR/macos" --scratch-path "$BUILD_DIR/$ARCH" \
    --disable-sandbox --configuration release --triple "$TRIPLE"
  BIN_DIR="$(swift build --cache-path "$BUILD_DIR/cache" --config-path "$BUILD_DIR/config" --security-path "$BUILD_DIR/security" --manifest-cache local --package-path "$ROOT_DIR/macos" --scratch-path "$BUILD_DIR/$ARCH" \
    --disable-sandbox --configuration release --triple "$TRIPLE" --show-bin-path)"
  BINARIES+=("$BIN_DIR/ChojemaCopyKeep")
done
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
if [[ "${#BINARIES[@]}" == 2 ]]; then
  xcrun lipo -create "${BINARIES[@]}" -output "$APP_BUNDLE/Contents/MacOS/ChojemaCopyKeep"
else
  cp "${BINARIES[0]}" "$APP_BUNDLE/Contents/MacOS/ChojemaCopyKeep"
fi
cp "$ROOT_DIR/macos/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
# SwiftPM locates its resource bundle alongside the executable or in Resources.
RESOURCE_BUNDLE="$BIN_DIR/ChojemaCopyKeep_CopyKeep.bundle"
test -d "$RESOURCE_BUNDLE"
ditto "$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/ChojemaCopyKeep_CopyKeep.bundle"
chmod 755 "$APP_BUNDLE/Contents/MacOS/ChojemaCopyKeep"
codesign --force --sign - --timestamp=none "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"
plutil -lint "$APP_BUNDLE/Contents/Info.plist"
xcrun lipo -archs "$APP_BUNDLE/Contents/MacOS/ChojemaCopyKeep"
echo "$APP_BUNDLE"
