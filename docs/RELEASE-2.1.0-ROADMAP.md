# Sonexis 2.1.0 release roadmap

Created: 2026-09-10. Target: 2.1.0, following the public 2.0.1 release.

## Scope

Ship the existing independent app chains, menu bar controls, starter presets, and refined workspace/tutorials as a cohesive update. The engine foundation remains Process Tap. This is a release plan; the [product and engine roadmap](PRODUCT-AND-ENGINE-ROADMAP.md) retains the longer-term discussion and history.

Feature scope is closed. Additional work should address demonstrated defects or complete distribution. Save/load/status is an accepted workflow and needs regression verification, not redesign. Keep the 4,096-frame buffer. Separate listening volume, global-default preferences, undo/redo, microphone processing, and broader device routing remain outside this release.

## Ordered work

| Step | Work | Completion evidence | Status |
| --- | --- | --- | --- |
| 1 | Establish the release baseline | Record source revision plus working-tree state, build configuration, machine, and test commands | Recorded in the audit |
| 2 | Test and reproduce | Run regression suites and targeted stress, audio, security/input-validation, tutorial, and UI/accessibility checks; retain logs and reproducers | First pass complete; see audit coverage and gaps |
| 3 | Agree on and fix proven issues | Work through `sonexis_issues_version210release.md` by severity; attach before/after evidence to each fix | Pending audit |
| 4 | Complete real-device acceptance | Check live app routing, listening, recovery, tutorial interaction, fresh launch, and upgrade in a release candidate | Pending |
| 5 | Prepare the release | Set version/build, commit the reviewed changes, prepare release notes and signed/notarized app and installer | Pending |
| 6 | Verify and publish | Install the exact candidate DMG, check launch/update behavior, then approve publication of that artifact | Pending |

## Testing and acceptance

### Engine and audio

- Default alone uses one processing pipeline. Two app overrides remain independent and exclude their audio from Default processing.
- Adding/removing a chain, changing presets, disabling/re-enabling effects, and restarting a source app do not introduce unintended duplicate audio or persistent silence.
- Automatic/manual switching, empty canvases, parallel paths, and split channels preserve the agreed routing behavior.
- Measure output peaks, non-finite samples, and discontinuities using deterministic offline signals. Distinguish intentional gain/distortion from failures in processing or protection.
- Exercise all built-in effects, variable block sizes, multiple sample rates, repeated edits, and increasing graph sizes. Report measured work against the audio block deadline and disclose build configuration.
- Verify recordings against final processed samples and test finalization/failure handling.
- Live acceptance: simultaneous distinguishable app sources; output-device changes; sleep/wake; stop/quit; extended playback. Record the device and OS actually tested. Offline tests do not certify these paths.

### Presets and work preservation

- Test save/load, clean versus modified state, unlink, import/export, missing plugins, and corrupted input using isolated fixtures.
- Verify fresh-install starter seeding and that deleted starters do not return.
- Upgrade a copy of a 2.0.1 workspace; preserve the original and verify chains, presets, gains, routing, and restart behavior.
- Tutorials must restore the user's workspace after completion, skipping, and lesson continuation; temporary demo work must not overwrite it.

### UI, accessibility, and tutorials

- Check narrow and wide windows: single-line labels/values, usable preset names, settings alignment, tray collapse, and distinguishable chain tabs.
- Exercise menu bar row hit areas, hover, chain enable state, presets, adding chains, dismissal, and panel positioning.
- Complete all three lessons by performing the actions, then test arrow navigation, exit, continuation, and launch-on-new-version behavior.
- Verify highlights leave the requested control usable, including effect parameters, wire gain, chain removal, and native menu bar controls.
- Check keyboard focus and accessible names/actions for core controls. Separate source-level checks from actual assistive-technology verification.

### Robustness and security

- Exercise malformed/oversized preset and graph data, duplicate identities, invalid numeric values, and unavailable plugins in isolated test processes.
- Inspect capture ownership and failure handling for unintended capture or muting. A source concern is not a confirmed vulnerability without a demonstrated failing boundary.
- Record crashes and resource exhaustion with reproducible input. Do not describe intended in-process plugin execution as a newly discovered exploit.

## Evidence rules

Only demonstrated defects go in [sonexis_issues_version210release.md](../sonexis_issues_version210release.md). Each entry needs severity, exact reproduction, expected/actual results, evidence paths, affected source, and scope limits. Passing checks and blocked/unavailable checks belong in the separate audit record. A missing test, speculative risk, or visual preference is not a proven defect.

Use temporary test data and offline audio for destructive/malformed-input tests. Preserve the user's real presets and workspace. Findings are to be reviewed before implementation; this audit does not authorize unrelated product changes.

## Release preparation

- Set marketing version to 2.1.0 and use an incremented build number for each candidate. The inspected project still says 2.0.1 (build 3).
- Commit the intended app, assets, tests, and documentation; record the exact revision used for the candidate.
- Run the existing `Scripts/test-*.sh` suites against a fresh matching Debug build. Several suites link its debug library, so build before running them. Also compile and exercise an optimized Release build.
- Export/sign/notarize the app, then use the [DMG workflow](../Scripts/DMG-README.md). The installer script consumes an already-notarized app; it does not perform the app notarization step.
- Test the final downloaded/installed artifact, including permission/setup behavior and launching from Applications. Confirm the supported macOS/architecture claims against actual build and test evidence.
- Write concise release notes covering app-specific chains, menu bar control, presets, and workspace improvements. Verify website/download version and artwork when preparing publication.

## Ship decision

Do not ship with a reproduced crash in a normal workflow, lost saved work, unintended capture/duplicate processing, persistent audio loss, or a blocked essential control. Resolve other proven issues or explicitly accept a documented limitation before release. An untested area remains unverified, not passed. No fixed release date is implied by this checklist.

Next: review confirmed issues 210-01 and 210-02, then fix and re-test them before continuing live acceptance.

## First audit outcome — 2026-09-10

The [audit record](RELEASE-2.1.0-AUDIT.md) documents passing regressions and additional stress checks. Six observed issues are recorded in [sonexis_issues_version210release.md](../sonexis_issues_version210release.md), including a malformed-preset crash, a main-thread HAL startup hang, and a Pitch activation gap. Review 210-01 and 210-02 first. Live routing/device and final installer acceptance remain open; an attempted or blocked check has not been marked passed.
