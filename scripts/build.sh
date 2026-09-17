#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/CursorLevel.app"
BIN="$APP/Contents/MacOS/CursorLevel"
SRC="$ROOT/CursorLevel"
INSTALL="/Applications/CursorLevel.app"
BUNDLE_ID="com.cursorlevel.CursorLevel"
DMG="$ROOT/dist/CursorLevel.dmg"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$SRC/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

ICON="$SRC/Resources/AppIcon.icns"
if [[ -f "$ICON" ]]; then
  cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
fi

MENUBAR="$SRC/Resources/MenuBarIcon.png"
MENUBAR2X="$SRC/Resources/MenuBarIcon@2x.png"
if [[ -f "$MENUBAR" ]]; then
  cp "$MENUBAR" "$APP/Contents/Resources/MenuBarIcon.png"
fi
if [[ -f "$MENUBAR2X" ]]; then
  cp "$MENUBAR2X" "$APP/Contents/Resources/MenuBarIcon@2x.png"
fi

SDK="$(xcrun --sdk macosx --show-sdk-path)"

xcrun swiftc \
  -target arm64-apple-macos13.0 \
  -sdk "$SDK" \
  -parse-as-library \
  -O \
  -framework SwiftUI \
  -framework AppKit \
  -framework CoreGraphics \
  -framework ApplicationServices \
  -framework ServiceManagement \
  -o "$BIN" \
  "$SRC/Config.swift" \
  "$SRC/DisplayResolver.swift" \
  "$SRC/MouseCorrector.swift" \
  "$SRC/AppState.swift" \
  "$SRC/StatusPanel.swift" \
  "$SRC/CursorLevelApp.swift"

IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: .*\)".*/\1/p' | head -1)"
fi

if [[ -n "$IDENTITY" ]]; then
  codesign --force --deep --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"
  echo "Signed with $IDENTITY"
else
  codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
  echo "Signed ad-hoc. Accessibility is unreliable until you sign with Apple Development."
fi

pkill -x CursorLevel >/dev/null 2>&1 || true
rm -rf "$INSTALL"
cp -R "$APP" "$INSTALL"
xattr -cr "$INSTALL"

STAGE="$ROOT/dist/dmg-root"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/CursorLevel.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create \
  -volname "CursorLevel" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG" >/dev/null
rm -rf "$STAGE"

WEB_PUBLIC="$ROOT/../Web/public"
if [[ -d "$WEB_PUBLIC" ]]; then
  cp "$DMG" "$WEB_PUBLIC/CursorLevel.dmg"
  echo "Copied disk image to $WEB_PUBLIC/CursorLevel.dmg"
fi

echo "Installed $INSTALL"
echo "Disk image $DMG"
echo "Open the app from /Applications, then enable Accessibility again."
