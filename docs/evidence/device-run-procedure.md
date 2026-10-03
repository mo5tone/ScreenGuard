# Device validation procedure — the cells Simulator could not answer

> **STATUS: NOT YET EXECUTED.** No physical device was attached to this machine when this procedure
> was written (`xcrun devicectl list devices` reports every known device as `reality: simulated`).
> **This document therefore produces no verdicts.** It describes how to obtain them, what they will
> fill, and what must be true first. Every device result below is marked as expected-or-unknown; none
> is measured. Do not quote anything in this file as evidence until a run has actually happened and
> its artifacts are committed.

**Command:**

```sh
Research/Scripts/capture_matrix_device.sh --device <UDID-or-name> --team <TEAMID>
```

That single command builds the `CaptureMatrix` harness for the device, installs it, runs
`matrix` + `feasibility` + `renderSanity`, pulls the app-side logs and PNGs off the device, and
re-derives the verdicts with the same Python analyzer the Simulator runs used.

Companion files:

| File | Role |
| --- | --- |
| [`Research/Scripts/capture_matrix_device.sh`](../../Research/Scripts/capture_matrix_device.sh) | The one command. Refuses to run without a physical device. |
| [`Research/Scripts/interpret_render_sanity.py`](../../Research/Scripts/interpret_render_sanity.py) | Turns the display image into a `PREVENTSCAPTURE-USABLE` / `-NOT-USABLE` verdict. |
| [`Research/Scripts/analyze_capture.py`](../../Research/Scripts/analyze_capture.py) | Unchanged; consumes the device artifacts in the same layout. |

---

## 1. What the device run fills, and what it does not

These are the rows [`capability-matrix.md`](capability-matrix.md) §7 marks
**"not measurable on Simulator — requires device"**, quoted from that table:

| §7 row | Why Simulator could not answer it | Which script mode fills it |
| --- | --- | --- |
| **Path B (`RPScreenRecorder`), all rows** — every recording-path cell | `startCapture` reports success (`isAvailable=true`, completion fired with no error) then delivers **zero callbacks in 30 s** (`callbacks=0 video=0 audioApp=0 audioMic=0`). `startRecording` reports `isRecording=true` and also yields no frames. `UIScreen.main.isCaptured` stays `false`; `capturedDidChangeNotification` never fires (0 observations). | `matrix` (and `replayKit` for a focused re-run) |
| **Row 2 / row 8, capture-specific claim** — the public `AVSampleBufferDisplayLayer.preventsCapture` behaviour, **both flag orders** | `preventsCapture=true` makes the layer paint nothing on the display itself (§4), confounding "excluded from capture" with "never rendered". | `renderSanity` + `matrix` |
| **Row 2 / row 8, protected-path fidelity** | Nothing is rendered to compare against. | `feasibility` |
| **Real screenshot event (side + volume-up)** | The Simulator exposes no volume button and no key-combo path, so `UIApplication.userDidTakeScreenshotNotification` cannot be fired. Screenshot *detection* is therefore unvalidated end-to-end. | **Not filled by this command** — needs a human to press side + volume-up on the device. |
| **App-switcher snapshot pixels** | Snapshots land in `data/Library/SplashBoard/Snapshots/**/*.ktx` in Apple's proprietary `AAPL`-magic KTX variant; neither ImageMagick nor ffmpeg can decode them. | **Not filled by this command** — see §5. |

**The two rows this command exists for are the first two**: the public `preventsCapture` capture
behaviour in both flag orders, and every recording-path cell. Those are precisely the rows the
package's central claim rests on.

### What a successful run does NOT establish

- It does **not** validate screenshot *detection* (no script can press two buttons at once).
- It does **not** decode app-switcher snapshots.
- It is **one device on one OS build**. It is not a compatibility statement. Record the model, iOS
  build and date next to every result, and re-run on each supported OS major version.

---

## 2. Preconditions

All six must hold. The script checks 1, 2 and 5 itself and fails with an actionable message if they
do not; 3, 4 and 6 it can only warn about.

| # | Precondition | How to satisfy / verify | Checked by |
| --- | --- | --- | --- |
| 1 | **Device connected** by cable or paired wirelessly, and **unlocked** | `xcrun devicectl list devices` shows it | script (exit 3) |
| 2 | **Device is genuinely physical** | `reality: physical` in `devicectl list devices --json-output -`. Simulators report `reality: simulated` and are **refused**. | script (exit 3) |
| 3 | **Trusted** — the host is trusted on the device | Tap *Trust* on the device prompt when connecting | script warns on `pairingState != paired` |
| 4 | **Developer Mode enabled** | Settings ▸ Privacy & Security ▸ Developer Mode ▸ on, then reboot. iOS 16+ requires this. | not directly detectable; surfaces as a build/launch failure |
| 5 | **A valid development signing identity exists** | `security find-identity -v -p codesigning` reports ≥ 1 | script (exit 4) |
| 6 | **A development-signed app with `get-task-allow`** | The script passes `CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=… CODE_SIGN_IDENTITY="Apple Development"`. `get-task-allow` is what lets `devicectl` launch and attach to the app. | build/launch step |

`Research/CaptureMatrix/project.yml` sets `CODE_SIGNING_ALLOWED: NO` so that Simulator builds need no
identity. That file is **out of scope for this task and is not edited**; the script overrides the
setting on the `xcodebuild` command line instead. This is why `--team` is mandatory.

Also required: **Xcode with the CoreDevice tooling** (`xcrun devicectl`), and ideally the device
prepared once by Xcode (*Window ▸ Devices and Simulators*, wait for *Preparing device* to finish),
which mounts the developer disk image (`ddiServicesAvailable`).

### Expected wall-clock time

| Phase | Typical | Notes |
| --- | --- | --- |
| First device build | 2–5 min | Longer if Xcode has to prepare the device or download support files. |
| Subsequent builds | ~40–90 s | Incremental. |
| `matrix` | ~60 s | Includes the 12 s bounded ReplayKit wait. |
| `feasibility` | ~50 s | 12 s display hold + two 60-frame throughput passes. |
| `renderSanity` | ~40 s | 30 s display hold plus the manual photograph window. |
| Collection + interpretation | ~10 s | `devicectl copy from` + `log collect`. |
| **Total, first run** | **≈ 5–8 min** | |
| **Total, warm rerun** | **≈ 3–4 min** | |

One extra manual step: during `renderSanity` the script pauses and prints a prompt asking you to
**photograph the device screen**. Budget ~30 s for that.

---

## 3. Running it

```sh
# 1. Confirm a physical device is visible.
xcrun devicectl list devices

# 2. One command: build, install, run all three modes, collect and interpret.
Research/Scripts/capture_matrix_device.sh \
    --device 00008101-000A0C123456001E \
    --team ABCDE12345
```

Useful variations:

```sh
# Select by device name instead of UDID.
Research/Scripts/capture_matrix_device.sh --device "My iPhone" --team ABCDE12345

# Re-run a single mode (e.g. after a first ReplayKit consent prompt).
Research/Scripts/capture_matrix_device.sh --device "My iPhone" --team ABCDE12345 --modes matrix

# Longer renderSanity hold, if 30 s is too short to photograph.
RENDER_SANITY_HOLD=60 Research/Scripts/capture_matrix_device.sh --device "My iPhone" --team ABCDE12345
```

### During the run

1. **Keep the app in the foreground** for the whole run. Backgrounding it stops the render paths.
2. **`renderSanity` will ask you to photograph the screen.** Do it: three full-width bands appear,
   labelled `A` (`preventsCapture=true`, set after add), `B` (`preventsCapture=true`, set before add)
   and `C` (`preventsCapture=false`, control). Save the photo as
   `<artifact-dir>/DISPLAY-photograph.png`. A **magenta (`rgb 200,0,160`) band means that layer
   painted nothing** — that is the whole point of the sentinel, and a camera is the only view of the
   display no capture API can influence.
3. **The first `matrix` run may show a ReplayKit consent prompt.** Accept it. If the recording path
   still reports no frames, **that is a result** — record it, do not retry until it looks better.

### Exit codes

| Code | Meaning |
| --- | --- |
| 0 | All requested modes ran and artifacts were collected. |
| 2 | Usage error (missing `--device`). |
| 3 | No physical device connected, or the named device is not physical / not paired. |
| 4 | Build or signing failure. |
| 5 | Install, launch, or artifact-collection failure. |

---

## 4. The three safety rules the script enforces

These exist because violating any one of them silently produces **unearned** evidence.

**1. A device is required, named explicitly, and there is no Simulator fallback.** There is no
default device. A Simulator would happily produce a `NO-LEAK(black)` for the protected band — and
per `capability-matrix.md` §4 that reading is worthless there, because on Simulator the layer never
paints in the first place. The script refuses (`exit 3`) rather than degrade quietly.

**2. Artifacts use the same layout as the Simulator runs, so the analyzer is unchanged.** Everything
lands in `Research/Artifacts/<run-id>-device/` with the identical shape:

```
Research/Artifacts/<run-id>-device/
├── RUN-PROVENANCE.txt                  # capture-matrix-run: DEVICE, udid, model, os build
├── toolchain.txt                       # Xcode, Swift, device + signing provenance
├── build.log, install.txt, launch-<mode>.txt
├── DISPLAY-ground-truth.png            # device screenshot (display question ONLY)
├── DISPLAY-photograph.png              # operator photo, if taken (the tie-breaker)
├── unified-log.txt                     # device unified log for our subsystem
├── copy-from.txt, device-screenshot.txt
└── app-documents/
    ├── matrix-<run-id>.log             # primary quoted source
    ├── feasibility-<run-id>.log
    ├── rendersanity-<run-id>.log
    ├── capture-app-render-drawHierarchy.png          # the screenshot-like path
    ├── capture-app-render-layer-render.png           # supplementary path
    ├── capture-system-capture-RPScreenRecorder.png   # ONLY IF the recording path delivers frames
    └── feasibility-app-render.png / feasibility-source.png
```

The recording PNG is listed as conditional on purpose. On Simulator it never appeared, because the
pipeline delivered no frames. **If it appears on the device, it is the single most important artifact
of the run** — the first real recording-path data the project will have. The script therefore
auto-discovers `capture-*.png` rather than hardcoding filenames, so a newly-appearing file cannot be
silently skipped, and it prints an explicit recording-path status line either way.

`analyze_capture.py` consumes `app-documents/capture-*.png` **unchanged** — verified by running it
against a device-shaped directory built from the existing Simulator artifacts:

```
$ python3 Research/Scripts/analyze_capture.py <device-dir>/app-documents/capture-app-render-drawHierarchy.png
=== ... (402x874, 8 bands) ===
  1 plain colour (control)   meanRGB=(229, 25, 25)  delta=0.0  -> LEAKED(visible)
  2 AVSBDL capture=ON        meanRGB=(200, 0, 160)  delta=191.0 -> SENTINEL-SHOWS(transparent)
  ...
```

Because the layouts are identical, the **`RUN-PROVENANCE.txt` marker is the only thing that
distinguishes a device run from a Simulator run.** It is written *before* the build, so even a failed
run records which device was targeted.

**3. Host-side capture is never a no-leak verdict.** The script takes a `DISPLAY-ground-truth.png`
via `devicectl device capture screenshot`, but whether *that* honours capture protection is itself
unmeasured. So it is used for exactly one question — **"is the protected layer painting on screen at
all?"** — and never to claim protection. That is also why the operator is asked for a photograph: a
camera is the one display view no capture API can influence, and it is the tie-breaker if the device
screenshot disagrees.

---

## 5. After the run: how to read the results

**Nothing the script prints is a verdict yet.** It prints measurements and one narrow interpretation.

### 5.1 `renderSanity` — the decisive one

`interpret_render_sanity.py` reads the display image and classifies each band:

| Reading | Meaning |
| --- | --- |
| the case's expected colour | the layer **PAINTED** |
| sentinel magenta `rgb(200,0,160)` | the layer painted **NOTHING** (contributed no pixels anywhere) |
| black | the layer painted, but this capture path **EXCLUDED** its content |

Because the backing is sentinel and never black, "black" can never be produced by a non-painting
layer — that is what makes the three states distinguishable.

| Verdict | What it means for the package | What to do |
| --- | --- | --- |
| `PREVENTSCAPTURE-USABLE` | The protected layer **renders on the display**. The capture path either honours protection (band reads black) or does not (band reads its colour) — but in both cases the layer is really painting, so a blank band in the app-side render becomes **attributable to protection** rather than to an absent layer. | Cross-check against `matrix`. This is the result that makes the public `preventsCapture` claim defensible. |
| `PREVENTSCAPTURE-NOT-USABLE` | On this OS build `preventsCapture=true` stops the layer rendering at all. The API is **not** a usable protection mechanism, and any black protected band is **unearned**. | Record as a genuine finding. The package must not advertise `preventsCapture` protection. |
| `GROUND-TRUTH-UNAVAILABLE` | Even the control band (`preventsCapture=false`) did not paint, so this image cannot show the display at all. | Use the photograph instead. If the photograph also fails, the run is void. |

`PREVENTSCAPTURE-USABLE` with the protected bands reading **black** is the strongest possible
outcome: it means the OS renders the content on screen and returns black to the capture, which is
exactly the "protected region comes out black" bar the package promises.

### 5.2 `matrix` — the per-cell verdicts

```sh
python3 Research/Scripts/analyze_capture.py <artifact-dir>/app-documents/capture-app-render-drawHierarchy.png
```

Expect the **controls to hold**, exactly as on Simulator — if they do not, the run is void:

- Band 1 (plain colour) must read `LEAKED(visible)`.
- Band 6 (swap DISABLED) must read `LEAKED(visible)`.
- Band 7 (plain field) must read `TEXT-LEAKED`.

Then read the cells:

- **Band 2 (`preventsCapture=true`)** — the headline unknown. If it reads `NO-LEAK(black)`, and
  `renderSanity` said `PREVENTSCAPTURE-USABLE`, the public API protects arbitrary content in the
  screenshot-like path. If it reads sentinel again, `preventsCapture` does not render on device
  either.
- **Band 8 (protected + black shield)** — only meaningful *given* `renderSanity` = USABLE. On its own
  it cannot distinguish "protection worked" from "the layer never painted".
- **Path B (`RPScreenRecorder`)** — the first real recording-path data this project will have. If
  frames arrive, `capture-system-capture-RPScreenRecorder.png` is written and the script analyses it
  automatically; the same band table then applies to it. If it still reports zero callbacks, record
  that verbatim, including whether a consent prompt appeared. Either outcome is a result.

### 5.3 `feasibility` — fidelity and cost

`feasibility` measures whether arbitrary content survives the `CMSampleBuffer` pipeline, and at what
cost. On Simulator the unprotected reference gave `meanAbsChannelError=3.77/255`, `~4–7 ms`
enqueue, `~4–7 ms` CPU/frame. On a device expect different absolute numbers; what matters is whether
the protected half *renders* at all, which is again `renderSanity`'s question.

### 5.4 Cross-check with the photograph

If `DISPLAY-ground-truth.png` and `DISPLAY-photograph.png` disagree about whether a protected band
painted, **trust the photograph**. The device screenshot is a capture path; the camera is not.

---

## 6. Recording the result

When the run is done, record for each cell: the **device model**, the **iOS build**, the **date**, and
the artifact directory. A device result is only meaningful with that provenance attached.

Do **not** edit `docs/evidence/capability-matrix.md` from inside this procedure: that file is owned by
the measurement task, and its verdicts must be updated deliberately, cell by cell, with the artifacts
cited. Hand the artifacts and the provenance over rather than rewriting the table ad hoc.

---

## 7. Honesty statement

- This procedure has **not been executed**. No physical device was attached; `xcrun devicectl list
  devices` reported all 7 known devices as `reality: simulated`.
- Every device-related number in this document is either a **precondition**, an **expected wall-clock
  estimate**, or a **description of how to interpret a future result**. None is a measurement.
- The script's own failure paths **were** exercised without a device, using a stubbed `devicectl`:
  missing `--device` (exit 2), a Simulator named as the device (exit 3, refused, no fallback), an
  unknown device name (exit 3), unpaired device (exit 3), no signing identity (exit 4), missing
  `--team` (exit 4), and build-failure diagnostics (exit 4). The device-present path cannot be
  exercised without hardware, and that is exactly the gap this procedure closes.
- `interpret_render_sanity.py` **was** validated on all three outcome branches using synthetic
  fixtures plus the real Simulator artifact (which correctly yields
  `PREVENTSCAPTURE-NOT-USABLE`).
