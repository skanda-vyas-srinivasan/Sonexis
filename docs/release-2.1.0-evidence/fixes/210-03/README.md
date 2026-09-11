# 210-03 — Pitch activation continuity verification

Tested 2026-09-10 on the audit Mac. Changes follow baseline `22344bd`, alongside the uncommitted 210-01 and 210-02 fixes. The [source manifest](source-manifest.json) identifies the wrapper, regression and reproducer sources. Original audit evidence is retained. No version bump or distribution build is implied.

## Behavior

During Pitch startup, the wrapper returns current dry input while the existing output buffer fills. Once ready, it linearly crossfades into wet output over 20 ms, using the same mix for every channel. Resetting Pitch resets this transition. If output runs short, missing frames use current input and the wrapper primes again.

The wrapper supplies `rubberband_get_preferred_start_pad` zeros and trims `rubberband_get_start_delay` frames, queried after the initial pitch ratio is set. This follows the real-time startup contract documented in the vendored `External/rubberband/rubberband/RubberBandStretcher.h`. Readiness depends on buffered frames, not signal amplitude, so intentional silence remains valid. Retrieval uses the actual returned frame count.

The 8,192-frame minimum process batch, two-batch prebuffer, Rubber Band quality options and 4,096-frame playback reservoir remain unchanged. Shifted output still has buffering latency; this change preserves audible continuity while waiting. It is not a claim of instantaneous pitch response or artifact-free transitions for every source.

## Original reproduction: before and after

The same continuous generated stereo signal changes from zero to +7 semitones after 40 blocks of 1,024 frames, through the actual graph update path, with -15/+15 dB gains.

| Rate | Original longest silence | Fixed Debug | Fixed Release |
| --- | --- | --- | --- |
| 44.1 kHz | 24,237 frames / 549.59 ms | 1 frame / 0.023 ms | 1 frame / 0.023 ms |
| 48 kHz | 24,236 frames / 504.92 ms | 1 frame / 0.021 ms | 1 frame / 0.021 ms |

Both fixed builds emit audio on the first frame after the edit. The isolated zero frame is a waveform crossing. Evidence: [original](../../pitch-edit.log), [Debug measurements](pitch-edit-debug.log), [Release measurements](pitch-edit-release.log), [Debug WAV](pitch-edit-debug.wav), [Release WAV](pitch-edit-release.wav). These WAVs contain generated test audio only. The original failing WAV was not overwritten.

## Regression coverage

- [Debug build](debug-build.log) and [Release build](release-build.log): passed.
- [Debug continuity suite](pitch-continuity-debug.log) and [optimized Release suite](pitch-continuity-release.log): each passed 72 cases: 44.1/48/96 kHz × mono/stereo × ±7/±12 semitones × initial activation, return from zero, and re-enable after bypass. Tests use fixed and variable block sizes, assert finite bounded output and no extended silence, check dry continuity during startup, and verify the eventual shifted frequency spectrally. The re-enable checks allow the existing 5 ms graph bypass transition.
- Both suites also passed silent startup followed by a tone, verifying zero output for silence and the correct shifted frequency afterwards.
- Existing [graph-transition integration](graph-transition-integration.log), [multichain](multichain.log), and [compiled-graph](compiled-graph.log) regressions passed against the updated Debug build.

Repeat after a fresh matching Debug build with `sh Scripts/test-pitch-continuity.sh`. The [audit instructions](../../../../Tests/ReleaseAudit/README.md) describe compiling the original reproducer; `pitch-edit /absolute/path/to/output.wav` preserves the original failure artifact. Release helpers link the optimized app objects, as in the original audit.

These are offline engine tests. No fresh hardware playback/listening test is claimed for this fix, and no user presets or recordings were modified. Final live listening, device recovery and release installer acceptance remain on the roadmap.
