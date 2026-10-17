#!/bin/bash
# Compile VolcaClock.app en binaire universel (Apple Silicon + Intel), pour macOS 12 et suivants.
# A lancer depuis le Terminal : bash build.sh
set -euo pipefail
cd "$(dirname "$0")"

MIN_MACOS="12.0"
ARCHS="arm64 x86_64"
LINK="Vendor/link"

if [ ! -d "$LINK/include" ]; then
  echo "Telechargement du SDK Ableton Link..."
  mkdir -p Vendor
  git clone --recursive --depth 1 https://github.com/Ableton/link.git "$LINK"
fi

mkdir -p build

for ARCH in $ARCHS; do
  TARGET="$ARCH-apple-macos$MIN_MACOS"

  echo "Compilation du pont Link (C++) pour $ARCH..."
  clang++ -target "$TARGET" -std=c++17 -O2 -DLINK_PLATFORM_MACOSX=1 \
    -I"$LINK/include" \
    -I"$LINK/modules/asio-standalone/asio/include" \
    -c Sources/LinkBridge.cpp -o "build/LinkBridge-$ARCH.o"

  echo "Compilation de l'app (Swift) pour $ARCH..."
  swiftc -O -swift-version 5 -target "$TARGET" \
    -import-objc-header Sources/LinkBridge.h \
    Sources/main.swift Sources/MidiIO.swift Sources/ClockEngine.swift Sources/MenuIcon.swift \
    "build/LinkBridge-$ARCH.o" \
    -lc++ -framework CoreMIDI -framework AppKit \
    -o "build/VolcaClock-$ARCH"
done

echo "Fusion des architectures..."
lipo -create build/VolcaClock-arm64 build/VolcaClock-x86_64 -output build/VolcaClock

echo "Assemblage de VolcaClock.app..."
APP="build/VolcaClock.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp build/VolcaClock "$APP/Contents/MacOS/VolcaClock"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "Termine : $APP ($(lipo -archs "$APP/Contents/MacOS/VolcaClock"))"
