# Research — capture-protection measurement harness

This directory holds the **measurement apparatus** behind
[`docs/evidence/capability-matrix.md`](../docs/evidence/capability-matrix.md). It is evidence
tooling, not package code: nothing here ships in `ScreenGuard`.

The question it answers is narrow and load-bearing: **for each capture-protection technique, does
the protected region come out black/blank in the capture — and in which capture paths?** Stopping the
user from screenshotting is explicitly *not* the bar; keeping pixels out of the capture is.

## Layout

| Path | Role |
| --- | --- |
| `CaptureMatrix/Sources/Bands.swift` | The eight bands, their colours, the sentinel, sampling geometry |
| `CaptureMatrix/Sources/TechniqueViews.swift` | The technique views (display layer, secure field, secure-layer swap) |
| `CaptureMatrix/Sources/CapturePaths.swift` | The capture paths: `drawHierarchy`, `RPScreenRecorder`, `layer.render` |
| `CaptureMatrix/Sources/PixelAnalyzer.swift` | sRGB normalisation, band sampling, verdict classification |
| `CaptureMatrix/Sources/MatrixProbe.swift` | Runs the technique × path matrix, writes the raw log + PNGs |
| `CaptureMatrix/Sources/FeasibilityProbe.swift` | Arbitrary-content fidelity, cadence and CPU cost |
| `CaptureMatrix/Sources/RenderSanityProbe.swift` | Does `preventsCapture` stop the layer painting on screen? |
| `CaptureMatrix/Sources/ReplayKitProbe.swift` | Why the recording path delivers no frames |
| `Scripts/capture_matrix.sh` | Build → install → launch → screenshot → pull artifacts |
| `Scripts/analyze_capture.py` | **Independent** host-side re-analysis of the written PNGs |
| `Scripts/fidelity_check.py` | Host-side, alignment-aware fidelity re-measurement |
| `Artifacts/<run-id>/` | Raw evidence: logs, PNGs per path, host contrast screenshot |

## Running it

```sh
# technique x capture-path matrix  (the main measurement)
Research/Scripts/capture_matrix.sh --device "iPhone 17 Pro" --runtime 26.2

# feasibility of hosting arbitrary content
Research/Scripts/capture_matrix.sh --mode feasibility

# diagnostics
Research/Scripts/capture_matrix.sh --mode renderSanity
Research/Scripts/capture_matrix.sh --mode replayKit
```

`--runtime` is normalised (`26.2` → `iOS-26-2`) before matching, because `simctl` reports runtime
keys as `com.apple.CoreSimulator.SimRuntime.iOS-26-2`.

Each run writes to `Research/Artifacts/<timestamp>-<mode>/` and prints the app's log at the end. The
script never interprets the numbers — it only moves them.

## Two rules that make the verdicts trustworthy

**1. Always check the artifacts host-side.** `Scripts/analyze_capture.py` re-implements the sampling
in Python from the written PNGs and deliberately does not trust the in-app analyzer. When the two
disagreed during development, the disagreement was real and exposed a colour-space bug — see
"Harness defects" below. A verdict backed only by the in-app log is half-verified.

**2. `preventsCapture` must be sanity-checked against the display.** A band that is blank in a
capture is ambiguous between "protection worked" and "nothing rendered there". `renderSanity` mode
screenshots the **display itself** (host-side, which capture protection cannot influence) to
separate the two. On Simulator this is what revealed that `preventsCapture = true` makes the layer
paint nothing anywhere — so `NO-LEAK(black)` there is unearned. Never quote a protected-band result
without this check.

## Harness defects found and fixed

Each of these produced *wrong numbers* before it was fixed. They are listed so a future reader can
recognise the symptoms:

| Defect | Symptom | Fix |
| --- | --- | --- |
| Dangling `CFData` pointer | `SIGSEGV` in `Bitmap.pixel(x:y:)` | `Bitmap` owns its `CFData` |
| Display-P3 pixels written as sRGB | Host reader disagreed with the app by 20–40/channel | Normalise **once** to sRGB; sample and write the same image |
| Pixel-`step` sampling across scales | Fidelity mean error `50.87` where truth was `3.77` | Fixed 64×64 `sampleGrid` |

## Traps (already reproduced — do not rediscover)

- `drawHierarchy(in:afterScreenUpdates: true)` forces a CATransaction commit and UIKit asserts inside
  `_UIRenderViewImageAfterCommit` (`SIGABRT`). **Keep it `false`.**
- `xcrun simctl io screenshot` and sim-use `screenshot`/`record-video` read the display surface from
  the host and **bypass render-server capture protection**. Contrast measurement only, never
  evidence. See [`docs/TOOLING.md`](../docs/TOOLING.md).
- `UIGraphicsImageRenderer` returns 16 bits per component (`bitsPerPixel == 64`); reading those bytes
  as 8-bit components yields noise. Normalise to RGBA8 first.
- `CALayer.render(in:)` uses a **bottom-left origin** (flip it) and **cannot see
  `AVSampleBufferDisplayLayer` content**, because that layer is render-server backed.
- Sample away from the label chip and from vertically-centred text, or you get false blacks.
- `RPScreenRecorder` may present a consent prompt or stall with no frame. Bound the wait and record
  `unavailable` honestly instead of hanging.

## Device-only measurements

Every device-required cell in the capability matrix is genuinely unmeasured, not merely unverified:
no physical device was attached during this work. `renderSanity`, `matrix` and `feasibility` should be
re-run on hardware first, because that is what settles whether the public `preventsCapture` API
protects content while still rendering it on screen.
