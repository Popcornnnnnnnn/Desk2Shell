using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Desk2Shell.Core;

var id = "11111111-2222-3333-4444-555555555555";
var created = "2026-09-08T00:00:00.000Z";
var expires = "2026-09-09T00:00:00.000Z";
var payload = new EnrollmentPayload
{
    SchemaVersion = 1,
    EnrollmentId = id,
    TargetAlias = "lab-win",
    ControllerPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestOnlyKey desk2shell:test",
    ControllerTailscaleIPv4 = "100.64.10.20",
    ControllerNodeName = "controller",
    TailnetName = "example.ts.net",
    CreatedAt = created,
    ExpiresAt = expires,
    TailscaleAuthKey = "tskey-auth-test-only"
};
var key = Enumerable.Range(0, 32).Select(value => (byte)value).ToArray();
var nonce = Enumerable.Range(1, 12).Select(value => (byte)value).ToArray();
var cleartext = JsonSerializer.SerializeToUtf8Bytes(payload, EnrollmentCryptography.JsonOptions);
var ciphertext = new byte[cleartext.Length];
var tag = new byte[16];
using (var aes = new AesGcm(key, tag.Length))
    aes.Encrypt(nonce, cleartext, ciphertext, tag, Encoding.UTF8.GetBytes(EnrollmentCryptography.AadPrefix + id));
var envelope = new EnrollmentEnvelope(1, id, created, Convert.ToBase64String(nonce), Convert.ToBase64String(ciphertext), Convert.ToBase64String(tag));
Assert(!JsonSerializer.Serialize(envelope).Contains(payload.TailscaleAuthKey, StringComparison.Ordinal), "transport excludes plaintext auth key");
var opened = EnrollmentCryptography.Open(
    JsonSerializer.Serialize(envelope, EnrollmentCryptography.JsonOptions),
    Convert.ToHexString(key),
    DateTimeOffset.Parse("2026-09-08T01:00:00Z"));
Assert(opened.TargetAlias == payload.TargetAlias, "round trip alias");
Assert(opened.TailscaleAuthKey == payload.TailscaleAuthKey, "round trip auth key");
Assert(EnrollmentCryptography.IsTailscaleIPv4("100.64.10.20"), "tailscale IPv4");
Assert(!EnrollmentCryptography.IsTailscaleIPv4("192.168.1.1"), "reject non-tailscale IPv4");

var damaged = envelope with { EnrollmentId = Guid.NewGuid().ToString() };
try
{
    EnrollmentCryptography.Open(JsonSerializer.Serialize(damaged), Convert.ToHexString(key), DateTimeOffset.Parse("2026-09-08T01:00:00Z"));
    throw new Exception("tamper detection did not fail");
}
catch (EnrollmentException exception) when (exception.Code == "pairing_failed") { }

Console.WriteLine("PASS: Desk2Shell.Core enrollment crypto and validation tests.");

static void Assert(bool condition, string name)
{
    if (!condition) throw new Exception("Assertion failed: " + name);
}
