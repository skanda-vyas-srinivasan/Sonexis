# Independent audio chains: engine milestone

The engine layer supports one default chain and multiple app overrides. This is separate from which canvas the user is editing. The app now launches through ChainWorkspaceView and uses this runtime. A persistent chain strip selects one canvas while the other processors keep running. Add app creates a new empty override; Default handles unassigned apps.

## Ownership and routing

`MultiChainAudioEngine` owns an `AudioEngine` processor and a `ProcessTapDSPEngine` pipeline per chain. Processors have separate node-state dictionaries, graph caches, transition state, scratch buffers, and plugin hosts. Presets may reuse node UUIDs across chains without sharing DSP state. Child processors skip app-wide device monitoring and termination observers; their capture pipelines and the coordinator own the lifecycle.

`AudioChainRoutingPlan` resolves all app process sets together. Each override gets an inclusive selection of only its processes. The default gets an exclusive selection containing the union of all override processes; each tap additionally excludes Sonexis itself. Unknown process IDs are removed. Duplicate app assignments, overlapping resolved process ownership, duplicate chain IDs, and a missing or duplicate default chain are rejected before changing playback.

A bypassed app chain still owns its processes. Its audio passes through that processor without effects; it does not fall back into the default chain. Global bypass temporarily bypasses every chain and preserves each chain's individual enabled setting.

## Reconfiguration

Initial startup and app process changes use immutable `ProcessTapSelection` values. Multi-chain taps do not independently poll or change their source selection. The coordinator polls once per second, resolves the full partition, and compares it with the active plan. Unchanged partitions do nothing.

When ownership changes, every old pipeline stops before any new pipeline starts. This avoids an overlap where the default and an override both capture the same process. It is intentionally conservative and can cause a short audible gap in all chains. Processors remain alive, retaining their effect state. Newly launched app audio can briefly use normal/default routing until discovery runs; seamless transitions are not promised.

Configuration failures tear down partially started pipelines and attempt to restore the previous definitions and routes. Failure to restore is surfaced through the coordinator's published state. Stop and runtime destruction release all owned pipelines.

## Graph loading and editing

`applyIndependentGraph` applies graph snapshots without a SwiftUI canvas. It supports automatic position order, manual wiring, stereo, dual mono, automatic wire gains, node parameters, and plugin synchronization. Graph validation rejects duplicate nodes and incomplete split endpoints. `updateGraph` changes one processor without restarting unrelated chains. Chain definitions are Codable, including the target, graph, preset identity, and individual effects state.

## Validation completed

- Debug build succeeds.
- Offline multi-chain tests exercise actual independent DSP using identical node IDs: a delay impulse in chain A produces a tail in A while chain B remains silent.
- Separate plugin host ownership is checked; live third-party AU behavior is not yet validated.
- Tests cover two overrides plus default exclusion, self-exclusion, ambiguous ownership rejection, absent/relaunched apps, unchanged-process no-op, individual/global bypass, stop-all-before-start ordering, failed reconfiguration rollback, validation, and Codable round trips.
- Pipeline lifecycle tests inject fake device pipelines; they do not claim live simultaneous Core Audio playback verification.
- Existing app-target and real-engine offline graph/recording integration tests remain part of the regression checks.

## Connected workspace and controls

ChainWorkspaceView owns the runtime across Home/Build, chain switches, and editor hiding. Launch still begins on Home and never starts audio automatically. Chain selection recreates the selected editor view with the existing processor, graph, and per-chain preset identity. Canvas disappearance flushes its pending graph apply. Undo history remains local to each canvas presentation; persisted graph content is preserved across selection and relaunch.

Global power starts/stops all pipelines. Header effects bypass applies to the selected chain. The menu bar provides global power/global bypass and a list of chains with individual bypass and editor access. Plugin editor window identities are now unique per PluginHost, preventing reused preset node IDs from opening another chain’s editor. Removing nodes or releasing their host closes their editor windows.

The Record control records the selected chain’s processed output, as indicated by its tooltip. A recording marker remains visible in that chain’s tab when editing another chain. Adding/removing chains is disabled during recording/finalization to avoid deliberate routing restarts mid-recording. Global stop ends all recordings; quit drains their writers. Output metering and gain controls likewise belong to the selected chain.

## Persistence and migration

A versioned chains.json stores all graphs, app assignments, selected chain, per-chain preset IDs, input/output gains, output protection, individual effects state, and global bypass. Writes are debounced and atomic, with a previous-good backup. Flush cancels delayed work before writing the latest state, preventing stale delayed writes from undoing a newer selection. Recovery archives corrupt primary data before restoring a valid backup; unsupported versions and unrecoverable files pause saving. The original workspace.json is left untouched during migration.

An existing All audio workspace becomes Default. An existing app-targeted workspace becomes that app’s override plus an empty Default, preserving other apps’ dry routing intent. Startup does not restore running/recording state. Tutorial practice graphs are excluded from workspace capture while active.

## Remaining live validation

The connected workspace passes tests for migration, two app chains, edit/selection preservation, per-chain preset identity, power/bypass, selected-chain restoration, gains, write ordering, removal, and backup recovery. An offscreen render at 1100 × 700 verified the chain strip and editor fit without wrapped controls. Device pipelines in automated tests remain fakes; DSP tests use real processors.

Playback uses separate output pipelines mixed by macOS. There is no combined recording or post-mix limiter; existing output protection is per chain. Simultaneous real-app isolation, helper relaunches, output changes, sleep/wake, plugin interaction, and CPU cost still require live testing. Routing membership changes can briefly interrupt all pipelines. These are test-build capabilities, not a claim of release readiness.

App-agnostic helper attribution: replaced the WebKit-specific fallback with exact responsible-app identity for non-regular processes, including headless helpers absent from NSRunningApplication. Direct bundle identity and embedded executable matching remain first. Regular applications cannot be reassigned through responsibility merely because another app launched them. No process names or framework allowlist are required. The optional private responsibility SPI remains a distribution consideration; missing ownership leaves unmatched helpers outside the app override. Live CPU scaling remains unmeasured.
