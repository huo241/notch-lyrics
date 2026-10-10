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
#   2. Zips "Notch Lyrics.app" with ditto (the format Sparkle expects).
#   3. Re-runs Sparkle's generate_appcast so the new build is signed with this
#      project's EdDSA key and appended to the feed.
#   4. Copies the refreshed appcast back into updater/appcast.xml.
#   5. Copies the zip to ./dist/ so it is easy to attach to a GitHub Release.
#
# What it does NOT do:
#   - Upload anything. Publishing is a separate, explicit step.
#
# After it finishes, publish with:
#   gh release create v<version> "dist/Notch Lyrics <version>.zip" --title "Notch Lyrics <version>"
#   git add updater/appcast.xml && git commit -m "Release <version>" && git push
#
# The appcast is served from
#   https://raw.githubusercontent.com/huo241/notch-lyrics/main/updater/appcast.xml
# which is what SUFeedURL in NotchLyrics/Info.plist points at, so the feed only
# goes live once updater/appcast.xml is pushed to main.

set -euo pipefail

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
    -derivedDataPath "$DERIVED" \
    -quiet \
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

ZIP_NAME="${APP_NAME} ${VERSION}.zip"
echo "==> Packaging ${ZIP_NAME}"
rm -f "$RELEASES/$ZIP_NAME"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$RELEASES/$ZIP_NAME"

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
echo
echo "Next steps:"
echo "  1. Attach it to a GitHub Release named ${TAG} (asset name must match"
echo "     '${ZIP_NAME}' exactly, so the appcast URL resolves):"
echo
echo "       gh release create ${TAG} \"dist/${ZIP_NAME}\" --title \"${APP_NAME} ${VERSION}\""
echo
echo "  2. Publish the feed:"
echo
echo "       git add updater/appcast.xml"
echo "       git commit -m \"Release ${VERSION}\""
echo "       git push"
echo
echo "     Feed URL: ${FEED_URL}"
