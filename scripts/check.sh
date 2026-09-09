#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dotnet_bin="$(command -v dotnet || true)"
if [[ -z "$dotnet_bin" && -x /opt/homebrew/opt/dotnet@8/bin/dotnet ]]; then
  dotnet_bin="/opt/homebrew/opt/dotnet@8/bin/dotnet"
fi
if [[ -z "$dotnet_bin" ]]; then
  printf 'ERROR: .NET 8 SDK is required.\n' >&2
  exit 1
fi
dotnet_root="${DOTNET_ROOT:-/opt/homebrew/opt/dotnet@8/libexec}"

swift test --package-path "$project_dir/macos/Desk2ShellApp"
DOTNET_ROOT="$dotnet_root" DOTNET_ROLL_FORWARD=Major "$dotnet_bin" run --project "$project_dir/windows/Desk2Shell.Core.Tests/Desk2Shell.Core.Tests.csproj"
if [[ "$(uname -s)" != "Darwin" ]]; then
  DOTNET_ROOT="$dotnet_root" "$dotnet_bin" build "$project_dir/windows/Desk2Shell.Bootstrap/Desk2Shell.Bootstrap.csproj" -c Release -r win-x64
else
  printf 'SKIP: WinForms Bootstrap compilation runs on the GitHub Windows runner.\n'
fi
"$project_dir/tests/security-smoke.sh"

printf 'PASS: Desk2Shell local tests and security contract checks.\n'
