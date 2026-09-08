using System.Diagnostics;

namespace Desk2Shell.Bootstrap;

internal static class Elevation
{
    public static void Relaunch(params string[] arguments)
    {
        var path = Environment.ProcessPath ?? throw new InvalidOperationException("Cannot locate the bootstrap executable.");
        var start = new ProcessStartInfo(path) { UseShellExecute = true, Verb = "runas" };
        foreach (var argument in arguments) start.ArgumentList.Add(argument);
        Process.Start(start);
    }
}
