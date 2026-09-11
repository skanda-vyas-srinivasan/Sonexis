# 210-04 — canvas viewport fix verification

Tested 2026-09-10 on the audit Mac. Changes follow baseline `22344bd`, alongside fixes 210-01 through 210-03. [Source hashes](source-manifest.json) identify this fix. The app remains version 2.0.1 (3), targeting 2.1.0; no release artifact or commit was produced.

## Behavior

The canvas now has a scrollable drawing document when its nodes extend beyond the visible drawing area. Content size includes the stored node coordinates, tile margin and space for End. Empty or fitting canvases do not need a scroll range. Resizing changes viewport geometry without rewriting node positions, changing tile/text scale, or applying an audio graph edit.

The chain strip, toolbar and settings overlay remain outside the scroll view. Drawing, dragging, drop locations and wire hit testing continue using document coordinates. Floating context menus translate that origin into the root view and clamp to the visible viewport. Wire Gain stays inside the viewport; effect editor lifting uses the visible bottom. The AppKit right-click capture refreshes its callback when geometry or graph state changes.

Dragging retains the current document extent so moving the outermost node inward does not change the scroll offset beneath the pointer. Loading another graph or clearing the canvas releases that retained extent. This extent is transient UI state, not a new preset field.

## Actual app checks

The original **Skanda's Brighten** preset was already loaded. Processing stayed stopped.

- [Original failing narrow view](../../ui-brighten-reloaded.png): Clarity was clipped with no horizontal way to reach it.
- [Narrow, scrolled right](ui-narrow-scrolled.png): the whole Clarity tile and End are reachable. The native canvas scroll area exposes **Scroll Left / Scroll Right** and its horizontal scrollbar reaches 1.
- [Effect controls](ui-scrolled-effect-controls.png) open from the scrolled Clarity tile. Its [context menu](ui-scrolled-node-menu.png) remains visible.
- [Wide window](ui-wide.png): all three nodes fit and the horizontal scrollbar disappears. [Narrow repeat, scrolled right](ui-narrow-repeat-scrolled.png): Clarity remains reachable after widening then narrowing again.
- [Wire Gain](ui-scrolled-wire-gain.png) opens from the Clarity-to-End wire after that resize/scroll repeat; its [slider and Done control](ui-scrolled-wire-gain.txt) are exposed and Done dismisses it.
- Final drag check: [before](ui-final-before-drag.png), [after](ui-final-after-drag.png). A 30-pixel left / 27-pixel down drag moves Clarity under the pointer while Bass Boost, Enhancer and End remain stationary. The saved [change comparison](drag-changes.json) contains only that node's two position values; topology, parameters and other graph fields did not change. Screenshot pixels and logical canvas points differ by the app/display scale.

Native accessibility scrolling was used for the horizontal check. The generic scroll-injection call did not move the document; that call is not counted as a passing wheel/trackpad test. The screenshots above show actual app output, not a mockup.

## Automated checks

- [Debug build](debug-build.log) and [optimized Release build](release-build.log): passed.
- [Viewport regression](canvas-viewport.log): 81 combinations of all nine bundled presets, three viewport sizes and three node scales. Checks right/bottom reachability via valid scroll offsets, the original Brighten overflow, wider/empty/fitting canvases, scrolled menu bounds, and stable extent while dragging. Run `sh Scripts/test-canvas-viewport.sh`.
- Existing [graph-transition integration](graph-transition-integration.log), [chain-workspace](chain-workspace.log), and [tutorial](tutorial.log) suites passed against the final Debug build.

The viewport checks preserve existing zoom behavior; they are not a claim to repair imported negative coordinates or tiles already extending above zero at enlarged zoom. Full live vertical scrolling, trackpad gesture acceptance, new tray drops while scrolled, and every tutorial spotlight were not exercised through UI automation. The tutorial canvas target is attached to the viewport rather than the larger document; the tutorial regression suite covers progression/restoration, not a visual certificate for every card.

## Preservation

Resizing, scrolling and opening controls did not alter the six saved JSON files. The deliberate drag changed the chain's node position and its backup. With the app quit, both were restored from the pre-test copies; [all six files match byte-for-byte](user-data-restored.json). [Before hashes](user-data-before-ui.json). The app was reopened on [Home](ui-final-home.png), stopped. No audio was recorded.
