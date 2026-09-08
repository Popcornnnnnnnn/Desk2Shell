#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

swift test --package-path "$project_dir/macos/Desk2ShellApp"
DOTNET_ROLL_FORWARD=Major dotnet run --project "$project_dir/windows/Desk2Shell.Core.Tests/Desk2Shell.Core.Tests.csproj"
dotnet build "$project_dir/windows/Desk2Shell.Bootstrap/Desk2Shell.Bootstrap.csproj" -c Release -r win-x64
"$project_dir/tests/security-smoke.sh"

printf 'PASS: Desk2Shell macOS, protocol, Windows compile, and security contract checks.\n'
