#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  printf 'Usage: %s APP_PATH VERSION OUTPUT_DMG\n' "$0" >&2
  exit 64
fi

app_path="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
version="$2"
output_dmg="$(cd "$(dirname "$3")" && pwd)/$(basename "$3")"
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
volume_name="Desk2Shell $version"
work_dir="$(mktemp -d /tmp/desk2shell-dmg.XXXXXX)"
staging_dir="$work_dir/staging"
mount_dir="/Volumes/$volume_name"
readwrite_dmg="$work_dir/Desk2Shell-readwrite.dmg"
attached_device=""

cleanup() {
  if [[ -n "$attached_device" ]]; then
    hdiutil detach "$attached_device" -quiet || true
  fi
  rm -rf "$work_dir"
}
trap cleanup EXIT

test -d "$app_path"
test ! -e "$mount_dir"
mkdir -p "$staging_dir/.background"
ditto "$app_path" "$staging_dir/Desk2Shell.app"
ln -s /Applications "$staging_dir/Applications"
cp "$project_dir/assets/desk2shell-logo.png" "$work_dir/background.png"
sips --resampleHeightWidth 150 150 "$work_dir/background.png" --out "$work_dir/background-small.png" >/dev/null
sips --padToHeightWidth 420 660 --padColor F4F7FB "$work_dir/background-small.png" --out "$staging_dir/.background/background.png" >/dev/null
cp "$project_dir/packaging/Desk2Shell.icns" "$staging_dir/.VolumeIcon.icns"

hdiutil create -quiet -srcfolder "$staging_dir" -volname "$volume_name" -fs APFS -format UDRW "$readwrite_dmg"
attach_output="$(hdiutil attach "$readwrite_dmg" -readwrite -noverify -noautoopen)"
attached_device="$(printf '%s\n' "$attach_output" | awk '/^\/dev\// { print $1; exit }')"
test -n "$attached_device"

SetFile -a V "$mount_dir/.background" "$mount_dir/.VolumeIcon.icns"
SetFile -a C "$mount_dir"
osascript - "$volume_name" <<'APPLESCRIPT'
on run argv
  set volumeName to item 1 of argv
  tell application "Finder"
    tell disk volumeName
      open
      set current view of container window to icon view
      set toolbar visible of container window to false
      set statusbar visible of container window to false
      set bounds of container window to {160, 120, 820, 540}
      set theViewOptions to icon view options of container window
      set arrangement of theViewOptions to not arranged
      set icon size of theViewOptions to 96
      set text size of theViewOptions to 13
      set background picture of theViewOptions to file ".background:background.png"
      set position of item "Desk2Shell.app" of container window to {170, 235}
      set position of item "Applications" of container window to {490, 235}
      update without registering applications
      delay 2
      close
    end tell
  end tell
end run
APPLESCRIPT

test -f "$mount_dir/.DS_Store"
sync
hdiutil detach "$attached_device" -quiet
attached_device=""

rm -f "$output_dmg"
hdiutil convert "$readwrite_dmg" -quiet -format ULFO -o "$output_dmg"
hdiutil verify "$output_dmg" >/dev/null

verify_mount="$work_dir/verify"
mkdir -p "$verify_mount"
verify_output="$(hdiutil attach "$output_dmg" -readonly -noverify -noautoopen -mountpoint "$verify_mount")"
attached_device="$(printf '%s\n' "$verify_output" | awk '/^\/dev\// { print $1; exit }')"
test -d "$verify_mount/Desk2Shell.app"
test -L "$verify_mount/Applications"
test -f "$verify_mount/.background/background.png"
test -f "$verify_mount/.DS_Store"
hdiutil detach "$attached_device" -quiet
attached_device=""

printf '%s\n' "$output_dmg"
