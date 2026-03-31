#!/bin/bash
set -e

APP_NAME="CodexSwitcher"
APP_BUNDLE="${APP_NAME}.app"
BUILD_DIR=".build/release"

echo "► Swift build başlıyor..."
swift build -c release 2>&1

echo "► App bundle oluşturuluyor..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/"
cp "Info.plist" "${APP_BUNDLE}/Contents/"

echo "► Build tamamlandı: ${APP_BUNDLE}"
echo ""
echo "Başlatmak için:"
echo "  open ${APP_BUNDLE}"
echo ""
echo "Her oturumda otomatik başlaması için:"
echo "  cp -R ${APP_BUNDLE} /Applications/"
echo "  Sistem Tercihleri → Genel → Giriş Öğeleri → + → CodexSwitcher.app"
