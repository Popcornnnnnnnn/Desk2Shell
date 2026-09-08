[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Write-Step([string]$Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Add-KeyLine([string]$Path, [string]$Key) {
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType File -Path $Path -Force | Out-Null
    }
    $present = Select-String -LiteralPath $Path -SimpleMatch $Key -Quiet -ErrorAction SilentlyContinue
    if (-not $present) {
        Add-Content -LiteralPath $Path -Value $Key -Encoding ascii
    }
}

try {
    if (-not (Test-Administrator)) {
        throw 'Administrator rights are required. Right-click RUN-AS-ADMIN.cmd and choose Run as administrator.'
    }

    $configPath = Join-Path $PSScriptRoot 'config.json'
    if (-not (Test-Path -LiteralPath $configPath)) {
        throw 'config.json is missing. Extract the entire package before running it.'
    }
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    $authKey = [string]$config.auth_key
    $publicKey = [string]$config.ssh_public_key
    $deviceName = [string]$config.hostname
    $controllerIp = [string]$config.controller_ip
    $targetUser = [string]$config.windows_user
    if ([string]::IsNullOrWhiteSpace($targetUser)) { $targetUser = $env:USERNAME }

    if ($authKey -notmatch '^tskey-(auth|client)-') { throw 'Invalid Tailscale Auth Key in config.json.' }
    if ($publicKey -notmatch '^(ssh-|ecdsa-|sk-)') { throw 'Invalid SSH public key in config.json.' }
    if ($controllerIp -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { throw 'Invalid controller IP in config.json.' }

    $adminKeys = Join-Path $env:ProgramData 'ssh\administrators_authorized_keys'
    $userProfile = Join-Path (Split-Path $env:USERPROFILE -Parent) $targetUser
    $userKeys = Join-Path $userProfile '.ssh\authorized_keys'
    $ruleName = 'ToDesk-SSH-Bootstrap-Tailscale'
    $stateDir = Join-Path $env:ProgramData 'ToDeskSshBootstrap'
    $statePath = Join-Path $stateDir 'state.json'
    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null

    $initialCapability = Get-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0'
    $initialService = Get-Service -Name sshd -ErrorAction SilentlyContinue
    $initialServiceMode = $null
    if ($initialService) {
        $initialServiceMode = (Get-CimInstance Win32_Service -Filter "Name='sshd'").StartMode
    }
    $initialDefaultRule = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue

    [ordered]@{
        schema_version = 1
        started_at = (Get-Date).ToString('o')
        target_user = $targetUser
        ssh_public_key = $publicKey
        admin_keys_path = $adminKeys
        user_keys_path = $userKeys
        firewall_rule = $ruleName
        controller_ip = $controllerIp
        openssh_was_installed = ($initialCapability.State -eq 'Installed')
        sshd_was_running = ($initialService -and $initialService.Status -eq 'Running')
        sshd_start_mode = $initialServiceMode
        default_firewall_rule_existed = [bool]$initialDefaultRule
        default_firewall_rule_was_enabled = ($initialDefaultRule -and $initialDefaultRule.Enabled -eq 'True')
        completed = $false
    } | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding utf8

    Write-Step 'Installing Tailscale when needed'
    $tailscale = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
    if (-not (Test-Path -LiteralPath $tailscale)) {
        $installer = Join-Path $PSScriptRoot 'tailscale-setup-amd64.msi'
        if (-not (Test-Path -LiteralPath $installer)) {
            throw 'Tailscale is not installed and tailscale-setup-amd64.msi is missing.'
        }
        $signature = Get-AuthenticodeSignature -FilePath $installer
        if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
            throw "Tailscale installer signature is not valid: $($signature.Status)"
        }
        $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i', $installer, '/qn', '/norestart') -Wait -PassThru
        if ($process.ExitCode -notin @(0, 3010)) {
            throw "Tailscale MSI failed with exit code $($process.ExitCode)."
        }
        $tailscale = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
        if (-not (Test-Path -LiteralPath $tailscale)) { throw 'Tailscale CLI was not found after installation.' }
    }

    Write-Step 'Joining the Tailscale network in unattended mode'
    $existingTailscaleIp = (& $tailscale ip -4 2>$null | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace([string]$existingTailscaleIp)) {
        $env:TS_AUTH_KEY = $authKey
        & $tailscale up "--auth-key=$env:TS_AUTH_KEY" "--hostname=$deviceName" --unattended=true --accept-dns=false --accept-routes=false
        if ($LASTEXITCODE -ne 0) { throw "tailscale up failed with exit code $LASTEXITCODE." }
        Remove-Item Env:TS_AUTH_KEY -ErrorAction SilentlyContinue
        $authKey = $null
    } else {
        & $tailscale up "--hostname=$deviceName" --unattended=true --accept-dns=false --accept-routes=false
        if ($LASTEXITCODE -ne 0) { throw "tailscale up failed with exit code $LASTEXITCODE." }
    }

    $tailscaleIp = (& $tailscale ip -4 | Select-Object -First 1).Trim()
    if ($tailscaleIp -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { throw 'Tailscale did not return an IPv4 address.' }

    Write-Step 'Installing Windows OpenSSH Server'
    $capability = Get-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0'
    if ($capability.State -ne 'Installed') {
        Add-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0' | Out-Null
    }
    Set-Service -Name sshd -StartupType Automatic
    Start-Service -Name sshd

    Write-Step "Authorizing the SSH key for $targetUser"
    Add-KeyLine -Path $adminKeys -Key $publicKey
    & icacls.exe $adminKeys '/inheritance:r' '/grant:r' '*S-1-5-32-544:F' '*S-1-5-18:F' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Failed to secure administrators_authorized_keys permissions.' }

    Add-KeyLine -Path $userKeys -Key $publicKey
    & icacls.exe $userKeys '/inheritance:r' '/grant:r' "${targetUser}:F" '*S-1-5-18:F' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to secure authorized_keys permissions for $targetUser." }

    Write-Step 'Restricting SSH ingress to the controller Tailscale IP'
    Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    New-NetFirewallRule -Name $ruleName -DisplayName 'SSH from approved Tailscale controller only' `
        -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 `
        -RemoteAddress "$controllerIp/32" | Out-Null

    $defaultRule = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
    if ($defaultRule) { $defaultRule | Disable-NetFirewallRule }

    $savedState = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $savedState | Add-Member -NotePropertyName completed_at -NotePropertyValue (Get-Date).ToString('o') -Force
    $savedState | Add-Member -NotePropertyName tailscale_ip -NotePropertyValue $tailscaleIp -Force
    $savedState.completed = $true
    $savedState | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding utf8

    $resultPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'todesk-ssh-result.txt'
    @(
        'READY'
        "Windows user: $targetUser"
        "Computer name: $env:COMPUTERNAME"
        "Tailscale IP: $tailscaleIp"
        "SSH service: $((Get-Service sshd).Status)"
        "Allowed controller: $controllerIp/32"
    ) | Set-Content -LiteralPath $resultPath -Encoding utf8

    Remove-Item -LiteralPath $configPath -Force

    Write-Host "`nREADY" -ForegroundColor Green
    Write-Host "Windows user: $targetUser"
    Write-Host "Tailscale IP: $tailscaleIp"
    Write-Host "Result file: $resultPath"
    Write-Host 'Return that result file, verify SSH from the Mac, then delete this package.'
}
catch {
    Remove-Item Env:TS_AUTH_KEY -ErrorAction SilentlyContinue
    Write-Host "`nFAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'Keep ToDesk connected, take a screenshot of this window, and do not rerun repeatedly.'
    exit 1
}
