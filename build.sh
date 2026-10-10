#!/bin/zsh
# Сборка Yonder: тесты → Yonder.app (arm64 + x86_64) → build/Yonder.zip
set -e
cd "${0:a:h}"
mkdir -p build
swiftc -O src/Scheduler.swift tests/main.swift -o build/tests && ./build/tests
APP=build/Yonder.app
rm -rf $APP && mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
for arch in arm64 x86_64; do
  swiftc -O -target $arch-apple-macos13.0 -o build/Yonder-$arch src/*.swift
done
lipo -create build/Yonder-arm64 build/Yonder-x86_64 -output $APP/Contents/MacOS/Yonder
rm build/Yonder-arm64 build/Yonder-x86_64
cp Info.plist $APP/Contents/
cp sounds/*.wav art/AppIcon.icns $APP/Contents/Resources/
codesign --force -s - $APP
rm -f build/Yonder.zip && ditto -c -k --keepParent $APP build/Yonder.zip
# DMG: перетащить Yonder в «Программы»
rm -rf build/dmg build/Yonder.dmg && mkdir build/dmg && cp -R $APP build/dmg/ && ln -s /Applications build/dmg/Applications
hdiutil create -quiet -volname Yonder -srcfolder build/dmg -ov -format UDZO build/Yonder.dmg && rm -rf build/dmg
echo "built $APP + build/Yonder.zip + build/Yonder.dmg"
