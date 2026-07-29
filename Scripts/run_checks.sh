#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

export XDG_CACHE_HOME="/tmp/freundeblick-cache"
export CLANG_MODULE_CACHE_PATH="/tmp/freundeblick-clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="/tmp/freundeblick-swift-cache"
export PYTHONPYCACHEPREFIX="/tmp/freundeblick-pycache"

cd "$PROJECT_DIR"
plutil -lint \
  "$PROJECT_DIR/Resources/Info.plist" \
  "$PROJECT_DIR/Resources/Freundeblick.entitlements"
[[ -n "$(
  /usr/libexec/PlistBuddy \
    -c "Print :NSPhotoLibraryUsageDescription" \
    "$PROJECT_DIR/Resources/Info.plist"
)" ]]
[[ "$(
  /usr/libexec/PlistBuddy \
    -c "Print :com.apple.security.personal-information.photos-library" \
    "$PROJECT_DIR/Resources/Freundeblick.entitlements"
)" == "true" ]]
swift test --disable-sandbox --scratch-path "$PROJECT_DIR/.build"
python3 -m unittest discover -s TestsPython -p "test_*.py" -q
