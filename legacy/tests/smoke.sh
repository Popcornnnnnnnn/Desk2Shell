#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/todesk-ssh-test.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

fake_key_file="$tmp_dir/auth.key"
fake_pub_file="$tmp_dir/id.pub"
fake_auth='tskey-auth-test-only-not-a-real-secret'
printf '%s\n' "$fake_auth" > "$fake_key_file"
printf '%s\n' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestOnlyFakePublicKey000000000000000000000 test' > "$fake_pub_file"
chmod 600 "$fake_key_file"

output="$tmp_dir/package.zip"
build_output="$tmp_dir/build.out"
"$project_dir/bin/build-package" \
  --hostname test-win10 \
  --auth-key-file "$fake_key_file" \
  --public-key "$fake_pub_file" \
  --controller-ip 100.64.10.20 \
  --no-installer \
  --output "$output" > "$build_output"

test -s "$output"
if grep -q "$fake_auth" "$build_output"; then
  printf 'FAIL: build output leaked the auth key\n' >&2
  exit 1
fi

unzip -q "$output" -d "$tmp_dir/unpacked"
payload="$tmp_dir/unpacked/todesk-ssh-test-win10"
for file in RUN-AS-ADMIN.cmd README.txt bootstrap.ps1 rollback.ps1 config.json rollback-config.json; do
  test -f "$payload/$file"
done

jq -e --arg key "$fake_auth" --arg ip '100.64.10.20' \
  '.auth_key == $key and .controller_ip == $ip and .hostname == "test-win10"' \
  "$payload/config.json" >/dev/null

if rg -F "$fake_auth" "$payload/bootstrap.ps1" "$payload/rollback.ps1" "$payload/README.txt" >/dev/null; then
  printf 'FAIL: auth key was embedded outside config.json\n' >&2
  exit 1
fi

if command -v pwsh >/dev/null 2>&1; then
  for script in "$payload/bootstrap.ps1" "$payload/rollback.ps1"; do
    SCRIPT_TO_PARSE="$script" pwsh -NoProfile -NonInteractive -Command \
      '$tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile($env:SCRIPT_TO_PARSE,[ref]$tokens,[ref]$errors) > $null; if($errors.Count){$errors|Out-String|Write-Error; exit 1}'
  done
fi

if "$project_dir/bin/build-package" --hostname 'bad name' --auth-key-file "$fake_key_file" --public-key "$fake_pub_file" --controller-ip 100.64.10.20 --no-installer --output "$tmp_dir/bad.zip" >/dev/null 2>&1; then
  printf 'FAIL: invalid hostname was accepted\n' >&2
  exit 1
fi

printf 'PASS: package structure, secret boundary, validation, and PowerShell syntax checks passed.\n'
