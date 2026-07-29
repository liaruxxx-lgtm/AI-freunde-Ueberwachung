#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build"
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="$DIST_DIR/Freundeblick.app"
ARCHIVE_PATH="$DIST_DIR/Freundeblick.zip"
ENTITLEMENTS="$PROJECT_DIR/Resources/Freundeblick.entitlements"

export XDG_CACHE_HOME="/tmp/freundeblick-cache"
export CLANG_MODULE_CACHE_PATH="/tmp/freundeblick-clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="/tmp/freundeblick-swift-cache"

cd "$PROJECT_DIR"
swift build \
  -c release \
  --disable-sandbox \
  --scratch-path "$BUILD_DIR"

mkdir -p "$DIST_DIR"
if [[ -e "$APP_DIR" ]]; then
  PREVIOUS_APP="$DIST_DIR/Freundeblick.previous.$(date +%Y%m%d-%H%M%S).app"
  mv "$APP_DIR" "$PREVIOUS_APP"
fi

mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
mkdir -p "$APP_DIR/Contents/Resources/Tools"

cp "$BUILD_DIR/release/Freundeblick" "$APP_DIR/Contents/MacOS/Freundeblick"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy \
  -c "Add :FreundeblickDataDirectory string $PROJECT_DIR/FreundeblickData" \
  "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/Tools/freundeblick_mcp.py" "$APP_DIR/Contents/Resources/Tools/freundeblick_mcp.py"
cp "$PROJECT_DIR/Tools/freundeblick_cli.py" "$APP_DIR/Contents/Resources/Tools/freundeblick_cli.py"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

chmod +x "$APP_DIR/Contents/MacOS/Freundeblick"
chmod 0644 "$APP_DIR/Contents/Resources/Tools/freundeblick_mcp.py"
chmod 0644 "$APP_DIR/Contents/Resources/Tools/freundeblick_cli.py"

SIGNED=0
for _ in 1 2 3 4 5; do
  xattr -cr "$APP_DIR"
  xattr -d com.apple.FinderInfo "$APP_DIR" 2>/dev/null || true
  xattr -d "com.apple.fileprovider.fpfs#P" "$APP_DIR" 2>/dev/null || true
  if codesign \
    --force \
    --deep \
    --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign - \
    "$APP_DIR"; then
    SIGNED=1
    break
  fi
done
if [[ "$SIGNED" -ne 1 ]]; then
  xattr -cr "$APP_DIR"
  codesign \
    --force \
    --deep \
    --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign - \
    "$APP_DIR"
fi

# The Documents/FileProvider volume may immediately restore Finder metadata on
# the bundle root. Publish an attribute-free ZIP and verify a clean extraction,
# so the delivered app has a reproducible, strict-valid signature.
if [[ -e "$ARCHIVE_PATH" ]]; then
  PREVIOUS_ARCHIVE="$DIST_DIR/Freundeblick.previous.$(date +%Y%m%d-%H%M%S).zip"
  mv "$ARCHIVE_PATH" "$PREVIOUS_ARCHIVE"
fi

ditto \
  --norsrc \
  --noextattr \
  --noqtn \
  --noacl \
  -c \
  -k \
  --keepParent \
  "$APP_DIR" \
  "$ARCHIVE_PATH"

VERIFY_DIRECTORY="$(mktemp -d /tmp/freundeblick-package.XXXXXX)"
trap 'rm -rf "$VERIFY_DIRECTORY"' EXIT
ditto -x -k "$ARCHIVE_PATH" "$VERIFY_DIRECTORY"
codesign \
  --verify \
  --deep \
  --strict \
  "$VERIFY_DIRECTORY/Freundeblick.app"

echo "$ARCHIVE_PATH"
