# Capability matrix — which iOS capture-protection techniques actually keep pixels OUT of a capture

**Status:** measured on Simulator only. Read §7 before quoting any number.
**Device:** iPhone 17 Pro simulator, iOS 26.2 (build from Xcode 27.0 / Swift 6.x)
**Harness:** `Research/CaptureMatrix/` — run with `Research/Scripts/capture_matrix.sh`
**Canonical runs:** matrix `20261002-151754-matrix` · feasibility `20261002-151341-feasibility` ·
replayKit `20261002-151448-replayKit` · renderSanity `20261002-153117-renderSanity`

---

## 1. The two questions, answered plainly

### (a) Does any PUBLIC API technique blank a region in a SCREENSHOT path?

**Yes — but only one, and only for its own content.**

| | Answer |
|---|---|
| `isSecureTextEntry` on a `UITextField` (public) | **YES — genuinely blanks.** Its text reads `TEXT-BLANKED` in the app-side render path (`darkPixels=0/1068`), while the *same* field's dots are visibly drawn on the display (host screenshot `19.02%` dark). The protection is real and capture-specific. **Scope: only the text field's own content.** |
| `AVSampleBufferDisplayLayer.preventsCapture = true` (public) | **NOT DETERMINABLE on Simulator.** The layer's pixels do disappear from the app-side render (sentinel shows through), but on Simulator the *same flag makes the layer paint nothing on the display either* (§4). "Absent from the capture" and "absent from the screen" are indistinguishable there. **Requires a device.** |
| secure-layer swap (`_UITextLayoutCanvasView`, private) | **YES — genuinely blanks arbitrary content.** Its band is painted on the display (host screenshot reads the real colour) but is excluded from the app-side render (sentinel). Unconfounded. **Private API.** |

So the honest answer to (a) is: **the only public API that demonstrably keeps content out of a
screenshot-like read is `isSecureTextEntry`, and it only protects the text field's own text.** For
protecting *arbitrary views*, the only mechanism measured as working is the **private** secure-layer
swap. The public `preventsCapture` flag is *plausibly* the right tool but **cannot be verified on
Simulator**, because on Simulator it does not render at all.

### (b) Does any PUBLIC API technique blank a region in a RECORDING/mirroring path?

**NOT MEASURABLE ON SIMULATOR — the recording-path guarantee is DEVICE-VALIDATED ONLY.**

`RPScreenRecorder.shared().startCapture` returns `isAvailable = true` and its completion handler
fires **with no error**, then delivers **zero callbacks in 30 s** — not a video frame, not an audio
buffer, nothing. `startRecording` reports `isRecording = true` and likewise produces no frames.
`UIScreen.main.isCaptured` stays `false` and `capturedDidChangeNotification` never fires.

**No verdict of any kind — `NO-LEAK` or `LEAKED` — can be claimed for the recording path from
Simulator data.** Every recording-path cell in §3 is marked not-measured for that reason, and the
package must not advertise recording protection on Simulator evidence.

---

## 2. Method — and why the verdicts can be trusted

### 2.1 Eight equal-height bands

One full-width band per technique, plus three controls that are **not** techniques. The controls are
the load-bearing part of the design: without them, a blank band is ambiguous between "protection
worked" and "nothing rendered here".

| # | Band | Kind | Painted colour |
|---|---|---|---|
| 1 | plain colour | **technique** (control) | `229,25,25` red |
| 2 | `AVSampleBufferDisplayLayer` `preventsCapture = true` | **technique** | `38,191,64` green |
| 3 | same layer, `preventsCapture = false` | **technique** (control for 2) | `242,216,25` yellow |
| 4 | secure-layer swap (private `_UITextLayoutCanvasView`) | **technique** | `38,102,242` blue |
| 5 | secure `UITextField` | **technique** (known-good control) | `242,140,13` orange, text `SECRET-9930` |
| 6 | secure-layer swap **DISABLED** | harness control | `38,102,242` blue |
| 7 | plain `UITextField`, same string | harness calibration | `150,60,200` purple, text `SECRET-9930` |
| 8 | band 2 + **opaque black shield** | package construction | `38,191,64` green over black |

- **Band 1** proves the harness itself works: if it does not survive a path, that path is broken.
- **Band 3** isolates band 2's flag. Same layer, same content, one boolean different.
- **Band 6** proves band 4's view renders when left alone, so a blank band 4 means *protection*, not
  *the private hack broke the view*.
- **Band 7** proves the capture path can resolve text at all, so a blank band 5 means *protection*,
  not *this path cannot image glyphs*. Its `TEXT-LEAKED` reading is the denominator for band 5.
- **Band 8** is the construction the package would actually ship: it converts "the protected pixels
  are gone" into the literal "the region comes out black" that the product promise is written in.

### 2.2 The sentinel — the reason a black region can be interpreted at all

Every technique view sits on a **sentinel** backing of `rgb(200,0,160)` magenta — a hue no band uses.
A capture-protection mechanism can remove a layer's pixels in two very different ways:

- it can **paint them black**, or
- it can **drop them from the composite** so whatever is *behind* shows through.

Only the second is dangerous, and a band whose backing happened to match its technique colour could
not tell them apart. So a band reading **sentinel** means *the pixels were removed from the
composite* — a distinct, and worse, outcome than black. **Band 8 is the deliberate exception**: its
backing is opaque black, which is precisely what turns "pixels removed" into "region is black".

This distinction is not academic — it is what exposed the Simulator confound in §4.

### 2.3 Sampling, and the three harness defects that had to be fixed first

Sampling geometry is expressed as fractions of the window, so the same numbers apply to a 402×874
app render and a 1206×2622 host screenshot. The colour rect sits **low-and-right** inside each band
(x 0.76–0.94, y 0.50–0.72 of the band), clear of the top-left label chip, clear of the centred text,
and clear of the home indicator. Sampling through the label or the text is what produced a false
black in the earlier probe. The text strip is sampled separately (x 0.28–0.72, y 0.40–0.62).

Three defects were found and fixed during this work. They are recorded because each one produced
*wrong numbers* before it was fixed, and a reader is entitled to know they were hunted down:

1. **Use-after-free segfault.** A `Bitmap` holding a `CGDataProvider` byte pointer was returned out
   of the closure that created it, leaving the pointer dangling; the process died with `SIGSEGV` in
   `PixelAnalyzer.Bitmap.pixel(x:y:)` (crash report `CaptureMatrix-2026-10-02-150037.ips`). The
   bitmap now **owns** its `CFData`.
2. **Display-P3 mislabelling.** The capture paths hand back bitmaps in the display's colour space
   (P3). Writing those P3-encoded pixels into a PNG tagged sRGB produced a file whose numbers
   matched *neither* the display nor the in-app reading — an independent host reader disagreed with
   the app by 20–40 per channel on saturated colours. The harness now normalises **once** to sRGB and
   uses that single image for both the artifact and the sampling.
3. **Scale-mismatched fidelity sampling.** Comparing a 1061×970 source against a 353×324 readback
   with the same pixel `step` zipped unrelated pixels and reported a mean error of `50.87` where the
   true value was `3.77`. Fidelity now goes through a fixed 64×64 sample grid.

### 2.4 Independent verification

`Research/Scripts/analyze_capture.py` re-implements the band sampling in Python from the written
PNGs, deliberately **not** trusting the in-app analyzer. After fix (2) above, the two agree exactly:

```
in-app : SAMPLE app-render(drawHierarchy) | band 0 1 plain colour (control) | meanRGB=(229, 25, 25) ... -> LEAKED(visible)
host   :   1 plain colour (control)   meanRGB=(229, 25, 25)    delta=   0.0 -> LEAKED(visible)
```

`Research/Scripts/fidelity_check.py` additionally re-measures fidelity host-side with an
alignment search.

---

## 3. Verdict table — technique × capture path

Paths: **A** = app-side render `window.drawHierarchy(in:afterScreenUpdates: false)` (the
screenshot-like app-side read). **A′** = `CALayer.render(in:)` (supplementary app-side read — see
§5). **B** = system capture pipeline `RPScreenRecorder.shared().startCapture` (the recording path).
**C** = host display capture `xcrun simctl io screenshot` (**contrast only, never evidence** — it
bypasses render-server protection).

| # | Technique | A — `drawHierarchy` (screenshot-like) | A′ — `layer.render` (supplementary) | B — `RPScreenRecorder` (recording) | C — host screenshot (contrast, not evidence) |
|---|---|---|---|---|---|
| 1 | plain colour (control) | **LEAKED(visible)** `(229,25,25)` Δ0.0 | **LEAKED(visible)** `(229,25,25)` Δ0.0 | not measurable — requires device | LEAKED(visible) `(229,25,25)` Δ0.0 |
| 2 | `AVSBDL` `preventsCapture=true` | **SENTINEL-SHOWS(transparent)** `(200,0,160)` Δ191.0 — ⚠️ confounded, see §4 | SENTINEL-SHOWS `(200,0,160)` Δ191.0 | not measurable — requires device | SENTINEL-SHOWS `(200,0,160)` Δ191.0 |
| 3 | `AVSBDL` `preventsCapture=false` | **LEAKED(visible)** `(242,216,25)` Δ0.0 | SENTINEL-SHOWS `(200,0,160)` Δ216.0 ⚠️ disagrees with A | not measurable — requires device | LEAKED(visible) `(242,216,25)` Δ0.0 |
| 4 | secure-layer swap (**private**) | **SENTINEL-SHOWS(transparent)** `(200,0,160)` Δ162.0 → **NO-LEAK** for arbitrary content | LEAKED(visible) `(38,102,242)` Δ0.0 ⚠️ disagrees with A | not measurable — requires device | LEAKED(visible) `(38,102,242)` Δ0.0 |
| 5 | secure `UITextField` (**public**) | **TEXT-BLANKED** `0/1068` = `0.00%` dark | TEXT-LEAKED `184/1068` = `17.23%` ⚠️ disagrees with A | not measurable — requires device | TEXT-LEAKED `808/4248` = `19.02%` |
| 6 | swap DISABLED (control) | LEAKED(visible) `(38,102,242)` Δ0.0 | LEAKED(visible) `(38,102,242)` Δ0.0 | not measurable — requires device | LEAKED(visible) `(38,102,242)` Δ0.0 |
| 7 | plain field (calibration) | TEXT-LEAKED `205/1068` = `19.19%` | TEXT-LEAKED `184/1068` = `17.23%` | not measurable — requires device | TEXT-LEAKED `907/4248` = `21.35%` |
| 8 | band 2 + black shield | **NO-LEAK(black)** `(0,0,0)` Δ191.0 — ⚠️ unearned on Simulator, see §4 | NO-LEAK(black) `(0,0,0)` Δ191.0 | not measurable — requires device | NO-LEAK(black) `(0,0,0)` Δ191.0 |

Reading the controls: **row 1 must read LEAKED** — it does, on every measured path, so the harness is
sound. **Row 3 must read LEAKED on path A** — it does, which is what makes row 2's sentinel
attributable to the `preventsCapture` flag and nothing else. **Row 6 must read LEAKED** — it does, so
row 4's blank is protection and not a broken view. **Row 7 must read TEXT-LEAKED** — it does, so row
5's `TEXT-BLANKED` is protection and not a path that cannot image glyphs.

**Per path, which technique yields NO-LEAK:**

| Path | Technique yielding NO-LEAK | Confidence |
|---|---|---|
| **A — screenshot-like (`drawHierarchy`)** | **Row 5 secure `UITextField`** — `TEXT-BLANKED`, unconfounded (dots visible on display, absent in capture). **Public API, but protects only the field's own text.** For **arbitrary content**, only **row 4 secure-layer swap** (private) achieves it, unconfounded. | High for 5 and 4; **not** for 2 |
| **B — recording (`RPScreenRecorder`)** | **None claimed.** The path delivered no frames, so no technique can be credited or blamed. | **Not measurable on Simulator — requires device** |

---

## 4. ⚠️ The Simulator confound — why row 2 and row 8 do NOT prove protection

This is the single most important caveat in this document, and it was found by asking the sentinel a
direct question: *is the protected layer painting at all?*

The `renderSanity` run renders three identically-built display layers that differ **only** in the
flag and in whether it is applied before or after the layer joins the tree, then screenshots the
**display itself** (host-side, which by construction cannot be fooled by capture protection):

```
RENDER-SANITY case 0 A capture=ON set-after-add  expect 229,25,25 | enqueued=1 rendererStatus=rendering preventsCapture=true
RENDER-SANITY case 1 B capture=ON set-before-add expect 38,191,64 | enqueued=1 rendererStatus=rendering preventsCapture=true
RENDER-SANITY case 2 C capture=OFF (control)     expect 242,216,25 | enqueued=1 rendererStatus=rendering preventsCapture=false
```

Sampled from `DISPLAY-ground-truth.png` (1206×2622):

```
A capture=ON set-AFTER-add   expect 229,25,25   nonBlack=4/4 [(200,0,160), (200,0,160), (200,0,160), (200,0,160)]
B capture=ON set-BEFORE-add  expect 38,191,64   nonBlack=4/4 [(200,0,160), (200,0,160), (200,0,160), (200,0,160)]
C capture=OFF control        expect 242,216,25  nonBlack=4/4 [(242,216,25), (242,216,25), (242,216,25), (242,216,25)]
```

**Both `preventsCapture = true` cases show the sentinel magenta — i.e. the layer contributed no
pixels to the display at all — while the `preventsCapture = false` case paints its colour
correctly.** All three report `rendererStatus = rendering`, `enqueued = 1`, and a correct
`402x291@0,0` layer frame. Setting the flag before or after adding the layer makes no difference.

**Conclusion:** on Simulator, `preventsCapture = true` does not *protect* the layer — it makes the
layer **render nothing, everywhere, including on screen**. `preventsCapture` is documented as
"image data should be protected from capture", which implies the content stays visible on the display
and is excluded only from captures. That is not what Simulator does.

**Therefore, on Simulator:**

- Row 2's `SENTINEL-SHOWS` and row 8's `NO-LEAK(black)` are **both fully explained by "the layer
  paints nothing"**. Row 8 is black because the backing behind a non-painting layer is black, not
  because capture protection engaged.
- **Row 8's `NO-LEAK(black)` is UNEARNED.** It must not be quoted as evidence that the public
  `preventsCapture` API protects content.
- The public `preventsCapture` API's actual capture behaviour is **NOT VERIFIABLE ON SIMULATOR —
  REQUIRES DEVICE**. This is the measurement the package's central claim depends on, and it is the
  first thing to run on hardware.

Note what *is* unconfounded, by the same test: **row 4** (secure-layer swap) reads the sentinel in
`drawHierarchy` but its **real colour** in the host display capture. Its content therefore *does*
reach the display surface and is excluded only from the render-server-backed read — genuine
capture-specific exclusion. The same asymmetry is what proves rows 2 and 8 are the opposite case.

---

## 5. Headline finding: `drawHierarchy` and `layer.render` DISAGREE

The two app-side reads contradict each other on three of eight bands, and this must not be averaged
or silently resolved.

| Band | A — `drawHierarchy` | A′ — `layer.render` | |
|---|---|---|---|
| 3 `preventsCapture=false` | LEAKED `(242,216,25)` Δ0.0 | SENTINEL `(200,0,160)` Δ216.0 | ✗ disagree |
| 4 secure-layer swap | SENTINEL `(200,0,160)` Δ162.0 | LEAKED `(38,102,242)` Δ0.0 | ✗ disagree |
| 5 secure `UITextField` | **TEXT-BLANKED** `0/1068` | **TEXT-LEAKED** `184/1068` | ✗ disagree |
| 1, 2, 6, 7, 8 | — | — | agree |

The mechanism is straightforward once stated: **`CALayer.render(in:)` walks the layer tree directly
and never goes through the render server.** Two consequences follow, and they explain all three
disagreements at once:

1. It **cannot see render-server-backed content**. `AVSampleBufferDisplayLayer` frames live in the
   render server, so the tree walk yields the backing colour instead of the frames — which is why
   band 3 (a display layer that *is* painting) reads sentinel while band 1 (an ordinary `CALayer`)
   reads its real colour.
2. It **does not honour capture exclusion**. The secure text field's dots and the swapped layer's
   content are both excluded at the render-server read stage, so a direct tree walk sails straight
   past the protection and captures them.

**Which path does a real screenshot or recording actually use?** Neither of these — a real iOS
screenshot is a **render-server** read, which is why the system's own secure text field is blanked in
screenshots. Of the two available app-side proxies, **`drawHierarchy` is the faithful one**: it goes
through the render server and therefore inherits the same exclusions a real screenshot does — which
is exactly why it reproduces the documented secure-field behaviour (`TEXT-BLANKED`) and `layer.render`
does not. `CALayer.render(in:)` is not a weaker screenshot; it is a *different and more permissive*
operation, and its readings of rows 3, 4 and 5 are **artifacts of bypassing the render server**, not
evidence about screenshot behaviour. (Stated as inference from the secure-field result, not as a
separately measured fact: the render-server claim itself is not directly observable from inside the
app, and is the reason the device run matters.)

**Practical consequence:** a package that used `CALayer.render(in:)`-style reads for its own
self-checking would conclude, wrongly, that it had leaked. And a *screenshot-like exfiltration
attempt built on `layer.render` would defeat both the secure field and the secure-layer swap* — that
is a real, if narrow, attack surface worth noting in the package's threat model.

---

## 6. Feasibility — can the public `preventsCapture` layer host arbitrary content?

**Verdict: the display-layer pipeline itself carries arbitrary content well, but on Simulator the
protected variant renders nothing at all, so the protected path's fidelity is NOT VERIFIABLE —
REQUIRES DEVICE.**

The probe pushed a real view-hierarchy render — gradient, solid block, monospaced glyphs
(`ACCT 4417-8823-0019 / BAL 1,284,930.55`), and a fine 1px grid — into two full-width display layers
differing only in the flag: the top protected over an opaque black shield, the bottom unprotected as
the fidelity reference.

**Content fidelity through the `CMSampleBuffer` → layer pipeline (measured on the unprotected
reference, canonical run `20261002-151341-feasibility`):**

```
FEASIBILITY fidelity[reference-layer(capture=OFF)] comparedPixels=4096 meanAbsChannelError=3.77 maxAbsChannelError=154.67 (0 = identical, 255 = inverted)
FEASIBILITY fidelity[reference-layer(capture=OFF)] sourceSampleRGB=(53, 25, 85) capturedSampleRGB=(54, 26, 85)
```

- **Mean absolute channel error `3.77` out of 255** — the pipeline reproduces arbitrary content
  faithfully. Glyph edges and the 1px grid survive. Host-side re-measurement with a LANCZOS
  downsample and a ±4px alignment search agreed: `mean abs channel error at zero offset : 8.31`, and
  the alignment search found **no better offset** (`best offset dx=0 dy=0`), so the residual is
  resampling, not misalignment.
- The high `maxAbsChannelError=154.67` is concentrated on hard glyph/edge boundaries where the
  `.resize` gravity resamples; it is a per-pixel worst case, not a systemic fidelity loss.

**Protected layer (top half), same run:**

```
FEASIBILITY region[protected-layer(capture=ON)] meanRGB=(0, 0, 0) maxChannel=0 nonBlackPixels=0/12744 -> NO-LEAK(black)
FEASIBILITY enqueue protected accepted=true status=rendering ready=true
```

`(0,0,0)` with `nonBlackPixels=0/12744` — and per §4 this is **the black shield showing through a
layer that painted nothing**, not evidence of protection. On Simulator there is nothing to compare,
so **fidelity of the protected path is not measurable here**.

**Frame-rate, latency and CPU cost (canonical run, 60 frames per pass, paced at 60fps):**

```
FEASIBILITY throughput[protected] frames=60 wall=1.28s achievedFPS=46.91 enqueue ms median=4.02 p95=6.12 max=10.22
FEASIBILITY cost[protected] cpuSeconds=0.254 cpuPerFrameMs=4.232 footprintDeltaMB=0.17 enqueueCount=61 rendererStatus=rendering
FEASIBILITY throughput[reference] frames=60 wall=1.42s achievedFPS=42.29 enqueue ms median=6.54 p95=8.03 max=9.61
FEASIBILITY cost[reference] cpuSeconds=0.426 cpuPerFrameMs=7.099 footprintDeltaMB=0.03 enqueueCount=61 rendererStatus=rendering
```

- **Enqueue cost median `4.0–6.5 ms`, p95 `6.1–8.0 ms`, worst `10.2 ms`.** This is the real cost
  number: the layer accepts a frame in single-digit milliseconds.
- **`42–47` achieved FPS is a floor, not a ceiling** — it is bounded by *my own* 16 ms pacing sleep
  plus the ~5 ms enqueue, so the ceiling was **not found**. I make no claim about the maximum
  sustainable rate.
- **CPU `4.2–7.1 ms per frame`; footprint growth `0.03–0.17 MB` over 60 frames.** Modest, and the
  footprint figure shows no per-frame leak at this duration.
- **Not measured:** on-screen presentation latency and dropped-frame count — no public API exposes
  them in-process, and a device capture of a moving target is required.

**Feasibility verdict.** Hosting arbitrary UIKit/SwiftUI content in an `AVSampleBufferDisplayLayer`
is **mechanically feasible with good fidelity and modest cost** — the content has to be rendered to
an image and pushed as a `CMSampleBuffer`, which the measurements above show works (error `3.77/255`,
~5 ms/frame, ~5 ms CPU/frame). The unresolved risk is **not** fidelity; it is that the protected
variant **renders nothing on Simulator**, so whether `preventsCapture = true` preserves on-screen
fidelity *while* excluding captures is exactly the question Simulator cannot answer. It must be
settled on hardware before the package promises anything.

---

## 7. Limitations — every cell that is not measured, and why

| Cell | Status | Reason |
|---|---|---|
| Path B (`RPScreenRecorder`), **all rows** | **not measurable on Simulator — requires device** | `startCapture` reports success (`isAvailable=true`, completion fired with no error) then delivers **zero callbacks in 30 s** (`callbacks=0 video=0 audioApp=0 audioMic=0`). `startRecording` reports `isRecording=true` and also yields no frames. `UIScreen.main.isCaptured` stays `false`; `capturedDidChangeNotification` never fires (0 observations). |
| Row 2 / row 8, capture-specific claim | **not measurable on Simulator — requires device** | `preventsCapture=true` makes the layer paint nothing on the display itself (§4), confounding "excluded from capture" with "never rendered". |
| Row 2 / row 8, protected-path fidelity | **not measurable on Simulator — requires device** | Nothing is rendered to compare against. |
| Real screenshot event (side + volume-up) | **not measurable on Simulator — requires device** | The Simulator exposes no volume button and no key-combo path, so `UIApplication.userDidTakeScreenshotNotification` cannot be fired. Screenshot *detection* is therefore unvalidated end-to-end. |
| App-switcher snapshot pixels | **not measurable on Simulator — requires device** | Snapshots land in `data/Library/SplashBoard/Snapshots/**/*.ktx` in Apple's proprietary `AAPL`-magic KTX variant; neither ImageMagick nor ffmpeg can decode them. |
| Maximum sustainable frame rate | not measured | The 16 ms pacing sleep bounds the achieved rate; the layer's ceiling was not probed. |
| On-screen latency / dropped frames | not measured | No public in-process API exposes them. |
| Path C (host screenshot) | **contrast only — never evidence** | `simctl io screenshot` reads the simulator's display surface from the host and bypasses render-server protection entirely. It is retained purely to *demonstrate* the bypass: rows 4 and 5 read `LEAKED` / `TEXT-LEAKED` there while `drawHierarchy` blanks them. |

**Everything above is Simulator-only.** No physical device was attached during this work
(`xcrun devicectl list devices` shows only `simulated` entries), so every device-required cell is
genuinely unmeasured rather than merely unverified.

---

## 8. Recommendation

**The package should rely on the secure `UITextField` (`isSecureTextEntry`) as its one
measured-and-public no-leak primitive, and on the private secure-layer swap as an explicitly opt-in,
clearly-labelled extension — with the public `AVSampleBufferDisplayLayer.preventsCapture` path
carried as *advisory, device-unverified* until it is measured on hardware.** Concretely: band 5 is
the only result in this matrix that is simultaneously public API, measured, and unconfounded — a
secure text field's content is blanked in the app-side render path (`TEXT-BLANKED`, `0/1068`) while
being visible on the display (`19.02%`), and the calibration band proves the path can image text
(`205/1068`), so the protection is real. Its hard limit is scope: it protects **the field's own
content only**, not arbitrary views, so the package must not present it as a general-purpose shield.
For protecting arbitrary regions, the only mechanism that measured as genuinely excluding content is
the **private** `_UITextLayoutCanvasView` swap (row 4), which must therefore be opt-in, off by
default, documented as non-contract and breakable by any iOS release, and never described as a
security guarantee. The **public `preventsCapture` API must not be advertised as protecting
screenshots or recordings on the strength of this Simulator data**: on Simulator it renders nothing
at all, so row 8's `NO-LEAK(black)` is unearned, and the recording path produced no frames
whatsoever — meaning **the entire recording-path guarantee is device-validated only**. The
overlay-shield and watermark features should be treated as *deterrent and forensic* measures, not as
leak prevention, because neither removes pixels from a capture. The immediate next action is a single
device run of `renderSanity`, `matrix` and `feasibility`, which is what converts the package's
central claim from *plausible* to *measured*.


## 9. Note on the committed artifacts

The raw logs committed under `Research/Artifacts/<run>/` are published **verbatim**, because an edited
transcript stops being evidence: `app-documents/*.log`, `unified-log.txt`, `build.log`,
`toolchain.txt` and `launch.txt` are exactly what the harness produced. They therefore contain
absolute paths from the machine that produced them (for example
`/Users/<user>/Developer/ScreenGuarantor/...`). Those path prefixes are the only content that
identifies the machine's owner — the user name in them is `jiefu`; Simulator device UDIDs
(`CoreSimulator/Devices/<udid>/…`) and `/Applications/Xcode.app` paths appear as well, and they
identify no person. No credential, token, password or key appears in any of them, and nothing is
redacted: the logs are left unedited on purpose so a reader can re-run the exact command each log
shows.
