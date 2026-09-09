# Direct-download macOS release

Desk2Shell publishes notarized Apple-silicon DMGs from the maintainer Mac. Public releases are built from a clean checkout and signed locally; signing credentials are never stored in GitHub Actions.

## Release identity

- Product: `Desk2Shell`
- Repository: `Popcornnnnnnnn/Desk2Shell`
- App slug: `desk2shell`
- Bundle ID: `app.desk2shell.controller`
- Version source: `packaging/Info.plist`
- Architecture: `arm64`
- Minimum macOS: `14.0`
- Release tag: `v<version>`
- Release branch: `release/v<version>`
- Update branch: `updates`
- Cloudflare Pages project: `desk2shell-updates`
- Update hostname: `desk2shell-updates.popcornnn.xyz`
- Sparkle feed: `https://desk2shell-updates.popcornnn.xyz/appcast.xml`
- Sparkle keychain account: `desk2shell`
- Developer ID: `Developer ID Application: WEIZHI WANG (R26X7B8XDT)`
- Notary profile: `port-tools-notary`

## Build

Run all checks, commit the release preparation, and use a clean release worktree. Download the `windows-bootstrap-<commit>` artifact from the successful GitHub `check` workflow for the exact release commit, then run:

```bash
./scripts/check.sh
DESK2SHELL_WINDOWS_BOOTSTRAP=/absolute/path/to/Desk2Shell\ Bootstrap.exe \
  ./scripts/release-macos.sh 0.1.0
```

The GitHub Windows runner builds the self-contained `win-x64` Bootstrap from the exact release commit. The release script embeds it in the Mac app, signs the app and Sparkle components with Hardened Runtime, creates and verifies a styled DMG, notarizes and staples the DMG, and emits a checksum plus the Sparkle EdDSA enclosure attributes.

The Windows Bootstrap in the `0.1.0` developer preview is intentionally unsigned. Windows may show `Unknown publisher`, SmartScreen may require `More info` and `Run anyway`, and policy-managed computers may refuse to run it. This boundary must be stated in the GitHub release notes and update feed. The Mac app and DMG remain Developer ID signed and notarized.

## Publish order

1. Tag the exact clean source commit as `v<version>`.
2. Create a GitHub prerelease and upload `Desk2Shell-<version>.dmg` plus its `.sha256` file.
3. Generate `appcast.xml` with build number, minimum macOS, Apple-silicon hardware requirement, release notes, public asset URL, length, and the emitted EdDSA signature.
4. Publish the feed and release notes from the `updates` branch through the `desk2shell-updates` Cloudflare Pages project.
5. Redownload the public DMG and repeat checksum, disk-image, notarization, Gatekeeper, mounted-content, and appcast checks.

The first prerelease cannot prove an old-build-to-new-build update. Before a stable release, install a signed lower-build release candidate, update through Sparkle, relaunch, and verify that `~/Library/Application Support/Desk2Shell` state is preserved.
