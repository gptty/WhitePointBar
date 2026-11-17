#!/usr/bin/env bash
# Build WhitePointBar.app into ./build. Pass --install to copy it to
# ~/Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/WhitePointBar"

APP="build/WhitePointBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/WhitePointBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p "$HOME/Applications"
  pkill -x WhitePointBar 2>/dev/null || true
  rm -rf "$HOME/Applications/WhitePointBar.app"
  cp -R "$APP" "$HOME/Applications/"
  open "$HOME/Applications/WhitePointBar.app"
  echo "Installed to ~/Applications and launched"
fi
