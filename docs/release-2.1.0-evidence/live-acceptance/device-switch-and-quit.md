# Device-switch and quit acceptance — 2026-09-10

Environment: Apple M4 MacBook Pro, macOS 26.5.2 (25F84).

## Device switching

The test temporarily muted output, selected MacBook Pro Speakers, and verified Core Audio reported the built-in device alive at 48 kHz. Sonexis started successfully on that device. While processing remained on, output changed to Hesh ANC Bluetooth at 44.1 kHz, back to the built-in 48 kHz device, and finally back to Hesh ANC. After every change, the Sonexis Power control remained On and exposed no runtime error. Sonexis then stopped normally.

The original output state was restored: Hesh ANC selected, 50% output volume, Mute off. No test tone played during this check.

## Quit and preservation

Sonexis was stopped before quit. After quit and relaunch, all six saved JSON files retained their exact SHA-256 hashes:

```text
b3a7d24915c88358cd5b9b141e9ae2c7f8dc921c891f26a17fddfa3534c2a09c  chains.json
663809fedce9f5395e82a330adf386b73b597ab372f6f59b42357e2bf7cfce27  chains.backup.json
d6fa61ecc12bd8940627fd9112c29da9eba3c4bd0faa4684caafe0e9144f0688  presets.json
3eef6f7c88939cc1ee6246190f45a2cfd7787396a3a9ea17811388e958aa0349  presets.backup.json
9098f072a3250e4f0981d1880f04b9635bb36c05371a5d93c8bbeb7eee7fc319  workspace.json
07ab1005b1838f0b73da6c0493d6cb046822bcef80558b2e475a71d7d5c0efa8  workspace.backup.json
```

The selected Messages chain and stopped state were restored after the recording and device tests.

## Sleep/wake boundary

A real sleep/wake cycle could not be completed unattended. Scheduling the required automatic wake with `pmset relative wake 60` requires an administrator password, which was unavailable noninteractively. No sleep command was issued without a guaranteed automatic wake. Deterministic lifecycle tests cover cancellation, stalled start/stop, serialized teardown, retry, and release during startup, but do not replace real sleep/wake acceptance.
