---
date: 2026-07-05
topic: visualizer-mode
---

# Surrealism — Visualizer / State-Change Mode Requirements

## Summary

Add a second mode to the Surrealism Mac app: an **audio-reactive visualizer**
that also serves as the front end for a broader **state-change** experience. Your
surreal AI loops become the visual engine — pulsing and shifting in sync with
audio, which can be **either external music** (whatever's playing on the Mac) **or
audio the app generates itself** (entrainment tones, breathing pacers). It reuses
the existing `VideoPlayerController` and runs in the (unsandboxed) host app.

v1 is a focused, shippable slice. The wider technique library from
`state-change-techniques-app-reference.md` (../../state-change-techniques-app-reference.md)
is captured as a **roadmap**, not v1 — the discipline here is to ship the core and
add techniques incrementally.

## Thesis

Surrealism.ai is "visuals for music experiences," and the reference maps how the
same AI-art pipeline powers evidence-based state-change tools (photic/audio
entrainment, breathing pacers, focus practices). So the visualizer is two things
at once: a music visualizer *and* the visual layer for calm/focus/sleep sessions.
Both are on-brand and both reuse the loop engine.

## Key Decisions

- **Two audio roles.** (a) *React* to external system audio; (b) *generate*
  entrainment audio (binaural/isochronic tones, noise beds, a breathing-pacer
  tone) and sync visuals to it. A preset picks which role is active.
- **External audio via ScreenCaptureKit** (system audio, macOS 13+; one-time
  screen-recording permission; feasible because the host app is unsandboxed).
- **Presets, not raw sliders.** Named session presets are the primary control
  (per founder decision), each bundling an audio behavior + a visual behavior.
- **Both windowed and fullscreen** (per founder decision).
- **Safe-mode visuals by default; strobe is gated.** Default is soft
  luminance/color "breathing," never hard flicker. Any strobing is behind a
  photosensitivity warning and locked out of the ~15–25 Hz seizure-risk band
  unless explicitly overridden.
- **Honest, non-medical framing.** Present entrainment/flicker effects as
  "varies person to person, try it and see," never as therapy or a cure. No
  clinical claims. (The reference stresses this throughout.)
- **Reuse `VideoPlayerController`**; the screensaver extension is untouched.
- **Free vs. paid: undecided** (open question — ties into pricing).

## Requirements

**Playback & effects**

- R1. A fullscreen and a windowed player render the loop library via the shared `VideoPlayerController`.
- R2. Audio is analyzed in real time for energy, beat/onset, and low/mid/high bands.
- R3. Audio drives effects over the video: energy pulse/zoom, bloom on peaks, band-mapped tint, and crossfade/transition intensity; loop switching can beat-sync.
- R4. Effects settle to calm ambient playback when audio is quiet.
- R5. Rendering holds ~60fps with effects on.

**Audio sources**

- R6. External mode captures system audio via ScreenCaptureKit, requesting screen-recording permission with a clear explanation and degrading gracefully if denied.
- R7. Generated mode plays app-synthesized entrainment audio — binaural/isochronic tones by target band, optional pink/brown-noise bed — and drives the visuals from that signal.

**Presets**

- R8. The primary control is a set of named presets, each bundling an audio behavior + a visual behavior. Launch set (indicative): "React to my music," "Sleep (delta)," "Deep calm (theta)," "Calm-alert (alpha)," "Focus (low beta)," and "Breathe" (resonance pacer).
- R9. A single "intensity/sensitivity" control adjusts the active preset; deeper per-effect tuning is deferred.

**Breathing & focus**

- R10. A breathing-pacer visual (expand/contract shape) with adjustable inhale:hold:exhale, defaulting to ~6 breaths/min resonance breathing, syncable with a pacer tone.
- R11. A focus-point ("Trataka") mode: a single steady symbol or loop held for a fixed-duration gaze.

**Safety & framing (must-have)**

- R12. A photosensitivity/seizure warning gate before any strobing visual; safe-mode luminance breathing is the default and strobe is off unless explicitly enabled.
- R13. Copy frames all effects as non-medical and individually variable; no therapy/treatment claims; gentle session-length reminders where relevant.

**Controls & UX**

- R14. A "Visualizer" entry point in the host app; auto-hiding controls (play/pause, next, preset, intensity, choose display, windowed/fullscreen, Esc to exit).
- R15. The user picks which display it fills (one or all).

## Key Flows

- F1. Launch → pick a preset → (first time, if external) grant screen-recording permission → player starts.
- F2. Music/entrainment plays → loops react/entrain; quiet → calm drift.
- F3. Breathe preset → pacer shape guides breathing, loops breathe with it.
- F4. Exit via Esc/control.

## Scope Boundaries

**v1 (build now)**
- Audio-reactive visualizer (external music via ScreenCaptureKit) + the effect set.
- Generated entrainment audio for the band presets + noise bed.
- The launch preset set, breathing pacer, focus-point mode.
- Safe-mode visuals + photosensitivity gate + honest framing. Windowed + fullscreen.

**Roadmap (deferred — from the reference, add incrementally)**
- Sigil / focus-symbol creator (feed intent → AI-art render).
- Hypnosis / guided-trance track template + affirmation loops.
- Memory-palace builder; reflective/"reality-tunnel" journal; NLP anchoring toolkit.
- Historical/aesthetic theme packs (Mesmerism, rocket-age occult, etc.).
- Personalized "metafive" metaphor generator; bilateral-stimulation mode.
- "Find your resonance rate" breathing test.

**Outside this product's identity**
- Any medical/therapeutic claim or positioning as treatment.
- Generating the core visuals live from scratch (the loops are the content).

## Dependencies / Assumptions

- Host app is unsandboxed (verified) — ScreenCaptureKit + AVPlayer in a normal window is feasible.
- macOS 14+ (ScreenCaptureKit is 13+).
- Audio analysis via Accelerate/vDSP FFT; entrainment tone synthesis via AVAudioEngine; effects via Metal or Core Image over the `AVPlayerLayer`.
- Same loop library / cache as the screensaver.

## Open Questions

- **Free vs. paid** — is the visualizer included free, or a lifetime/Plus perk? (Ties to pricing; leaning "premium mode" to add buy-value, but undecided.)
- Which presets ship in v1 vs. later.
- Windowed and fullscreen both in v1 (yes) — is windowed a floating always-on-top option too?
- Where the roadmap wellness features live long-term — inside Surrealism, or a separate companion app sharing the loop/art pipeline?

## Reference

- `state-change-techniques-app-reference.md` (repo root of `surrealism-app/`) — evidence review + feature map that informs the audio engine, visual entrainment, presets, safety guardrails, and the deferred roadmap.
