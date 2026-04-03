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
cp "Sources/CodexSwitcher/Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/"

# Bundle Sparkle framework
mkdir -p "${APP_BUNDLE}/Contents/Frameworks"
cp -R "${BUILD_DIR}/Sparkle.framework" "${APP_BUNDLE}/Contents/Frameworks/"

# Fix rpath so the binary finds Sparkle in Contents/Frameworks
install_name_tool -add_rpath "@executable_path/../Frameworks" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}" 2>/dev/null || true

# Ad-hoc sign — Gatekeeper "damaged" hatasını önler
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "► Build tamamlandı: ${APP_BUNDLE}"
echo ""
echo "Başlatmak için:"
echo "  open ${APP_BUNDLE}"
echo ""
echo "Her oturumda otomatik başlaması için:"
echo "  cp -R ${APP_BUNDLE} /Applications/"
echo "  Sistem Tercihleri → Genel → Giriş Öğeleri → + → CodexSwitcher.app"
