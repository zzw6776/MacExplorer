#!/bin/zsh
set -euo pipefail
APP_PATH="${1:?App bundle required}"
SIGNING_IDENTITY="${2:--}"
SIGN_ARGS=(--force --sign "$SIGNING_IDENTITY")
if [[ "$SIGNING_IDENTITY" == 'Developer ID Application:'* ]]; then
  SIGN_ARGS+=(--options runtime --timestamp)
elif [[ "$SIGNING_IDENTITY" != '-' && "$SIGNING_IDENTITY" != 'Mac Development: Explorer Self-Signed' ]]; then
  print -u2 'Expected Developer ID Application or the Explorer local signing identity'
  exit 1
fi
if [[ "$SIGNING_IDENTITY" == 'Mac Development: Explorer Self-Signed' && -n "${EXPLORER_LOCAL_SIGNING_SHA1:-}" ]]; then
  SIGN_ARGS=(--force --sign "$EXPLORER_LOCAL_SIGNING_SHA1")
fi
FRAMEWORK="$APP_PATH/Contents/Frameworks/Sparkle.framework"
# Sign nested code inside out. Preserve Sparkle helper entitlements.
for nested in "$FRAMEWORK"/Versions/B/XPCServices/*.xpc(N) "$FRAMEWORK/Versions/B/Updater.app" "$FRAMEWORK/Versions/B/Autoupdate" "$FRAMEWORK"; do
  codesign "${SIGN_ARGS[@]}" --preserve-metadata=entitlements "$nested"
done
codesign "${SIGN_ARGS[@]}" --entitlements "${0:A:h:h}/Support/Explorer.entitlements" "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
if [[ "$SIGNING_IDENTITY" == 'Developer ID Application:'* ]]; then
  SIGNATURE_INFO=$(codesign -dv --verbose=4 "$APP_PATH" 2>&1)
  [[ "$SIGNATURE_INFO" == *'TeamIdentifier=B5M99337GK'* ]] || { print -u2 'Unexpected signing team'; exit 1; }
elif [[ "$SIGNING_IDENTITY" == 'Mac Development: Explorer Self-Signed' ]]; then
  SIGNATURE_INFO=$(codesign -dv --verbose=4 "$APP_PATH" 2>&1)
  [[ "$SIGNATURE_INFO" == *'Authority=Mac Development: Explorer Self-Signed'* ]] || { print -u2 'Unexpected local signing authority'; exit 1; }
  REQUIREMENT=$(codesign -dr - "$APP_PATH" 2>&1)
  [[ "$REQUIREMENT" != *'cdhash '* && "$REQUIREMENT" == *'identifier "io.bquick.explorer"'* ]] || { print -u2 'Local signature does not provide a stable Explorer identity'; exit 1; }
  if [[ -n "${EXPLORER_LOCAL_SIGNING_SHA1:-}" ]]; then
    [[ "$REQUIREMENT" == *"certificate root = H\"${EXPLORER_LOCAL_SIGNING_SHA1:l}\""* ]] || { print -u2 'Development certificate differs from the fixed identity'; exit 1; }
  fi
fi
