#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bootstrap_dir="$project_dir/windows/Desk2Shell.Bootstrap"

search_quiet() {
  local pattern="$1"
  local path="$2"
  if command -v rg >/dev/null 2>&1; then
    rg -q "$pattern" "$path"
  else
    grep -Eq "$pattern" "$path"
  fi
}

search_product_paths() {
  local pattern="$1"
  shift
  if command -v rg >/dev/null 2>&1; then
    rg -n "$pattern" "$@"
  else
    grep -EnR "$pattern" "$@"
  fi
}

search_quiet 'AES-256-GCM' "$project_dir/docs/enrollment-v1.md"
search_quiet 'ListenAddress \{targetIPv4\}' "$bootstrap_dir/Installer.cs"
search_quiet 'localport=\{SshPort\}' "$bootstrap_dir/Installer.cs"
search_quiet 'remoteip=\{payload.ControllerTailscaleIPv4\}' "$bootstrap_dir/Installer.cs"
search_quiet 'PasswordAuthentication no' "$bootstrap_dir/Installer.cs"
search_quiet 'Desk2Shell-Expiry' "$bootstrap_dir/Installer.cs"

if search_product_paths 'administrators_authorized_keys|LocalPort 22|localport=22' \
  "$project_dir/macos" "$project_dir/windows" "$project_dir/scripts"; then
  printf 'FAIL: product path contains the legacy shared-admin key or port-22 setup.\n' >&2
  exit 1
fi

printf 'PASS: isolated listener, scoped firewall, public-key-only auth, and expiry contracts are present.\n'
