namespace Desk2Shell.Bootstrap;

internal sealed class BootstrapState
{
    public int SchemaVersion { get; init; } = 1;
    public required string EnrollmentId { get; init; } = "";
    public required string TargetAlias { get; init; } = "";
    public required string WindowsUser { get; init; } = "";
    public required string TargetSid { get; init; } = "";
    public required string ControllerIPv4 { get; init; } = "";
    public required string TargetIPv4 { get; init; } = "";
    public int SshPort { get; init; } = Installer.SshPort;
    public required string HostKeyFingerprint { get; init; } = "";
    public required string ExpiresAt { get; set; } = "";
    public bool TailscaleEnrolledByDesk2Shell { get; init; }
    public required string Status { get; set; } = "active";
}

internal sealed record TargetResult(
    int SchemaVersion,
    string EnrollmentId,
    string TargetAlias,
    string WindowsUser,
    string TailscaleIPv4,
    int SshPort,
    string HostKeyFingerprint,
    string ExpiresAt);
