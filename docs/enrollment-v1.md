# Desk2Shell enrollment protocol v1

## Envelope (`*.d2s`)

The transport file is UTF-8 JSON:

```json
{
  "schemaVersion": 1,
  "enrollmentId": "UUID",
  "createdAt": "RFC3339 UTC",
  "nonce": "base64",
  "ciphertext": "base64",
  "tag": "base64"
}
```

Encryption is AES-256-GCM. The 32-byte key is displayed separately as a 64-character hexadecimal pairing code. Dashes and whitespace in entered pairing codes are ignored. The nonce is 12 random bytes and the tag is 16 bytes.

The authenticated additional data is the UTF-8 byte sequence `Desk2Shell.Enrollment.v1:<enrollmentId>`.

## Decrypted payload

```json
{
  "schemaVersion": 1,
  "enrollmentId": "UUID matching the envelope",
  "targetAlias": "SSH-safe name",
  "controllerPublicKey": "OpenSSH public key",
  "controllerTailscaleIPv4": "100.x.y.z",
  "tailnetName": "tailnet identifier reported by tailscale status --json",
  "expiresAt": "RFC3339 UTC",
  "tailscaleAuthKey": "one-off Tailscale auth key"
}
```

The bootstrap rejects unknown schema versions, mismatched enrollment IDs, malformed aliases/IPs/public keys, expired payloads, lifetimes greater than seven days, and payloads whose creation time is more than five minutes in the future.

## Controller state

Per-device metadata is stored in `~/Library/Application Support/Desk2Shell/enrollments.json`. It contains enrollment IDs, aliases, public metadata, expiry, and paths to encrypted private-key files. Private-key passphrases are stored as generic-password items in macOS Keychain under service `app.desk2shell.controller` and account equal to the enrollment ID.

## Target state

`C:\ProgramData\Desk2Shell\state.json` records only what Desk2Shell created and the public data needed for status and exact removal. The Tailscale Auth Key and SSH private key are never written there.

The installed bootstrap supports:

```text
Desk2Shell Bootstrap.exe --status
Desk2Shell Bootstrap.exe --revoke
Desk2Shell Bootstrap.exe --extend-hours 24
```

Mutating operations self-elevate. `--revoke` is also the expiry task action and must be idempotent.
