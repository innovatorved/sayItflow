#!/usr/bin/env bash
# Build SayItFlow.dmg — SayItFlow installer (Desert Ant Voz ANE STT)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME=SayItFlow
CONFIG=Release
DERIVED="${HOME}/Library/Developer/Xcode/DerivedData"
STAGING="$ROOT/build/dmg-staging"
DMG="$ROOT/build/SayItFlow.dmg"

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "ERROR: Full Xcode required." >&2
  exit 1
fi

echo "==> Build SayItFlow.app"
cd "$ROOT/apps/macos"
xcodebuild -scheme "$SCHEME" -configuration "$CONFIG" -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build

APP="$(find "$DERIVED" -path "*/Build/Products/$CONFIG/SayItFlow.app" -type d 2>/dev/null | head -1)"
if [[ -z "$APP" ]]; then
  echo "ERROR: SayItFlow.app not found after build" >&2
  exit 1
fi

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  echo "==> Code sign (SIGN_IDENTITY set)"
  chmod +x "$ROOT/scripts/codesign-app.sh"
  NOTARIZE="${NOTARIZE:-0}" "$ROOT/scripts/codesign-app.sh" "$APP"
else
  echo "==> Ad-hoc sign app"
  codesign --force --deep --sign - "$APP"
  codesign --verify --deep --strict "$APP"
fi

echo "==> Create DMG"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/SayItFlow.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "SayItFlow" -srcfolder "$STAGING" -ov -format UDZO "$DMG"

echo ""
echo "Done: $DMG"
echo "Install: open DMG → drag to Applications → launch SayItFlow"
