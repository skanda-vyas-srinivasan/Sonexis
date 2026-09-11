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
| 3 | Agree on and fix proven issues | Work through `sonexis_issues_version210release.md` by severity; attach before/after evidence to each fix | 210-01–04 and 210-06–07 fixed; 210-05 deferred |
| 4 | Complete real-device acceptance | Check live app routing, listening, recovery, tutorial interaction, fresh launch, and upgrade in a release candidate | Available-device checks passed; real sleep/wake requires an attended run |
| 5 | Prepare the release | Set version/build, commit the reviewed changes, prepare release notes and signed/notarized app and installer | 2.1.0 (5), notes and builds complete; refresh internal DMG, then Developer ID/notary credentials remain unavailable |
| 6 | Verify and publish | Install the exact candidate DMG, check launch/update behavior, then approve publication of that artifact | Blocked until a signed/notarized artifact exists; nothing published |

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

- Marketing version is 2.1.0 and the first candidate build is 4. Increment the build number for any replacement candidate.
- Commit the intended app, assets, tests, and documentation; record the exact revision used for the candidate.
- Run the existing `Scripts/test-*.sh` suites against a fresh matching Debug build. Several suites link its debug library, so build before running them. Also compile and exercise an optimized Release build.
- Export/sign/notarize the app, then use the [DMG workflow](../Scripts/DMG-README.md). The installer script consumes an already-notarized app; it does not perform the app notarization step.
- Test the final downloaded/installed artifact, including permission/setup behavior and launching from Applications. Confirm the supported macOS/architecture claims against actual build and test evidence.
- Write concise release notes covering app-specific chains, menu bar control, presets, and workspace improvements. Verify website/download version and artwork when preparing publication.

## Ship decision

Do not ship with a reproduced crash in a normal workflow, lost saved work, unintended capture/duplicate processing, persistent audio loss, or a blocked essential control. Resolve other proven issues or explicitly accept a documented limitation before release. An untested area remains unverified, not passed. No fixed release date is implied by this checklist.

Next: on a machine with the Developer ID certificate and notary credentials, sign/notarize/staple build 5, build the final DMG, and perform its install/launch check. An attended real sleep/wake cycle remains the only uncompleted device test. Default plus two simultaneous app chains routed independently, device switching passed in both directions while running, the fixed recorder passed a 96.70-second live Bluetooth repeat, and quit/relaunch preserved all saved files. Issues 210-01–04 and 210-06–07 have passing fix evidence. Gain slider accessibility (210-05) is deferred by user decision and remains a known limitation.

## First audit outcome — 2026-09-10

The [audit record](RELEASE-2.1.0-AUDIT.md) documents passing regressions and additional stress checks. Seven observed issues are recorded in [sonexis_issues_version210release.md](../sonexis_issues_version210release.md), including the live-recording frame loss found during real-device acceptance. Device recovery and final installer acceptance remain open; an attempted or blocked check has not been marked passed.

## Fix progress

- **210-01 fixed:** Bitcrusher values are bounded on load and before DSP integer conversion. Original crash probes and additional safety regressions pass in Debug and optimized Release; preset, workspace and chain-workspace regressions pass. [Verification](release-2.1.0-evidence/fixes/210-01/README.md).
- **210-02 fixed:** Serial background HAL ownership, pending/cancel/timeout handling, late-start cleanup, and safe retry. Blocked-call tests, normal live Power start/stop, and all 14 regression suites pass. [Verification](release-2.1.0-evidence/fixes/210-02/README.md). The underlying OS stall is not claimed fixed.
- **210-03 fixed:** Current audio remains audible during Pitch warm-up, then fades into shifted output. The original half-second silent gap is gone in Debug and Release; 72 activation cases and a silent-startup check pass in each configuration. Existing buffering latency remains. [Verification](release-2.1.0-evidence/fixes/210-03/README.md).
- **210-04 fixed:** Oversized canvases scroll without resizing tiles or rewriting saved node positions. Scrolled controls/menus and the original wide/narrow resize case are verified in the app; viewport and existing regressions pass. [Verification](release-2.1.0-evidence/fixes/210-04/README.md).
- **210-05 deferred by user:** Gain sliders still lack accessible names/units; this is a known limitation, not a passing check.
- **210-06 fixed:** Power is available throughout App Chains in the header, menu bar and workspace action. Finish/Skip/Continue restore the original Power state; regression and actual app checks pass. [Verification](release-2.1.0-evidence/fixes/210-06/README.md).
- **210-07 fixed:** The recording reserve now absorbs 128 blocks and the writer uses user-initiated scheduling. The deterministic 96-block stall, all regressions, Debug/Release builds, and a 96.70-second live Bluetooth repeat pass. [Verification](release-2.1.0-evidence/fixes/210-07/README.md).
- **Device acceptance:** Built-in 48 kHz and Bluetooth 44.1 kHz hot switches passed while running; quit/relaunch preserved all six saved files. [Evidence](release-2.1.0-evidence/live-acceptance/device-switch-and-quit.md). Real sleep/wake requires an attended check.
- **Release candidate:** 2.1.0 build 5 includes the final settings-panel layout and is being packaged as an internally verified unsigned DMG. Developer ID signing/notarization are blocked by missing Keychain credentials. [Evidence](release-2.1.0-evidence/release-candidate-build5.md).
- **Next:** Produce and install-test the signed/notarized artifact on a credentialed machine, then approve publication.
