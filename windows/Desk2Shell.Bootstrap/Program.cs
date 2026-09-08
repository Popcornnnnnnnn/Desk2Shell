namespace Desk2Shell.Bootstrap;

internal static class Program
{
    [STAThread]
    private static async Task Main(string[] args)
    {
        if (args.Contains("--service", StringComparer.OrdinalIgnoreCase))
        {
            System.ServiceProcess.ServiceBase.Run(new SshWindowsService());
            return;
        }
        ApplicationConfiguration.Initialize();
        try
        {
            if (args.Contains("--scheduled", StringComparer.OrdinalIgnoreCase))
            {
                if (args.Contains("--revoke", StringComparer.OrdinalIgnoreCase))
                    await new Installer().RevokeAsync();
                return;
            }

            var revokeIndex = Array.FindIndex(args, value => value.Equals("--revoke", StringComparison.OrdinalIgnoreCase));
            if (revokeIndex >= 0)
            {
                if (!Installer.IsAdministrator()) { Elevation.Relaunch("--revoke"); return; }
                await new Installer().RevokeAsync();
                MessageBox.Show("Desk2Shell access has been revoked.", "Desk2Shell", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            var extendIndex = Array.FindIndex(args, value => value.Equals("--extend-hours", StringComparison.OrdinalIgnoreCase));
            if (extendIndex >= 0 && extendIndex + 1 < args.Length && int.TryParse(args[extendIndex + 1], out var hours))
            {
                if (!Installer.IsAdministrator()) { Elevation.Relaunch("--extend-hours", hours.ToString()); return; }
                var state = await new Installer().ExtendAsync(hours);
                MessageBox.Show($"Access now expires at {state.ExpiresAt}.", "Desk2Shell", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            Application.Run(new MainForm(args));
        }
        catch (Exception exception)
        {
            MessageBox.Show(exception.Message, "Desk2Shell", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
}
