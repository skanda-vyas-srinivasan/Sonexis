# Live acceptance — 2026-09-10

Environment: Apple M4 MacBook Pro, macOS 26.5.2 (25F84), 44.1 kHz, Hesh ANC Bluetooth output.

Three signed local helper apps generated distinct continuous tones at 330 Hz, 550 Hz, and 770 Hz. Sonexis routed the first two through separate app chains and left the third on Default. Each selected chain was recorded through Sonexis, then the resulting WAV was analyzed independently.

## Confirmed results

- Tone A recording: 330 Hz amplitude 0.0799998; 550 Hz 0.00000468; 770 Hz 0.00000198.
- Tone B recording: 550 Hz amplitude 0.0800007; 330 Hz 0.00000408; 770 Hz 0.00000524.
- Default recording: 770 Hz amplitude 0.127941; 330 Hz 0.001396; 550 Hz 0.000708.
- All three recordings contain finite samples and no extended near-zero run. The intended source dominates each recording, and the two app-specific sources are strongly excluded from Default.
- Power start/stop and selection of each chain worked through the normal app UI.
- All 16 `Scripts/test-*.sh` regression suites passed after the live run. Logs are under `regressions/`.

## Confirmed failure

The 43.55-second Default recording displayed this warning while recording:

> Recording has gaps: the disk writer could not keep up. Live playback continues.

On stop, Sonexis reported 14,848 missing frames. At 44.1 kHz that is 336.69 ms of omitted audio. The saved WAV is finite and playable, but omitted frames shorten the file and can create time/phase discontinuities without producing a run of literal zero samples. This is tracked as 210-07.

## 210-07 fixed-build repeat

After increasing the preallocated reserve to 128 blocks and promoting the recording writer to user-initiated QoS, a fresh Debug build recorded Default for 96.70 seconds on the same 44.1 kHz Bluetooth output path. This is more than twice the original failing duration. No warning appeared during recording or after finalization, so Sonexis reported zero dropped frames. The resulting 4,264,448-frame stereo WAV contains only finite samples and no near-zero run. See the [UI observation record](21007-live-repeat-ui.txt), updated measurements, and hash list.

## Limits

- No output-device switch or sleep/wake cycle was performed. Other user audio was active after the generated tones stopped, so switching from headphones to speakers would have been disruptive.
- The generated tones were stopped at the user's request and were not restarted.
- The four large WAV files are retained outside documentation in `.build/LiveAcceptanceRecordings/`. Their hashes and measurements are recorded here in `recording-sha256.txt` and `recording-analysis.jsonl`.
- This run used a development build. Signed installer, fresh-install, upgrade, Intel, minimum-macOS, wired/USB output, and assistive-technology acceptance remain open.
