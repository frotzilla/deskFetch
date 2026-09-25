#!/bin/bash
# Builds deskFetch.app and optionally installs it to /Applications.
#
#   ./build.sh              build only, output in ./build/
#   ./build.sh --install    build, then install to /Applications and relaunch
#
# Signing: set DEVELOPMENT_TEAM to your Apple Developer Team ID. A free
# personal team works fine for running it on your own machine. Find it with:
#   security find-identity -v -p codesigning
set -euo pipefail

CONFIG=Release
INSTALL=false
[[ "${1:-}" == "--install" ]] && INSTALL=true

for tool in xcodegen xcodebuild; do
  command -v "$tool" >/dev/null || { echo "error: $tool not found" >&2; exit 1; }
done

if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
  echo "error: DEVELOPMENT_TEAM is not set." >&2
  echo "Find your team ID with: security find-identity -v -p codesigning" >&2
  echo "Then: DEVELOPMENT_TEAM=XXXXXXXXXX ./build.sh" >&2
  exit 1
fi

command -v fastfetch >/dev/null || \
  echo "warning: fastfetch not found on PATH; the widgets will show an error until you 'brew install fastfetch'" >&2

echo "==> Generating Xcode project"
xcodegen generate

echo "==> Building ($CONFIG)"
xcodebuild -project deskFetch.xcodeproj \
           -scheme deskFetch \
           -configuration "$CONFIG" \
           -derivedDataPath build/DerivedData \
           -allowProvisioningUpdates \
           build

APP="build/DerivedData/Build/Products/$CONFIG/deskFetch.app"
[[ -d "$APP" ]] || { echo "error: build succeeded but $APP is missing" >&2; exit 1; }
echo "==> Built $APP"

if [[ "$INSTALL" == true ]]; then
  EXT="/Applications/deskFetch.app/Contents/PlugIns/deskFetchWidget.appex"
  echo "==> Installing to /Applications"
  pkill -f deskFetch 2>/dev/null || true
  sleep 1
  pluginkit -r "$EXT" 2>/dev/null || true
  rm -rf /Applications/deskFetch.app
  cp -R "$APP" /Applications/
  pluginkit -a "/Applications/deskFetch.app/Contents/PlugIns/deskFetchWidget.appex" 2>/dev/null || true
  # macOS caches the widget gallery aggressively; nudge it.
  killall chronod NotificationCenter 2>/dev/null || true
  open /Applications/deskFetch.app
  echo "==> Installed and launched."
  echo "    Add widgets: right-click the desktop -> Edit Widgets -> search \"deskFetch\""
fi
