# 210-01 fix verification

Changes follow baseline commit `22344bd`. Original audit logs above this directory remain unchanged.

Imported and persisted Bitcrusher values are bounded to the UI ranges (Bit Depth 4–16, Downsample 1–20), including legacy preset migration. The audio processor repeats the finite/range check before integer conversion, protecting direct in-memory updates as well as decoded values. Non-finite values fall back to existing defaults (8 and 4). No user library or workspace files were edited by these offline tests.

## Results

- [Debug build](debug-build.log) and [Release build](release-build.log): pass.
- [Debug safety suite](bitcrusher-safety-debug.log) and [optimized Release safety suite](bitcrusher-safety-release.log): pass. Covers original JSON fixtures, wrapped imports, a temporary disk library, legacy migration, negative/fractional values, and clean round-trip comparisons. Direct node/global DSP tests cover huge values, NaN, infinities, supported boundaries, fractional truncation, and disabled effects, comparing real samples with bounded reference inputs.
- Original first-block crash probes: [bit depth Debug](fixture-bit-depth-debug.log), [downsample Debug](fixture-downsample-debug.log), [bit depth Release](fixture-bit-depth-release.log), [downsample Release](fixture-downsample-release.log): all return normally. The probe's `value` field records the original incoming test value, not the normalized parameter stored in the graph.
- Existing [preset persistence](preset-persistence.log), [workspace persistence](workspace-persistence.log), and [chain workspace](chain-workspace.log) suites: pass.

## Repeat

Build Debug, then run `sh Scripts/test-bitcrusher-safety.sh`. The test uses the two unchanged audit fixtures and temporary storage; no capture or playback is opened.

For optimized verification, prepare the Release audit library using `python3 Scripts/prepare-release-audit.py`, then compile `Tests/BitcrusherSafety/main.swift` with `swiftc -O`, importing `.build/ReleaseAudit/Build/Products/Release` and linking `.build/ReleaseAudit/libSonexisAudit.dylib`. Pass the repository root as the executable's only argument. The original malformed-input commands are in the [audit tool README](../../../../Tests/ReleaseAudit/README.md).

Scope: resolves the two demonstrated Bitcrusher integer-conversion crashes. Other effect parameters and the five other release findings are separate work.
