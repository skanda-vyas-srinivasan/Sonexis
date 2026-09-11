# Sonexis 2.1.0 build 4 candidate — 2026-09-10

## Built and verified

- Marketing version: 2.1.0
- Build: 4
- Bundle identifier: `com.sonexis.app`
- Deployment target: macOS 14.4
- Release executable: universal arm64 and x86_64 Mach-O
- Fresh Debug build: passed
- Fresh universal Release build: passed
- All 16 `Scripts/test-*.sh` suites: passed against the final source
- Release notes: `docs/RELEASE-NOTES-2.1.0.md`

An internal unsigned disk image was created at `.build/ReleaseCandidate/Sonexis-2.1.0-build4-unsigned.dmg`. `hdiutil verify` passed, the mounted image contained Sonexis.app and the Applications shortcut, and its SHA-256 is:

```text
41d04ca4d49a200881db117deaaed76844cb695e5022adb2d7bc0a21efbf5e4c
```

## Distribution boundary

This internal image is not a publishable artifact. The login Keychain reports zero valid code-signing identities, no **Developer ID Application** certificate is available, and the configured `notarytool` profile is unavailable. Therefore the final app cannot be Developer ID signed, submitted to Apple notarization, stapled, or passed through Gatekeeper acceptance on this machine. The repository's final DMG script correctly refuses to package an app without those prerequisites.

Publication must use a machine/keychain with the Developer ID certificate and notarization credentials. Build the same committed revision, increment build 4 if the source changes, notarize and staple the app, run `Scripts/build-sonexis-dmg.sh`, then install and launch that exact downloaded DMG before publishing it.
