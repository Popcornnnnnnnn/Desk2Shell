using System.Diagnostics;
using System.Text;

namespace Desk2Shell.Bootstrap;

internal sealed record CommandResult(int ExitCode, string StandardOutput, string StandardError);

internal static class CommandRunner
{
    public static async Task<CommandResult> RunAsync(string executable, IEnumerable<string> arguments, CancellationToken cancellationToken = default)
    {
        using var process = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = executable,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
                StandardOutputEncoding = Encoding.UTF8,
                StandardErrorEncoding = Encoding.UTF8
            }
        };
        foreach (var argument in arguments) process.StartInfo.ArgumentList.Add(argument);
        process.Start();
        var stdout = process.StandardOutput.ReadToEndAsync(cancellationToken);
        var stderr = process.StandardError.ReadToEndAsync(cancellationToken);
        await process.WaitForExitAsync(cancellationToken);
        return new CommandResult(process.ExitCode, await stdout, await stderr);
    }

    public static async Task<string> CheckedAsync(string executable, IEnumerable<string> arguments, string operation, CancellationToken cancellationToken = default)
    {
        var result = await RunAsync(executable, arguments, cancellationToken);
        if (result.ExitCode != 0)
        {
            var detail = string.IsNullOrWhiteSpace(result.StandardError) ? result.StandardOutput : result.StandardError;
            throw new BootstrapException(operation, $"{operation} failed with exit code {result.ExitCode}: {detail.Trim()}");
        }
        return result.StandardOutput.Trim();
    }

    public static async Task<string> PowerShellAsync(string script, string operation, CancellationToken cancellationToken = default)
    {
        var encoded = Convert.ToBase64String(Encoding.Unicode.GetBytes("$ErrorActionPreference='Stop';" + script));
        return await CheckedAsync(
            Path.Combine(Environment.SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe"),
            ["-NoLogo", "-NoProfile", "-NonInteractive", "-EncodedCommand", encoded],
            operation,
            cancellationToken);
    }
}

internal sealed class BootstrapException : Exception
{
    public BootstrapException(string code, string message, Exception? inner = null) : base(message, inner) => Code = code;
    public string Code { get; }
}
