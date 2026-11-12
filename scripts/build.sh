#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="${0:A:h:h}"
cd "$PROJECT_ROOT"
export CLANG_MODULE_CACHE_PATH="$PROJECT_ROOT/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_ROOT/.build/module-cache"

# Some macOS Command Line Tools releases ship a current ManifestAPI library
# alongside a stale private PackageDescription interface. SwiftPM prefers that
# private interface and fails before it can build the package. Use a project-
# local copy without the stale interface when this exact mismatch is present.
SWIFT_EXECUTABLE=$(xcrun --find swift)
MANIFEST_API="${SWIFT_EXECUTABLE:h:h}/lib/swift/pm/ManifestAPI"
PRIVATE_INTERFACE="$MANIFEST_API/PackageDescription.swiftmodule/arm64-apple-macos.private.swiftinterface"
PUBLIC_INTERFACE="$MANIFEST_API/PackageDescription.swiftmodule/arm64-apple-macos.swiftinterface"
if [[ -f "$PRIVATE_INTERFACE" && -f "$PUBLIC_INTERFACE" ]] \
   && ! grep -q 'swiftLanguageModes' "$PRIVATE_INTERFACE" \
   && grep -q 'swiftLanguageModes' "$PUBLIC_INTERFACE"; then
  FIXED_SWIFTPM_LIBS="$PROJECT_ROOT/.build/fixed-swiftpm-libs"
  if [[ ! -f "$FIXED_SWIFTPM_LIBS/ManifestAPI/libPackageDescription.dylib" ]]; then
    mkdir -p "$FIXED_SWIFTPM_LIBS/ManifestAPI/stale-private-interfaces"
    cp -R "$MANIFEST_API/." "$FIXED_SWIFTPM_LIBS/ManifestAPI/"
    mv "$FIXED_SWIFTPM_LIBS"/ManifestAPI/PackageDescription.swiftmodule/*private.swiftinterface \
       "$FIXED_SWIFTPM_LIBS/ManifestAPI/stale-private-interfaces/"
  fi
  export SWIFTPM_CUSTOM_LIBS_DIR="$FIXED_SWIFTPM_LIBS"
fi
RELEASE_BUILD=0
UNIVERSAL_BUILD=0
for arg in "$@"; do
  case "$arg" in
    --release) RELEASE_BUILD=1 ;;
    --universal) UNIVERSAL_BUILD=1 ;;
    *) print -u2 "Unknown option: $arg"; exit 2 ;;
  esac
done
if (( RELEASE_BUILD )); then
  : "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION to your Developer ID Application identity}"
fi
BUILD_ARGS=(-c release --build-system native -debug-info-format none --disable-sandbox --cache-path "$PROJECT_ROOT/.build/cache" --config-path "$PROJECT_ROOT/.build/config" --security-path "$PROJECT_ROOT/.build/security")
if (( UNIVERSAL_BUILD )); then BUILD_ARGS+=(--arch arm64 --arch x86_64); fi
swift build "${BUILD_ARGS[@]}"
BIN_PATH=$(swift build "${BUILD_ARGS[@]}" --show-bin-path)
SPARKLE_ROOT="$PROJECT_ROOT/.build/artifacts/sparkle/Sparkle"
FRAMEWORK="$SPARKLE_ROOT/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[[ -d "$FRAMEWORK" ]] || { print -u2 'Sparkle framework is missing'; exit 1; }
STAGING_ROOT=$(mktemp -d "$PROJECT_ROOT/.build/app-staging.XXXXXX")
trap 'rm -rf "$STAGING_ROOT"' EXIT
APP_STAGE="$STAGING_ROOT/Explorer.app"
mkdir -p "$APP_STAGE/Contents/MacOS" "$APP_STAGE/Contents/Resources" "$APP_STAGE/Contents/Frameworks"
cp "$BIN_PATH/Explorer" "$APP_STAGE/Contents/MacOS/Explorer"
cp Support/Info.plist "$APP_STAGE/Contents/Info.plist"
ditto "$FRAMEWORK" "$APP_STAGE/Contents/Frameworks/Sparkle.framework"
for RESOURCE_BUNDLE in "$BIN_PATH"/*.bundle; do
  [[ -d "$RESOURCE_BUNDLE" ]] || continue
  ditto "$RESOURCE_BUNDLE" "$APP_STAGE/Contents/Resources/${RESOURCE_BUNDLE:t}"
done
if [[ ! -f .build/AppIcon.icns || scripts/generate-icon.swift -nt .build/AppIcon.icns ]]; then
  swift -module-cache-path "$PROJECT_ROOT/.build/module-cache" scripts/generate-icon.swift "$PROJECT_ROOT/.build/AppIcon.iconset"
fi
cp .build/AppIcon.icns "$APP_STAGE/Contents/Resources/AppIcon.icns"
cp LICENSE "$APP_STAGE/Contents/Resources/LICENSE.txt"
ditto Support/Licenses "$APP_STAGE/Contents/Resources/Licenses"
if (( RELEASE_BUILD )); then
  plutil -replace ExplorerUpdatesEnabled -bool YES "$APP_STAGE/Contents/Info.plist"
  zsh scripts/sign-app.sh "$APP_STAGE" "$DEVELOPER_ID_APPLICATION"
  APP_PATH="$PROJECT_ROOT/build/release/Explorer.app"
else
  plutil -replace ExplorerDevelopmentBuild -bool YES "$APP_STAGE/Contents/Info.plist"
  LOCAL_SIGNING_IDENTITY="${EXPLORER_LOCAL_SIGNING_IDENTITY:-Mac Development: Explorer Self-Signed}"
  if [[ "$LOCAL_SIGNING_IDENTITY" == '-' ]] || security find-identity -v -p codesigning | grep -Fq "\"$LOCAL_SIGNING_IDENTITY\""; then
    zsh scripts/sign-app.sh "$APP_STAGE" "$LOCAL_SIGNING_IDENTITY"
  else
    print -u2 "Missing stable signing identity: $LOCAL_SIGNING_IDENTITY"
    print -u2 'Run: zsh scripts/create-local-signing-identity.sh'
    exit 1
  fi
  APP_PATH="$PROJECT_ROOT/build/Explorer.app"
fi
if (( UNIVERSAL_BUILD )); then
  ARCHS=" $(lipo -archs "$APP_STAGE/Contents/MacOS/Explorer") "
  [[ "$ARCHS" == *' arm64 '* && "$ARCHS" == *' x86_64 '* ]] || { print -u2 'Universal build is missing an architecture'; exit 1; }
fi
mkdir -p "${APP_PATH:h}"
if [[ -e "$APP_PATH" ]]; then mv "$APP_PATH" "$STAGING_ROOT/previous.app"; fi
mv "$APP_STAGE" "$APP_PATH"
printf 'Built: %s\n' "$APP_PATH"
