#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to your Developer ID Application identity}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a stored notarytool keychain profile}"
case "$SIGN_IDENTITY" in
  "Developer ID Application:"*) ;;
  *) echo "A Developer ID Application signing identity is required." >&2; exit 1 ;;
esac
version=$(cat VERSION)
make test
make universal SIGN_IDENTITY="$SIGN_IDENTITY" SIGN_FLAGS="--options runtime --timestamp"
codesign --verify --deep --strict --verbose=2 build/ZIFburn.app
mkdir -p build/release
archive="build/release/ZIFburn-${version}-macOS-universal.zip"
ditto -c -k --sequesterRsrc --keepParent build/ZIFburn.app "$archive"
xcrun notarytool submit "$archive" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple build/ZIFburn.app
xcrun stapler validate build/ZIFburn.app
spctl --assess --type execute --verbose=2 build/ZIFburn.app
# Recreate the download with the stapled ticket included.
rm "$archive"
ditto -c -k --sequesterRsrc --keepParent build/ZIFburn.app "$archive"
shasum -a 256 "$archive" > "$archive.sha256"
"${PYTHON:-python3}" scripts/dmg_release.py
make dist
echo "Release ready: $archive"
