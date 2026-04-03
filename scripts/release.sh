#!/usr/bin/env bash

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <issuer-id>"
  exit 1
fi

ISSUER_ID="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$ROOT_DIR/Info.plist")"
TAG="v${VERSION}"
ZIP_PATH="$ROOT_DIR/release/CodexSwitcher-v${VERSION}-signed.zip"

extract_changelog() {
  awk -v version="$VERSION" '
    $0 == "### v" version { capture=1; next }
    /^### v/ && capture { exit }
    capture { print }
  ' "$ROOT_DIR/README.md"
}

CHANGELOG_CONTENT="$(extract_changelog)"
if [ -z "${CHANGELOG_CONTENT// }" ]; then
  echo "❌ README changelog entry for ${TAG} not found."
  exit 1
fi

echo "==> Running tests"
cd "$ROOT_DIR"
swift test

echo "==> Building signed release"
"$ROOT_DIR/scripts/build_signed.sh" "$ISSUER_ID"

if [ ! -f "$ZIP_PATH" ]; then
  echo "❌ Signed asset not found at $ZIP_PATH"
  exit 1
fi

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "==> Tag $TAG already exists"
else
  echo "==> Creating tag $TAG"
  git tag "$TAG"
  git push origin "$TAG"
fi

TMP_NOTES="$(mktemp)"
trap 'rm -f "$TMP_NOTES"' EXIT
{
  echo "## CodexSwitcher ${TAG}"
  echo
  printf "%s\n" "$CHANGELOG_CONTENT"
  echo
  echo "### Release"
  echo "- Developer ID signed"
  echo "- Apple notarized"
  echo "- Asset: \`$(basename "$ZIP_PATH")\`"
} > "$TMP_NOTES"

if gh release view "$TAG" >/dev/null 2>&1; then
  echo "==> Updating existing GitHub release $TAG"
  gh release upload "$TAG" "$ZIP_PATH" --clobber
  gh release edit "$TAG" --title "$TAG" --notes-file "$TMP_NOTES"
else
  echo "==> Creating GitHub release $TAG"
  gh release create "$TAG" "$ZIP_PATH" --title "$TAG" --notes-file "$TMP_NOTES"
fi

echo "✅ Release published: $(gh release view "$TAG" --json url -q .url)"
