#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
package_dir="$project_dir/macos/Desk2ShellApp"
output_dir="${1:-$project_dir/artifacts}"
app_dir="$output_dir/Desk2Shell.app"

swift build --package-path "$package_dir" -c release
binary="$(swift build --package-path "$package_dir" -c release --show-bin-path)/Desk2Shell"
resource_bundle="$(find "$(dirname "$binary")" -maxdepth 1 -type d -name '*Desk2ShellApp*.bundle' -print -quit)"

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary" "$app_dir/Contents/MacOS/Desk2Shell"
cp "$project_dir/packaging/Info.plist" "$app_dir/Contents/Info.plist"
if [[ -f "$project_dir/packaging/Desk2Shell.icns" ]]; then
  cp "$project_dir/packaging/Desk2Shell.icns" "$app_dir/Contents/Resources/Desk2Shell.icns"
fi
if [[ -n "$resource_bundle" ]]; then
  cp -R "$resource_bundle" "$app_dir/Contents/Resources/"
fi

if [[ -n "${DESK2SHELL_APPLE_SIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$DESK2SHELL_APPLE_SIGN_IDENTITY" "$app_dir"
else
  codesign --force --sign - "$app_dir"
  printf 'WARNING: created an ad-hoc signed developer app.\n' >&2
fi

printf '%s\n' "$app_dir"
