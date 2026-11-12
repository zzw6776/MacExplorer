#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
BUILT_APP="$PROJECT_ROOT/build/Explorer.app"
INSTALLED_APP="/Applications/Explorer.app"
IDENTITY="${EXPLORER_LOCAL_SIGNING_IDENTITY:-Mac Development: Explorer Self-Signed}"

if ! security find-identity -v -p codesigning | grep -Fq "\"$IDENTITY\""; then
  zsh "$PROJECT_ROOT/scripts/create-local-signing-identity.sh"
fi

for executable in "$BUILT_APP/Contents/MacOS/Explorer" "$INSTALLED_APP/Contents/MacOS/Explorer"; do
  for pid in ${(f)"$(pgrep -f -- "$executable" || true)"}; do
    [[ -n "$pid" ]] && kill -TERM "$pid"
  done
done

zsh "$PROJECT_ROOT/scripts/build.sh"

STAGING_ROOT=$(mktemp -d "/Applications/.Explorer-dev.XXXXXX")
trap 'rm -rf "$STAGING_ROOT"' EXIT
ditto "$BUILT_APP" "$STAGING_ROOT/Explorer.app"
if [[ -e "$INSTALLED_APP" ]]; then
  mv "$INSTALLED_APP" "$STAGING_ROOT/previous.app"
fi
mv "$STAGING_ROOT/Explorer.app" "$INSTALLED_APP"
open "$INSTALLED_APP"
