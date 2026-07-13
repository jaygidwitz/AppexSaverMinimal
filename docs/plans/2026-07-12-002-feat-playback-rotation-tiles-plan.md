---
title: "feat: Redesign playback rotation onto library tiles (Choose Loops mode)"
type: feat
date: 2026-07-12
status: planned
branch: feat/playback-controls
depth: standard
---

# feat: Redesign playback rotation onto library tiles (Choose Loops mode)

## Summary

The Playback panel currently renders a wall of ~19 loop-ID chips (`loop-03`,
`loop-11`, …) for choosing which loops are in rotation. It's cluttered and leaks
internal file identifiers into the UI. This plan replaces that with:

1. A calm Playback panel holding only the two elegant controls (Shuffle,
   Cross-fade) plus a subtle read-only summary — *"In rotation: All N loops"* —
   and a single **Choose…** affordance.
2. A **Choose Loops mode**: tapping *Choose…* puts the existing "Your Loops"
   thumbnail grid into a selection state where each tile carries a checkmark/dim
   overlay, and tapping a tile adds/removes it from rotation instead of playing
   it full-screen. **Done** exits the mode.

This is presentation + one small store method. The playback **engine**
(`VideoPlayerController`), the persistence keys, and `RotationResolver` are
untouched — rotation is still persisted as a `Set<String>` of stable loop
identifiers where **empty = all loops**.

**Not in this plan:** the Catalog-stuck-spinning bug. That is a runtime
diagnosis, not a design decision, and is being routed to `/ce-debug` for live
root-causing.

---

## Problem Frame

`PlaybackControlsView.swift` builds a `LazyVGrid` of `Capsule` chips, one per
library video, each labeled with `video.displayName` (derived from the file
stem). Selecting rotation there means reading abstract IDs divorced from the art.
The user already browses their loops as thumbnails in the "Your Loops" grid
(`ContentView.librarySection`) — that is where selecting from the art belongs.

The core technical constraint: `PlaybackSettings.rotation` uses **empty set to
mean "all loops"** (see `PlaybackSettings.swift:24`, `RotationResolver.activeURLs`).
The existing `toggle(_:)` inserts into the set, so calling it from the "all"
state (empty) with one tile would produce `{thatId}` — i.e. *only that one loop
in rotation* — the exact inverse of the user's intent (deselect one). Tile
selection therefore needs a normalizing setter that understands the "all"
sentinel. This is the one piece of real logic in the plan.

---

## Requirements

- **R1** — The Playback panel shows Shuffle and Cross-fade controls plus a
  one-line rotation summary and a Choose affordance; no per-loop chips.
- **R2** — Rotation summary reads naturally: *"All N loops"* when everything is in
  rotation, *"M of N loops"* otherwise. No internal IDs shown.
- **R3** — Choose Loops mode overlays a selected/deselected state on each "Your
  Loops" tile; tapping a tile in this mode toggles its rotation membership.
- **R4** — Outside Choose mode, tiles behave exactly as today (tap = play full
  screen; the × remove button still works).
- **R5** — The "all loops" invariant is preserved on disk: when the user's
  selection covers every current loop, the stored set collapses back to empty so
  it keeps meaning "all" as the library grows.
- **R6** — At least one loop must remain in rotation; the UI prevents deselecting
  the final selected loop (a screensaver must play something).
- **R7** — No regression to persistence, the playback engine, or full-screen
  playback. Existing `PlaybackSettings` round-trip tests continue to pass.

---

## High-Level Technical Design

Two small state surfaces. **(a)** Selection-mode is transient view state owned by
`ContentView` and shared into the panel via a `Binding`. **(b)** The rotation set
is normalized by a new `PlaybackSettings` method whose behavior against the
"empty = all" sentinel is the decision table below.

Rotation normalization — `setSelected(id, isOn, allIdentifiers)` where
`current` = the resolved on-screen selection (empty is expanded to `allIdentifiers`):

| Starting state         | Action        | Resulting stored `rotation`                              |
|------------------------|---------------|----------------------------------------------------------|
| Empty (all selected)   | Deselect one  | `Set(allIdentifiers) − {id}` (materialize all-minus-one) |
| Partial                | Select one    | `current ∪ {id}`; if that now covers all → store empty   |
| Partial                | Deselect one  | `current − {id}`, unless it would empty → **no-op (R6)** |
| All explicitly listed  | Select last   | covers all → store empty (collapse to sentinel)          |

*Directional guidance, not implementation spec.* The invariant: **stored empty ⇔
every current loop is in rotation**, and the set is never allowed to resolve to
zero loops.

Selection-mode state flow:

```
[Browsing]  --tap "Choose…"-->  [Selecting]  --tap "Done"-->  [Browsing]
 tile tap = play                 tile tap = toggle rotation
 no overlays                     checkmark/dim overlay per tile
```

---

## Key Technical Decisions

- **KTD1 — Normalize in the store, not the view.** Add a single
  `setSelected(_:isOn:allIdentifiers:)` method to `PlaybackSettings` that
  encapsulates the decision table above. Views call it with a boolean and the
  current library identifiers; they never manipulate the set directly. Keeps the
  "empty = all" invariant in one testable place and leaves `RotationResolver` and
  the engine untouched. The old `toggle(_:)` stays (still used by tests) but is no
  longer wired to any UI. Rationale: the sentinel logic is the only real
  correctness risk here — it belongs behind the store's boundary with unit tests,
  not scattered across SwiftUI tap handlers.
- **KTD2 — Selection mode owned by `ContentView`.** `ContentView` already renders
  *both* the Playback panel and the "Your Loops" grid, so it is the natural owner
  of `@State private var isSelectingRotation`. The panel receives a
  `Binding<Bool>`; the grid reads the value to switch tile behavior. No new
  shared/observable object — this is ephemeral view state, not persisted.
  Rationale: avoids threading transient UI state through the persisted
  `PlaybackSettings` (which is app-owned and injected), keeping the store clean.
- **KTD3 — Floor of one, no explicit "none".** Because empty means "all", there is
  no distinct representation for "zero loops chosen". Rather than overload the
  model, the UI forbids deselecting the last loop (R6). Rationale: matches product
  reality (the screensaver must play something) and sidesteps an ambiguous state.
- **KTD4 — Reuse the existing tile, add an overlay.** The checkmark/dim selection
  affordance is an `overlay` on the current `cell(_:)` thumbnail, gated on
  `isSelectingRotation`. No new tile component. Rationale: the tile already has an
  overlay stack (play glyph, remove button); selection is one more conditional
  layer.

---

## Implementation Units

### U1. Normalized rotation selection API in `PlaybackSettings`

**Goal:** Add a store method that toggles one loop's rotation membership while
preserving the "empty = all" invariant and the one-loop floor.

**Requirements:** R5, R6, R7.

**Dependencies:** none.

**Files:**
- `AppexSaverMinimal/PlaybackSettings.swift` — add `setSelected(_ id:isOn:allIdentifiers:)`
  and a small `isAllSelected(allIdentifiers:)` helper for the summary/overlay.
- `AppexSaverMinimal/PlaybackSettingsTests.swift` — add cases below.

**Approach:** Resolve the current on-screen selection by expanding empty to
`allIdentifiers`, apply the add/remove, then re-normalize: if the result covers
every id in `allIdentifiers`, store empty; if a deselect would leave zero, no-op.
Follows the decision table in High-Level Technical Design. Persist via the
existing `setRotation(_:)` so the UserDefaults path and `@Published` update are
unchanged.

**Patterns to follow:** mirror the existing `toggle(_:)` / `setRotation(_:)`
shape in `PlaybackSettings.swift`; tests mirror `testToggle_addsAndRemoves` and
`testEmptyRotation_persistsAndReloadsEmpty`.

**Test scenarios:**
- Deselect-from-all: fresh store (empty), `setSelected("loop-02", isOn: false, allIdentifiers: [loop-01,02,03])` → rotation == `{loop-01, loop-03}`.
- Collapse-to-empty: from `{loop-01, loop-03}`, `setSelected("loop-02", isOn: true, all: [01,02,03])` → rotation is empty (covers all ⇒ sentinel).
- Partial deselect stays partial: from `{loop-01, loop-02}` with all=[01,02,03], `setSelected("loop-01", isOn:false, …)` → `{loop-02}`.
- One-loop floor (R6): from `{loop-02}`, `setSelected("loop-02", isOn:false, all:[01,02,03])` → **unchanged** `{loop-02}` (never empties to "none").
- Floor from all-minus-one down: repeated deselects can reach exactly one loop but not zero.
- `isAllSelected` true when rotation empty; true when rotation lists every current id; false for a strict subset.
- Persistence round-trip after `setSelected`: a second store reads the same normalized set.
- Stale ids ignored for "covers all": rotation `{loop-01, gone-99}` with all=[01,02] does not report all-selected.

**Verification:** New unit tests pass under `xcodebuild test -scheme AppexSaverMinimal -destination 'platform=macOS'`; existing `PlaybackSettingsTests` still green.

---

### U2. Simplify the Playback panel (drop the chip wall)

**Goal:** Replace the chip `LazyVGrid` with a one-line rotation summary and a
**Choose… / Done** button bound to selection mode.

**Requirements:** R1, R2.

**Dependencies:** U1 (uses `isAllSelected` for the summary), and the binding
introduced in U3 — build U3's state first or stub the binding.

**Files:**
- `AppexSaverMinimal/PlaybackControlsView.swift` — remove `chipColumns`,
  `chip(for:)`, and the chip grid; add `@Binding var isSelecting: Bool`; render the
  summary row + Choose/Done button. Keep Shuffle and Cross-fade exactly as-is.

**Approach:** The rotation block becomes a single `HStack`: *"In rotation"* label,
the `rotationSummary` text (reuse existing computed property; it already produces
"All N loops" / "M of N"), and a trailing button that reads **Choose…** when
`!isSelecting` and **Done** when selecting, flipping the binding. Preserve the
existing panel card styling, spacing, and the accent color. The "All" reset button
can move next to the summary (calls `settings.setRotation([])`).

**Patterns to follow:** existing panel layout and `GhostButtonStyle` usage in
`PlaybackControlsView.swift`; summary via the existing `rotationSummary`.

**Test scenarios:** `Test expectation: none — presentation-only view change; behavior is covered by U1 (store) and exercised via U3 (tap wiring). Manual check: panel shows two controls + summary + Choose button, no chips.`

**Verification:** App builds; Playback panel renders Shuffle, Cross-fade, a
rotation summary, and a Choose button — zero loop-ID chips.

---

### U3. Choose Loops mode on the "Your Loops" tiles

**Goal:** Add selection-mode state to `ContentView`, overlay a checkmark/dim state
on each tile while selecting, and route tile taps to rotation toggling (via U1)
instead of full-screen playback.

**Requirements:** R3, R4, R6.

**Dependencies:** U1 (calls `setSelected`), U2 (shares the `isSelecting` binding).

**Files:**
- `AppexSaverMinimal/ContentView.swift` — add `@State private var isSelectingRotation`;
  pass `$isSelectingRotation` to `PlaybackControlsView`; in `cell(_:)`, add a
  selection overlay and branch the `onTapGesture` on the mode; compute per-tile
  selected state from `playback` + current identifiers.

**Approach:** When `isSelectingRotation` is true: dim unselected tiles, show a
filled checkmark on selected ones, and make `onTapGesture` call
`playback.setSelected(id, isOn: !isSelected, allIdentifiers: currentIds)` where
`currentIds = library.videos.map { RotationResolver.identifier(for: $0.url) }` and
`id = RotationResolver.identifier(for: video.url)`. Selected state per tile =
`playback.isAllSelected(...)` OR `playback.rotation.contains(id)`. When false, keep
today's behavior (tap = `FullScreenPlayer.play`). Suppress the × remove button (or
leave it — decide during impl; default: hide it in selection mode to avoid a
double-action tile). Enforce R6 by disabling deselect on the last remaining
selected tile (the U1 no-op already protects the model; the tile should also read
as still-selected).

**Patterns to follow:** the existing overlay stack in `cell(_:)`
(`ContentView.swift:363`) — play glyph and remove button are already conditional
overlays; add selection as one more. Accent color from `PlaybackControlsView`.

**Test scenarios:**
- Selection state derivation: with rotation empty, every tile reports selected (all).
- With rotation `{loop-01}` and library [01,02], tile 01 selected, tile 02 not.
- Tap in selection mode toggles membership through `setSelected` (behavior asserted at the U1 store level; view wiring verified manually).
- `Test expectation: view-layer wiring — the toggling logic is unit-tested in U1; add a lightweight test only if a testable view-model seam is extracted. Otherwise manual: enter Choose mode, deselect a tile → summary drops to "M of N"; re-select all → summary returns to "All N loops"; last tile cannot be deselected.`

**Verification:** In Choose mode, tiles show checkmark/dim, tapping updates the
panel summary live, the last loop can't be removed; exiting via Done restores
tap-to-play. `xcodebuild build` succeeds.

---

## Scope Boundaries

**In scope:** the three units above — a store method + its tests, panel
simplification, and tile-based selection mode.

### Deferred to Follow-Up Work
- Per-surface rotation (rotation is global for v1 by design — see
  `PlaybackSettings.swift` header).
- Drag-to-reorder rotation / custom play order.
- Bridging rotation to the sandboxed screensaver config (deferred R7 in the
  original playback plan).

### Outside this plan
- **Catalog-stuck-spinning bug** — routed to `/ce-debug` for live diagnosis
  (runtime, not design).
- Any change to `VideoPlayerController`, `FullScreenPlayer`, or persistence keys.

---

## Risks & Dependencies

- **Sentinel confusion (empty = all).** The single highest-risk area; fully
  contained in U1 behind unit tests. If the decision table is implemented wrong,
  the symptom is inverted rotation (one loop plays instead of all). The
  deselect-from-all and collapse-to-empty tests are the guardrails.
- **Two-action tile.** In selection mode a tile could both toggle selection and
  trigger remove/play. Mitigation: branch `onTapGesture` on the mode and hide the ×
  in selection mode (U3).
- **Binding ordering (U2/U3).** U2 needs the `isSelecting` binding that U3 owns.
  Build U3's `@State` first (or stub `.constant(false)`), then wire U2.

---

## Verification Strategy

1. `xcodebuild test -scheme AppexSaverMinimal -destination 'platform=macOS'` —
   U1's new cases plus all existing `PlaybackSettingsTests` pass.
2. `xcodebuild build` — app compiles with the simplified panel and selection mode.
3. Manual pass in the running host app: panel shows no chips; **Choose…** enters
   selection mode; deselecting/selecting tiles updates the *"M of N" / "All N"*
   summary live; the last loop can't be deselected; **Done** restores tap-to-play;
   quit-and-relaunch shows the selection persisted.
