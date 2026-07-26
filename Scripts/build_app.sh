#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build"
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="$DIST_DIR/Freundeblick.app"

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
mkdir -p "$APP_DIR/Contents/Helpers"

cp "$BUILD_DIR/release/Freundeblick" "$APP_DIR/Contents/MacOS/Freundeblick"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy \
  -c "Add :FreundeblickDataDirectory string $PROJECT_DIR/FreundeblickData" \
  "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/Tools/freundeblick_mcp.py" "$APP_DIR/Contents/Helpers/freundeblick_mcp.py"
cp "$PROJECT_DIR/Tools/freundeblick_cli.py" "$APP_DIR/Contents/Helpers/freundeblick_cli.py"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

chmod +x "$APP_DIR/Contents/MacOS/Freundeblick"
chmod +x "$APP_DIR/Contents/Helpers/freundeblick_mcp.py"
chmod +x "$APP_DIR/Contents/Helpers/freundeblick_cli.py"

xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"

# Some Documents/FileProvider volumes can re-add their bookkeeping attributes
# immediately after signing. Clear only those harmless root attributes and retry
# verification without touching any bundle contents.
VERIFIED=0
for _ in 1 2 3; do
  xattr -d com.apple.FinderInfo "$APP_DIR" 2>/dev/null || true
  xattr -d "com.apple.fileprovider.fpfs#P" "$APP_DIR" 2>/dev/null || true
  if codesign --verify --deep --strict "$APP_DIR" 2>/dev/null; then
    VERIFIED=1
    break
  fi
done
if [[ "$VERIFIED" -ne 1 ]]; then
  codesign --verify --deep --strict "$APP_DIR"
fi
echo "$APP_DIR"
