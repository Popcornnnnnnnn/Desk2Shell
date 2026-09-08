[CmdletBinding()]
param(
    [switch]$LogoutTailscale
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Remove-KeyLine([string]$Path, [string]$Key) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $remaining = @(Get-Content -LiteralPath $Path | Where-Object { $_.Trim() -ne $Key.Trim() })
    Set-Content -LiteralPath $Path -Value $remaining -Encoding ascii
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run rollback.ps1 from an administrator PowerShell.'
}

$fallbackConfigPath = Join-Path $PSScriptRoot 'rollback-config.json'
$statePath = Join-Path $env:ProgramData 'ToDeskSshBootstrap\state.json'
$state = $null
if (Test-Path -LiteralPath $statePath) {
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
} elseif (Test-Path -LiteralPath $fallbackConfigPath) {
    $fallback = Get-Content -LiteralPath $fallbackConfigPath -Raw | ConvertFrom-Json
    $targetUser = [string]$fallback.windows_user
    if ([string]::IsNullOrWhiteSpace($targetUser)) { $targetUser = $env:USERNAME }
    $state = [pscustomobject]@{
        ssh_public_key = [string]$fallback.ssh_public_key
        admin_keys_path = (Join-Path $env:ProgramData 'ssh\administrators_authorized_keys')
        user_keys_path = (Join-Path (Join-Path (Split-Path $env:USERPROFILE -Parent) $targetUser) '.ssh\authorized_keys')
        firewall_rule = 'ToDesk-SSH-Bootstrap-Tailscale'
        openssh_was_installed = $false
        sshd_was_running = $false
        sshd_start_mode = $null
        default_firewall_rule_existed = $false
        default_firewall_rule_was_enabled = $false
    }
} else {
    throw 'No rollback state or rollback-config.json was found.'
}

Remove-KeyLine -Path ([string]$state.admin_keys_path) -Key ([string]$state.ssh_public_key)
Remove-KeyLine -Path ([string]$state.user_keys_path) -Key ([string]$state.ssh_public_key)
Get-NetFirewallRule -Name ([string]$state.firewall_rule) -ErrorAction SilentlyContinue | Remove-NetFirewallRule

$defaultRule = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
if ($defaultRule -and [bool]$state.default_firewall_rule_existed) {
    if ([bool]$state.default_firewall_rule_was_enabled) {
        $defaultRule | Enable-NetFirewallRule
    } else {
        $defaultRule | Disable-NetFirewallRule
    }
}

if ([bool]$state.openssh_was_installed) {
    switch ([string]$state.sshd_start_mode) {
        'Auto' { Set-Service -Name sshd -StartupType Automatic }
        'Manual' { Set-Service -Name sshd -StartupType Manual }
        'Disabled' { Set-Service -Name sshd -StartupType Disabled }
    }
    if ([bool]$state.sshd_was_running) {
        Start-Service -Name sshd
    } else {
        Stop-Service -Name sshd -Force -ErrorAction SilentlyContinue
    }
} else {
    Stop-Service -Name sshd -Force -ErrorAction SilentlyContinue
    Set-Service -Name sshd -StartupType Disabled -ErrorAction SilentlyContinue
}

if ($LogoutTailscale) {
    $tailscale = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
    if (Test-Path -LiteralPath $tailscale) { & $tailscale logout }
}

if (Test-Path -LiteralPath $statePath) { Remove-Item -LiteralPath $statePath -Force }
Write-Host 'SSH bootstrap access removed.' -ForegroundColor Green
if (-not $LogoutTailscale) {
    Write-Host 'Tailscale remains connected. Re-run with -LogoutTailscale to disconnect it.'
}
