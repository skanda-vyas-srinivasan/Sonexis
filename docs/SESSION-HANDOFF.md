# Sonexis session handoff

Updated: 2026-09-11

## Where the app stands

Sonexis is preparing for its next release after 2.0.1. The working release version is currently set to **2.1.0 build 5**, but the user has **not approved the app as release-ready**. Do not package, publish, change the version, or commit work unless the user explicitly asks. Let the user visually inspect each UI change before treating it as accepted.

The previous committed baseline is:

```text
0297a88 Prepare Sonexis 2.1.0 release candidate
```

On 2026-09-11 the user explicitly requested that all current source, test, and release-document changes be committed as a checkpoint before menu-bar visual work continues.

## Most recent work

### Chrome-style chain-tab reordering

App-chain tabs can be reordered while **Default remains pinned first**. Reordering changes only the stored presentation order; processors and live audio pipelines remain keyed by chain ID and are not restarted.

The first implementation used SwiftUI system drag and drop. The user rejected it because the tab became transparent and displayed a cyan drop outline. It has now been replaced with an in-strip `DragGesture` in `Sonexis/ContentView/ChainWorkspace.swift`:

- the dragged tab stays opaque;
- it follows the cursor horizontally;
- adjacent tabs move when the cursor crosses them;
- there is no system drag ghost or cyan destination box;
- the order persists across workspace restoration.

The user visually tested this behavior and reported that it worked.

### Tab closing and themed dialogs

An app tab's X and its **Close Tab** context-menu action now close immediately without an individual confirmation. The X receives a compact red circular hover highlight. **Close All App Tabs** retains a safeguard.

All ten app-controlled warning and confirmation flows now use one reusable Sonexis-styled sheet. It follows the selected Black, Classic, Magenta, or Gold palette and provides consistent information, warning, error, destructive, primary, and cancel treatments. System-owned file pickers remain native macOS panels. The Debug build plus preset, recording, and chain regression suites passed; visual approval remains pending.

### Responsive canvas End node

The scrollable canvas previously derived End from the expanding document width, so dragging a block toward it pushed End off-screen. An initial rigid boundary fix harmed windowed layouts and was removed. The latest fix derives End from the actual canvas viewport width while preserving stored effect coordinates and scrollable layout space. Canvas viewport tests and the Debug build pass. The user supplied a screenshot proving the earlier coordinate conversion still placed End off-screen; the viewport-width correction was made afterward and needs visual retesting.

### Full-screen close behavior

Closing the editor with the macOS red X while Sonexis is full screen previously left a black full-screen Space. `Sonexis/EditorWindowController.swift` now exits full screen first and hides the editor after `windowDidExitFullScreen`. Ordinary window close still hides the editor so its menu-bar process can continue running. Quit still closes normally.

`Tests/BackgroundWindow/main.swift` covers the exit-then-hide sequence. The targeted test and Debug/Release builds passed. The user has not yet reported a visual retest of this behavior.

### Settings panel

The compact, one-line audio settings panel is anchored immediately beneath the header gear and floats over the workspace without resizing it or hiding the toolbar. The user visually approved this layout with: **“THIS IS GOOD.”** Do not redesign it.

The relevant files are:

- `Sonexis/ContentView/ContentView.swift`
- `Sonexis/ContentView/HeaderView.swift`
- `Sonexis/CanvasView/CanvasView.swift`

## Next visual direction

The user finds the menu-bar panel too barren but wants it to remain minimal. Preserve the logo-only header: do not add a Sonexis title. Do not use gradients, glow, glass, or decorative textures. Add structure with solid theme surfaces, spacing, thin borders/dividers, quiet tone-on-tone chain cards, a narrow selected-chain accent, restrained control hover states, useful preset secondary text, and an understated footer. The user approved trying this direction after the checkpoint commit.

## Verification completed

- The complete set of 16 repository regression scripts passed after the settings-panel and original tab-reordering work.
- `Scripts/test-chain-workspace.sh` passed after the reorder model and persistence coverage was added.
- `Scripts/test-background-window.sh` passed for the full-screen close fix.
- A Debug build passed after the latest opaque, in-strip tab-drag implementation.
- A universal arm64/x86_64 Release build passed before the latest visual drag implementation; the latest drag implementation received a Debug compile check.
- No Computer Use or MCP UI testing was used for the latest drag change.
- The canvas viewport suite passed after the viewport-anchored End correction.
- Preset persistence, recording, and chain workspace suites passed after themed dialogs were introduced.
- A Debug build passed with the latest canvas and dialog work.

## Release boundaries

The user wants to decide when Sonexis is ready. A successful build or test run does not mean release approval.

Known external boundaries remain:

- Developer ID signing and notarization credentials are unavailable on this Mac.
- A real attended sleep/wake acceptance check remains incomplete.
- Gain-slider accessibility issue 210-05 was explicitly deferred by the user.
- Intel was built but not executed on Intel hardware.

An unsigned build-5 DMG was generated in `.build/ReleaseCandidate/` during this session even though it was not needed for the latest task. Treat it as an ignored internal artifact only. Do not present it as approved or publishable, and do not do more packaging unless asked.

## Product decisions already made

- Independent app chains coexist with the Default chain.
- An app-specific chain overrides Default for that app.
- Chains remain process-agnostic; users choose running apps rather than naming process rules manually.
- Default is always present and stays first in the tab strip.
- Newly added chains start enabled.
- The menu bar can add apps, select chains and presets, toggle chain state, control Power, and quit.
- Volume mixer controls were removed/deferred. Input Gain and Output Gain remain the advanced controls; defaults are -15 dB and +15 dB with Ceiling off.
- Undo/redo was removed because its scope was unclear and increasingly complex.
- Closing the editor hides it while processing can continue; Quit ends the app.
- Do not add UI text merely to explain visual state. Prefer clear color, layout, and interaction cues.

## How to resume

1. Continue with the approved minimal, flat menu-bar visual polish described above.
2. Ask the user to visually inspect that panel; do not launch or control the app unless explicitly asked.
3. Also have the user visually retest the latest End-node placement, themed dialogs, and full-screen red-X behavior.
4. Do not infer that Sonexis is ready to release. Wait for explicit release approval.

## Working preferences

- Do not use MCP Computer Use, browser control, screenshots, or automated UI control unless the user explicitly asks you to test visually.
- The user will perform visual checks.
- Keep each change tightly scoped to what was requested.
- Explain the result directly and briefly.
- After a decision is completed, mention the next relevant item, but do not begin unrelated release work automatically.
- Do not play test tones unless explicitly requested.
