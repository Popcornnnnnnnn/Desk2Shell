# Windows acceptance matrix

Automated compilation is necessary but not sufficient. A release candidate is not production-ready until every required row has attached screen recording, `desk2shell-result.json`, controller verification output, expiry/revoke evidence, and a snapshot comparison of pre-existing services/firewall rules.

| Scenario | Windows 10 22H2 | Windows 11 | Expected result |
|---|---:|---:|---|
| Local standard user, separate UAC admin | Required | Required | SSH identity is the original interactive standard user |
| Local administrator | Required | Required | SSH identity is that administrator |
| AD domain user | Required | Required | Domain account logs in with its existing permissions |
| Entra-only account | Required | Required | Preflight stops without system changes |
| Tailscale and OpenSSH absent | Required | Required | Official Tailscale signature is checked; isolated sshd starts |
| Both dependencies already present | Required | Required | Existing services and configuration remain unchanged |
| Tailscale connected to another tailnet | Required | Required | Setup stops without logout or takeover |
| Expired/changed `.d2s` or pairing code | Required | Required | Setup stops without persistent changes |
| Network interrupted at each install stage | Required | Required | Partial Desk2Shell state is rolled back |
| Reboot before expiry | Required | Required | Access returns and original expiry remains |
| Manual revoke | Required | Required | Port, service, keys, rule, and task disappear |
| Expiry while Mac is offline | Required | Required | Local SYSTEM task revokes access |
| Repeated setup/revoke | Required | Required | Operations are idempotent; no duplicate rule/service |

Release thresholds: at least 10 real enrollments, 70% unassisted first-attempt success, median ready-to-SSH time at most eight minutes, three completed AI-agent tasks, and four users repeating within 14 days.
