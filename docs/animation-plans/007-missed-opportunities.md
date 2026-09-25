# 007 — Additive motion: symbol morphs, track-change crossfade, Listening pill, shared artwork

- **Status**: TODO (depends on 001)
- **Commit**: a793545
- **Severity**: LOW (additive)
- **Category**: Missed opportunities
- **Estimated scope**: 5 files; part D is risky

## A. Symbol morphs
`ExpandedPlayerView` play/pause and shuffle icons swap with no animation. Add `.contentTransition(.symbolEffect(.replace))` (exemplar `TeleprompterControlStrip.swift:69`) and drive the swap with `NotchAnimations.press`; gate with Reduce Motion.

## B. Track-change crossfade
Title/artist/artwork changing snaps. Add `.contentTransition(.opacity)`-style crossfade WITHOUT `.id(text)` on containers (a previous `.id(text)` change was the root cause of a track-switch race; do not reintroduce it). Prefer `.animation(.easeOut(duration: 0.2), value: info?.title)` on the text views and `.transition(.opacity)` on artwork inside a fixed-size frame.

## C. Listening pill in/out
`TeleprompterListeningPill` appears/disappears abruptly. Give its host an `.transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))` with `NotchAnimations.standard`.

## D. Shared artwork pill -> peek -> expanded
Use `matchedGeometryEffect(id: "artwork", in: namespace)` on the artwork in PillPlayerView/PeekPlayerView/ExpandedPlayerView with a `@Namespace` in `NotchRootView`. Constraints: outer containers stay `.transition(.identity)` (ADR 0014), so matched geometry only works if source and destination are in the same render pass; if the artwork jumps or content escapes the clip, REVERT D and report (do not force it). Panel size never changes (Invariant 3); only content animates.

## Boundaries
Reduce Motion: no matched geometry, no scale. Do not touch teleprompter scroll logic.

## Verification
- Mechanical: build + tests green.
- Feel check per part, incl. rapid skip x10 (no stuck old track), Reduce Motion on.
