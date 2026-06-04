#!/usr/bin/env bash
set -euo pipefail

APP_BUNDLE=${1:?usage: build-dmg.sh <app-bundle> <output-dmg> [volume-name]}
OUTPUT_DMG=${2:?usage: build-dmg.sh <app-bundle> <output-dmg> [volume-name]}
VOLUME_NAME=${3:-OKXMenuBar}

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "App bundle not found: $APP_BUNDLE" >&2
  exit 1
fi

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/okx-menubar-dmg.XXXXXX")
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

STAGING_DIR="$TMP_DIR/root"
mkdir -p "$STAGING_DIR"
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
cat > "$STAGING_DIR/How to install.txt" <<'TXT'
1. Drag OKXMenuBar.app into Applications.
2. Launch the app from Applications.
3. If macOS warns that the app is from an unidentified developer, right click the app and choose Open.
TXT

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$STAGING_DIR/$(basename "$APP_BUNDLE")" >/dev/null 2>&1 || true
fi

mkdir -p "$(dirname "$OUTPUT_DMG")"
rm -f "$OUTPUT_DMG"
hdiutil create -volname "$VOLUME_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$OUTPUT_DMG" >/dev/null

echo "Built $OUTPUT_DMG"
