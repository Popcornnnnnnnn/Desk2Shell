using System.Security.Principal;
using System.Text;
using System.Text.Json;

namespace Desk2Shell.Bootstrap;

internal sealed record TargetIdentity(string UserName, string Domain, string Sid, string ProfilePath)
{
    public string LogonName => string.IsNullOrWhiteSpace(Domain) || Domain == "." || Domain.Equals(Environment.MachineName, StringComparison.OrdinalIgnoreCase)
        ? UserName
        : $"{Domain}\\{UserName}";

    public static TargetIdentity Capture()
    {
        using var identity = WindowsIdentity.GetCurrent();
        var name = identity.Name.Split('\\', 2);
        return new TargetIdentity(
            name.Length == 2 ? name[1] : Environment.UserName,
            name.Length == 2 ? name[0] : Environment.UserDomainName,
            identity.User?.Value ?? throw new InvalidOperationException("Cannot determine the current Windows SID."),
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile));
    }

    public string Encode() => Convert.ToBase64String(Encoding.UTF8.GetBytes(JsonSerializer.Serialize(this)))
        .TrimEnd('=').Replace('+', '-').Replace('/', '_');

    public static TargetIdentity Decode(string encoded)
    {
        var normalized = encoded.Replace('-', '+').Replace('_', '/');
        normalized += new string('=', (4 - normalized.Length % 4) % 4);
        return JsonSerializer.Deserialize<TargetIdentity>(Convert.FromBase64String(normalized))
            ?? throw new InvalidOperationException("Target identity is missing.");
    }

    public void Validate()
    {
        if (UserName.Length is < 1 or > 64 || UserName.Any(char.IsWhiteSpace) || UserName.Contains('/') || UserName.Contains('\\'))
            throw new InvalidOperationException("Windows accounts containing whitespace or path separators are not supported in v0.1.");
        if (Domain.Equals("AzureAD", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Microsoft Entra-only Windows accounts do not support OpenSSH public-key login in v0.1.");
        _ = new SecurityIdentifier(Sid);
        if (!Directory.Exists(ProfilePath))
            throw new InvalidOperationException("The captured Windows user profile no longer exists.");
    }
}
