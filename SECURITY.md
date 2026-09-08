# Security policy

Desk2Shell creates temporary remote command access. Treat every change to enrollment decryption, user identity capture, SSH configuration, firewall scoping, expiry, and rollback as security-sensitive.

## Supported versions

Only the latest published v0.x build receives security fixes during the developer preview.

## Reporting

Do not open a public issue containing a real Tailscale Auth Key, SSH key, IP address, Windows username, setup package, or log captured from a private machine. Until a private disclosure address is published, create a GitHub security advisory draft for the repository owner.

## Invariants

- A setup package never contains an SSH private key.
- A `.d2s` file never contains a plaintext Tailscale credential.
- The Windows listener binds only to the target Tailscale address and uses port 2222.
- The firewall allows only the enrolled controller Tailscale address.
- Expiry and manual revoke must work without the Mac controller.
- Existing Tailscale, Windows OpenSSH, firewall, and SSH configuration must not be overwritten.
- Desk2Shell diagnostic logs and opt-in telemetry must not contain secrets. Local OpenSSH logs can contain connection metadata and are deleted on revoke.
