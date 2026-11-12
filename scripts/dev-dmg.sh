#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="${0:A:h:h}"
cd "$PROJECT_ROOT"
for arg in "$@"; do
  [[ "$arg" == '--universal' ]] || { print -u2 "Unknown development DMG option: $arg"; exit 2; }
done
SIGNING_IDENTITY="${EXPLORER_LOCAL_SIGNING_IDENTITY:-Mac Development: Explorer Self-Signed}"
[[ "$SIGNING_IDENTITY" != '-' ]] || { print -u2 'Downloadable DMGs require the fixed development signing identity'; exit 1; }
zsh scripts/build.sh "$@"

WORK=$(mktemp -d "$PROJECT_ROOT/.build/dev-dmg.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
OUTPUT="$PROJECT_ROOT/build/dmg"
VERSION=$(plutil -extract CFBundleShortVersionString raw build/Explorer.app/Contents/Info.plist)
REVISION="${GITHUB_SHA:-$(git rev-parse HEAD)}"
DMG_NAME="MacExplorer-$VERSION-dev-${REVISION[1,7]}.dmg"
mkdir -p "$WORK/disk" "$OUTPUT"
ditto build/Explorer.app "$WORK/disk/Explorer.app"
ln -s /Applications "$WORK/disk/Applications"
hdiutil create -volname Explorer -srcfolder "$WORK/disk" -format UDZO -ov "$OUTPUT/$DMG_NAME"
codesign --force --sign "${EXPLORER_LOCAL_SIGNING_SHA1:-$SIGNING_IDENTITY}" "$OUTPUT/$DMG_NAME"
codesign --verify --strict "$OUTPUT/$DMG_NAME"
(cd "$OUTPUT" && shasum -a 256 "$DMG_NAME" > checksums.txt)
printf 'DMG: %s\n' "$OUTPUT/$DMG_NAME"
