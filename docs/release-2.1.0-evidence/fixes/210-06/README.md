# 210-06 — App Chains tutorial Power fix

Changes follow baseline `22344bd`, alongside the preceding uncommitted release fixes. [Source hashes](source-manifest.json) identify the tested sources. No commit, version bump or publication was performed.

## Behavior

The shared `TutorialStep.allowsPowerControl` rule permits Power in every App Chains step. Header and menu-bar buttons use it, as does `ChainWorkspace.togglePower`. The header Power target remains clear of tutorial dimming without adding a blue border or changing the exercise card's anchor. Read-only review still blocks workspace interaction as before. Basics and Advanced keep their existing Power restrictions and internal startup behavior.

Entry is refused while audio is starting/stopping, with an explanation to wait for that transition. This avoids recording an ambiguous original running state. The existing restoration path restores the original document and Power state when finishing, skipping or continuing.

## Automated verification

- [Debug build](debug-build.log) and [Release build](release-build.log): passed.
- [Chain/workspace suite](chain-workspace.log): both Power action paths at all 11 App Chains steps; originally stopped and running entry states; Finish, Skip and Continue restoring the entry state after deliberate toggles; saved chains unchanged; pending-start entry waits for settlement; failed startup remains at the same step and can be retried; other lesson locks remain intact. Existing graph, preset, practice-chain and failed-restoration tests also pass.
- [Tutorial suite](tutorial.log): passed, including arrow navigation, all lesson boundaries, completion and continuation.

Run `sh Scripts/test-chain-workspace.sh` after a fresh matching Debug build, and `sh Scripts/test-tutorial.sh`. Workspace tests use temporary stores and injected pipelines. They do not capture live audio. Release compilation passed; these regression executions used Debug app objects.

## Actual app check

Started from Home with processing stopped. Chose App chains & menu bar. [Power was enabled](ui-power-available.txt), with [the control undimmed](ui-power-available.png). Clicking it reached [Power On](ui-power-running.txt) while remaining on the same introductory card. No practice edits were required to start it.

Clicked Skip and confirmed Exit. [Power returned to Off](ui-power-restored.txt), with the original editor and chain selection restored. [All six saved JSON files remained byte-identical](user-data-after-ui.json) against the [before hashes](user-data-before-ui.json). Sonexis was returned to Home with processing stopped. No user audio was recorded.

This live check exercised header Power and Skip. All-step Finish/Continue and originally-running restoration are verified with the injected workspace tests. The menu-bar button's shared permission and action are compiled and covered at the model/action boundary; a fresh native menu-bar click was not part of this UI check. This does not replace the outstanding multi-app/device/listening release acceptance.
