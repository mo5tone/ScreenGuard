# ScreenGuardDemo — the example app

A real iOS app target that consumes **ScreenGuard as a local package dependency by relative path**
(`../..`), exactly the way an outside app would. Nothing in `Sources/` is compiled into the app
target: the only link between the two is the package reference in `project.yml`. If the package
were not drop-in usable, this example would not build — which is the point of it existing.

> The repository's own top-level `README.md` is owned by a different task. This file covers the
> example app and its verification script only.

---

## 1. Build and run it

`swift build` / `swift test` **do not work** for this iOS-only package — they resolve the macOS SDK
and fail with `unable to resolve module dependency: 'UIKit'` (`docs/TOOLING.md` §1). Use
`xcodebuild`:

```sh
# build
xcodebuild build -project Examples/ScreenGuardDemo/ScreenGuardDemo.xcodeproj \
  -scheme ScreenGuardDemo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  -derivedDataPath .build/demo-dd

# install and launch the interactive demo
xcrun simctl boot 'iPhone 17 Pro' 2>/dev/null || true
xcrun simctl install booted \
  .build/demo-dd/Build/Products/Debug-iphonesimulator/ScreenGuardDemo.app
xcrun simctl launch booted com.screenguard.demo
```

The project is generated from `project.yml` by [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
cd Examples/ScreenGuardDemo && xcodegen generate
```

> ⚠️ **After a fresh clone, regenerate the project.** The repository's root `.gitignore` carries a
> `*.xcodeproj` rule, so `ScreenGuardDemo.xcodeproj` is **not** committed and a new checkout contains
> only `project.yml`. Run `xcodegen generate` in this directory (one line, `brew install xcodegen`)
> before using the `xcodebuild` command above. `Scripts/verify_capture.sh` does this for you
> automatically when the project is missing, if XcodeGen is installed.

### One command for the whole verification

```sh
Scripts/verify_capture.sh
```

It builds the example, installs it, drives five scripted probe pages, samples the PNGs the app
writes, and prints an explicit `PASS` / `FAIL` / `DEVICE` / `SKIP` / `FINDING` verdict per check.
Exit code `0` = every Simulator-checkable assertion passed, `1` = at least one failed, `2` = the run
could not be completed. Artifacts land in `.build/verify-capture/<run-id>/`.

The graded sections are: 1 build (the drop-in proof) · 2 the capability registry · 3 no-leak ·
4 watermark · 5 detection · 6 app-switcher · 7 recording (device-only).

---

## 2. What the app shows

The interactive demo has one section per capability from `docs/api-contract.md` §3, plus the
package's own capability-status table (§4) read from the runtime registry rather than transcribed:

| Section | What it demonstrates | Honest status |
|---|---|---|
| 1. Detection | Live `monitor.state`: `isMonitoring`, `captureState`, `detectionSource`, `lastScreenshotAt`, last event | API public; **end-to-end event delivery is device-pending** — a Simulator cannot fire a real screenshot |
| 2. No-leak shield | A secret card inside a `ScreenGuardShieldView` on both the public and the opt-in private path, over a magenta sentinel | Public path **device-pending**; private path **measured** but private API |
| 3. Forensic watermark | `.screenGuardWatermarked(...)` — a tiled, rotated, timestamped overlay | **Not a security control.** It removes no pixels and stops nothing |
| 4. App-switcher cover | The cover installed on the window while the scene is inactive | **Device-pending** — snapshot pixels are not decodable on Simulator |
| Status table | `ScreenGuard.capabilityStatuses`, the ten rows of §4 | The source of truth for every claim in this repo |

Every enum is rendered through its `.rawValue`. `Text("\(someEnum)")` is a **deprecation error** at an
iOS 15 deployment target (`docs/api-contract.md` §6.9, `docs/TOOLING.md` §6.4).

### What the app does *not* claim

`iOS does not allow an app to prevent a screenshot or a recording.` The demo says so on screen, and
the package's registry reports both prevention capabilities as `notPossible`. ScreenGuard **detects**
captures and keeps sensitive content **out of** them; it never blocks the user's action, and no
wording in the app or the script implies otherwise.

---

## 3. The no-leak page, and how to read it

`Scripts/verify_capture.sh` drives a scripted probe page (`-ProbeMode noLeak`) with three horizontal
regions over one sentinel background, and grades the pixels. The same three regions are what a human
sees in the interactive demo.

| Region | What it is | What a correct result looks like |
|---|---|---|
| `control` | The secret card with **no protection** | Reads the secret's own colour. This is the calibration: if this region does not image, no other reading means anything |
| `publicShield` | `AVSampleBufferDisplayLayer.preventsCapture = true` over an opaque black shield | **DEVICE-REQUIRED on Simulator** — see below |
| `privateShield` | The opt-in private secure-layer swap | The region is **excluded** from the app-side read while still **visible on the display** |

The read that counts is the app's own `window.drawHierarchy(in:afterScreenUpdates:false)` — the
app-side, screenshot-like path that goes through the render server and reproduced the documented
secure-field behaviour (`docs/evidence/capability-matrix.md` §5). `afterScreenUpdates` must stay
`false`; `true` is a `SIGABRT` (`docs/TOOLING.md` §5).

**A black region is ambiguous**, so the two readings are always read together:

| App-side render | Display (host contrast) | Meaning |
|---|---|---|
| blank / sentinel | **content visible** | genuine capture exclusion — the good outcome |
| blank / black | blank | the region never painted; **no protection can be concluded** |
| content colour | content visible | **leaked** |

The host-side display capture is taken with `xcrun simctl io screenshot`. It is
**`CONTRAST(host-side-bypass)` and is never evidence**: it reads the display surface from the host and
bypasses render-server capture protection by construction (`docs/TOOLING.md` §2). It exists for one
purpose only — telling "excluded from the capture" apart from "never painted" — and the script never
lets it produce a no-leak PASS.

### The watermark page, and why its check is the opposite of the shield's

`-ProbeMode watermark` renders two **matched** bands of the same flat colour: one wearing the tiled
mark, one without it. A watermark is a **deterrent and forensic** measure, so the honest expectation
is the reverse of the shield's:

| Band | Correct result | What it rules out |
|---|---|---|
| `watermarkMarked` | **not flat** — the mark really is drawn into the capture | a watermark that silently draws nothing |
| `watermarkControl` | **flat** — the identical band with no mark | "the marked band is not flat" being just read-path noise |

The page also emits its tile geometry (bounds, tile pitch, every tile origin), and the script checks
independently that the tiles **cover the whole view** — a tiling that leaves part of the view bare is
a real defect that a unit test on a rectangular bounds can miss.

**This is not a no-leak check and it is never reported as one.** The script prints that explicitly:
a watermark removes no pixels from any capture (`docs/api-contract.md` §3.3).

---

## 4. What the Simulator **cannot** validate

These are printed as `DEVICE` by `Scripts/verify_capture.sh` and are **never** reported as a pass.
Each one needs a physical device, and the script prints the exact commands with
`Scripts/verify_capture.sh --print-device-command`.

| Check | Why the Simulator cannot answer it |
|---|---|
| A **real screenshot event** (side + volume-up) | sim-use exposes no volume button and there is no key-combo path, so `UIApplication.userDidTakeScreenshotNotification` cannot be fired by the system (`docs/TOOLING.md` §2). The script checks observer **wiring** with a deliberately synthetic post, labelled `WIRING-ONLY`, and reports the real event as device-required |
| **No-leak on the recording / mirroring / AirPlay path**, by any technique | `RPScreenRecorder.startCapture` reports `isAvailable = true` and fires its completion with no error, then delivers **zero callbacks in 30 s**. `UIScreen.isCaptured` stays `false` (`docs/TOOLING.md` §7.3) |
| The **public** `preventsCapture` layer's capture behaviour | With `preventsCapture = true` the layer paints **nothing at all, on screen included**, while `rendererStatus = rendering` and a frame is enqueued (`docs/TOOLING.md` §7.1). "Absent from the capture" and "absent from the screen" are therefore indistinguishable: a black reading here is **unearned** |
| The **app-switcher snapshot's pixels** | The system writes them to `data/Library/SplashBoard/Snapshots/**/*.ktx`, Apple's proprietary `AAPL`-magic KTX variant, which neither ImageMagick nor ffmpeg can decode (`docs/TOOLING.md` §4) |
| **Preventing** a screenshot or a recording | `notPossible` — iOS does not permit it. On any device |

What the Simulator *does* check on the app-switcher capability is the cover's **installation** and its
**synchrony**: a deferred cover is a defect (`docs/api-contract.md` §6.7), and the probe asserts the
cover is already engaged inside the `UIScene.willDeactivateNotification` handler.

---

## 5. The `PrivateAPI` trait — and why this example enables it

`project.yml` declares the local package with the consumer-side trait:

```yaml
packages:
  ScreenGuard:
    path: ../..
    traits: ["PrivateAPI"]
```

This is the exact one-line consumer opt-in from `docs/api-contract.md` §9.4 / §13 A1, and the example
is a live proof that it is consumer-actionable with no fork and no change to the package. The trait
gates the private secure-layer code at **compile** time (`ScreenGuard.PrivateAPI.isCompiledIn`
reports whether it took effect).

**Why the example turns it on.** The private secure-layer swap is the only mechanism measured to keep
*arbitrary* content out of the app-side capture path while still painting it on the display
(`docs/evidence/capability-matrix.md` §3 rows 4 and 6). The public `preventsCapture` path cannot be
measured on a Simulator at all (§7.1 of `docs/TOOLING.md`). Without the trait, no Simulator-checkable
no-leak pixel outcome exists in this repository.

**What that costs.** The private UIKit class-name string is compiled into **this demo's** binary. That
is inherent to the trait — App Review exposure is a **compile-time** property, not a runtime flag
(`docs/api-contract.md` §9.3) — and it is exactly why the trait is **off by default** for real
consumers. Deleting the `traits:` line restores the default posture with no other change.

⚠️ The private path is a **private API**: opt-in, off by default, non-contract, fragile across iOS
releases, an App Review risk, and **never a security guarantee**. It must never be described as
secure, safe, recommended or production-ready (`docs/api-contract.md` §9.5).

---

## 6. Device run

```sh
Scripts/verify_capture.sh --print-device-command
```

prints the exact `xcodebuild` / `devicectl` sequence, including the four checks above and how to pull
the app's artifacts back off the device.

---

## 7. Layout

```
Examples/ScreenGuardDemo/
├── project.yml                     XcodeGen spec — the local package reference and the trait
├── ScreenGuardDemo.xcodeproj/      generated from project.yml
├── Support/Info.plist
└── Sources/
    ├── DemoApp.swift               entry point; picks the interactive demo or a probe page
    ├── Interactive/
    │   ├── DemoRootView.swift      the interactive demo — one section per capability
    │   └── DemoShieldRepresentable.swift  SwiftUI ↔ ScreenGuardShieldView seam
    ├── Probes/
    │   ├── DemoCapabilityProbeView.swift   dumps §4's registry to an artifact
    │   ├── DemoNoLeakProbeView.swift       the three-region no-leak page
    │   ├── DemoWatermarkProbeView.swift    the two matched watermark bands + tile geometry
    │   ├── DemoDetectionProbeView.swift    monitor state + observer wiring
    │   └── DemoAppSwitcherProbeView.swift  cover installation + deactivation synchrony
    └── Support/
        ├── DemoConfig.swift        launch-argument parsing (`-ProbeMode`, `-RunID`, `-PrivateOptIn`)
        ├── DemoGeometry.swift      the shared colours and normalised region rects
        ├── DemoEvidence.swift      the `drawHierarchy` read, sRGB normalisation, artifact writing
        ├── DemoShieldContainer.swift  the shield, engaged in the order the package requires
        ├── DemoSensitiveCard.swift the secret card
        └── DemoCapabilityListView.swift
```

The probe pages exist so the verification is automated and repeatable rather than "a human looked at
it", and because a headless pixel check needs an app-side read that a human cannot perform.
