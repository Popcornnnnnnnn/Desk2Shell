#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
artifact_dir="$project_dir/artifacts"
resource_dir="$project_dir/macos/Desk2ShellApp/Sources/Desk2ShellApp/Resources"
rid="${DESK2SHELL_WINDOWS_RID:-win-x64}"

mkdir -p "$artifact_dir" "$resource_dir"
dotnet publish "$project_dir/windows/Desk2Shell.Bootstrap/Desk2Shell.Bootstrap.csproj" \
  -c Release -r "$rid" --self-contained true \
  -o "$artifact_dir/windows-$rid"
cp "$artifact_dir/windows-$rid/Desk2Shell Bootstrap.exe" "$resource_dir/Desk2Shell Bootstrap.exe"

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
