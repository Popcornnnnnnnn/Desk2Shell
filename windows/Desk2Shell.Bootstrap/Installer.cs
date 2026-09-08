using System.Diagnostics;
using System.Net.Http;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
using System.Text.Json;
using Desk2Shell.Core;

namespace Desk2Shell.Bootstrap;

internal sealed class Installer
{
    internal const string ServiceName = "Desk2ShellSSHD";
    internal const string FirewallRule = "Desk2Shell-SSH";
    internal const string ExpiryTask = "Desk2Shell-Expiry";
    internal const int SshPort = 2222;
    internal static readonly string Root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "Desk2Shell");
    internal static readonly string StatePath = Path.Combine(Root, "state.json");
    internal static readonly string InstalledExe = Path.Combine(Root, "Desk2Shell Bootstrap.exe");
    private static readonly JsonSerializerOptions JsonOptions = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase, WriteIndented = true };

    public async Task<BootstrapState> InstallAsync(
        string enrollmentPath,
        string pairingCode,
        TargetIdentity target,
        IProgress<string>? progress = null,
        CancellationToken cancellationToken = default)
    {
        RequireAdministrator();
        ValidatePlatform();
        target.Validate();
        if (!File.Exists(enrollmentPath)) throw new BootstrapException("enrollment_missing", "The selected .d2s file does not exist.");
        if (TryLoadState() is { Status: "active" })
            throw new BootstrapException("enrollment_exists", "This computer already has active Desk2Shell access. Revoke it before enrolling again.");

        progress?.Report("Decrypting and validating enrollment…");
        var payload = EnrollmentCryptography.Open(await File.ReadAllTextAsync(enrollmentPath, cancellationToken), pairingCode);
        var enrolledTailscale = false;
        var serviceCreated = false;
        var firewallCreated = false;
        var rootCreated = false;
        try
        {
            Directory.CreateDirectory(Root);
            rootCreated = true;
            await SecureDirectoryAsync(Root, cancellationToken);
            CopySelfToInstalledLocation();

            progress?.Report("Checking Tailscale…");
            var tailscale = await EnsureTailscaleAsync(progress, cancellationToken);
            var before = await ReadTailscaleStatusAsync(tailscale, cancellationToken);
            if (before.IsConnected)
            {
                if (!string.Equals(NormalizeTailnet(before.TailnetName), NormalizeTailnet(payload.TailnetName), StringComparison.OrdinalIgnoreCase))
                    throw new BootstrapException("tailnet_mismatch", "Tailscale is already connected to a different tailnet. Desk2Shell did not log it out or replace it.");
                await RunTailscaleUpAsync(tailscale, payload.TargetAlias, null, cancellationToken);
            }
            else
            {
                await RunTailscaleUpAsync(tailscale, payload.TargetAlias, payload.TailscaleAuthKey, cancellationToken);
                enrolledTailscale = true;
            }
            payload.TailscaleAuthKey = string.Empty;

            var tailscaleStatus = await ReadTailscaleStatusAsync(tailscale, cancellationToken);
            if (!tailscaleStatus.IsConnected || tailscaleStatus.IPv4 is null)
                throw new BootstrapException("tailscale_not_ready", "Tailscale did not return an active IPv4 address after enrollment.");

            progress?.Report("Installing the Windows OpenSSH capability…");
            var sshd = await EnsureOpenSshAsync(cancellationToken);
            await ConfigureSshAsync(sshd, payload, target, tailscaleStatus.IPv4, cancellationToken);

            var fingerprint = await CommandRunner.CheckedAsync(
                Path.Combine(Path.GetDirectoryName(sshd)!, "ssh-keygen.exe"),
                ["-lf", Path.Combine(Root, "ssh_host_ed25519_key.pub"), "-E", "sha256"],
                "host_key_fingerprint",
                cancellationToken);
            fingerprint = fingerprint.Split(' ', StringSplitOptions.RemoveEmptyEntries).Skip(1).FirstOrDefault() ?? fingerprint;

            progress?.Report("Creating the isolated SSH service…");
            await EnsureNoStaleServiceAsync(cancellationToken);
            var binaryPath = $"\"{InstalledExe}\" --service";
            await CommandRunner.CheckedAsync("sc.exe", ["create", ServiceName, "binPath=", binaryPath, "start=", "auto", "DisplayName=", "Desk2Shell temporary SSH"], "service_create", cancellationToken);
            serviceCreated = true;
            await CommandRunner.CheckedAsync("sc.exe", ["description", ServiceName, "Temporary SSH access managed by Desk2Shell"], "service_description", cancellationToken);
            await CommandRunner.CheckedAsync("sc.exe", ["config", ServiceName, "depend=", "Tailscale"], "service_dependency", cancellationToken);
            await CommandRunner.CheckedAsync("sc.exe", ["failure", ServiceName, "reset=", "86400", "actions=", "restart/5000/restart/15000/restart/30000"], "service_recovery", cancellationToken);

            progress?.Report("Restricting the Windows firewall to the controller…");
            await CommandRunner.CheckedAsync("netsh.exe", [
                "advfirewall", "firewall", "add", "rule",
                $"name={FirewallRule}", "dir=in", "action=allow", "enable=yes", "profile=any",
                "protocol=TCP", $"localport={SshPort}", $"localip={tailscaleStatus.IPv4}",
                $"remoteip={payload.ControllerTailscaleIPv4}", $"program={sshd}"
            ], "firewall_create", cancellationToken);
            firewallCreated = true;

            var state = new BootstrapState
            {
                EnrollmentId = payload.EnrollmentId,
                TargetAlias = payload.TargetAlias,
                WindowsUser = target.LogonName,
                TargetSid = target.Sid,
                ControllerIPv4 = payload.ControllerTailscaleIPv4,
                TargetIPv4 = tailscaleStatus.IPv4,
                SshPort = SshPort,
                HostKeyFingerprint = fingerprint,
                ExpiresAt = payload.ExpiresAt,
                TailscaleEnrolledByDesk2Shell = enrolledTailscale,
                Status = "active"
            };
            SaveState(state);
            await ScheduleExpiryAsync(EnrollmentCryptography.ParseDate(state.ExpiresAt, "expiresAt"), cancellationToken);
            await CommandRunner.CheckedAsync("sc.exe", ["start", ServiceName], "service_start", cancellationToken);
            await WaitForListenerAsync(state.TargetIPv4, state.SshPort, cancellationToken);
            var resultPath = await WriteResultAsync(state, target, enrollmentPath, cancellationToken);
            await TrySendResultWithTaildropAsync(tailscale, payload.ControllerNodeName, resultPath, cancellationToken);
            await TryCreateStatusShortcutAsync(cancellationToken);
            progress?.Report("READY");
            return state;
        }
        catch
        {
            payload.TailscaleAuthKey = string.Empty;
            await CleanupFailedInstallAsync(serviceCreated, firewallCreated, enrolledTailscale, rootCreated, cancellationToken);
            throw;
        }
    }

    public async Task RevokeAsync(CancellationToken cancellationToken = default)
    {
        RequireAdministrator();
        var state = TryLoadState();
        await IgnoreFailure(() => CommandRunner.RunAsync("sc.exe", ["stop", ServiceName], cancellationToken));
        await IgnoreFailure(() => CommandRunner.RunAsync("sc.exe", ["delete", ServiceName], cancellationToken));
        await IgnoreFailure(() => CommandRunner.RunAsync("netsh.exe", ["advfirewall", "firewall", "delete", "rule", $"name={FirewallRule}"], cancellationToken));
        await IgnoreFailure(() => CommandRunner.RunAsync("schtasks.exe", ["/Delete", "/TN", ExpiryTask, "/F"], cancellationToken));

        foreach (var name in new[] { "authorized_keys", "ssh_host_ed25519_key", "ssh_host_ed25519_key.pub", "sshd_config", "sshd.pid", "sshd.log" })
            TryDelete(Path.Combine(Root, name));

        if (state?.TailscaleEnrolledByDesk2Shell == true)
        {
            var tailscale = FindTailscale();
            if (tailscale is not null)
                await IgnoreFailure(() => CommandRunner.RunAsync(tailscale, ["logout"], cancellationToken));
        }
        if (state is not null)
        {
            state.Status = "revoked";
            SaveState(state);
        }
    }

    public async Task<BootstrapState> ExtendAsync(int hours, CancellationToken cancellationToken = default)
    {
        RequireAdministrator();
        if (hours is < 1 or > 168) throw new BootstrapException("extension_invalid", "Extension must be between 1 and 168 hours.");
        var state = TryLoadState() ?? throw new BootstrapException("state_missing", "No Desk2Shell state was found.");
        if (state.Status != "active") throw new BootstrapException("state_inactive", "Desk2Shell access is not active.");
        var expiry = DateTimeOffset.UtcNow.AddHours(hours);
        state.ExpiresAt = expiry.ToString("O");
        SaveState(state);
        await ScheduleExpiryAsync(expiry, cancellationToken);
        return state;
    }

    public static BootstrapState? TryLoadState()
    {
        try { return File.Exists(StatePath) ? JsonSerializer.Deserialize<BootstrapState>(File.ReadAllText(StatePath), JsonOptions) : null; }
        catch { return null; }
    }

    public static bool IsAdministrator()
    {
        using var identity = WindowsIdentity.GetCurrent();
        return new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator);
    }

    private static void RequireAdministrator()
    {
        if (!IsAdministrator()) throw new BootstrapException("administrator_required", "Administrator rights are required for this operation.");
    }

    private static void ValidatePlatform()
    {
        if (!OperatingSystem.IsWindows() || Environment.OSVersion.Version.Build < 19045)
            throw new BootstrapException("windows_unsupported", "Desk2Shell v0.1 requires Windows 10 22H2 or Windows 11.");
        if (RuntimeInformation.OSArchitecture != Architecture.X64)
            throw new BootstrapException("architecture_unsupported", "Desk2Shell v0.1 currently supports x64 Windows only.");
    }

    private static async Task<string> EnsureTailscaleAsync(IProgress<string>? progress, CancellationToken cancellationToken)
    {
        var existing = FindTailscale();
        if (existing is not null) return existing;

        progress?.Report("Downloading the official Tailscale installer…");
        var msi = Path.Combine(Path.GetTempPath(), "Desk2Shell-Tailscale.msi");
        using (var client = new HttpClient { Timeout = TimeSpan.FromMinutes(5) })
        using (var response = await client.GetAsync("https://pkgs.tailscale.com/stable/tailscale-setup-latest-amd64.msi", HttpCompletionOption.ResponseHeadersRead, cancellationToken))
        {
            response.EnsureSuccessStatusCode();
            await using var output = File.Create(msi);
            await response.Content.CopyToAsync(output, cancellationToken);
        }

        var escaped = msi.Replace("'", "''");
        var signature = await CommandRunner.PowerShellAsync(
            $"$s=Get-AuthenticodeSignature -LiteralPath '{escaped}'; Write-Output ($s.Status.ToString()+'|'+$s.SignerCertificate.Subject)",
            "tailscale_signature",
            cancellationToken);
        if (!signature.StartsWith("Valid|", StringComparison.OrdinalIgnoreCase) || !signature.Contains("Tailscale", StringComparison.OrdinalIgnoreCase))
            throw new BootstrapException("tailscale_signature_invalid", "The downloaded Tailscale installer does not have a valid Tailscale Authenticode signature.");

        var exit = await CommandRunner.RunAsync("msiexec.exe", ["/i", msi, "/qn", "/norestart"], cancellationToken);
        TryDelete(msi);
        if (exit.ExitCode is not (0 or 3010))
            throw new BootstrapException("tailscale_install_failed", $"Tailscale installation failed with exit code {exit.ExitCode}.");
        return FindTailscale() ?? throw new BootstrapException("tailscale_missing", "Tailscale was not found after installation.");
    }

    private static string? FindTailscale()
    {
        var candidates = new[]
        {
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Tailscale", "tailscale.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Tailscale", "tailscale.exe")
        };
        return candidates.FirstOrDefault(File.Exists);
    }

    private static async Task RunTailscaleUpAsync(string tailscale, string alias, string? authKey, CancellationToken cancellationToken)
    {
        var arguments = new List<string> { "up", $"--hostname={alias}", "--unattended=true", "--accept-dns=false", "--accept-routes=false" };
        if (!string.IsNullOrEmpty(authKey)) arguments.Add($"--auth-key={authKey}");
        var result = await CommandRunner.RunAsync(tailscale, arguments, cancellationToken);
        arguments.Clear();
        if (result.ExitCode != 0)
            throw new BootstrapException("tailscale_up_failed", $"Tailscale enrollment failed with exit code {result.ExitCode}: {result.StandardError.Trim()}");
    }

    private sealed record TailscaleState(bool IsConnected, string TailnetName, string? IPv4);

    private static async Task<TailscaleState> ReadTailscaleStatusAsync(string tailscale, CancellationToken cancellationToken)
    {
        var result = await CommandRunner.RunAsync(tailscale, ["status", "--json"], cancellationToken);
        if (result.ExitCode != 0 || string.IsNullOrWhiteSpace(result.StandardOutput)) return new(false, "", null);
        using var json = JsonDocument.Parse(result.StandardOutput);
        var root = json.RootElement;
        var backend = root.TryGetProperty("BackendState", out var backendValue) ? backendValue.GetString() ?? "" : "";
        var tailnet = root.TryGetProperty("CurrentTailnet", out var current) && current.TryGetProperty("Name", out var name) ? name.GetString() ?? "" : "";
        string? ip = null;
        if (root.TryGetProperty("Self", out var self) && self.TryGetProperty("TailscaleIPs", out var addresses))
            ip = addresses.EnumerateArray().Select(value => value.GetString()).FirstOrDefault(value => value is not null && EnrollmentCryptography.IsTailscaleIPv4(value));
        return new(backend.Equals("Running", StringComparison.OrdinalIgnoreCase) && ip is not null, tailnet, ip);
    }

    private static string NormalizeTailnet(string value) => value.Trim().TrimEnd('.');

    private static async Task<string> EnsureOpenSshAsync(CancellationToken cancellationToken)
    {
        var sshd = Path.Combine(Environment.SystemDirectory, "OpenSSH", "sshd.exe");
        if (!File.Exists(sshd))
        {
            var result = await CommandRunner.RunAsync("dism.exe", ["/Online", "/Add-Capability", "/CapabilityName:OpenSSH.Server~~~~0.0.1.0", "/NoRestart", "/Quiet"], cancellationToken);
            if (result.ExitCode is not (0 or 3010))
                throw new BootstrapException("openssh_install_failed", $"Windows OpenSSH installation failed with exit code {result.ExitCode}: {result.StandardError.Trim()}");
        }
        return File.Exists(sshd) ? sshd : throw new BootstrapException("openssh_missing", "sshd.exe was not found after OpenSSH installation.");
    }

    private static async Task ConfigureSshAsync(string sshd, EnrollmentPayload payload, TargetIdentity target, string targetIPv4, CancellationToken cancellationToken)
    {
        var sshDirectory = Path.GetDirectoryName(sshd)!;
        var keygen = Path.Combine(sshDirectory, "ssh-keygen.exe");
        var hostKey = Path.Combine(Root, "ssh_host_ed25519_key");
        if (!File.Exists(hostKey))
            await CommandRunner.CheckedAsync(keygen, ["-q", "-t", "ed25519", "-N", "", "-f", hostKey], "host_key_create", cancellationToken);

        var authorizedKeys = Path.Combine(Root, "authorized_keys");
        await File.WriteAllTextAsync(authorizedKeys, payload.ControllerPublicKey.Trim() + Environment.NewLine, Encoding.ASCII, cancellationToken);
        await CommandRunner.CheckedAsync("icacls.exe", [authorizedKeys, "/inheritance:r", "/grant:r", $"*{target.Sid}:R", "*S-1-5-18:F", "*S-1-5-32-544:F"], "authorized_keys_acl", cancellationToken);
        await CommandRunner.CheckedAsync("icacls.exe", [hostKey, "/inheritance:r", "/grant:r", "*S-1-5-18:F", "*S-1-5-32-544:F"], "host_key_acl", cancellationToken);

        var slashRoot = Root.Replace('\\', '/');
        var slashSftp = Path.Combine(sshDirectory, "sftp-server.exe").Replace('\\', '/');
        var allowUser = target.LogonName.ToLowerInvariant();
        var config = $"""
            Port {SshPort}
            ListenAddress {targetIPv4}
            HostKey {slashRoot}/ssh_host_ed25519_key
            PidFile {slashRoot}/sshd.pid
            AuthorizedKeysFile {slashRoot}/authorized_keys
            PubkeyAuthentication yes
            PasswordAuthentication no
            KbdInteractiveAuthentication no
            PermitEmptyPasswords no
            AllowUsers {allowUser}
            AllowTcpForwarding yes
            GatewayPorts no
            X11Forwarding no
            LogLevel ERROR
            Subsystem sftp {slashSftp}
            """;
        var configPath = Path.Combine(Root, "sshd_config");
        await File.WriteAllTextAsync(configPath, config + Environment.NewLine, new UTF8Encoding(false), cancellationToken);
        await CommandRunner.CheckedAsync("icacls.exe", [configPath, "/inheritance:r", "/grant:r", "*S-1-5-18:F", "*S-1-5-32-544:F"], "sshd_config_acl", cancellationToken);
        await CommandRunner.CheckedAsync(sshd, ["-t", "-f", configPath], "sshd_config_validate", cancellationToken);
    }

    private static async Task SecureDirectoryAsync(string path, CancellationToken cancellationToken) =>
        _ = await CommandRunner.CheckedAsync("icacls.exe", [path, "/inheritance:r", "/grant:r", "*S-1-5-18:(OI)(CI)F", "*S-1-5-32-544:(OI)(CI)F"], "state_directory_acl", cancellationToken);

    private static async Task EnsureNoStaleServiceAsync(CancellationToken cancellationToken)
    {
        var query = await CommandRunner.RunAsync("sc.exe", ["query", ServiceName], cancellationToken);
        if (query.ExitCode == 0)
            throw new BootstrapException("stale_service", "A Desk2ShellSSHD service already exists without active state. Remove it manually before continuing.");
    }

    private static async Task ScheduleExpiryAsync(DateTimeOffset expiry, CancellationToken cancellationToken)
    {
        var exe = InstalledExe.Replace("'", "''");
        var at = expiry.ToUniversalTime().ToString("O");
        var script = $"$a=New-ScheduledTaskAction -Execute '{exe}' -Argument '--revoke --scheduled';" +
                     $"$t=New-ScheduledTaskTrigger -Once -At ([DateTimeOffset]::Parse('{at}').LocalDateTime);" +
                     "$p=New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest;" +
                     "$s=New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 10);" +
                     $"Register-ScheduledTask -TaskName '{ExpiryTask}' -Action $a -Trigger $t -Principal $p -Settings $s -Force | Out-Null";
        await CommandRunner.PowerShellAsync(script, "expiry_schedule", cancellationToken);
    }

    private static async Task<string> WriteResultAsync(BootstrapState state, TargetIdentity target, string enrollmentPath, CancellationToken cancellationToken)
    {
        var result = new TargetResult(1, state.EnrollmentId, state.TargetAlias, state.WindowsUser, state.TargetIPv4, state.SshPort, state.HostKeyFingerprint, state.ExpiresAt);
        var json = JsonSerializer.Serialize(result, JsonOptions);
        var besideEnrollment = Path.Combine(Path.GetDirectoryName(enrollmentPath)!, "desk2shell-result.json");
        await File.WriteAllTextAsync(besideEnrollment, json, new UTF8Encoding(false), cancellationToken);
        var desktop = Path.Combine(target.ProfilePath, "Desktop");
        if (Directory.Exists(desktop))
            await File.WriteAllTextAsync(Path.Combine(desktop, "desk2shell-result.json"), json, new UTF8Encoding(false), cancellationToken);
        return besideEnrollment;
    }

    private static async Task TrySendResultWithTaildropAsync(string tailscale, string controllerNodeName, string resultPath, CancellationToken cancellationToken)
    {
        try
        {
            _ = await CommandRunner.RunAsync(
                tailscale,
                ["file", "cp", "--name", $"desk2shell-result-{Guid.NewGuid():N}.json", resultPath, $"{controllerNodeName}:"],
                cancellationToken);
        }
        catch { }
    }

    private static async Task WaitForListenerAsync(string address, int port, CancellationToken cancellationToken)
    {
        for (var attempt = 0; attempt < 20; attempt++)
        {
            try
            {
                using var client = new TcpClient();
                await client.ConnectAsync(address, port, cancellationToken).AsTask().WaitAsync(TimeSpan.FromSeconds(1), cancellationToken);
                return;
            }
            catch when (attempt < 19)
            {
                await Task.Delay(500, cancellationToken);
            }
        }
        throw new BootstrapException("ssh_listener_not_ready", "The isolated SSH service started but did not open its Tailscale listener.");
    }

    private static async Task TryCreateStatusShortcutAsync(CancellationToken cancellationToken)
    {
        try
        {
            var exe = InstalledExe.Replace("'", "''");
            var shortcut = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonPrograms), "Desk2Shell Access.lnk").Replace("'", "''");
            var script = $"$w=New-Object -ComObject WScript.Shell;$s=$w.CreateShortcut('{shortcut}');$s.TargetPath='{exe}';$s.Arguments='--status';$s.Save()";
            await CommandRunner.PowerShellAsync(script, "shortcut_create", cancellationToken);
        }
        catch { }
    }

    private static void CopySelfToInstalledLocation()
    {
        var current = Environment.ProcessPath ?? throw new BootstrapException("process_path_missing", "Cannot locate the running bootstrap executable.");
        if (!Path.GetFullPath(current).Equals(Path.GetFullPath(InstalledExe), StringComparison.OrdinalIgnoreCase))
            File.Copy(current, InstalledExe, true);
    }

    private static void SaveState(BootstrapState state)
    {
        Directory.CreateDirectory(Root);
        var temporary = StatePath + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(state, JsonOptions), new UTF8Encoding(false));
        File.Move(temporary, StatePath, true);
    }

    private static async Task CleanupFailedInstallAsync(bool serviceCreated, bool firewallCreated, bool enrolledTailscale, bool rootCreated, CancellationToken cancellationToken)
    {
        if (serviceCreated)
        {
            await IgnoreFailure(() => CommandRunner.RunAsync("sc.exe", ["stop", ServiceName], cancellationToken));
            await IgnoreFailure(() => CommandRunner.RunAsync("sc.exe", ["delete", ServiceName], cancellationToken));
        }
        if (firewallCreated)
            await IgnoreFailure(() => CommandRunner.RunAsync("netsh.exe", ["advfirewall", "firewall", "delete", "rule", $"name={FirewallRule}"], cancellationToken));
        await IgnoreFailure(() => CommandRunner.RunAsync("schtasks.exe", ["/Delete", "/TN", ExpiryTask, "/F"], cancellationToken));
        if (enrolledTailscale && FindTailscale() is { } tailscale)
            await IgnoreFailure(() => CommandRunner.RunAsync(tailscale, ["logout"], cancellationToken));
        if (rootCreated)
        {
            foreach (var name in new[] { "authorized_keys", "ssh_host_ed25519_key", "ssh_host_ed25519_key.pub", "sshd_config", "sshd.pid", "sshd.log", "state.json", "state.json.tmp" })
                TryDelete(Path.Combine(Root, name));
        }
    }

    private static async Task IgnoreFailure(Func<Task<CommandResult>> action)
    {
        try { _ = await action(); } catch { }
    }

    private static void TryDelete(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); } catch { }
    }
}
