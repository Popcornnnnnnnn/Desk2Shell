using System.Diagnostics;
using System.ServiceProcess;

namespace Desk2Shell.Bootstrap;

internal sealed class SshWindowsService : ServiceBase
{
    private Process? sshd;
    private bool stopping;

    public SshWindowsService()
    {
        ServiceName = Installer.ServiceName;
        CanStop = true;
        CanShutdown = true;
        AutoLog = true;
    }

    protected override void OnStart(string[] args)
    {
        var sshdPath = Path.Combine(Environment.SystemDirectory, "OpenSSH", "sshd.exe");
        var configPath = Path.Combine(Installer.Root, "sshd_config");
        var logPath = Path.Combine(Installer.Root, "sshd.log");
        if (!File.Exists(sshdPath) || !File.Exists(configPath))
            throw new InvalidOperationException("Desk2Shell SSH files are missing.");

        var start = new ProcessStartInfo(sshdPath)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            WorkingDirectory = Installer.Root
        };
        start.ArgumentList.Add("-D");
        start.ArgumentList.Add("-f");
        start.ArgumentList.Add(configPath);
        start.ArgumentList.Add("-E");
        start.ArgumentList.Add(logPath);
        sshd = Process.Start(start) ?? throw new InvalidOperationException("Unable to start the isolated sshd process.");
        sshd.EnableRaisingEvents = true;
        sshd.Exited += (_, _) =>
        {
            if (!stopping) Environment.FailFast("The isolated sshd process exited unexpectedly.");
        };
    }

    protected override void OnStop() => StopChild();
    protected override void OnShutdown() => StopChild();

    private void StopChild()
    {
        stopping = true;
        if (sshd is null) return;
        try
        {
            if (!sshd.HasExited)
            {
                sshd.Kill(entireProcessTree: true);
                sshd.WaitForExit(5000);
            }
        }
        finally
        {
            sshd.Dispose();
            sshd = null;
        }
    }
}
