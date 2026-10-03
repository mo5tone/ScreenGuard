# Repair record — F-R2-1, the silent blank on `screenGuardProtected(strategy: .privateSecureLayer)`

**Date:** 2026-10-03 · **Scope:** one open finding (`docs/api-contract.md` §13 A3, F-R2-1) and the two
further defects that measuring it exposed · **Contract entry:** `docs/api-contract.md` §13 A4.

Everything below was executed on this machine: iPhone 17 Pro Simulator, iOS 26.2, Xcode 27.0.
`swift build` / `swift test` are unusable for this iOS-only package (`docs/TOOLING.md` §1); every
command below uses `xcodebuild` with an explicit iOS destination.

---

## 1. What was wrong

`ScreenGuardShieldRepresentable.makeUIView` supplies content **only** through
`protectedContentRenderer`, because SwiftUI content is not a `UIView`. The private path hosts a **live
view** — `ScreenGuardShieldView.synchronizeContentHosting()` began with
`guard let protectedContentView else { return }` — and the public path's display layer is not engaged
on the private strategy. So the renderer's output reached nothing at all, and the shield reported

```
isProtecting = true   shieldMode = privateSecureLayer   protectionFailure = nil
```

over an empty black card. The `renderer × privateSecureLayer` cell of the support matrix was
implemented by neither side and reported by neither side.

Two more defects were uncovered by MEASURING the repair rather than by reasoning about it:

* the renderer returned `nil` on **every** strategy, so the default public `screenGuardProtected()`
  route never rasterised anything either (masked on Simulator by the `preventsCapture` confound —
  `docs/TOOLING.md` §7.1 / §10.2);
* with the default `.manual` refresh policy, a renderer-backed shield whose first attempt happened
  while it was still zero-sized never tried again.

---

## 2. Falsification — the final test file, on pristine pre-repair sources

Two throwaway copies of the pre-repair tree were kept for this, and the **final** test file was copied
into both. `/tmp/fr21-base` is the default configuration; `/tmp/fr21-trait` is the same tree with
`.default(enabledTraits: ["PrivateAPI"])` in its own `Package.swift` — the package in the repository
was never modified for this.

```
xcodebuild test -scheme ScreenGuard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  -derivedDataPath /tmp/fr21-base-dd \
  -only-testing:ScreenGuardTests/ScreenGuardRendererContentTests
```

### 2.1 Default configuration (trait OFF) — RED

```
[file]:175: error: testDisabledStrategyWithARendererShowsTheRenderedContent : XCTAssertGreaterThan
            failed: ("0") is not greater than ("0") - a shield with a renderer and no live view must
            call the renderer at all — before the repair it never did, so nothing could ever be shown
[file]:181: error: testDisabledStrategyWithARendererShowsTheRenderedContent : XCTUnwrap failed:
            expected non-nil value of type "UIImage" - `.disabled` must show the rendered content;
            showing nothing is the F-R2-1 blank
[file]:214: error: testLabelledFallbackWithARendererShowsTheRenderedContent : XCTUnwrap failed:
            expected non-nil value of type "UIImage" - the labelled fallback must SHOW the content it
            cannot protect; showing nothing makes the degraded state indistinguishable from an opaque cover
[file]:401: error: testSwitchingToThePublicPathRemovesRendererBackedContent : XCTAssertNotNil failed -
            precondition: a showing mode hosts the rendered content, so the assertion below can
            actually fail if the public path leaves it behind
[file]:379: error: testTheRealSwiftUIModifierRasterisesOnTheDefaultPublicStrategy : XCTAssertTrue
            failed - the public path must have rasterised the SwiftUI content and enqueued it
[file]:339: error: testTheRealSwiftUIModifierShowsRenderedContent : XCTAssertNotNil failed - stage 3 —
            the package's own rasteriser must turn the SwiftUI content into an image for a
            (320.0, 178.0) region
[file]:345: error: testTheRealSwiftUIModifierShowsRenderedContent : XCTAssertNotNil failed - stage 4 —
            the package's own SwiftUI modifier must put the rendered content on screen
     Executed 7 tests, with 2 tests skipped and 7 failures (0 unexpected) in 0.113 seconds
```

**All five tests that run in this configuration fail.** The two skipped ones are the private-path
tests, which need the trait.

### 2.2 Trait-enabled configuration — RED

```
[file]:175: ... testDisabledStrategyWithARendererShowsTheRenderedContent ... ("0") is not greater than ("0")
[file]:181: ... .disabled must show the rendered content; showing nothing is the F-R2-1 blank
[file]:214: ... the labelled fallback must SHOW the content it cannot protect
[file]:243: ... testPrivateStrategyWithARendererHostsTheRenderedContent : the renderer is the shield's
            only content source here
[file]:245: ... a shield that reports `.privateSecureLayer` and `isProtecting` while hosting no content
            is the F-R2-1 defect: it claims protection over a region that was never painted
[file]:271: ... testPrivateStrategyWithARendererNeverClaimsProtectionOverNothing : XCTAssertFalse
            failed - the shield reports isProtecting=true / mode=privateSecureLayer while its hierarchy
            contains no content at all — a silent blank with a success claim on top (F-R2-1)
[file]:401: ... testSwitchingToThePublicPathRemovesRendererBackedContent : precondition failed
[file]:379: ... testTheRealSwiftUIModifierRasterisesOnTheDefaultPublicStrategy
[file]:339: ... stage 3 — the rasteriser must turn the SwiftUI content into an image
[file]:345: ... stage 4 — the modifier must put the rendered content on screen
     Executed 7 tests, with 10 failures (0 unexpected) in 0.111 seconds
```

**All seven tests fail.** Line 271 is the F-R2-1 state itself, reproduced in-process: the shield
reports the private path engaged while its hierarchy contains nothing.

---

## 3. The measurement that found the second defect

The first repair attempt (shield hosts renderer output) made the hand-rolled reproduction pass while
the **real** route still produced a black card. `Scripts/verify_capture.sh` said so before any unit
test did:

```
[FAIL] the SwiftUI route's excluded region is still VISIBLE on the display
       contrast=0,0,0 -> BLACK — the region did not paint, so the blank capture is unearned
[FAIL] the shield shows rendered content AND reports the private path engaged
       requested=privateSecureLayer mode=privateSecureLayer isProtecting=True
       hostsRenderedContent=False failure=None
```

and the demo's own artifact named the shield's entire subview list:

```json
"subviewClasses": ["UITextField"]
```

A staged probe then located the failing stage exactly, against the real modifier:

```
DIAG A shield bounds=(0.0, 0.0, 320.0, 178.0)  mode=disabled
DIAG B subviews=[]                                     <- nothing hosted
DIAG C renderer(bounds.size=(320.0, 178.0), 2) -> false
DIAG D renderer(100x50, 2) -> false
DIAG E renderer(100x50, 1) -> false
DIAG F renderer(100x50, 3) -> false
DIAG G direct rasteriser with Color(uiColor:) -> true   <- the SAME rasteriser, called directly
DIAG H direct rasteriser with Color.red       -> true
```

`ImageRenderer` itself was not the problem — every standalone variant worked:

```
DIAG 1 minimal+proposedSize uiImage=true       DIAG 6 ScreenGuardSwiftUIRasteriser.image uiImage=true
DIAG 2 no proposedSize      uiImage=true       DIAG 7 after a runloop turn      uiImage=true
DIAG 3 fixed frame          uiImage=true       DIAG 8 Text content              uiImage=true
DIAG 4 proposedSize(w:h:)   uiImage=true       DIAG 9 320x178                   uiImage=true
DIAG 5 default scale        uiImage=true       DIAG 10 iOS 15 rasteriser branch -> true
```

The difference was the **content value**, and the isolating experiment is two lines long:

```
DIAG 1  a ViewModifier's own `content`  -> ImageRenderer.uiImage != nil : false
DIAG 2  a wrapper view's STORED content -> ImageRenderer.uiImage != nil : true
```

`ScreenGuardProtectedModifier` was a `ViewModifier`, and `body(content:)` hands back a
`_ViewModifier_Content` **placeholder** that does not render outside the modifier machinery. It
produced no image at any size or scale, so `protectedContentRenderer` was effectively `nil`-returning
on every strategy — including the default public one. The repair replaces the modifier with
`ScreenGuardProtectedView`, a real `View` that stores the content as a property; the public API and
every call site are unchanged. Recorded as a reusable environment fact in `docs/TOOLING.md` §10.

---

## 4. GREEN — the repaired tree

```
# default configuration
xcodebuild test -scheme ScreenGuard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -derivedDataPath .build/fr21-dd
     Executed 131 tests, with 13 tests skipped and 0 failures (0 unexpected) in 0.256 seconds
     ** TEST SUCCEEDED **

# trait-enabled throwaway copy (/tmp/fr21-trait, its own Package.swift patched)
xcodebuild test -scheme ScreenGuard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -derivedDataPath /tmp/fr21-trait-dd
     Executed 131 tests, with 7 tests skipped and 0 failures (0 unexpected) in 0.301 seconds
     ** TEST SUCCEEDED **
```

The two private-path tests RUN rather than skip in the second configuration:

```
Test Case '...testPrivateStrategyWithARendererHostsTheRenderedContent' passed (0.018 seconds).
Test Case '...testPrivateStrategyWithARendererNeverClaimsProtectionOverNothing' passed (0.004 seconds).
```

Every test in the new file is therefore RED before and GREEN after, in the configuration where it
runs.

---

## 5. End-to-end pixel evidence — `Scripts/verify_capture.sh` §3b, new

The documented route, measured with the package's own modifier over a sentinel, with an unshielded
SwiftUI control:

```
  3b. No-leak — SwiftUI screenGuardProtected(.privateSecureLayer), the documented route
  [PASS] host-side contrast capture taken for the SwiftUI route (CONTRAST ONLY)  119389 bytes
  [PASS] demo and script agree on the SwiftUI page's region geometry              2 regions matched
  [PASS] the region sampler read both SwiftUI-route PNGs                          4 rows (2 regions x 2 images)
  [PASS] SwiftUI control reads the sensitive colour (calibration)                 app-side=38,102,242
  [PASS] no-leak: the SwiftUI private route excludes the region from the capture
         app-side=200,0,160 -> SENTINEL (readable, and not the content colour)
  [PASS] the SwiftUI route's excluded region is still VISIBLE on the display
         contrast=SENSITIVE — exclusion, not a non-painting layer
  [PASS] the shield shows rendered content AND reports the private path engaged
         requested=privateSecureLayer mode=privateSecureLayer isProtecting=True hostsRenderedContent=True

  PASS   29   Simulator-checkable assertions that passed
  FAIL   0
  FIND   0
  SKIP   0
  DEVICE 4
  RESULT: PASSED — every Simulator-checkable assertion passed.      exit 0
```

The whole run, including the pre-existing sections, is unchanged and green; the baseline before this
repair was `PASS 22 · FAIL 0 · FINDING 0 · SKIP 0 · DEVICE 4`, so the seven new assertions are
additive and no existing verdict moved.

**Why the reading is unconfounded.** `app-side = SENTINEL` alone would also be produced by a region
that never painted. The `contrast = SENSITIVE` reading is what rules that out: it is a HOST-side
capture, which bypasses render-server protection by construction and is therefore never evidence
(`docs/TOOLING.md` §2) — it is used only as this discriminator. The asymmetry that remains — real
content on the display, sentinel in the app-side `drawHierarchy` read — is the same one
`docs/evidence/capability-matrix.md` §3 row 4 uses to credit the secure-layer swap. Both of the last
two checks FAILED on the pre-repair run (§3), so neither is vacuous.

---

## 6. Scope, and what was deliberately left alone

Files changed: `Sources/ScreenGuard/Shield/ScreenGuardShieldView.swift`,
`Sources/ScreenGuard/SwiftUI/ScreenGuardModifiers.swift`,
`Tests/ScreenGuardTests/ScreenGuardRendererContentTests.swift` (new),
`Examples/ScreenGuardDemo/Sources/Probes/DemoSwiftUIPrivateProbeView.swift` (new),
`Examples/ScreenGuardDemo/Sources/Support/DemoConfig.swift`,
`Examples/ScreenGuardDemo/Sources/Support/DemoGeometry.swift`,
`Examples/ScreenGuardDemo/Sources/DemoApp.swift`,
`Examples/ScreenGuardDemo/ScreenGuardDemo.xcodeproj` (regenerated by `xcodegen` — it is gitignored),
`Scripts/verify_capture.sh` (new §3b, plus the sampler and the two sampling helpers hoisted to
functions so two sections can share them), `docs/api-contract.md`, `docs/TOOLING.md`, `README.md`.

A shield given **neither** a live view **nor** a render closure still engages the private path and
reports `isProtecting = true` with nothing to protect. That is a different condition from F-R2-1 — it
drops no supplied content, it has none — it is the state
`testShieldReattemptsPrivateEngagementWhenItJoinsAWindow` pins as the documented
`init(strategy: .privateSecureLayer)` behaviour, and changing it would make the shield refuse during
the legitimate "content arrives a moment later" window that `DemoShieldContainer.sync()` occupies. It
is recorded in `docs/api-contract.md` §13 A4 as a residual rather than silently changed.

**Not verified here:** anything requiring a physical device. The public `preventsCapture` path's
capture behaviour, the recording path, a real screenshot event and the app-switcher snapshot pixels
all remain DEVICE-REQUIRED and are reported as such by the run above.
