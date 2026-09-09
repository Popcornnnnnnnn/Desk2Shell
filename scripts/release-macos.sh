#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'Usage: %s VERSION\n' "$0" >&2
  exit 64
fi

version="$1"
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
artifact_dir="$project_dir/artifacts/release-$version"
resource_dir="$project_dir/macos/Desk2ShellApp/Sources/Desk2ShellApp/Resources"
info_plist="$project_dir/packaging/Info.plist"
identity="${DESK2SHELL_APPLE_SIGN_IDENTITY:-Developer ID Application: WEIZHI WANG (R26X7B8XDT)}"
notary_profile="${DESK2SHELL_NOTARY_PROFILE:-port-tools-notary}"
sparkle_version="2.9.6"
sparkle_archive_sha256="52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192"
sparkle_tools_dir="$artifact_dir/sparkle-tools"
dmg="$artifact_dir/Desk2Shell-$version.dmg"
bootstrap="${DESK2SHELL_WINDOWS_BOOTSTRAP:-}"

plist_version="$(plutil -extract CFBundleShortVersionString raw "$info_plist")"
if [[ "$plist_version" != "$version" ]]; then
  printf 'ERROR: Info.plist version is %s, expected %s.\n' "$plist_version" "$version" >&2
  exit 1
fi
if [[ -n "$(git -C "$project_dir" status --short)" ]]; then
  printf 'ERROR: release source checkout is not clean.\n' >&2
  exit 1
fi

if [[ -z "$bootstrap" || ! -f "$bootstrap" ]]; then
  printf 'ERROR: set DESK2SHELL_WINDOWS_BOOTSTRAP to the artifact built from this commit by the GitHub Windows runner.\n' >&2
  exit 1
fi

mkdir -p "$artifact_dir" "$resource_dir" "$sparkle_tools_dir"
file "$bootstrap" | grep -q 'PE32+'
cp "$bootstrap" "$resource_dir/Desk2Shell Bootstrap.exe"

DESK2SHELL_APPLE_SIGN_IDENTITY="$identity" "$project_dir/scripts/build-macos-app.sh" "$artifact_dir"
app="$artifact_dir/Desk2Shell.app"
test -f "$app/Contents/Resources/Desk2ShellApp_Desk2ShellApp.bundle/Resources/Desk2Shell Bootstrap.exe"
test "$(plutil -extract CFBundleVersion raw "$app/Contents/Info.plist")" = "1"
test "$(plutil -extract LSMinimumSystemVersion raw "$app/Contents/Info.plist")" = "14.0"
test "$(lipo -archs "$app/Contents/MacOS/Desk2Shell")" = "arm64"
codesign --verify --deep --strict --verbose=2 "$app"

"$project_dir/scripts/create-dmg.sh" "$app" "$version" "$dmg"
xcrun notarytool submit "$dmg" --keychain-profile "$notary_profile" --wait --output-format json > "$artifact_dir/notary.json"
test "$(plutil -extract status raw "$artifact_dir/notary.json")" = "Accepted"
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl -a -t open --context context:primary-signature -vv "$dmg"
hdiutil verify "$dmg" >/dev/null
shasum -a 256 "$dmg" > "$dmg.sha256"

sparkle_archive="$artifact_dir/Sparkle-$sparkle_version.tar.xz"
curl -L --fail --silent --show-error \
  -o "$sparkle_archive" \
  "https://github.com/sparkle-project/Sparkle/releases/download/$sparkle_version/Sparkle-$sparkle_version.tar.xz"
test "$(shasum -a 256 "$sparkle_archive" | awk '{print $1}')" = "$sparkle_archive_sha256"
tar -xJf "$sparkle_archive" -C "$sparkle_tools_dir"
"$sparkle_tools_dir/bin/sign_update" --account desk2shell "$dmg" > "$artifact_dir/sparkle-signature.txt"

printf '%s\n%s\n%s\n' "$dmg" "$dmg.sha256" "$artifact_dir/sparkle-signature.txt"
