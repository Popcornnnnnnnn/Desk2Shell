using System.Text.Json.Serialization;

namespace Desk2Shell.Core;

public sealed record EnrollmentEnvelope(
    [property: JsonPropertyName("schemaVersion")] int SchemaVersion,
    [property: JsonPropertyName("enrollmentId")] string EnrollmentId,
    [property: JsonPropertyName("createdAt")] string CreatedAt,
    [property: JsonPropertyName("nonce")] string Nonce,
    [property: JsonPropertyName("ciphertext")] string Ciphertext,
    [property: JsonPropertyName("tag")] string Tag);

public sealed class EnrollmentPayload
{
    [JsonPropertyName("schemaVersion")]
    public int SchemaVersion { get; init; }

    [JsonPropertyName("enrollmentId")]
    public required string EnrollmentId { get; init; }

    [JsonPropertyName("targetAlias")]
    public required string TargetAlias { get; init; }

    [JsonPropertyName("controllerPublicKey")]
    public required string ControllerPublicKey { get; init; }

    [JsonPropertyName("controllerTailscaleIPv4")]
    public required string ControllerTailscaleIPv4 { get; init; }

    [JsonPropertyName("controllerNodeName")]
    public required string ControllerNodeName { get; init; }

    [JsonPropertyName("tailnetName")]
    public required string TailnetName { get; init; }

    [JsonPropertyName("createdAt")]
    public required string CreatedAt { get; init; }

    [JsonPropertyName("expiresAt")]
    public required string ExpiresAt { get; set; }

    [JsonPropertyName("tailscaleAuthKey")]
    public required string TailscaleAuthKey { get; set; }
}
