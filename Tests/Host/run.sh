#!/bin/bash
# Builds the stand-in app with the add-on inside and runs it in the booted simulator.
# Usage: run.sh <name> [extra compiler flags]   Prints the app's output; the last line is RESULT.
set -euo pipefail
name=$1; shift
app="build-$name/Host.app"
rm -rf "build-$name"; mkdir -p "$app"
cat > "$app/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.inverspe.alarmlock.host.$name</string>
<key>CFBundleExecutable</key><string>Host</string>
<key>CFBundleName</key><string>Host</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>UILaunchScreen</key><dict/>
</dict></plist>
EOF
sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
swiftlib=$(dirname "$(xcrun --find swiftc)")/../lib/swift/iphonesimulator
xcrun -sdk iphonesimulator swiftc -c -parse-as-library -module-name Alarmy -target arm64-apple-ios15.0-simulator -sdk "$sdk" \
  Tests/Host/Screens.swift -o "build-$name/screens.o"
xcrun -sdk iphonesimulator clang -arch arm64 -isysroot "$sdk" -L"$swiftlib" -L"$sdk/usr/lib/swift" -Wl,-rpath,/usr/lib/swift \
  -mios-simulator-version-min=15.0 -fobjc-arc -Wno-deprecated-declarations -DALTEST=1 "$@" \
  -framework Foundation -framework UIKit -framework AVFoundation -framework UserNotifications -framework MetricKit \
  -o "$app/Host" "build-$name/screens.o" Tests/Host/main.m AlarmLock/AlarmLock.m AlarmLock/LockRules.m
codesign -f -s - "$app"
xcrun simctl install booted "$app"
xcrun simctl launch --console-pty booted "com.inverspe.alarmlock.host.$name" > "host-$name.log" 2>&1 || true
cat "host-$name.log"
