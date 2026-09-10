# Sonexis 2.1.0 audit record

Date: 2026-09-10. First audit pass completed on the available Mac. **Release acceptance is not complete.** Six demonstrated issues are in [sonexis_issues_version210release.md](../sonexis_issues_version210release.md); this document records coverage, passing results, stress limits, and verification gaps.

## Environment and method

- Apple M4, 16 GiB RAM, 10 logical CPUs; macOS 26.5.2 (25F84), Xcode 26.6.
- Source baseline: `451f5baf66dce0bbfb6c87b35e154fdef92a5359` plus the pre-existing uncommitted changes. [Baseline metadata](release-2.1.0-evidence/baseline.json) includes the working-tree inventory and tracked-diff hash.
- Current app version is still 2.0.1, build 3. Target release is 2.1.0. No application source was changed by this audit.
- Debug app built successfully, then all 12 existing regression scripts ran sequentially against that matching build. Release also built successfully for arm64 and x86_64; Intel execution was not tested.
- Additional offline probes link the actual optimized Release object files as an audit library with test visibility. This is not a signed distribution build and is not a replacement DSP implementation.
- UI evidence comes from the actual current Debug app at `.build/DerivedData/Build/Products/Debug/Sonexis.app`, using Computer Use. An initial app-name lookup opened the installed older app; it was not used as the basis of any reported defect. Current-build UI checks used its full path.
- Stress/malformed-data tests use isolated helper processes. No malicious preset was placed in the real library. Generated WAV evidence contains synthetic signals, not recorded user audio.

Build logs: [Debug](release-2.1.0-evidence/debug-build.log), [Release](release-2.1.0-evidence/release-build.log). Reproduction setup: [audit instructions](../Tests/ReleaseAudit/README.md) and [preparation script](../Scripts/prepare-release-audit.py).

## Existing regression suites

All twelve returned exit code 0 in this pass.

| Suite | Coverage exercised | Log |
| --- | --- | --- |
| Background window | Editor hide/reopen and window lifecycle behavior | [log](release-2.1.0-evidence/test-background-window.log) |
| Capture target | Process ownership matching, helper attribution, safe capture selection | [log](release-2.1.0-evidence/test-capture-target.log) |
| Chain workspace | Multi-chain workspace, edits, menu preset targeting, persistence, tutorial isolation/restoration | [log](release-2.1.0-evidence/test-chain-workspace.log) |
| Compiled graph | Legacy/new sample equivalence, topology cases, variable blocks, cache invalidation, split isolation | [log](release-2.1.0-evidence/test-compiled-graph.log) |
| Graph transition integration | Real engine edits/bypass/routing and recorded final-output samples | [log](release-2.1.0-evidence/test-graph-transition-integration.log) |
| Graph transitions | Transition ramp behavior and rapid changes | [log](release-2.1.0-evidence/test-graph-transitions.log) |
| Knob controls | Numeric formatting, parameter adjustment and bounds | [log](release-2.1.0-evidence/test-knob-controls.log) |
| Multi-chain | Disjoint routing plans, independent processors/plugin hosts, actual delay-state isolation, rollback | [log](release-2.1.0-evidence/test-multichain.log) |
| Preset persistence | Atomic write failures, recovery, names/IDs, seeding, dirty-state comparison | [log](release-2.1.0-evidence/test-preset-persistence.log) |
| Recording | Exact sample order, variable blocks, drain/finalization, overload, format/disk failures | [log](release-2.1.0-evidence/test-recording.log) |
| Tutorial | All lesson paths, guards, per-version onboarding, restoration gates, arrows and continuation | [log](release-2.1.0-evidence/test-tutorial.log) |
| Workspace persistence | Recovery, migration/storage failure handling and saved workspace behavior | [log](release-2.1.0-evidence/test-workspace-persistence.log) |

Tests using fake capture pipelines verify orchestration and state, not real HAL handoffs. The multi-chain suite also contains genuine offline audio rendering to check state isolation. Neither constitutes a completed multi-app listening/device test.

## Additional engine, clipping, and stress probes

### Signal validity and transitions

- **120 effect/format cases:** 20 current non-plugin effects × mono/stereo × 44.1/48/96 kHz. Each cycles through 1, 17, 128, 1,024, 4,096, and 31-frame blocks. Across 2,542,560 frames, no non-finite final output was observed. [Full sweep](release-2.1.0-evidence/sweep.log).
- **1,000 neutral topology changes:** 2,048,000 output samples; zero zeroed samples and maximum deviation from the constant input of `1.49e-8`. This checks add/remove transitions with disabled neutral effects, not every audible effect transition. [Log](release-2.1.0-evidence/edits.log).
- **Ceiling and invalid signal containment:** Two Bass Boost nodes were fed a high-level signal and a block containing NaN/+Inf/−Inf. Final output stayed finite and subsequently recovered to nonzero sound. Peak with Ceiling on was approximately **0.949934**; with Ceiling off it was **1.761562**. [Log](release-2.1.0-evidence/ceiling.log).
- **Pitch activation:** The above passing checks did not cover the Pitch warm-up gap. The dedicated probe reproduced it, resulting in issue **210-03**. [Log](release-2.1.0-evidence/pitch-edit.log).

Some effects in the sweep exceeded full scale with Ceiling off and a 0.8-amplitude input. Amp reached approximately 5.05. That establishes the output level under those settings; it does not prove a regression or a limiter malfunction. The user explicitly chose -15/+15 dB defaults with Ceiling off. This audit does not silently reverse that decision or treat intentional amplification/distortion as a newly discovered defect. Nor does keeping final samples below full scale prove the absence of audible nonlinear distortion inside effects.

### Ring-buffer correctness and memory safety

Built the actual C ring buffer with AddressSanitizer and UndefinedBehaviorSanitizer. A deterministic model checked randomized wraparound, full/empty buffers, overflow/underflow accounting, channels 1/2/4/8, and 80,000 operations. A separate concurrent producer/consumer moved 2,000,000 frames. **377,027,164 sample comparisons passed**, with no sanitizer report. [Log](release-2.1.0-evidence/ring-stress.log), [source](../Tests/ReleaseAudit/ring_stress.c).

This is not a ThreadSanitizer certificate for every engine/plugin thread, nor a test of malformed OS-provided AudioBufferList memory layouts.

### Optimized rendering performance

1,024-frame stereo blocks at 48 kHz represent **21.33 ms** of audio. Each row below summarizes 100 timed blocks after warm-up on this M4. GUI automation and normal OS background work were not suppressed; these are host observations, not universal performance guarantees. [All measurements](release-2.1.0-evidence/performance-active-pitch.log).

| Chain | Median render time | 95th percentile | Blocks above 21.33 ms |
| --- | ---: | ---: | ---: |
| 1 Simple EQ | 0.152 ms | 0.216 ms | 0 |
| 16 Simple EQ | 0.333 ms | 0.397 ms | 0 |
| 1 Bass Boost | 0.191 ms | 0.320 ms | 0 |
| 16 Bass Boost | 0.648 ms | 2.578 ms | 0 |
| 1 Reverb | 0.356 ms | 0.642 ms | 0 |
| 16 Reverb | 1.369 ms | 3.059 ms | 0 |
| 1 Pitch, +7 semitones | 0.059 ms | 11.438 ms | 0 |
| 4 Pitch, +7 semitones each | 0.117 ms | 47.830 ms | 13 |
| 16 Pitch, +7 semitones each | 0.345 ms | 152.192 ms | 13 |

Pitch batches work internally, so its low median hides expensive periodic calls. The initial performance probe used zero semitones, which bypasses pitch shifting; those numbers in `performance.log` are **not** evidence of active Pitch performance. The table uses the corrected +7-semitone run.

To test whether the reservoir absorbs the bursts, a second probe ran the actual processing worker and rings against a synthetic device clock for 8.53 seconds per run, with the existing 4,096-frame reservoir:

| Active Pitch nodes | Output underflow frames | Interpretation |
| --- | ---: | --- |
| 0 | 0, including repeat | Control run |
| 1 | 0 | Tested reservoir absorbed the work |
| 4 | 0 | Slow individual blocks did not cause underruns in this run |
| 16 | 6,124, identical count in repeat | Measured stress limit: approximately 127.6 ms of missing frames |

No test-clock tick was more than 5 ms late; observed maximum lateness was at most 2.22 ms. No input or output ring overflow was reported. [Worker logs](release-2.1.0-evidence/worker-16.log), [repeat](release-2.1.0-evidence/worker-16-repeat.log), [control](release-2.1.0-evidence/worker-0.log), [source](../Tests/ReleaseAudit/worker.swift).

This deliberately stacks 16 pitch shifters in one serial chain. It is a demonstrated capacity limit, but is **not listed as a required product defect** without an agreed supported workload. It does not establish that Default-only processing or a typical one-pitch chain uses excessive CPU. If supporting this workload is desired, improve batching/performance or define a usable workload limit; do not infer that every over-budget individual block causes an audible gap.

### Sustained processing and isolation

Four independent processors used identical node UUIDs with EQ, Delay, Reverb, and Chorus. The Chorus lane received silence while the others received signal. After **10,000 blocks per chain / 40.96 million aggregate frames**, there were no non-finite outputs or nonzero samples leaking into the silent lane. Peak RSS reported by `getrusage` went from 16,498,688 bytes at block 1,000 to 16,613,376 at block 10,000. [Log](release-2.1.0-evidence/longrun.log).

This represents approximately 213 seconds of audio per chain processed faster than real time, not hours of wall-clock playback or a proof of no memory leaks. `/usr/bin/time` printed an additional sandbox diagnostic for `kern.clockrate`; the probe's own measurements and completion line are present independently.

## Imports, security boundaries, and presets

- **Malformed numeric presets:** Bitcrusher bit depth and downsample values of `1e100` passed import/graph validation and crashed in both Debug and optimized Release. These are issue **210-01**. Eleven other selected extreme numeric parameters rendered one block without crashing; that limited sample is not proof that every numeric field is safe. [Results](release-2.1.0-evidence/numeric-input-results.json).
- **Structural import fuzzing:** 2,000 deterministic mutated inputs returned 325 accepted / 1,675 rejected without a crash; all 37 truncated prefixes of the valid input were rejected. Accepted cases include supported omitted/null/default forms. No rendering or real storage writes occurred in this probe. [Log](release-2.1.0-evidence/import-fuzz.log).
- **Nine bundled presets:** All were decoded, validated, and rendered with generated input. The initial sandboxed run could not instantiate AUPitch and therefore did not validate the two AU-based presets. The unsandboxed offline repeat instantiated the Apple units without the earlier errors and rendered all nine. [Repeat log](release-2.1.0-evidence/starter-render-unsandboxed.log). This does not certify subjective sound quality or every third-party plugin.
- Reviewed the preset decode/validation boundary, plugin loading path, and process-selection ownership code. Capture ownership tests passed. No demonstrated remote code execution, credential exposure, or unintended cross-app capture is claimed. This is targeted local robustness testing, not a comprehensive external penetration test.

## Actual UI and tutorial checks

Observed and retained screenshots/accessibility trees for:

- Tutorial entry, Power action in Basics, readable Right-arrow progression, separate gain/ceiling instructions, and gear placement below the toolbar.
- Advanced seed layout with nodes at different heights; switching Automatic → Manual; opening Wire Gain from a wire context menu; decrementing its accessible slider from 100% to 90% without dismissing it; Done advancing only afterwards.
- Clear Canvas and switching to Dual Mono; practice exit restoring the original chain and stopped state.
- Adding and removing a Terminal practice chain with its confirmation; enabled close-tab target and completion choices.
- Loading the saved Brighten preset, settings slider accessibility, and wide/narrow canvas comparison.

Examples: [settings tutorial](release-2.1.0-evidence/ui-basics-input-gain.png), [wire-gain edit](release-2.1.0-evidence/ui-wire-gain-edited.txt), [wire-gain Done](release-2.1.0-evidence/ui-wire-gain-done.txt), [tab-close confirmation](release-2.1.0-evidence/ui-close-practice-tab.txt), [completion choices](release-2.1.0-evidence/ui-app-tutorial-complete.txt).

UI issues **210-04**, **210-05**, and **210-06** came from these checks. App Chains → Advanced continuation also exposed the main-thread HAL hang, **210-02**. Automated restoration/continuation tests pass; that does not cancel the observed live failure.

Limitations: drag injection did not reliably add a tray effect through the automation tool, so some exercise cards were advanced using the explicitly supported arrows. The native menu bar could not be fully driven: attempts to inspect its system surface timed out. Menu-bar model actions have regression coverage, but hit areas, hover, positioning, and its full tutorial interaction remain live acceptance work. Full VoiceOver/Full Keyboard Access, all themes, and every parameter editor were not completed.

## Live audio and remaining acceptance

A quiet generated tone played successfully through `afplay` outside the sandbox. A separate probe selected only that generated source's HAL process object and attempted capture/process/playback, edit, and restart. Sandboxed playback failed; unsandboxed probes stalled in HAL IOProc creation or stopping. Each stalled helper was sampled and stopped with a bounded cleanup. These attempts **do not count as successful end-to-end live audio tests**. [Probe source](../Tests/ReleaseAudit/live.swift), [repeat log](release-2.1.0-evidence/live-repeat-1.log), [stack](release-2.1.0-evidence/live-repeat-1.sample.txt).

Later, the normal Sonexis app blocked in `AudioDeviceStart` during tutorial continuation. Two actual-app samples 62 seconds apart confirm the UI-thread block; this is the reported defect. Why the audio service entered this state remains unknown. No system audio service was reset, and no unrelated applications were reconfigured.

Still required before claiming release acceptance:

- Complete real audio routing with two distinguishable apps plus Default, including helper-heavy apps such as browsers, after the HAL responsiveness issue is addressed.
- Live listening for clicks/distortion, recording on the final device path, device switch/unplug, sleep/wake, and stop/quit restoring native audio.
- Built-in speakers, wired/USB, and Bluetooth coverage; minimum macOS 14.4 and Intel runtime coverage if advertised. Only this M4/macOS 26.5.2 environment was available here.
- Full native menu-bar interaction and remaining tutorial exercises, keyboard/assistive-technology acceptance, and fresh-install/2.0.1 upgrade testing of the final signed installer.
- Verify signing/notarization and the final DMG. This audit built unsigned binaries; packaging scripts alone do not prove the shipped artifact passes installation checks.

## Preservation and next action

The user's six existing Sonexis JSON files were backed up before further UI work and compared afterwards. Both the comparison after the tutorial hang and the [final comparison](release-2.1.0-evidence/data-final.json) found all six byte-identical. The frozen test app was terminated only after that comparison, then reopened from its saved workspace. Sonexis was left stopped on [Home](release-2.1.0-evidence/ui-final-home.png), and no audit helpers or generated-audio playback processes remained. No app fixes, version bump, commit, or release publication were performed during the audit.

Next: review and fix **210-01** and **210-02**, followed by the Pitch transition gap. Re-run the relevant reproducer after each fix, then resume the outstanding live acceptance checks from the [release roadmap](RELEASE-2.1.0-ROADMAP.md).
