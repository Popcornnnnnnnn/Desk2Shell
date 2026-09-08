#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bootstrap_dir="$project_dir/windows/Desk2Shell.Bootstrap"

rg -q 'AES-256-GCM' "$project_dir/docs/enrollment-v1.md"
rg -q 'ListenAddress \{targetIPv4\}' "$bootstrap_dir/Installer.cs"
rg -q 'localport=\{SshPort\}' "$bootstrap_dir/Installer.cs"
rg -q 'remoteip=\{payload.ControllerTailscaleIPv4\}' "$bootstrap_dir/Installer.cs"
rg -q 'PasswordAuthentication no' "$bootstrap_dir/Installer.cs"
rg -q 'Desk2Shell-Expiry' "$bootstrap_dir/Installer.cs"

if rg -n 'administrators_authorized_keys|LocalPort 22|localport=22' \
  "$project_dir/macos" "$project_dir/windows" "$project_dir/scripts"; then
  printf 'FAIL: product path contains the legacy shared-admin key or port-22 setup.\n' >&2
  exit 1
fi

printf 'PASS: isolated listener, scoped firewall, public-key-only auth, and expiry contracts are present.\n'
