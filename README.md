# Palma

Control your laptop's cursor with computer vision — a webcam, your hand, no mouse.

## Status: MVP implemented (`PalmCtrl/`)

A native macOS app (Swift, no Python/Electron) that implements the cursor-control core of the spec below:

- Index finger moves the cursor
- Pinch thumb+index → click / long-click / drag (same press-hold-release logic as a real trackpad — no custom timers, it falls out of just forwarding mouseDown/mouseDragged/mouseUp)
- Pinch index+middle → scroll
- Pinch thumb+index+middle → right-click
- Smoothed with a One Euro filter so the cursor doesn't jitter, and holds its last position briefly if the hand drops out of frame instead of jumping

**Not built yet** (deferred past MVP — see [Full spec](#full-spec)): pinch-to-zoom, the floating on-screen keyboard, the annotation overlay (pen/highlight/eraser/undo/redo), the hand-distance warning, and anything phone-side. Each of those is its own UI subsystem and was intentionally cut so the core "hand as a mouse" feel could be validated first.

### Why native Swift, not a browser extension or Python+Electron

A browser extension can't move the real OS cursor or click outside its own tab — it's sandboxed to a webpage. True system-wide cursor/click control needs OS-level APIs (Accessibility `CGEvent`), and Apple's own **Vision** framework (`VNDetectHumanHandPoseRequest`) gives hand landmarks natively with no separate CV runtime to install — so the whole thing is one signed app, one language, permissions granted once.

### Run it

```bash
cd PalmCtrl
swift run
```

First run prompts for **Camera**, then **Accessibility** access (grant it to your terminal app in System Settings → Privacy & Security if the dialog doesn't appear automatically). `Ctrl+C` to quit — it releases any held mouse button on exit or if your hand leaves the frame, so it won't leave the trackpad "stuck" mid-drag.

### Known rough edges (needs hands-on tuning, not visually testable from here)

- Pinch sensitivity (`pinchEnter` / `pinchExit` in `GestureController.swift`) — tune if clicks feel too sticky or fire too easily.
- Cursor mirroring/axis direction — flip `mirrorX` in `GestureController.swift` if motion ever feels backwards for your camera setup.
- Smoothing feel (lag vs. jitter) — adjust the `OneEuroPointFilter` constants in `GestureController.swift`.

## Full spec

The original feature list this project is working toward:

- A button to choose whether the cursor follows the right hand (default) or left hand
- Cursor response should be smoothed and fluid, like a real trackpad
  1. Cursor follows the index finger — no jumping; if the finger disappears, it should pick up from where the motion left off
  2. Pinch thumb+index → click / long-click / drag / block, same logic as a single-finger trackpad click
  3. Pinch index+middle → scroll
  4. Pinch thumb+index+middle → right-click
  5. Spread index finger & thumb apart → zoom in; close them (without touching) → zoom out
- A button to show a floating, transparent on-screen keyboard, typed with all 10 fingertips visible on it (with an option to show the right hand, left hand, or both)
- A button to enter annotation mode: pen, highlight, eraser, undo, redo, done (and more features to be added)
- A warning indicating when the hand is too close or too far from the camera
