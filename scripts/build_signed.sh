#!/usr/bin/env bash
# CodexSwitcher — Build, Sign & Notarize
# Usage: ./scripts/build_signed.sh <issuer-id>
# Find Issuer ID: App Store Connect → Users and Access → Integrations → App Store Connect API

set -euo pipefail

# ── Config ──────────────────────────────────────────────────────────────────
APP_NAME="CodexSwitcher"
VERSION="1.9.1"
SIGN_IDENTITY="Developer ID Application: SENOL DOGAN (79DZ4AA4DW)"
KEY_ID="VMU73YXDVJ"
KEY_PATH="$HOME/Downloads/AuthKey_VMU73YXDVJ.p8"
ISSUER_ID="${1:-}"

if [ -z "$ISSUER_ID" ]; then
    echo "❌ Issuer ID gerekli."
    echo "   Bul: App Store Connect → Users and Access → Integrations → App Store Connect API"
    echo "   Kullanım: $0 <issuer-id>"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$ROOT_DIR/.build/arm64-apple-macosx/release"
STAGING="$ROOT_DIR/build"
APP_BUNDLE="$STAGING/$APP_NAME.app"
RELEASE_DIR="$ROOT_DIR/release"

# ── 1. Build ─────────────────────────────────────────────────────────────────
echo "🔨 Building release..."
cd "$ROOT_DIR"
swift build -c release 2>&1 | grep -v "^note:" | grep -v "^warning:" || true
echo "   ✓ Build complete"

# ── 2. Create .app bundle ────────────────────────────────────────────────────
echo "📦 Creating .app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"

# Executable
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

# Resource bundle — placed in Contents/Resources/ (standard, codesign-friendly)
# BundleExtension.swift in source looks here for signed .app builds
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp -r "$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle" "$APP_BUNDLE/Contents/Resources/"

# Info.plist & PkgInfo
cp "$ROOT_DIR/Info.plist" "$APP_BUNDLE/Contents/"
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

# App icon — required for Dock/Finder icon
ICON_SRC="$ROOT_DIR/Sources/CodexSwitcher/Resources/AppIcon.icns"
if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

echo "   ✓ Bundle structure:"
find "$APP_BUNDLE" -not -path '*/\.*' | sed 's|'"$STAGING"'/||' | head -20

# ── 3. Sign ──────────────────────────────────────────────────────────────────
echo "✍️  Signing with Developer ID..."

# Resource bundle needs an Info.plist for codesign to accept it
if [ ! -f "$APP_BUNDLE/Contents/Resources/${APP_NAME}_${APP_NAME}.bundle/Info.plist" ]; then
    cat > "$APP_BUNDLE/Contents/Resources/${APP_NAME}_${APP_NAME}.bundle/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.personal.codex-switcher.resources</string>
    <key>CFBundleName</key>
    <string>CodexSwitcher_CodexSwitcher</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleVersion</key>
    <string>1</string>
</dict>
</plist>
PLIST
fi

# Sign resource bundle first (inner component before outer)
codesign --force --sign "$SIGN_IDENTITY" \
    --options runtime \
    --entitlements "$ROOT_DIR/entitlements.plist" \
    --timestamp \
    "$APP_BUNDLE/Contents/Resources/${APP_NAME}_${APP_NAME}.bundle"

# Sign the app bundle
codesign --force --sign "$SIGN_IDENTITY" \
    --options runtime \
    --entitlements "$ROOT_DIR/entitlements.plist" \
    --timestamp \
    "$APP_BUNDLE"

# Verify
codesign --verify --deep --strict "$APP_BUNDLE"
echo "   ✓ Signature valid"

spctl --assess --type execute --verbose "$APP_BUNDLE" 2>&1 | head -5 || echo "   (spctl assess — Gatekeeper check)"

# ── 4. Notarize ──────────────────────────────────────────────────────────────
echo "☁️  Submitting for notarization..."
NOTARIZE_ZIP="$STAGING/${APP_NAME}-notarize.zip"
rm -f "$NOTARIZE_ZIP"
ditto -c -k --keepParent "$APP_BUNDLE" "$NOTARIZE_ZIP"

xcrun notarytool submit "$NOTARIZE_ZIP" \
    --key "$KEY_PATH" \
    --key-id "$KEY_ID" \
    --issuer "$ISSUER_ID" \
    --wait

echo "   ✓ Notarization complete"

# ── 5. Staple ────────────────────────────────────────────────────────────────
echo "📎 Stapling notarization ticket..."
xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"
echo "   ✓ Stapled"

# ── 6. Distribution zip ──────────────────────────────────────────────────────
mkdir -p "$RELEASE_DIR"
DIST_ZIP="$RELEASE_DIR/${APP_NAME}-v${VERSION}-signed.zip"
rm -f "$DIST_ZIP"
ditto -c -k --keepParent "$APP_BUNDLE" "$DIST_ZIP"

echo ""
echo "🎉 Hazır!"
echo "   Signed app: $APP_BUNDLE"
echo "   Release zip: $DIST_ZIP"
echo ""
echo "   Kullanıcılar açarken sorun yaşamaz — Developer ID + Notarized ✅"
