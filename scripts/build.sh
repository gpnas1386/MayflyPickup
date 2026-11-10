#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
which xcodegen >/dev/null 2>&1 || brew install xcodegen
xcodegen generate

SCHEME=MayflyPickup
BUILD_DIR="$PWD/build"
rm -rf "$BUILD_DIR"; mkdir -p "$BUILD_DIR"

xcodebuild -project MayflyPickup.xcodeproj -scheme "$SCHEME" -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath "$BUILD_DIR/dd" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  ENABLE_BITCODE=NO clean build | tee "$BUILD_DIR/build.log" | tail -40

APP="$BUILD_DIR/dd/Build/Products/Release-iphoneos/MayflyPickup.app"
test -d "$APP"

if command -v ldid >/dev/null 2>&1; then
  ldid -SSources/App/App.entitlements "$APP/MayflyPickup" || true
  for ext in "$APP"/PlugIns/*.appex; do
    [ -d "$ext" ] || continue
    name=$(basename "$ext" .appex)
    ldid -SSources/Widget/Widget.entitlements "$ext/$name" || true
  done
fi

rm -rf "$BUILD_DIR/Payload"; mkdir -p "$BUILD_DIR/Payload"
cp -R "$APP" "$BUILD_DIR/Payload/"
cd "$BUILD_DIR" && zip -qry MayflyPickup-1.3.0.ipa Payload
echo "IPA: $BUILD_DIR/MayflyPickup-1.3.0.ipa"
