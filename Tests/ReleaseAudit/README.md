# 2.1.0 release audit reproducers

These exercise the real engine independently of audio devices and user storage.
They are diagnostic probes, not tests asserting that known failures are correct.
The main issue report is [sonexis_issues_version210release.md](../../sonexis_issues_version210release.md).

From the repository root:

```sh
python3 Scripts/prepare-release-audit.py
.build/ReleaseAudit/audit sweep
.build/ReleaseAudit/audit ceiling
.build/ReleaseAudit/audit edits
.build/ReleaseAudit/audit pitch-gaps
.build/ReleaseAudit/audit pitch-edit
.build/ReleaseAudit/audit performance
.build/ReleaseAudit/audit seed Sonexis/StarterPresets.json
.build/ReleaseAudit/ring-stress
.build/ReleaseAudit/worker-audit 0
.build/ReleaseAudit/worker-audit 1
.build/ReleaseAudit/worker-audit 4
.build/ReleaseAudit/worker-audit 16
.build/ReleaseAudit/longrun-audit
.build/ReleaseAudit/import-fuzz
```

The following reproduced issue 210-01 before its fix. They now must return from
rendering without a crash, with no device output or writes to the user's library:

```sh
.build/ReleaseAudit/audit malformed bitcrusherBitDepth
.build/ReleaseAudit/audit malformed bitcrusherDownsample
```

After a fresh Debug build, `sh Scripts/test-bitcrusher-safety.sh` asserts import,
persistence and actual DSP behavior for these inputs and additional numeric boundaries.

`malformed` accepts an optional third argument giving the effect's serialized
name, allowing the same numeric-boundary probe to test other effects.

`pitch-edit` writes `docs/release-2.1.0-evidence/pitch-edit-output.wav` with a quiet
generated signal, not captured user audio. Pass a path after `pitch-edit` to save
new verification audio without overwriting the original failure evidence.
`sh Scripts/test-pitch-continuity.sh` checks activation/reactivation, requested
pitch frequency, silence, and mono/stereo at three sample rates after a Debug build.
Performance timings are offline
optimized DSP timings; they are not whole-app CPU percentages. `worker-audit`
uses the actual worker and rings with a synthetic 48 kHz device clock, a
4,096-frame output reservoir and 1,024-frame read/write blocks. It reports clock
lateness separately from audio underflows.

`live.swift` is a separate device probe. Do not include it in unattended normal
regression runs: it starts a quiet generated tone with `afplay`, captures only
that source process, and opens real Core Audio resources. In this audit it hit
HAL call stalls. Use a bounded process-group timeout, retain a stack sample,
and terminate only the probe group if a stall recurs. It does not touch user
presets or workspace files. An unsuccessful live probe does not establish
successful live routing, recording, or output restoration.
