#!/bin/bash
# Credentials stay in Keychain; this script never accepts a password.
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:-prepare}"
if [[ "$mode" != prepare && "$mode" != notarize ]]; then
  echo "Usage: $0 prepare | notarize" >&2; exit 2
fi
if [[ "$mode" == notarize ]]; then
  : "${DEVELOPER_ID_IDENTITY:?Set the full Developer ID Application identity name}"
  : "${NOTARY_PROFILE:?Set the notarytool Keychain profile name}"
  [[ "$DEVELOPER_ID_IDENTITY" == 'Developer ID Application: '* ]] || { echo 'Developer ID Application required' >&2; exit 2; }
  security find-identity -v -p codesigning | grep -F -- "\"$DEVELOPER_ID_IDENTITY\"" >/dev/null
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null
fi
sh Tests/run.sh
release_dir="$(mktemp -d "$PWD/build-release.XXXXXX")"
echo "Release workspace: $release_dir"
xcodebuild -project 'Touch Up.xcodeproj' -scheme 'Touch Up' -configuration Release \
  -derivedDataPath "$release_dir/DerivedData" ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO build > "$release_dir/build.log" 2>&1
app="$release_dir/DerivedData/Build/Products/Release/Touch Up.app"
resources="$app/Contents/Resources"
test -f "$resources/LICENSE"
test -f "$resources/Icon.icns"
architectures="$(lipo -archs "$app/Contents/MacOS/Touch Up")"
for architecture in arm64 x86_64; do
  case " $architectures " in
    *" $architecture "*) ;;
    *) echo "Missing architecture: $architecture" >&2; exit 1 ;;
  esac
done
cat > "$resources/Distribution.txt" <<'EOF'
Touch Up — Ragura fork
Source: https://github.com/Ragura/Touch-Up/tree/codex/drawing-mode
Based on Touch Up by Sebastian Hueber. See LICENSE for the MIT licence.
EOF
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
build=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$app/Contents/Info.plist")
if [[ "$mode" == prepare ]]; then
  echo "Unsigned app prepared: $app"
  echo 'Not ready for distribution; run notarize with Developer ID and Keychain credentials.'
  exit 0
fi
codesign --force --sign "$DEVELOPER_ID_IDENTITY" --timestamp --options runtime "$app/Contents/Frameworks/TouchUpCore.framework"
codesign --force --sign "$DEVELOPER_ID_IDENTITY" --timestamp --options runtime \
  --entitlements 'Touch Up/Touch_Up.entitlements' "$app"
codesign --verify --deep --strict "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "$release_dir/submission.zip"
xcrun notarytool submit "$release_dir/submission.zip" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$release_dir/app-notary.json"
/usr/bin/plutil -extract status raw "$release_dir/app-notary.json" | grep -qx Accepted
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
mkdir "$release_dir/image"
ditto "$app" "$release_dir/image/Touch Up.app"
ln -s /Applications "$release_dir/image/Applications"
cp LICENSE "$release_dir/image/LICENSE.txt"
cp docs/INSTALL.txt "$release_dir/image/Install.txt"
dmg="$release_dir/Touch-Up-$version-$build.dmg"
hdiutil create -volname 'Touch Up' -srcfolder "$release_dir/image" -format UDZO "$dmg"
codesign --sign "$DEVELOPER_ID_IDENTITY" --timestamp "$dmg"
xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$release_dir/dmg-notary.json"
/usr/bin/plutil -extract status raw "$release_dir/dmg-notary.json" | grep -qx Accepted
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
hdiutil verify "$dmg"
echo "Notarized package: $dmg"
