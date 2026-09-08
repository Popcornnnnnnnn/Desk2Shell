using System.Globalization;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Desk2Shell.Core;

public static partial class EnrollmentCryptography
{
    public const int SchemaVersion = 1;
    public const string AadPrefix = "Desk2Shell.Enrollment.v1:";

    public static EnrollmentPayload Open(string envelopeJson, string pairingCode, DateTimeOffset? now = null)
    {
        var envelope = JsonSerializer.Deserialize<EnrollmentEnvelope>(envelopeJson, JsonOptions)
            ?? throw new EnrollmentException("enrollment_invalid", "The enrollment file is not valid JSON.");
        if (envelope.SchemaVersion != SchemaVersion)
            throw new EnrollmentException("schema_unsupported", $"Enrollment schema {envelope.SchemaVersion} is not supported.");

        var key = DecodePairingCode(pairingCode);
        var nonce = DecodeBase64(envelope.Nonce, 12, "nonce");
        var ciphertext = DecodeBase64(envelope.Ciphertext, null, "ciphertext");
        var tag = DecodeBase64(envelope.Tag, 16, "tag");
        var plaintext = new byte[ciphertext.Length];
        try
        {
            using var aes = new AesGcm(key, tag.Length);
            aes.Decrypt(
                nonce,
                ciphertext,
                tag,
                plaintext,
                Encoding.UTF8.GetBytes(AadPrefix + envelope.EnrollmentId));
            var payload = JsonSerializer.Deserialize<EnrollmentPayload>(plaintext, JsonOptions)
                ?? throw new EnrollmentException("payload_invalid", "The decrypted enrollment payload is empty.");
            Validate(payload, envelope, now ?? DateTimeOffset.UtcNow);
            return payload;
        }
        catch (CryptographicException exception)
        {
            throw new EnrollmentException("pairing_failed", "The pairing code is incorrect or the enrollment file was changed.", exception);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(key);
            CryptographicOperations.ZeroMemory(plaintext);
        }
    }

    public static byte[] DecodePairingCode(string value)
    {
        var compact = new string(value.Where(Uri.IsHexDigit).ToArray());
        if (compact.Length != 64)
            throw new EnrollmentException("pairing_code_invalid", "The pairing code must contain 64 hexadecimal characters.");
        try { return Convert.FromHexString(compact); }
        catch (FormatException exception)
        {
            throw new EnrollmentException("pairing_code_invalid", "The pairing code is malformed.", exception);
        }
    }

    public static void Validate(EnrollmentPayload payload, EnrollmentEnvelope envelope, DateTimeOffset now)
    {
        if (payload.SchemaVersion != SchemaVersion || payload.EnrollmentId != envelope.EnrollmentId)
            throw new EnrollmentException("payload_mismatch", "The envelope and payload do not match.");
        if (!AliasRegex().IsMatch(payload.TargetAlias))
            throw new EnrollmentException("alias_invalid", "The target alias is invalid.");
        if (!PublicKeyRegex().IsMatch(payload.ControllerPublicKey))
            throw new EnrollmentException("ssh_key_invalid", "The controller SSH public key is invalid.");
        if (!IsTailscaleIPv4(payload.ControllerTailscaleIPv4))
            throw new EnrollmentException("controller_ip_invalid", "The controller address is not a Tailscale IPv4 address.");
        if (string.IsNullOrWhiteSpace(payload.ControllerNodeName) || string.IsNullOrWhiteSpace(payload.TailnetName))
            throw new EnrollmentException("tailnet_invalid", "Controller node or tailnet identity is missing.");
        if (!payload.TailscaleAuthKey.StartsWith("tskey-auth-", StringComparison.Ordinal) &&
            !payload.TailscaleAuthKey.StartsWith("tskey-client-", StringComparison.Ordinal))
            throw new EnrollmentException("auth_key_invalid", "The Tailscale Auth Key is malformed.");

        var created = ParseDate(payload.CreatedAt, "createdAt");
        var expires = ParseDate(payload.ExpiresAt, "expiresAt");
        if (created > now.AddMinutes(5))
            throw new EnrollmentException("created_in_future", "The enrollment creation time is in the future.");
        if (expires <= now)
            throw new EnrollmentException("enrollment_expired", "The enrollment has expired.");
        if (expires - created > TimeSpan.FromDays(7))
            throw new EnrollmentException("lifetime_too_long", "The enrollment lifetime exceeds seven days.");
    }

    public static DateTimeOffset ParseDate(string value, string field)
    {
        if (!DateTimeOffset.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var parsed))
            throw new EnrollmentException("date_invalid", $"{field} is not an RFC3339 date.");
        return parsed;
    }

    public static bool IsTailscaleIPv4(string value)
    {
        if (!IPAddress.TryParse(value, out var address) || address.AddressFamily != System.Net.Sockets.AddressFamily.InterNetwork)
            return false;
        var bytes = address.GetAddressBytes();
        return bytes[0] == 100 && bytes[1] is >= 64 and <= 127;
    }

    private static byte[] DecodeBase64(string value, int? expectedLength, string field)
    {
        try
        {
            var bytes = Convert.FromBase64String(value);
            if (expectedLength is not null && bytes.Length != expectedLength)
                throw new EnrollmentException("envelope_invalid", $"The {field} length is invalid.");
            return bytes;
        }
        catch (FormatException exception)
        {
            throw new EnrollmentException("envelope_invalid", $"The {field} is not base64.", exception);
        }
    }

    public static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true
    };

    [GeneratedRegex("^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$")]
    private static partial Regex AliasRegex();

    [GeneratedRegex("^(ssh-ed25519|ssh-rsa|ecdsa-sha2-[^ ]+|sk-ssh-ed25519@openssh.com|sk-ecdsa-sha2-nistp256@openssh.com) [A-Za-z0-9+/=]+(?: .*)?$")]
    private static partial Regex PublicKeyRegex();
}

public sealed class EnrollmentException : Exception
{
    public EnrollmentException(string code, string message, Exception? inner = null) : base(message, inner) => Code = code;
    public string Code { get; }
}
