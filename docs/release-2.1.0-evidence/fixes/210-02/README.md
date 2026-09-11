# 210-02 — audio lifecycle fix verification

Changes follow baseline commit `22344bd`, alongside the earlier 210-01 fix. [Source hashes](source-manifest.json) identify the tested app and lifecycle regression sources. Original audit evidence is retained. The application version remains 2.0.1 (3), targeting the planned 2.1.0 release.

## Behavior

The workspace's audio runtime resolves process IDs and owns capture/playback pipeline construction, start, stop and release on one serial background queue. Its Process Tap timers, route listeners and recovery tasks use that queue too. Main-thread code owns graph configuration and observable UI state.

Power shows a pending indicator until startup or teardown finishes. A 10-second watchdog reports an unresponsive operation and requests cancellation. Cancellation does not destroy IO resources concurrently with a blocked HAL call. The request retains its pipelines and processors until that call returns and cleanup finishes. Retry is suppressed during this interval. A cancellation arriving between worker completion and its main-thread delivery is also cleaned up before the runtime becomes available again.

Changing the app list stops all previous partitions before starting replacements. A failed reconfiguration restores previous chains. Tutorial restoration keeps the original user document even if restarting its audio fails; it cannot roll back to a temporary practice chain. Tutorial add/close steps wait for asynchronous configuration completion. Repeated editor/tutorial start requests do not toggle a pending start off.

## Verification

- [Debug build](debug-build.log) and [optimized Release build](release-build.log): pass.
- [All 14 regression suites](regression-results.json): pass, including recording, workspace/preset persistence, tutorials, routing, graph transitions and the earlier Bitcrusher fix.
- [Lifecycle tests](test-audio-lifecycle.log): main-queue heartbeat during a blocked start; timeout; stop while blocked; no overlapping retry; late-completion cleanup; normal retry after cleanup; a blocked stop; cancellation during process resolution; runtime release during startup; processor retention until IO teardown; idempotent editor/tutorial start. Stalls are controlled with semaphores in injected pipelines; no real audio devices are opened by these tests.
- [Multichain tests](test-multichain.log): independent delay/plugin state, disjoint app routes, default exclusion, bypass, refresh without unnecessary restarts, stop-all-before-start-any, asynchronous failure reporting and rollback.
- [Workspace tests](test-chain-workspace.log): editor Power, asynchronous add/remove, preset/selection preservation, tutorial progression and original-document restoration even when audio restart fails.
- The same three suites also pass linked to the optimized app objects: [lifecycle](audio-lifecycle-release.log), [multichain](multichain-release.log), [workspace](chain-workspace-release.log).

Repeat after a fresh Debug build with `sh Scripts/test-audio-lifecycle.sh`, `sh Scripts/test-multichain.sh`, and `sh Scripts/test-chain-workspace.sh`. Run all `Scripts/test-*.sh` for the broader regression set. As with the original audit, Release helpers link the optimized app objects into `libSonexisAudit.dylib`; these test artifacts are not distribution binaries.

## Actual app check

In the built Debug app, Power reached the running state with a non-silent output meter, then returned to stopped. The editor responded to inspection and navigation. No user audio was recorded. Evidence: [start UI state](ui-power-start.txt), [start screenshot](ui-power-start.png), [stop UI state](ui-power-stop.txt), [stop screenshot](ui-power-stop.png).

Sonexis was returned to Home with processing stopped. All six existing Sonexis JSON files were byte-identical [after the check](user-data-after-ui.json), compared with the [before hashes](user-data-before-ui.json).

## Limits

The exact original macOS HAL stall was not forced during this live check. Blocking injected lifecycle calls reproduce the application's dependency on a call that does not return; they do not establish the cause of the OS stall. The watchdog cannot safely kill a Core Audio call in process. If the OS never returns, cancellation remains pending and quitting/reopening is the available recovery path.

Device unplug/switch, sleep/wake, minimum-OS/Intel runtime, multiple real-app routing and signed-installer acceptance still need their release checks. Moving recovery callbacks onto the serial owner was inspected and compiled; this pass did not simulate physical device changes or put the Mac to sleep. This fix covers the chain workspace runtime used by the product; the legacy standalone backend/prototype still defaults to its original queue.
