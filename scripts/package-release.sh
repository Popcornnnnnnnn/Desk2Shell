#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
artifact_dir="$project_dir/artifacts"
resource_dir="$project_dir/macos/Desk2ShellApp/Sources/Desk2ShellApp/Resources"
rid="${DESK2SHELL_WINDOWS_RID:-win-x64}"
bootstrap="${DESK2SHELL_WINDOWS_BOOTSTRAP:-}"
if [[ -z "$bootstrap" || ! -f "$bootstrap" ]]; then
  printf 'ERROR: set DESK2SHELL_WINDOWS_BOOTSTRAP to a Bootstrap built by the GitHub Windows runner.\n' >&2
  exit 1
fi

mkdir -p "$artifact_dir" "$resource_dir"
mkdir -p "$artifact_dir/windows-$rid"
cp "$bootstrap" "$artifact_dir/windows-$rid/Desk2Shell Bootstrap.exe"
cp "$bootstrap" "$resource_dir/Desk2Shell Bootstrap.exe"

"$project_dir/scripts/build-macos-app.sh" "$artifact_dir"

mac_archive="$artifact_dir/Desk2Shell-macOS-v0.1.0-UNSIGNED.zip"
windows_exe="$artifact_dir/Desk2Shell-Bootstrap-$rid-v0.1.0-UNSIGNED.exe"
rm -f "$mac_archive" "$windows_exe"
cp "$artifact_dir/windows-$rid/Desk2Shell Bootstrap.exe" "$windows_exe"
(
  cd "$artifact_dir"
  ditto -c -k --sequesterRsrc --keepParent Desk2Shell.app "$(basename "$mac_archive")"
  shasum -a 256 "$(basename "$mac_archive")" "$(basename "$windows_exe")" > SHA256SUMS
)
printf '%s\n%s\n' "$mac_archive" "$windows_exe"
