#!/bin/zsh
set -euo pipefail

if (( $# < 3 || $# > 5 )); then
  echo "Usage: $0 APP_PATH BACKGROUND_PNG OUTPUT_DMG [SIGNING_IDENTITY] [VOLUME_NAME]" >&2
  exit 64
fi

app_path=${1:A}
background_path=${2:A}
output_path=${3:A}
signing_identity=${4:-}
volume_name=${5:-"Sonexis Installer"}

[[ -d "$app_path" ]] || { echo "App not found: $app_path" >&2; exit 66; }
[[ -f "$background_path" ]] || { echo "Background not found: $background_path" >&2; exit 66; }

work_dir=$(mktemp -d /private/tmp/sonexis-dmg.XXXXXX)
stage_dir="$work_dir/stage"
mount_dir="/Volumes/$volume_name"
rw_image="$work_dir/Sonexis-rw.dmg"
attached_by_script=false

if mount | grep -Fq " on $mount_dir "; then
  echo "A volume named '$volume_name' is already mounted." >&2
  echo "Eject it in Finder, then run the DMG maker again." >&2
  exit 75
fi

cleanup() {
  if [[ "$attached_by_script" == true ]]; then
    hdiutil detach "$mount_dir" -quiet 2>/dev/null || true
  fi
  rm -rf "$work_dir"
}
trap cleanup EXIT

mkdir -p "$stage_dir/.background" "${output_path:h}"
ditto "$app_path" "$stage_dir/Sonexis.app"
cp "$background_path" "$stage_dir/.background/background.png"
ln -s /Applications "$stage_dir/Applications"

hdiutil create -quiet -srcfolder "$stage_dir" -volname "$volume_name" \
  -fs HFS+ -format UDRW "$rw_image"
hdiutil attach -quiet -readwrite -noverify -noautoopen \
  -mountpoint "$mount_dir" "$rw_image"
attached_by_script=true

osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$volume_name"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set pathbar visible of container window to false
    set sidebar width of container window to 0
    set bounds of container window to {180, 120, 900, 590}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 112
    set text size of viewOptions to 13
    set label position of viewOptions to bottom
    set background color of viewOptions to {64225, 62900, 64800}
    set background picture of viewOptions to file ".background:background.png"
    set position of item "Sonexis.app" of container window to {190, 220}
    set position of item "Applications" of container window to {530, 220}
    update without registering applications
    delay 3
  end tell
end tell
APPLESCRIPT

sync
sleep 2
hdiutil detach -quiet "$mount_dir"
attached_by_script=false
hdiutil convert -quiet "$rw_image" -format UDZO -imagekey zlib-level=9 \
  -o "$output_path"

if [[ -n "$signing_identity" ]]; then
  codesign --force --timestamp --sign "$signing_identity" "$output_path"
fi

echo "Created $output_path"
