ToDesk SSH Bootstrap
====================

1. Extract this entire folder. Do not run it from inside the zip preview.
2. Right-click RUN-AS-ADMIN.cmd and choose Run as administrator.
3. Accept the Windows UAC prompt.
4. Wait until the window shows READY.
5. Send todesk-ssh-result.txt from the Desktop back to the person helping you.

Do not share this folder or zip with anyone else. It contains a one-off Tailscale
enrollment key. Delete the zip and extracted folder after SSH is verified.

To remove the access later, open PowerShell as administrator in this folder and run:

  powershell -NoProfile -ExecutionPolicy Bypass -File .\rollback.ps1

Add -LogoutTailscale to also disconnect this computer from Tailscale.
