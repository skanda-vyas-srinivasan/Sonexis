# Latency investigation

Date: 2026-09-08. Scope: source inspection and deterministic tests of the actual C playback ring. No live capture, hardware loopback, listening test, or default-buffer change was performed.

The playback ring targets 4,096 frames and startup waits for that same fill. That is 85.33 ms at 48 kHz, 92.88 ms at 44.1 kHz, or 42.67 ms at 96 kHz. These are buffer-derived figures, not measured end-to-end latency. Capture/device buffers, worker scheduling, effect/plugin delay and playback hardware also contribute. The two-second allocation is ring capacity, not the intended operating delay.

The DSP worker wakes every 1 ms with 250 microseconds of requested timer leeway. It processes whatever input is available, up to 1,024 frames per chunk and 32 chunks per wake. The chunk limit does not force a 21 ms wait for a full block at 48 kHz. Scheduler delays and DSP execution time are not yet measured. Startup readiness is polled on the main queue every 5 ms, so busy UI work can delay startup; this polling does not add a recurring 5 ms delay to every audio block.

Existing diagnostics report ring fill and drop/underflow deltas. They do not establish hardware latency or worst-case DSP execution time. Plugin maximum render capacity is not plugin latency; the current path does not provide a complete latency estimate for arbitrary effect chains.

## Reproducible buffer experiment

Run `sh Scripts/probe-latency-buffer.sh`. The probe compiles the actual `RealtimeAudioRing.c`, prefills a stereo playback ring, writes and consumes 256-frame blocks at a simulated 48 kHz, pauses the producer, then writes its backlog. No real-time scheduler or device is involved. Each case runs 1,000 simulated callbacks. The startup poll and capture ring are not simulated.

| Target | Buffer-derived delay | No stall | 21.33 ms stall | 42.67 ms stall | 85.33 ms stall |
| --- | --- | --- | --- | --- | --- |
| 4,096 frames | 85.33 ms | 0 | 0 | 0 | 0 |
| 2,048 frames | 42.67 ms | 0 | 0 | 0 | 2,040 |
| 1,024 frames | 21.33 ms | 0 | 0 | 1,020 | 3,068 |

Cells after the delay column are underflow frames. Every case had zero overflow drops. These results show the reservoir tradeoff under the specified synthetic schedule, not that a target is safe on the user's device. One-frame consumption correction explains why some missing-frame counts differ slightly from the nominal backlog deficit.

The ring consumes one fewer frame when fill is low and one extra when fill is high, using interpolation for the adjusted block. Simply lowering the target during playback does not immediately remove queued latency. With 256-frame callbacks at 48 kHz, a 2,048-frame surplus takes roughly 10.9 seconds to drain at one extra frame per callback, assuming matched producer/output rates. Any live profile-switch design must account for this instead of just changing a displayed setting.

## Recommended next implementation

Deferred by user decision on 2026-09-08: retain the current 4,096-frame target. Latency is not a current priority. The steps below are future options, not active work.

1. Add measurements for DSP block duration, peak capture/playback queue fill, and underflow/drop counts. Record sample rate, callback size, device and chain alongside results.
2. Trial a 2,048-frame target as an opt-in setting applied at engine start, with matching preroll. It halves the nominal playback reservoir delay at 48 kHz while retaining more stall tolerance than 1,024. Keep 4,096 as the stable fallback until live validation supports a new default.
3. Measure end-to-end delay with a known impulse/loopback setup. Exercise music/video, larger chains, plugins, recording, UI activity, output-device changes and sustained CPU load. Compare underflow counts and listening results across settings.
4. Consider 1,024 only after measurements establish enough headroom. Do not promise a fixed total latency from the reservoir alone or automatically reduce every user's buffer.

The current audio configuration remains unchanged after this investigation.
