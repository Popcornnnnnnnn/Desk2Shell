# Optional telemetry

Telemetry is disabled by default and developer builds contain no collection endpoint. The Mac controller may ask the user to opt in. The Windows target never transmits telemetry independently.

Allowed event shape:

```json
{
  "schemaVersion": 1,
  "installationId": "random UUID created on the Mac",
  "event": "package_created | target_observed | ssh_verified | access_expired | access_revoked | operation_failed",
  "appVersion": "semantic version",
  "osFamily": "macOS | Windows",
  "osMajor": 15,
  "durationBucket": "under_2m | 2_to_5m | 5_to_8m | over_8m",
  "errorCode": "stable non-sensitive code or null",
  "occurredAt": "RFC3339 UTC"
}
```

Forbidden fields include usernames, hostnames, device aliases, IP or MAC addresses, tailnet names, filesystem paths, command text/output, SSH material, Tailscale credentials, remote-desktop provider IDs, and file contents.
