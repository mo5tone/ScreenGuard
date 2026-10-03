# ScreenGuard — independent verification report (task t5)

**Verifier:** `verifier` (Independent Verifier) · **Attempt:** `e99ebb3b-378a-4721-9b53-01d58b618c84`
**Date:** 2026-10-02 · **Repository:** `/Users/jiefu/Developer/ScreenGuarantor` (repo root; `Package.swift` is at the root)
**Verified against:** `docs/api-contract.md` (§4 claim table, §7.2 availability, §9 private path, §13 A1) and
`docs/evidence/capability-matrix.md` (t1's measurements), with the rules of `docs/TOOLING.md`.
**Written by the verifier.** Nothing in this report was copied from an implementer's summary: every number
below is either a raw command output produced in this attempt or a pixel I decoded myself.

---

## 0. Verdict at a glance

| # | Acceptance criterion | Verdict | Where |
|---|---|---|---|
| 1 | Build + test re-run from a clean derived-data dir, raw command/exit/tail recorded | **PASSED** | §2, §4 |
| 2 | Each implementation acceptance criterion checked against artifacts on disk | **PASSED** | §3, §8, §9 |
| 3 | No-leak claim **tested by measurement** in a valid capture path (`drawHierarchy`) | **PASSED** for the private path; **NOT EARNED** (device-pending) for the public path — reported as such, not as a pass | §5 |
| 4 | iOS 15 build with no unguarded `UIScreen.isCaptured`; `@available(iOS 17.0, *)` on `sceneCaptureState` | **PASSED** (with one precision note) | §6 |
| 5 | Private secure-layer path OFF by default, reachable only via explicit opt-in | **PASSED** | §7 |
| 6 | Simulator-unverifiable capabilities listed as unverified, not passing | **PASSED** | §10 |
| 7 | Report records every command, exit code, per-criterion verdict, and a deliberate falsification attempt | **PASSED** | §2, §5.4, §11 |

**Overall: the package's contract claims are honest and the load-bearing no-leak claim is independently
reproduced — but two real package defects were found (one medium, fail-closed) and are reported for the
reviewer/implementer in §11. No leak was found in any measured path.**

The single most important sentence in this report: **on Simulator, the only no-leak claim that can be
earned is the opt-in private secure-layer path (arbitrary content) and the `isSecureTextEntry` primitive;
the package's default public `preventsCapture` path is correctly declared device-pending and its blank
Simulator reading must never be quoted as protection.**

---

## 1. Environment and method

```
Xcode 27.0 (27A266a) · iOS 27.0 SDK · iPhone 17 Pro Simulator, iOS 26.2
UDID DCF67420-9B92-463F-AE79-858C03C7AA38
Package consumed as a local path dependency (Examples/ScreenGuardDemo/project.yml: path: ../..)
```

Method, in order:

1. Read `docs/TOOLING.md`, `docs/api-contract.md` §0–§5, §7–§9, §13, and `docs/evidence/capability-matrix.md` in full.
2. Read the package source **without modifying it** and record what it actually does.
3. Delete `.build/verify-dd` and re-run the two verify commands from that clean directory.
4. Run the package's own end-to-end harness (`Scripts/verify_capture.sh`), then **re-derive every pixel
   verdict myself** from the raw PNGs with an independent decoder (Pillow) and an independent sampling grid —
   deliberately not the repository's `sample_regions.py`.
5. Re-run t1's research harness on my own derived-data path under `/tmp` and re-sample its raw PNGs myself.
6. Run one deliberate falsification run (protection withheld) and the built-in disabled controls.

**Evidence rules applied (from the task and `TOOLING.md` §2/§3):**

- A no-leak verdict is only read from `window.drawHierarchy(in:afterScreenUpdates:false)` (screenshot-like)
  or `RPScreenRecorder.startCapture` (recording). **No verdict in this report comes from a host-side capture.**
- `xcrun simctl io screenshot` / sim-use captures are used **only** as the discriminator between
  "excluded from the capture" and "never painted", and are labelled `CONTRAST(bypass)` throughout.
- A blank reading that could be produced by a non-rendering path is never counted as a pass. The
  mandatory unshielded control region (same content, same read path) must leak, and does.
- `drawHierarchy` and `CALayer.render(in:)` are reported per-path; they are never averaged or generalised.

---

## 2. Command log — raw command, exit code, output tail

All commands run from the repo root. Derived data for the package is `.build/verify-dd`, deleted before
the build so the tree was genuinely cold.

| # | Command | Exit | Output tail |
|---|---|---|---|
| C1 | `rm -rf .build/verify-dd` then `xcodebuild build -scheme ScreenGuard -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -derivedDataPath .build/verify-dd` | **0** | `** BUILD SUCCEEDED **` — `-target arm64-apple-ios15.0-simulator`, `-swift-version 5`, **0** `warning:` lines |
| C2 | `xcodebuild test -scheme ScreenGuard -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -derivedDataPath .build/verify-dd` | **0** | `Executed 105 tests, with 6 tests skipped and 0 failures (0 unexpected) in 0.191 (0.220) seconds` · `** TEST SUCCEEDED **` |
| C3 | `bash -n Scripts/verify_capture.sh` | **0** | (no output — syntax clean) |
| C4 | `Scripts/verify_capture.sh` | **0** | `PASS 21 · FAIL 0 · FINDING 1 · SKIP 0 · DEVICE 4` → `RESULT: PASSED` |
| C5 | `Scripts/verify_capture.sh --skip-build --no-private-opt-in --run-id t5-falsify-optout` (deliberate falsification) | **0** | private region reads `38,102,242` = **LEAKED** (protection withheld) |
| C6 | `xcodebuild build -project Research/CaptureMatrix/... -derivedDataPath /tmp/t5-cm-dd` then `-Mode matrix` | **0** | t1's matrix numbers reproduced exactly (§5.3) |
| C7 | same harness `-Mode replayKit` | **0** | `RK startCapture result: NO FRAME in 30s (callbacks=0 video=0 audioApp=0 audioMic=0 …)` |
| C8 | same harness `-Mode renderSanity` + host display screenshot | **0** | cases A/B show sentinel on screen; case C paints (§5.2) |

### 2.1 Test skips (C2) — all 6 have explicit reasons, none silent

```
5 x  Test skipped - DEVICE-REQUIRED: not measurable on Simulator — see docs/TOOLING.md §7 and
      docs/evidence/capability-matrix.md §4/§7. Run on a physical device.
1 x  Test skipped - SCENE-REQUIRED: exercising the drawHierarchy branch needs a window attached to a
      UIWindowScene, and a unit-test host has no connected scene.
```

The only `warning:` in the C2 log is the toolchain's
`appintentsmetadataprocessor: Metadata extraction skipped, no AppIntents.framework dependency found` —
not a source diagnostic.

---

## 3. What was checked against the artifacts on disk (criterion 2)

| Claim under test | Artifact inspected | Result |
|---|---|---|
| `swift-tools-version: 6.1` (traits require it, §13 A1) | `Package.swift:1` | ✅ |
| `platforms: [.iOS(.v15)]`, one library product, `dependencies: []` | `Package.swift:31-43, 69` | ✅ |
| `PrivateAPI` trait present and **not** in `default(enabledTraits:)` | `Package.swift:61-67` = `.default(enabledTraits: [])` | ✅ |
| `.swiftLanguageMode(.v5)` pinned on **both** targets | `Package.swift:78` (library) and `:90` (test) | ✅ |
| `products:` precedes `traits:` (parse-order trap) | `Package.swift:36` before `:61`; manifest parses (C1, C2) | ✅ |
| 105 tests / 6 skips / 0 failures | C2 raw log | ✅ (but the "22 source files" claim is off by one — see F3) |
| Zero networking | `grep -rniE 'URLSession|URLRequest|CFNetwork|NWConnection|NSURLConnection|import Network|http://|https://' Sources/` → **no matches** (exit 1) | ✅ |
| Imports are system frameworks only | `UIKit`, `SwiftUI`, `Foundation`, `Combine`, `CoreGraphics`, `AVFoundation` | ✅ |
| Capability registry returns §4 exactly, in order | `Sources/ScreenGuard/ScreenGuard.swift:58-165` (10 cases) and the app's runtime artifact `capability-*.json` | ✅ (10/10 statuses match §4) |
| SwiftUI ergonomics exist (`.screenGuardProtected` / `Watermarked` / `AppSwitcherProtected`) | `Sources/ScreenGuard/SwiftUI/ScreenGuardModifiers.swift:38, 151, 189` | ✅ |
| UIKit wrappers exist (`ScreenGuardShieldView`, `ScreenGuardAppSwitcherShield`, watermark view) | `Sources/ScreenGuard/Shield/`, `AppSwitcher/`, `Watermark/` | ✅ |
| Default no-leak strategy is the public one | `ScreenGuardConfiguration.swift:46` and `ShieldView:188` = `.publicPreventsCaptureLayer` | ✅ |
| Trade-off stated, not hidden: public path is a refreshed rasterisation, private path is live | `ScreenGuardShieldView.swift:20-24` | ✅ |
| t3's five claimed defect fixes | `ScreenGuardObserverTokenStore.swift` used by monitor/observer/app-switcher; off-thread `deinit` regression tests at `ScreenGuardMonitorTests.swift:81, 100` | ✅ present |
| §4 status vocabulary is exposed at runtime (`ScreenGuardVerificationStatus`) | `ScreenGuardCapability.swift`; runtime artifact lists `devicePending/measured/notMeasured/notPossible` | ✅ |

### 3.1 Runtime capability table, read from the demo's own artifact (not from source)

```
screenshotDetection            -> devicePending      noLeakRecordingPath            -> notMeasured
captureStateDetection          -> devicePending      watermark                      -> notMeasured
noLeakSecureTextEntry          -> measured           appSwitcherSnapshotProtection  -> devicePending
noLeakPublicPreventsCapture    -> devicePending      preventUserScreenshot          -> notPossible
noLeakPrivateSecureLayer       -> measured           preventUserRecording           -> notPossible
count = 10
```

This matches `docs/api-contract.md` §4 row-for-row, **including** the two `notPossible` refusals and
`noLeakRecordingPath = notMeasured`. The package does not claim to prevent anything.

---

## 4. Clean-room build and test (criterion 1)

`swift build`/`swift test` are unusable for this iOS-only package (`TOOLING.md` §1) and were not used.
`xcodebuild` with an explicit Simulator destination was used, from a **deleted** derived-data directory.

**C1 tail:**

```
SwiftDriverJobDiscovery normal arm64 Compiling ScreenGuardSecureTextField.swift, ScreenGuardShieldView.swift (in target 'ScreenGuard' from project 'ScreenGuard')
Ld /Users/jiefu/Developer/ScreenGuarantor/.build/verify-dd/Build/Products/Debug-iphonesimulator/ScreenGuard.o normal (in target 'ScreenGuard' from project 'ScreenGuard')
** BUILD SUCCEEDED **
```

Compiler flags observed in the raw log — this is the evidence for the deployment floor and the language mode:

```
4 x  -target arm64-apple-ios15.0-simulator
3 x  -swift-version 5
0 x  warning:
```

**C2 tail:**

```
Test Suite 'All tests' passed at 2026-10-02 21:20:09.372.
	 Executed 105 tests, with 6 tests skipped and 0 failures (0 unexpected) in 0.191 (0.223) seconds
** TEST SUCCEEDED **
```

This independently reproduces t3's and t9's reported outcome (105 / 6 skipped / 0 failures), **and** the
`.v5` pin is confirmed to be doing its job: the same source under the tools-version-6.1 default (Swift 6
language mode) is the documented failure mode (`TOOLING.md` §6.7), and it does not occur here.

---

## 5. The no-leak claim: measured, not assumed (criterion 3 — the load-bearing section)

### 5.1 The package's own harness, re-run and re-sampled by me

`Scripts/verify_capture.sh` runs the demo app in a **real scene**, where `drawHierarchy` actually renders
(a unit-test host cannot — the package's own test at `ScreenGuardRasterizerTests.swift:76` pins that
`drawHierarchy` returns `(0,0,0)` there; that is exactly the vacuous-reading trap and it is why this
verification uses the app harness, not the test bundle).

I did **not** trust the script's sample numbers. I decoded `capture-app-render-final.png` and
`CONTRAST-host-side-display.png` myself with Pillow (a different decoder from the repo's stdlib sampler)
and an 11×11 grid over each region's own `bodyRect` from the app's JSON:

| Region | `drawHierarchy` read (the only valid path) | Host contrast (bypass — **not evidence**) | Reading |
|---|---|---|---|
| `control` (unshielded, same content) | mean `(41,104,242)`, median `(38,102,242)`, dominant `(38,102,242)` ×116/121 → **SENSITIVE** | `(42,105,242)` → SENSITIVE | **The control leaks, as it must.** This is what makes the other rows mean anything. |
| `publicShield` (`preventsCapture` + black shield) | `(0,0,0)` ×121/121 → BLACK | `(0,0,0)` ×121/121 → **BLACK on the display too** | **UNEARNED.** The layer paints nothing anywhere. Reported device-pending, **not** a pass. |
| `privateShield` (opt-in private swap) | mean `(200,0,160)`, median `(200,0,160)`, dominant `(200,0,160)` ×121/121 → **SENTINEL (excluded)** | `(38,102,242)` ×121/121 → **content IS on the display** | **NO-LEAK, unconfounded.** The pixels exist and are excluded only from the render-server-backed read. |

Raw app-side readings (from the app's own JSON artifact, verified by my re-sampling):

```
readPath: window.drawHierarchy(in:afterScreenUpdates:false)
control       mean=40.49,103.75,242.15  median=38,102,242   maxChannel=253  samples=1024 -> SENSITIVE
publicShield  mean=0,0,0                median=0,0,0        maxChannel=0    samples=1024 -> BLACK
privateShield mean=200,0,160            median=200,0,160    maxChannel=200  samples=1024 -> SENTINEL
```

**Conclusion for the private path:** protected arbitrary content comes out **blank (sentinel) in the
screenshot-like capture path**, while the same content is **visible on the display** — a genuine
capture-specific exclusion. This is the same asymmetry argument `capability-matrix.md` §4 uses, and it is
reproduced here from pixels I sampled myself.

### 5.2 Simulator confound re-measured (why the public path is NOT a pass)

`renderSanity` re-run by me, display sampled by my own script:

```
case A preventsCapture=true  (set AFTER add)   expect 229,25,25  -> dominant (200,0,160)  NOT-PAINTED(sentinel)
case B preventsCapture=true  (set BEFORE add)  expect 38,191,64  -> dominant (200,0,160)  NOT-PAINTED(sentinel)
case C preventsCapture=false (control)         expect 242,216,25 -> dominant (242,216,25) PAINTED
```

All three layers reported `enqueued=1 rendererStatus=rendering layerFrames=402x291@0,0`. On Simulator,
`preventsCapture = true` makes the layer contribute **no pixels to the display at all**, so "absent from
the capture" and "absent from the screen" are indistinguishable. Row 8's `NO-LEAK(black)` is therefore
**unearned** and this report does not quote it as protection. `capability-matrix.md` §4 is confirmed.

### 5.3 t1's matrix harness, re-run by me (the "same harness approach" the criterion names)

I rebuilt and ran `Research/CaptureMatrix` myself (derived data in `/tmp`, artifacts copied to `/tmp`, no
repository file touched) and re-sampled its raw PNGs with my own band sampler. The numbers reproduce t1's
matrix **exactly**:

| Band | Path A — `drawHierarchy` (valid) | Path A′ — `layer.render` (different, more permissive read) | Host contrast (bypass) |
|---|---|---|---|
| 0 plain colour (control) | LEAKED `(229,25,25)` Δ0.0 | LEAKED Δ0.0 | CONTENT-VISIBLE |
| 1 `AVSBDL` capture=ON | SENTINEL `(200,0,160)` — **confounded** | SENTINEL | **SENTINEL (paints nothing on screen)** |
| 2 `AVSBDL` capture=OFF | LEAKED `(242,216,25)` Δ0.0 | SENTINEL ⚠️ disagrees | CONTENT-VISIBLE |
| 3 secure-layer swap (**private**) | **SENTINEL** `(200,0,160)` → excluded | LEAKED `(38,102,242)` ⚠️ disagrees | **CONTENT-VISIBLE `(38,102,242)`** |
| 4 secure `UITextField` | **TEXT-BLANKED `0/1068` (0.00%)** | TEXT-LEAKED `184/1068` (17.23%) ⚠️ | text strip not sampled by my band sampler (see note) |
| 5 swap **DISABLED** (control) | **LEAKED `(38,102,242)`** | LEAKED Δ0.0 | CONTENT-VISIBLE |
| 6 plain `UITextField` (calibration) | **TEXT-LEAKED `205/1068` (19.19%)** | TEXT-LEAKED `184/1068` | text strip not sampled (note) |
| 7 `AVSBDL` + black shield | NO-LEAK(black) — **unearned** | NO-LEAK(black) | BLACK |

Reading the controls (all of them are load-bearing):

- **Band 0 leaks on every path** → the harness itself works.
- **Band 6 (plain field) images text, `205/1068`** → band 4's `TEXT-BLANKED 0/1068` is protection, not a
  path that cannot resolve glyphs. This independently reproduces capability 3's measured public primitive
  (`isSecureTextEntry`), which is the one result that is public + measured + unconfounded.
- **Band 5 (swap disabled) leaks** on both app-side reads and paints on the display → band 3's blank is
  protection, not a broken view.
- **Band 3 blanks in `drawHierarchy` while painting on the display** → the private swap is the only
  measured mechanism that excludes *arbitrary* content.
- Bands 2/3/4 disagreements between the two app-side reads reproduce `capability-matrix.md` §5 and are
  reported **per path**; nothing is averaged. `drawHierarchy` is the faithful proxy.
- My contrast sampler's colour rect sits outside the narrow text fields, so bands 4/6 are uninformative in
  the host column; I do not draw a conclusion from them. (The matrix's own text-strip sampling is where
  the `TEXT-*` numbers come from, and I reproduced those in the app-side columns.)

### 5.4 Deliberate falsification attempts and their results

| # | Falsification | What would prove the no-leak claim false | Result |
|---|---|---|---|
| F-a | **Protection withheld, same region, same read path.** Ran `Scripts/verify_capture.sh --skip-build --no-private-opt-in --run-id t5-falsify-optout` and sampled the PNGs myself. | The protected region reads the content colour. | The same region reads **`38,102,242` ×121/121 = LEAKED**. With protection granted it reads **`(200,0,160)` ×121/121 = excluded**. The check has discriminating power and would fail if the claim were untrue. |
| F-b | **Swap-disabled control band** in t1's harness (band 5) through the valid path. | Band 5 is blank too (i.e. the "protection" is just a broken view). | Band 5 reads `(38,102,242)` LEAKED on both app-side paths → band 3's blank is protection. |
| F-c | **Unshielded control region** in the demo, same content, same `drawHierarchy` read. | Control reads blank/BLACK (i.e. the read path cannot image anything). | Control reads `(38,102,242)` SENSITIVE → the read path images content, so the protected blanks are meaningful. |
| F-d | **Calibration band** (plain field vs secure field), t1 harness. | The text strip reads blank for the plain field too. | Plain field `205/1068` TEXT-LEAKED vs secure field `0/1068` TEXT-BLANKED → glyphs *are* imageable. |

All four controls came out on the "the claim could be false" side **before** the protected readings were
credited. No vacuous pass was accepted: every blank reading reported here is accompanied by a readable,
non-blank control on the same image.

### 5.5 What is NOT earned

- **Public `preventsCapture` path:** blank reading exists, but the same flag makes the layer paint nothing
  on the display (`§5.2`), so it is **not** a verified no-leak result. **Unverified on Simulator.**
- **Recording path:** no frames at all (§10). **Unverified on Simulator.**

---

## 6. Availability verification (criterion 4)

**The `@available(iOS 17.0, *)` guard on `sceneCaptureState` is present and enclosing.**
`Sources/ScreenGuard/Detection/ScreenGuardCaptureStateObserver.swift`:

```
:87   if #available(iOS 17.0, *) {            // .view host
:96       ... environment.traitCollection.sceneCaptureState
:104      publish(view.traitCollection.sceneCaptureState)
:110  if #available(iOS 17.0, *) {            // .windowScene host
:115      ... environment.traitCollection.sceneCaptureState
:123      publish(scene.traitCollection.sceneCaptureState)
:155  if #available(iOS 17.0, *), let reg = registration as? any UITraitChangeRegistration {
:220  @available(iOS 17.0, *)
:221  private func publish(_ state: UISceneCaptureState)     // the only type that touches the 17.0 enum
```

Every use of an iOS-17-only symbol (`UITraitSceneCaptureState`, `registerForTraitChanges`,
`UITraitChangeRegistration`, `UISceneCaptureState`, `sampleBufferRenderer`) is inside a guard. The
mechanical proof is C1: an **unguarded** use of an iOS 17.0 symbol at an iOS 15.0 deployment target is a
hard compile error (`'…' is only available in iOS 17.0 or newer`), and the build succeeded with 0 warnings
at `arm64-apple-ios15.0-simulator`.

**`UIScreen.isCaptured` — precise reading.** There is **no availability-illegal use**:
`isCaptured` is iOS 11.0+, i.e. available at the iOS 15 floor, so it needs no guard, and it compiles with
zero diagnostics (`TOOLING.md` §6.2 — soft `API_TO_BE_DEPRECATED`). Every use is on the legacy path:

```
:106  startLegacy(screen: view.window?.windowScene?.screen)      <- else branch of #available(iOS 17.0,*)
:125  startLegacy(screen: scene.screen)                          <- else branch
:175  publishLegacy(screen.isCaptured)
:188  publishLegacy(resolved.isCaptured)
:207  publishLegacy(screen?.isCaptured ?? false)
```

`startLegacy` is `private` with exactly those two call sites, both in the iOS-17 `else` branch, so on iOS 17+
the legacy observer is never installed and never reads `isCaptured`. **Precision note:** the two `isCaptured`
reads are not *lexically* wrapped in an `if #available` block — they are guarded by call-site reachability
instead. For an iOS 11.0 symbol that is correct and warning-free, but it is weaker than a lexical guard and
is recorded as an observation in §12 rather than a defect.

`UIScreen.main` (hard-deprecated iOS 26.0, `TOOLING.md` §6.1) is **not used**: the three grep hits are a
comment, a doc string, and a comment (`ScreenGuardMonitor.swift:164`, `ScreenGuard.swift:78`,
`ScreenGuardCaptureStateObserver.swift:17`). The screen is always resolved from
`view.window?.windowScene?.screen`.

---

## 7. Private-API gating (criterion 5)

Three independent lines of evidence, all reproduced in this attempt:

1. **Manifest.** `Package.swift:61-67` declares the trait and `.default(enabledTraits: [])` — the trait is
   not enabled by default. `Package.swift:80` is the **only** thing that defines `SCREENGUARD_PRIVATE_API`
   (`.define(…, .when(traits: ["PrivateAPI"]))`).
2. **Two explicit runtime acts are required.** `ScreenGuard.PrivateAPI.isEnabled` defaults to `false`
   (`ScreenGuardPrivateSecureLayerSupport.swift:69`), and `ScreenGuardPrivateSecureLayer.engage` refuses
   with `.privateSecureLayerUnavailable` when it is not set (`ScreenGuardPrivateSecureLayer.swift:106-111`).
   The default strategy is `.publicPreventsCaptureLayer` (§3). Unit tests assert the default-off property,
   that naming the strategy alone does not protect, and that the refusal is reported through the callback
   seam — all passing in C2.
3. **Pixel-level, end to end (F-a).** With the opt-in withheld, the same region on the same read path reads
   `(38,102,242)` = **LEAKED**; with it granted, `(200,0,160)` = **excluded**. The opt-in is what changes
   the pixels, and its absence leaks rather than silently appearing protected.

**Trait gating measured in both directions** (my own `grep -a` on the build products, default build from a
clean derived-data directory):

| Build | Artifact | `_UITextLayoutCanvasView` occurrences |
|---|---|---|
| **Trait absent** (default, `.build/verify-dd`) | `Products/…/ScreenGuard.o` | **0** |
| **Trait absent** | `Products/…/ScreenGuard.swiftmodule/*.swiftmodule` | **0** |
| **Trait absent** | `Products/…/ScreenGuard.swiftmodule/*.swiftdoc` | **6** — see finding **F2** |
| **Trait enabled** (demo, `.build/demo-dd`) | `Products/…/ScreenGuard.o` | **1** |
| **Trait enabled** | `ScreenGuardDemo.app/ScreenGuardDemo.debug.dylib` | **1** |
| **Trait enabled** | any file under `Products/` | **4 files** |

Direction confirmed: the private class name is absent from the **compiled code** of the default build and
present when the trait is enabled. The reverse control (present-when-enabled) proves the search has
discriminating power.

---

## 8. Example app and scripts (criterion 2, continued)

- `bash -n Scripts/verify_capture.sh` → exit 0 (C3).
- `Scripts/verify_capture.sh` → exit 0; **PASS 21 · FAIL 0 · FINDING 1 · SKIP 0 · DEVICE 4**; reproduced t4's
  reported result exactly, from a fresh run of my own (C4).
- The demo consumes the package as an **external local path dependency** with its own
  `traits: ["PrivateAPI"]` line (`Examples/ScreenGuardDemo/project.yml:57-58`,
  `project.pbxproj` `XCLocalSwiftPackageReference … traits = (PrivateAPI,)`) — i.e. the trait mechanism is
  exercised from a *consumer* manifest, which is the point of §13 A1.
- Demo build produced **0** `warning:` lines.
- The script's honesty design was read and independently judged sound: host-side capture is labelled
  `CONTRAST(host-side-bypass)` and can never produce a no-leak PASS; the `UNREADABLE` outcome is graded as a
  failure, never as a pass; and the device-required checks are printed as `DEVICE`, never as PASS.

---

## 9. Contract §4 claim-by-claim

| §4 row | Contract status | Verified how | Verdict |
|---|---|---|---|
| 1 screenshot detection | device-pending | registry artifact + no volume button on Simulator (`TOOLING.md` §2); wiring proven only synthetically, and the app says so (`syntheticPostIsARealScreenshot: false`) | **honest, unverified on Simulator** |
| 2 capture-state detection | device-pending | registry artifact; the demo *did* receive a real `sceneCaptureState` signal (`inactive`) through the iOS 17 trait path | **honest**; end-to-end capture *change* not triggerable on Simulator |
| 3 no-leak `isSecureTextEntry` | measured | C6 band 4 `0/1068` vs band 6 calibration `205/1068`; package refuses `isSecureTextEntry = false` (unit test, C2) | **confirmed** (scope: the field's own text') |
| 4 no-leak public `preventsCapture` | device-pending | C8: the layer paints nothing anywhere on Simulator | **honest; NOT a pass** |
| 5 no-leak private secure-layer | measured, opt-in | C4 + my resample (sentinel in `drawHierarchy`, content on display); C6 band 3 + band 5 control | **confirmed** (private, non-contract) |
| 6 no-leak recording path | notMeasured | C7: 0 callbacks in 30 s | **honest; no verdict claimed** |
| 7 watermark | notMeasured, not a security control | C4: marked band deviates `0.198` while the unmarked control is flat (`0`) → the mark is drawn *into* the capture and removes nothing; app artifact `isASecurityControl=false` | **honest** |
| 8 app-switcher snapshot | device-pending | C4: cover installs and is already covering *inside* the `willDeactivate` handler; snapshot pixels not decodable (KTX) | **honest; device-pending** |
| 9/10 prevent screenshot/recording | notPossible | registry artifact | **honest** |

---

## 10. Unverified on Simulator — listed, with the specific reason (criterion 6)

These are **not** reported as passing anywhere above.

| Capability | Status here | Specific reason (measured or recorded) |
|---|---|---|
| No-leak on the **public** `preventsCapture` path | **UNVERIFIED — requires device** | Re-measured C8: with `preventsCapture = true` the layer paints **nothing at all**, on screen included, for both set-before-add and set-after-add, while `preventsCapture = false` paints correctly. A blank capture read cannot be distinguished from a never-painted region. |
| No-leak on the **recording / mirroring / AirPlay** path | **UNVERIFIED — requires device** | Re-measured C7: `isAvailable=true`, `startCapture` completion `error=none`, then `callbacks=0 video=0 audioApp=0 audioMic=0` in 30 s; `startRecording` reports `isRecording=true` with no frames; `capturedDidChange observations=0`, `finalIsCaptured=false`. No verdict of any kind is derivable. |
| A **real screenshot event** (side + volume-up) end to end | **UNVERIFIED — requires device** | `TOOLING.md` §2: the Simulator exposes no volume button and no key-combo/menu path, so `userDidTakeScreenshotNotification` cannot be fired. The demo proves *wiring* only, through a synthetic post, and labels it `syntheticPostIsARealScreenshot: false`. |
| **App-switcher snapshot pixels** | **UNVERIFIED — requires device** | `TOOLING.md` §4: snapshots are Apple's proprietary `AAPL`-magic KTX; ImageMagick and ffmpeg both refuse them. Only the *cover's* install timing is checkable, and it was. |
| Recording-path **fidelity / latency / dropped frames** | **not measured** | No in-process API exposes them; `capability-matrix.md` §6. |
| iOS-26-deployment-target zero-warning claim | **not re-verified by me** | My build was at the iOS 15 deployment target (which is what the verify command specifies). The iOS 26-target deprecation behaviour in §7.2 is t2's verified claim, not re-measured here. |
| Physical-device run of any kind | **not performed** | `xcrun devicectl list devices` shows no physical device attached in this environment. `docs/evidence/device-run-procedure.md` is the procedure that would fill the cells above. |

---

## 11. Findings (for the reviewer / implementer — I did not modify any source)

### F1 — `medium` — the private-path shield reports failure while its protection is actually engaged (state and pixels disagree)

**File:** `Sources/ScreenGuard/Shield/ScreenGuardShieldView.swift` (state machine, `apply`/`engage`) and
`Sources/ScreenGuard/Shield/ScreenGuardPrivateSecureLayer.swift` (`engage`/`disengage` restore path).

**Reproduced 2/2 read passes, and by both the script's sampler and my own:**

```
SHIELD privateShield | requested=privateSecureLayer effective=disabled
                       mode=detectionAndOverlayFallback isProtecting=false
                       protectionFailure=privateSecureLayerSwapFailed
SAMPLE app-render(drawHierarchy) | privateShield | medianRGB=200,0,160 -> SENTINEL  (excluded)
CONTRAST host-side display       | privateShield | medianRGB=38,102,242 -> SENSITIVE (visible on screen)
```

`ScreenGuardShieldMode.detectionAndOverlayFallback` is documented as "shows the content as a plain visual
overlay … removes **no pixels** from any capture" (`ScreenGuardShieldView.swift:63-68`). The measured pixels
contradict that: the region **is** excluded from the capture read while the same content is on the display.
The layer swap is therefore still in effect (or was re-applied and only the postcondition/teardown bookkeeping
failed) at the moment the shield reports `.privateSecureLayerSwapFailed`.

**Consequences (none is a leak — the direction is over-protection, hence fail-closed):**

1. A host that branches on `isProtecting` under-reports its own protection and raises a spurious
   `protectionDegraded` event (`api-contract.md` §9.2/§10 promise failure is *reported*, not invented).
2. The documented degradation contract is false in this state: the fallback is supposed to make the content
   visible in captures.
3. A later `apply(.disabled)` / `apply(.publicPreventsCaptureLayer)` may be leaving a stale canvas swap in
   place, because `teardown()` → `disengage()` evidently did not restore the layer in this path. That is the
   part with real functional risk and it is **not** covered by a test.

**Required fix:** make `engage`'s failure path fully restore the previous layer arrangement (and assert it),
or make `isProtecting`/`shieldMode` reflect the pixels when the swap is in effect; then add a regression test
that applies `.privateSecureLayer`, forces the failure path, and asserts **both** the reported state and the
measured pixels agree. The demo's own `FINDING` (C4) is this defect, and it is correctly graded as a finding
rather than a failed verification, because the property the package promises is "sensitive content does not
leak" and that still holds.

### F2 — `low` — "0 occurrences in build products" (t9 report, `api-contract.md` §9.4) is imprecise

Measured in this attempt:

| Trait absent — artifact | `_UITextLayoutCanvasView` |
|---|---|
| `ScreenGuard.o` (the compiled code) | **0** |
| `.swiftmodule` | **0** |
| `.swiftdoc` (generated documentation index) | **6** |

Three **always-compiled** files mention the literal in **doc comments**:
`ScreenGuardShieldView.swift:57`, `ScreenGuardNoLeakStrategy.swift:35`, and `ScreenGuardCapability.swift:49`.
These are comments, so no code references the class and the private lookup can never happen — the escape
hatch's *substantive* promise (the string is absent from the shipped binary, which is what App Review scans)
holds and I verified it. But a verifier who greps the whole **build-products directory** (or `strings` on the
`.swiftdoc`, which a consumer receiving a binary distribution could do) will see 6 occurrences and conclude
the claim is false.

**Required fix:** state the claim in the form that is actually true and measurable — "absent from the
compiled object/binary (`ScreenGuard.o`, the app binary)" — and either accept or remove the doc-comment
occurrences if a whole-directory grep is to be the acceptance check. Either way, correct the wording in
`docs/api-contract.md` §9.4 and `docs/TOOLING.md` §6.7, which both say "build products".

### F3 — `low` — implementation-to-contract drift in the module layout and file count

- t3's report says "22 files"; `find Sources -name '*.swift' | wc -l` = **21**.
- `api-contract.md` §1 lists 16 files; `Sources/` contains 21. Five files exist that §1 does not list:
  `ScreenGuardObserverTokenStore.swift`, `ScreenGuardEventMapper.swift`, `ScreenGuardContentRasterizer.swift`,
  `ScreenGuardNoLeakStrategy.swift`, `ScreenGuardPrivateSecureLayerSupport.swift`.

No functional impact — the extra files are internal and the contract's *behavioural* clauses are met — but
§1 is normative, and a verifier comparing the tree to §1 will see a mismatch.

**Required fix:** update §1's layout (or the task summary) to match the tree on disk.

---

## 12. Observations (not defects, recorded so the next reader does not have to re-derive them)

1. `UIScreen.isCaptured` is guarded by **call-site reachability** (legacy `else` branch), not by a lexical
   `if #available` — see §6. For an iOS 11.0 symbol that is correct and warning-free at iOS 15.
2. `ScreenGuard.PrivateAPI.isEnabled` is a mutable public global (`…Support.swift:69`). It compiles only
   because `.swiftLanguageMode(.v5)` is pinned; under the tools-version-6.1 Swift 6 default it is a
   `MutableGlobalVariable` error. This is exactly what `docs/api-contract.md` §13 A1 and the `.v5` pin
   document, and the pin is verified present on both targets. Migrating to Swift 6 remains deferred work.
3. The public path is a **refreshed rasterisation**, not a live view (`ScreenGuardShieldView.swift:20-24`).
   This is documented in the source, and it means the shield needs `setNeedsContentRefresh()` (or a refresh
   policy) after content changes — an ergonomic constraint a README should surface.
4. `drawHierarchy(afterScreenUpdates: false)` renders **nothing** in a unit-test host without a
   `UIWindowScene` (pinned by the package's own test and re-confirmed by its skip). Any future pixel test for
   no-leak must run in an app scene, or it will produce a vacuous black and could be mistaken for protection.

---

## 13. Residual uncertainty / what this report does not prove

- **No physical device was available.** Every device-required cell in §10 is genuinely unmeasured here, not
  merely unverified. The package's central public-path claim remains *plausible, designed and
  device-pending* — never measured — exactly as `api-contract.md` §4 says.
- The recording path was measured only to the extent of proving it delivers **no frames** on Simulator.
- The no-leak evidence for the private path is from the **app-side `drawHierarchy`** read plus the host
  contrast *discriminator*. A real screenshot is a render-server read; `drawHierarchy` is the faithful
  available proxy (`capability-matrix.md` §5) but it is a proxy.
- I did not re-run the iOS-26-deployment-target warning experiment (§10, last-but-one row).
- My scratch tools (`/tmp/t5_resample.py`, `/tmp/t5_rendersanity.py`, `/tmp/t5_contrast_bands.py`) live
  outside the repository on purpose: the verifier's write scope is this report only, and no package source,
  test, example, script, or teammate artifact was modified.

## 14. Artifacts produced by this attempt

```
.build/verify-dd/                                     clean-room package build + test (C1, C2)
.build/verify-capture/20261002-212218-verify/         my full verify_capture.sh run (C4)
    noleak/capture-app-render-final.png               the drawHierarchy read I re-sampled
    noleak/CONTRAST-host-side-display.png             the bypass contrast I re-sampled
    noleak/noleak-…-final.json                        app-side readings + shield states
    samples.txt, capability/, detection/, appswitcher/, watermark/
.build/verify-capture/t5-falsify-optout/              the deliberate falsification run (C5)
.build/demo-dd/                                       demo build, trait enabled (C4)
/tmp/t5-research/                                     independent research-harness reruns (C6, C7, C8)
    matrix/matrix-t5-matrix.log                       band verdicts (drawHierarchy + layer.render)
    replayKit/replaykit-t5-replayKit.log              zero-callback recording measurement
    renderSanity/rendersanity-t5-renderSanity.log     the three preventsCapture cases
    DISPLAY-ground-truth-renderSanity.png             display ground truth I sampled myself
/tmp/t5-build.log · /tmp/t5-test.log · /tmp/t5-verifycapture.log · /tmp/t5-falsify.log
```

**Bottom line.** The package builds and tests clean from a cold tree, its capability table is honest
row-for-row, its availability and private-API gating are as specified, and the one no-leak claim that is
earnable on Simulator — the opt-in private secure-layer swap, plus the `isSecureTextEntry` primitive — is
reproduced from raw pixels with all four falsification controls on the correct side. The public
`preventsCapture` path and the whole recording path are **unverified on Simulator** and are reported as
such. Two real package defects (F1 medium, fail-closed; F2/F3 low) are handed to the reviewer/implementer.
