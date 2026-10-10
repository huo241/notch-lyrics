#!/bin/bash
#
# Build a Notch Lyrics release and refresh updater/appcast.xml.
#
# Usage:
#   ./scripts/release.sh                 # version from MARKETING_VERSION
#   ./scripts/release.sh 2.9.0           # explicit version
#
# What it does:
#   1. Builds the Release configuration (ad-hoc signed, no Apple certificate).
#   2. Zips "Notch Lyrics.app" with ditto (the format Sparkle expects). The
#      archive is named NotchLyrics-<version>.zip: GitHub rewrites spaces in
#      asset names to dots, which would silently break the appcast URL.
#   3. Builds a styled DMG for people who would rather drag the app across.
#   4. Re-runs Sparkle's generate_appcast so the new build is signed with this
#      project's EdDSA key and appended to the feed.
#   5. Copies the refreshed appcast back into updater/appcast.xml.
#   6. Copies the zip and the DMG to ./dist/ so they are easy to attach to a
#      GitHub Release.
#
# What it does NOT do:
#   - Upload anything. Publishing is a separate, explicit step.
#
# After it finishes, publish with:
#   gh release create v<version> "dist/Notch Lyrics <version>.zip" \
#       "dist/NotchLyrics-<version>.dmg" --title "Notch Lyrics <version>"
#   git add updater/appcast.xml && git commit -m "Release <version>" && git push
#
# The appcast is served from
#   https://raw.githubusercontent.com/huo241/notch-lyrics/main/updater/appcast.xml
# which is what SUFeedURL in NotchLyrics/Info.plist points at, so the feed only
# goes live once updater/appcast.xml is pushed to main.

set -euo pipefail

# --------------------------------------------------------- build sandbox ---
# xcodebuild runs parts of its own build inside nested sandboxes: evaluating
# package manifests, hosting the macro plugin server, and running script
# phases. macOS does not allow creating a sandbox from inside another one, so
# every one of those steps dies with
#
#     sandbox-exec: sandbox_apply: Operation not permitted
#
# whenever xcodebuild is launched from an already-sandboxed process (an agent,
# a container, some CI runners). The three settings below switch that nested
# sandboxing off. They change how the build is executed, not what is built.
# An ordinary Xcode or Finder build never needs them; set
# NOTCHLYRICS_KEEP_BUILD_SANDBOX=1 to leave them out.
SANDBOX_ARGS=()
if [[ "${NOTCHLYRICS_KEEP_BUILD_SANDBOX:-0}" != "1" ]]; then
    export XBS_DISABLE_SANDBOXED_BUILDS=YES
    defaults write com.apple.dt.Xcode IDEPackageSupportDisableManifestSandbox -bool YES 2>/dev/null || true
    SANDBOX_ARGS=(
        OTHER_SWIFT_FLAGS='$(inherited) -Xfrontend -disable-sandbox'
        ENABLE_USER_SCRIPT_SANDBOXING=NO
    )
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PROJECT="NotchLyrics.xcodeproj"
SCHEME="NotchLyrics"
APP_NAME="Notch Lyrics"
REPO="huo241/notch-lyrics"
FEED_URL="https://raw.githubusercontent.com/${REPO}/main/updater/appcast.xml"

# ---------------------------------------------------------------- version ---
VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    VERSION="$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' "$PROJECT/project.pbxproj" | head -1)"
fi
if [[ -z "$VERSION" ]]; then
    echo "error: could not determine version; pass it as the first argument" >&2
    exit 1
fi
TAG="v${VERSION}"

echo "==> Releasing ${APP_NAME} ${VERSION} (tag ${TAG})"

# ------------------------------------------------------------------ build ---
DERIVED="$ROOT/build/DerivedData"
echo "==> Building Release"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$DERIVED" \
    -quiet \
    ONLY_ACTIVE_ARCH=NO \
    ${SANDBOX_ARGS[@]+"${SANDBOX_ARGS[@]}"} \
    build

APP="$DERIVED/Build/Products/Release/${APP_NAME}.app"
if [[ ! -d "$APP" ]]; then
    echo "error: build product not found at $APP" >&2
    exit 1
fi

# Locate the Sparkle tools inside the build's resolved packages.
SPARKLE_BIN="$(find "$DERIVED/SourcePackages/artifacts/sparkle" -type f -name generate_appcast -exec dirname {} \; 2>/dev/null | head -1)"
if [[ -z "$SPARKLE_BIN" ]]; then
    echo "error: Sparkle tools not found under $DERIVED/SourcePackages" >&2
    echo "       (open the project in Xcode once so the package resolves)" >&2
    exit 1
fi
echo "==> Using Sparkle tools from $SPARKLE_BIN"

# -------------------------------------------------------------------- zip ---
RELEASES="$ROOT/build/releases"
STAGING="$ROOT/dist"
mkdir -p "$RELEASES" "$STAGING"

ZIP_NAME="NotchLyrics-${VERSION}.zip"
echo "==> Packaging ${ZIP_NAME}"
rm -f "$RELEASES/$ZIP_NAME"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$RELEASES/$ZIP_NAME"

# -------------------------------------------------------------------- dmg ---
# The DMG is what a person downloads and drags across; the zip is what Sparkle
# updates from. The DMG deliberately stays out of $RELEASES so that the appcast
# does not end up with two entries for the same build.
DMG_NAME="NotchLyrics-${VERSION}.dmg"
if command -v dmgbuild >/dev/null 2>&1; then
    echo "==> Packaging ${DMG_NAME}"
    rm -f "$STAGING/$DMG_NAME"
    "$ROOT/Configuration/dmg/create_dmg.sh" "$APP" "$STAGING/$DMG_NAME" "$APP_NAME"
else
    echo "==> Skipping the DMG: dmgbuild is not on PATH."
    echo "    python3 -m pip install --require-hashes -r Configuration/dmg/requirements.txt"
fi

# ---------------------------------------------------------------- appcast ---
# generate_appcast reuses an existing appcast.xml in the archives directory so
# previous releases stay in the feed. Seed it from the committed one.
if [[ -f "$ROOT/updater/appcast.xml" ]]; then
    cp "$ROOT/updater/appcast.xml" "$RELEASES/appcast.xml"
fi

echo "==> Generating appcast"
"$SPARKLE_BIN/generate_appcast" \
    --download-url-prefix "https://github.com/${REPO}/releases/download/${TAG}/" \
    "$RELEASES"

cp "$RELEASES/appcast.xml" "$ROOT/updater/appcast.xml"
cp "$RELEASES/$ZIP_NAME" "$STAGING/$ZIP_NAME"

# ----------------------------------------------------------------- report ---
echo
echo "==> Done"
echo "    appcast : updater/appcast.xml"
echo "    archive : dist/${ZIP_NAME}"
[[ -f "$STAGING/$DMG_NAME" ]] && echo "    disk image: dist/${DMG_NAME}"
echo
echo "Next steps:"
echo "  1. Attach the archive to a GitHub Release named ${TAG} (asset name must"
echo "     match '${ZIP_NAME}' exactly, so the appcast URL resolves), plus the"
echo "     DMG for people who prefer dragging the app across:"
echo
echo "       gh release create ${TAG} \"dist/${ZIP_NAME}\" \"dist/${DMG_NAME}\" \\"
echo "           --title \"${APP_NAME} ${VERSION}\""
echo
echo "  2. Publish the feed:"
echo
echo "       git add updater/appcast.xml"
echo "       git commit -m \"Release ${VERSION}\""
echo "       git push"
echo
echo "     Feed URL: ${FEED_URL}"
