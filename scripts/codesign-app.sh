#!/usr/bin/env bash
# Sign SayItFlow.app and nested Python engine binaries for Gatekeeper/notarization.
set -euo pipefail

APP="${1:?Usage: codesign-app.sh /path/to/SayItFlow.app}"
IDENTITY="${SIGN_IDENTITY:?Set SIGN_IDENTITY to your Developer ID Application certificate name}"

ENTITLEMENTS="${ENTITLEMENTS:-$(dirname "$0")/../apps/macos/SayItFlow/SayItFlow.entitlements}"

echo "==> Signing nested engine binaries"
ENGINE="$APP/Contents/Resources/engine"
if [[ -d "$ENGINE" ]]; then
  while IFS= read -r -d '' bin; do
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$bin"
  done < <(find "$ENGINE" -type f \( -perm -111 -o -name '*.so' -o -name '*.dylib' \) -print0 2>/dev/null || true)
  if [[ -x "$ENGINE/.venv/bin/python" ]]; then
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$ENGINE/.venv/bin/python"
  fi
fi

echo "==> Signing app bundle"
if [[ -f "$ENTITLEMENTS" ]]; then
  codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
else
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi

codesign --verify --deep --strict --verbose=2 "$APP"
echo "Signed: $APP"

if [[ "${NOTARIZE:-0}" == "1" ]]; then
  : "${NOTARY_APPLE_ID:?Set NOTARY_APPLE_ID}"
  : "${NOTARY_TEAM_ID:?Set NOTARY_TEAM_ID}"
  : "${NOTARY_PASSWORD:?Set NOTARY_PASSWORD (app-specific password)}"
  ZIP="$(mktemp -t sayitflow-notarize).zip"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "==> Submitting for notarization"
  xcrun notarytool submit "$ZIP" \
    --apple-id "$NOTARY_APPLE_ID" \
    --team-id "$NOTARY_TEAM_ID" \
    --password "$NOTARY_PASSWORD" \
    --wait
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
  echo "Notarized and stapled: $APP"
fi
