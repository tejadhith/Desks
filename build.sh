#!/bin/bash
set -euo pipefail

swift build -c release

APP="Desks.app"
CONTENTS="$APP/Contents"
TARGET="$HOME/Applications"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS"
cp .build/release/Desks "$CONTENTS/MacOS/Desks"
cp Resources/Info.plist "$CONTENTS/Info.plist"
mkdir -p "$CONTENTS/Resources"
cp -R Resources/Fonts "$CONTENTS/Resources/Fonts"
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ { print $2; exit }')}"
codesign --force --sign "${IDENTITY:--}" "$APP"

pkill -x Desks 2>/dev/null || true
sleep 0.5

mkdir -p "$TARGET"
rm -rf "$TARGET/$APP"
cp -R "$APP" "$TARGET/"
open "$TARGET/$APP"

echo "Installed $TARGET/$APP"
