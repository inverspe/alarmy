#!/usr/bin/env bash
set -euo pipefail
APP="build/Build/Products/Release-iphoneos/Alarmy.app"
rm -rf Payload Alarmy.tipa && mkdir Payload && cp -R "$APP" Payload/
ldid -SApp/Alarmy.entitlements Payload/Alarmy.app/Alarmy
zip -qry Alarmy.tipa Payload
