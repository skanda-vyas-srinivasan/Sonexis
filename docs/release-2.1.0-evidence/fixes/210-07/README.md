# 210-07 recording-buffer fix verification

Date: 2026-09-10.

## Change

`AudioRecordingSession` now preallocates 128 recording buffers instead of eight and runs its serial file writer at user-initiated QoS. The real-time append path remains bounded: it only takes a prepared buffer, copies the current block, and enqueues the write. It does not allocate a buffer, write to disk, or wait for disk IO.

At the normal 1,024-frame stereo capacity, the pool preallocates room for 131,072 frames (up to 2.97 seconds at 44.1 kHz when callbacks fill those blocks) and occupies about 1 MiB of sample storage per active recording. Explicit pool exhaustion and disk errors retain the existing warning and missing-frame accounting.

## Verification

- The recording suite now freezes the first disk write while queuing another 96 blocks with the default pool. Finalization retains all 99 frames in exact order with zero drops.
- The existing one-buffer overload case still drops and counts the rejected frame, proving bounded overload behavior remains intact.
- Exact WAV samples/order, variable block sizes, stop/drain, post-stop rejection, oversized blocks, format changes, disk failures, and independent mono sessions pass.
- The graph-transition integration suite records the real engine's final processed output exactly.
- All 16 `Scripts/test-*.sh` suites pass.
- Full Debug and universal arm64/x86_64 Release builds succeed.

## Live confirmation

A fresh Debug build recorded Default for 96.70 seconds on the same 44.1 kHz Hesh ANC Bluetooth path, more than twice the original failing duration. A new signed helper supplied a near-inaudible 990 Hz source at amplitude 0.00005. Sonexis displayed no warning during recording or after finalization, which confirms zero frames entered its dropped-frame accounting. The WAV contains 4,264,448 stereo frames, all finite, with no near-zero run. The helper was stopped immediately afterward, and Sonexis was stopped and returned to Home. [Live evidence](../../live-acceptance/21007-live-repeat-ui.txt).

210-07 is closed for this tested device path. Broader device-switch, sleep/wake, and signed-installer acceptance remain separate release tasks.
