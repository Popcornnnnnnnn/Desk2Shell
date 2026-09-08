using System.Text;

namespace Desk2Shell.Bootstrap;

internal sealed class MainForm : Form
{
    private readonly TextBox enrollmentPath = new() { Dock = DockStyle.Fill };
    private readonly TextBox pairingCode = new() { Dock = DockStyle.Fill, UseSystemPasswordChar = true };
    private readonly TextBox output = new() { Dock = DockStyle.Fill, Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical };
    private readonly Button primary = new() { Height = 38, Dock = DockStyle.Top };
    private readonly TargetIdentity? target;
    private readonly bool elevatedInstall;

    public MainForm(string[] args)
    {
        Text = "Desk2Shell";
        Width = 720;
        Height = 520;
        StartPosition = FormStartPosition.CenterScreen;
        Font = new Font("Segoe UI", 10);

        var installIndex = Array.FindIndex(args, value => value.Equals("--install", StringComparison.OrdinalIgnoreCase));
        elevatedInstall = installIndex >= 0;
        if (elevatedInstall)
        {
            enrollmentPath.Text = ValueAfter(args, "--enrollment") ?? "";
            target = TargetIdentity.Decode(ValueAfter(args, "--target") ?? throw new InvalidOperationException("Target identity is missing."));
            BuildInstallScreen(true);
        }
        else if (args.Contains("--status", StringComparer.OrdinalIgnoreCase) || Installer.TryLoadState() is not null)
        {
            BuildStatusScreen();
        }
        else
        {
            target = TargetIdentity.Capture();
            var adjacent = Directory.GetFiles(AppContext.BaseDirectory, "*.d2s").SingleOrDefault();
            enrollmentPath.Text = adjacent ?? "";
            BuildInstallScreen(false);
        }
    }

    private void BuildInstallScreen(bool elevated)
    {
        var layout = BaseLayout(elevated ? "Complete secure setup" : "Turn this Windows session into temporary SSH access");
        layout.Controls.Add(LabelFor($"Windows account: {target!.LogonName}\r\nPermissions are inherited exactly as they are now."), 0, 1);

        var picker = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2 };
        picker.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        picker.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 100));
        picker.Controls.Add(enrollmentPath, 0, 0);
        var browse = new Button { Text = "Browse…", Dock = DockStyle.Fill };
        browse.Click += (_, _) => BrowseEnrollment();
        picker.Controls.Add(browse, 1, 0);
        layout.Controls.Add(Wrap("Enrollment file", picker), 0, 2);

        if (elevated)
        {
            layout.Controls.Add(Wrap("One-time pairing code", pairingCode), 0, 3);
            primary.Text = "Install temporary SSH access";
            primary.Click += async (_, _) => await InstallAsync();
        }
        else
        {
            layout.Controls.Add(LabelFor("The next step requests UAC elevation. If Windows asks for a different administrator credential, SSH still binds to the account shown above."), 0, 3);
            primary.Text = "Continue";
            primary.Click += (_, _) => StartElevatedInstall();
        }
        layout.Controls.Add(primary, 0, 4);
        layout.Controls.Add(output, 0, 5);
        Controls.Add(layout);
    }

    private void BuildStatusScreen()
    {
        var state = Installer.TryLoadState();
        var layout = BaseLayout("Desk2Shell access status");
        output.Text = state is null
            ? "No Desk2Shell state was found."
            : $"Status: {state.Status}\r\nWindows account: {state.WindowsUser}\r\nTarget: {state.TargetAlias} ({state.TargetIPv4}:{state.SshPort})\r\nController: {state.ControllerIPv4}\r\nExpires: {state.ExpiresAt}\r\nHost key: {state.HostKeyFingerprint}";
        layout.Controls.Add(output, 0, 1);
        var buttons = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.LeftToRight };
        var extend = new Button { Text = "Extend 24 hours", AutoSize = true };
        extend.Click += (_, _) => { Elevation.Relaunch("--extend-hours", "24"); Close(); };
        var revoke = new Button { Text = "Revoke now", AutoSize = true };
        revoke.Click += (_, _) => { Elevation.Relaunch("--revoke"); Close(); };
        buttons.Controls.Add(extend);
        buttons.Controls.Add(revoke);
        layout.Controls.Add(buttons, 0, 2);
        Controls.Add(layout);
    }

    private TableLayoutPanel BaseLayout(string title)
    {
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(22), RowCount = 6, ColumnCount = 1 };
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 58));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 48));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        layout.Controls.Add(new Label { Text = title, Font = new Font("Segoe UI", 18, FontStyle.Bold), AutoSize = true }, 0, 0);
        return layout;
    }

    private static Control LabelFor(string text) => new Label { Text = text, AutoSize = true, Padding = new Padding(0, 4, 0, 10) };

    private static Control Wrap(string label, Control control)
    {
        var panel = new TableLayoutPanel { Dock = DockStyle.Top, AutoSize = true, RowCount = 2, ColumnCount = 1, Padding = new Padding(0, 5, 0, 8) };
        panel.Controls.Add(new Label { Text = label, AutoSize = true }, 0, 0);
        panel.Controls.Add(control, 0, 1);
        return panel;
    }

    private void BrowseEnrollment()
    {
        using var dialog = new OpenFileDialog { Filter = "Desk2Shell enrollment (*.d2s)|*.d2s", CheckFileExists = true };
        if (dialog.ShowDialog(this) == DialogResult.OK) enrollmentPath.Text = dialog.FileName;
    }

    private void StartElevatedInstall()
    {
        if (!File.Exists(enrollmentPath.Text))
        {
            MessageBox.Show("Choose the .d2s enrollment file first.", "Desk2Shell", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }
        Elevation.Relaunch("--install", "--enrollment", Path.GetFullPath(enrollmentPath.Text), "--target", target!.Encode());
        Close();
    }

    private async Task InstallAsync()
    {
        primary.Enabled = false;
        try
        {
            var progress = new Progress<string>(message => output.AppendText(message + Environment.NewLine));
            var state = await new Installer().InstallAsync(enrollmentPath.Text, pairingCode.Text, target!, progress);
            pairingCode.Clear();
            output.AppendText($"\r\nREADY\r\nWindows account: {state.WindowsUser}\r\nTailscale IP: {state.TargetIPv4}\r\nSSH port: {state.SshPort}\r\nExpires: {state.ExpiresAt}\r\n\r\nReturn desk2shell-result.json to the Mac or enter the Windows account there, then verify SSH.\r\n");
            primary.Text = "Installed";
        }
        catch (Exception exception)
        {
            pairingCode.Clear();
            output.AppendText("\r\nFAILED: " + exception.Message + Environment.NewLine);
            primary.Enabled = true;
        }
    }

    private static string? ValueAfter(string[] args, string key)
    {
        var index = Array.FindIndex(args, value => value.Equals(key, StringComparison.OrdinalIgnoreCase));
        return index >= 0 && index + 1 < args.Length ? args[index + 1] : null;
    }
}
