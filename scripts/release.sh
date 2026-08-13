#!/bin/zsh
set -euo pipefail

if [[ -z "$DEVELOPER_ID_APPLICATION" || -z "$NOTARY_PROFILE" ]]; then
  print -u2 "Set DEVELOPER_ID_APPLICATION and NOTARY_PROFILE first."
  exit 64
fi

task_root="$(cd "$(dirname "$0")/.." && pwd)"
archive_path="$task_root/build/Ujer.xcarchive"
export_path="$task_root/build/export"
dmg_path="$task_root/build/Ujer.dmg"

rm -rf "$archive_path" "$export_path" "$dmg_path"
xcodebuild archive \
  -project "$task_root/Ujer.xcodeproj" \
  -scheme Ujer \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$archive_path" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
  OTHER_CODE_SIGN_FLAGS="--options runtime"

mkdir -p "$export_path"
cp -R "$archive_path/Products/Applications/Ujer.app" "$export_path/"
hdiutil create -volname Ujer -srcfolder "$export_path" -ov -format UDZO "$dmg_path"
xcrun notarytool submit "$dmg_path" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"
spctl --assess --type open --context context:primary-signature "$dmg_path"

