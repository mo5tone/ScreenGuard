# ScreenGuard — independent review, round 2 (task t11)

**Reviewer:** `gate` (Review Gate) · **Attempt:** `39cb9c98-7ea7-4d9e-9b1c-7c11b0e448f0`
**Date:** 2026-10-02 · **Repository:** `/Users/jiefu/Developer/ScreenGuarantor`
**Reviewed:** the working tree as repaired by t10 (`Sources/`, `Tests/`), against `docs/api-contract.md`
(now 1264 lines, incl. §13 A2), `docs/TOOLING.md`, `docs/evidence/capability-matrix.md` and
`docs/evidence/verification-report.md`; the previous round is `docs/evidence/review-round1.md`.
**Write scope:** this file only. No source, test, example, script or team-state file was modified.
Probes ran in a throwaway copy of the package under `/tmp/t11-review` (manifest patched **in the copy
only**) and were deleted afterwards.

---

## 0. Verdict

## **Verdict: `pass`** — 0 open high findings, 0 blockers, 1 medium, 1 low.

Every round-1 finding is closed, and in each case I re-derived the result from the current source and,
where an in-process check exists, from a probe I wrote and ran myself rather than from the repair
summary. The two round-1 `high` findings — the live-hierarchy leak (F1) and the private path that could
never report success (F2) — are both genuinely fixed, and the private path's protection still holds end
to end: I re-decoded the post-repair demo PNGs with my own Pillow sampler and a withheld-opt-in
falsification run, and the exclusion is unchanged (sentinel `200,0,160` app-side while the display reads
the sensitive `38,102,242`).

The one open `medium` (F-R2-1) is on a surface round 1 did not name: the **SwiftUI** modifier supplies
its content only through `protectedContentRenderer`, and the private strategy has no way to display a
renderer — so `screenGuardProtected(strategy: .privateSecureLayer)` reports `isProtecting == true` and
shows **nothing**, while the modifier's own doc comment and contract §6.8 promise *"the content stays
live"*. It is fail-closed (no leak, no false capture-protection claim), which is why it is `medium` and
not `high` under the acceptance bar ("`pass` only if there are no open high or blocker findings"), but it
is a real functional/documentation defect and should be closed before the README (t7) repeats the claim.

### 0.1 Criterion-by-criterion

| # | Review criterion | Result |
|---|---|---|
| 1 | Review judges the actual current source, not the implementer's description | **PASS** — all 21 source files and all 9 test files read; probes run against a copy of the tree |
| 2 | No deprecated API (`UIScreen.isCaptured`, `capturedDidChangeNotification`) reachable on iOS 15–16 without a guard; `UIScreen.main` banned | **PASS** — and the round-1 `medium` (F4) is also closed: an iOS 26.0 deployment-target build now emits **0** source warnings |
| 3 | Private path opt-in only, off by default, documented non-contract + App Review risk; no default-on private hack | **PASS** — unchanged, and no default-on private hack exists |
| 4 | Package/README do not overclaim; nothing implies the user's action is blocked | **PASS** — re-swept after the repair; every prevention statement is a negation or a `notPossible` row |
| 5 | No-leak guarantee scoped per capture path, not asserted as blanket | **PASS** — registry, §3/§4/§8, source doc comments and the demo copy stay per-path; the private path's exclusion is re-measured, the public path stays `devicePending`, recording stays `notMeasured` |
| 6 | No vacuous tests | **PASS** — the 19 new tests carry controls (a baseline-when-live read, a counterpart test, a skip-with-reason where a host cannot answer), and none passes because nothing rendered |
| 7 | Public API drop-in usable without reading the source | **PASS with one gap** — round-1 F9 is fixed (`didMoveToWindow` re-attempt + documented ordering); the gap is F-R2-1 on the SwiftUI/private combination |
| 8 | Findings carry file, line, severity, problem, fix; verdict `pass` only with no open high/blocker | **PASS** — 2 findings, both with file/line/severity/fix |

---

## 1. Commands I ran, with exit codes

| # | Command | Exit | Result |
|---|---|---|---|
| C1 | `xcodebuild test -scheme ScreenGuard … -derivedDataPath /tmp/t11-dd` (default trait = off) | **0** | `Executed 124 tests, with 11 tests skipped and 0 failures (0 unexpected)` · `** TEST SUCCEEDED **`; the only `warning:` line is the toolchain's `appintentsmetadataprocessor` note — **0 source warnings** |
| C2 | `grep -ral _UITextLayoutCanvasView /tmp/t11-dd/Build/Products` (default) | 1 | **no match anywhere** — `.o`, `.swiftmodule`, `.swiftdoc`, test bundle all 0. F5's wording is now *literally* true |
| C3 | `xcodebuild build -scheme ScreenGuard … -derivedDataPath /tmp/t11-ios26-dd IPHONEOS_DEPLOYMENT_TARGET=26.0` | **0** | `-target arm64-apple-ios26.0`, `** BUILD SUCCEEDED **`, **0** source warnings (round 1 measured 1) |
| C4 | full suite in `/tmp/t11-review` (manifest patched there to `.default(enabledTraits: ["PrivateAPI"])`) **+ my 9 probes** | **0** | `Executed 132 tests, with 7 tests skipped and 0 failures` — 124 repo tests (the 4 `PRIVATEAPI-REQUIRED` skips now **run**) + 9 probes. Raw probe output below |
| C5 | `Scripts/verify_capture.sh --run-id t11-round2` (end-to-end example, my own run) | **0** | `PASS 22 · FAIL 0 · FIND 0 · SKIP 0 · DEVICE 4` → `RESULT: PASSED` |
| C6 | my own Pillow re-decode of C5's PNGs (not the repo's sampler) | — | see §4; control SENSITIVE, privateShield app-side SENTINEL `(200,0,160)`×121/121 vs host SENSITIVE `(38,102,242)`×121/121, publicShield BLACK/BLACK (unearned, device-pending) |
| C7 | `Scripts/verify_capture.sh --skip-build --no-private-opt-in --run-id t11-falsify` (protection withheld) | **0** | the same region reads `[38,102,242]` = **LEAKED**; with the opt-in granted it reads `[200,0,160]` = excluded → the check has discriminating power |

Raw probe output (C4), verbatim:

```
P1  isProtecting=true mode=publicPreventsCaptureLayer contentDescendant=false
P2  mode=publicPreventsCaptureLayer isProtecting=true contentDescendant=false
P3  contentDescendant=false superviewNil=true
P4  engine engage=true isEngaged=true failure=nil
P4  shield isProtecting=true mode=privateSecureLayer effective=privateSecureLayer failure=nil engineEngaged=true
P6  engaged:      isProtecting=true layerAttached=true superlayerIsSuperviewLayer=true hiddenFields=1
P6  after leaving: contentDescendant=true hiddenFields=0 layerAttached=true superlayerIsSuperviewLayer=true
                   centrePixel=Optional((38, 102, 242))
P8  isProtecting=true mode=privateSecureLayer failure=nil
P9  isProtecting=true hasPushedFrame=false
P10 isProtecting=true mode=privateSecureLayer hasPushedFrame=false failure=nil
    contentView=nil subviewClasses=["UITextField"] centrePixel=Optional((0, 0, 0))
```

---

## 2. Round-1 findings, re-adjudicated against the current source

Each row is my own re-derivation, not t10's summary.

| Round-1 finding | Status | Evidence in this attempt |
|---|---|---|
| **F1** `high` — switching to the public path left the protected content live while claiming protection | **CLOSED** | `teardown()` now detaches unconditionally (`ScreenGuardShieldView.swift:535`) and `apply` re-hosts only what the mode requires (`synchronizeContentHosting()`, `:476-486`, gated by `requiresDetachedContent` on `shieldMode`, `:466`). Probes P1/P2/P3: after `.disabled → public`, after a failed-private fallback → public, and after three repeated `apply(.public…)` calls, `contentDescendant=false` (and the content has no superview), while `isProtecting=true`. `teardown()` also detaches *before* `engage`, so the private path re-hosts deliberately rather than by accident |
| **F2** `high` — the private path could never report success, mislabelled its own degradation, and could not be torn down | **CLOSED** | The unreachable `canvas.layer === host.layer` postcondition is gone; the new one (`ScreenGuardPrivateSecureLayer.swift:168-175`) asserts only what the sequence establishes (the canvas is restored, the host still owns its layer, that layer is still attached) and says so at `:149-167`. Probe P4: `engage=true isEngaged=true failure=nil`; through the API the shield reports `isProtecting=true mode=privateSecureLayer failure=nil engineEngaged=true`. Teardown is real: `ScreenGuardPrivateLayerOwner` (`ScreenGuardPrivateSecureLayerSupport.swift:124-161`) is adopted on success (`ScreenGuardShieldView.swift:325`) and released by `teardown()`/`deinit`; probe P6 shows leaving the path removes the hidden field, restores the layer arrangement and re-paints the content, and the trait-enabled suite's `testSwitchingAwayReleasesTheEngagedPrivateLayer` passes |
| **F3** `medium` — `requestedStrategy` was an init-time `let` | **CLOSED** | Now `public private(set) var`, assigned at the top of `apply` (`ScreenGuardShieldView.swift:284`) and documented at `:173-184`; probe P7 passes, and the SwiftUI bridge's comparison (`ScreenGuardModifiers.swift:130`) now converges — the suite's verbatim-reproduction test (`ScreenGuardShieldRegressionTests.swift:336-374`) shows the second and third update no longer re-rasterise |
| **F4** `medium` — unguarded `traitCollectionDidChange` (deprecated iOS 17) warned at an iOS 26 target | **CLOSED** | The override is gone; iOS 17+ uses `registerForTraitChanges([UITraitDisplayScale.self])` (`:395-404`) and iOS 15/16 compares the scale in `layoutSubviews` (`:376-381`). C3: the iOS 26.0 deployment-target build now has **0** source deprecation warnings. The registration's lifetime is pinned by `testShieldFromAWindowDeallocates` |
| **F5** `low` — "0 occurrences in build products" was imprecise (6 in `.swiftdoc`) | **CLOSED** | The literal now appears only inside the trait-gated file (`grep` over `Sources/` shows 3 hits, all in `ScreenGuardPrivateSecureLayer.swift`); the always-compiled files were reworded (`ScreenGuardShieldView.swift:56`, `ScreenGuardNoLeakStrategy.swift:35-42`, `ScreenGuardCapability.swift:47-51`). C2: **0 occurrences anywhere** in a default build's products |
| **F6** `low` — the public path reported a private-API failure reason | **CLOSED** | `README`-visible enum gained `.publicPreventsCaptureLayerUnavailable` (`ScreenGuardEvent.swift:78-83`), used at `ScreenGuardShieldView.swift:308` |
| **F7** `low` — inert app-switcher failure seam + a test that could not fail | **CLOSED** | `install(on:)` reports `.appSwitcherCoverUnavailable` when the window has no scene to bind to (`ScreenGuardAppSwitcherShield.swift:180-182`, predicate at `:204-206`), and `coverNow()` reports when nothing is installed (`:215-219`). New tests cover the predicate, both public routes and the non-reporting case (`ScreenGuardShieldRegressionTests.swift:486-558`), and the monitor test was replaced by one that asserts real installation or **skips with a reason** (`:572-609`) instead of passing vacuously |
| **F8** `low` — `isProtecting == true` before any frame was pushed, enqueue result discarded | **CLOSED** | `hasPushedFrame` added and documented (`ScreenGuardShieldView.swift:146-152`), driven by the real enqueue result (`:436`); probe P9 shows `isProtecting=true hasPushedFrame=false`, and the suite pins both directions |
| **F9** `medium` — the private path's required window ordering was undocumented | **CLOSED** | `didMoveToWindow` re-attempts the un-engaged private request (`:557-565`) and the initialiser documents the contract (`:232-239`). Probe P8: `ScreenGuardShieldView(strategy: .privateSecureLayer)` created outside a window, then added to one, reaches `isProtecting=true mode=privateSecureLayer` with no host-side re-apply |

---

## 3. New findings

### F-R2-1 — `medium` — the SwiftUI private path reports engaged protection while showing nothing, and the documented claim that the content "stays live" is false on that surface

**Files/lines:** `Sources/ScreenGuard/SwiftUI/ScreenGuardModifiers.swift:22-28` (the claim) and `:60-69`
(the modifier supplies **only** `protectedContentRenderer`), `:121-127` (`makeUIView` sets the renderer and
no content view); `Sources/ScreenGuard/Shield/ScreenGuardShieldView.swift:476-486`
(`synchronizeContentHosting()` returns immediately when `protectedContentView == nil`) and `:438-443`
(the private case rasterises nothing); `docs/api-contract.md` §6.8 (same claim).

**Problem.** `screenGuardProtected(strategy: .privateSecureLayer)` is a documented SwiftUI call site, and
`screenGuardProtected`'s own documentation says *"With `.privateSecureLayer` the content stays live"*
(contract §6.8 repeats it). But the representable passes the SwiftUI content as a **render closure**, and
the private path has no code that displays renderer output: `synchronizeContentHosting()` does nothing
with a nil `protectedContentView`, and `refresh()`'s private case pushes no frame. Probe P10 (C4) measures
the outcome with the trait compiled in, the opt-in granted and the shield in a window:

```
isProtecting=true mode=privateSecureLayer hasPushedFrame=false failure=nil
contentView=nil subviewClasses=["UITextField"] centrePixel=Optional((0, 0, 0))
```

The shield reports success with no failure, and the only thing on screen is the shield's own black
backing — the SwiftUI content is gone. A host cannot tell this from a working shield: `isProtecting` is
`true`, `shieldMode` says `.privateSecureLayer`, and `protectionFailure` is `nil`.

It is **fail-closed** (nothing is displayed, so nothing leaks, and the capture shows black, which is the
documented success shape), which is why this is `medium`. But for a financial app it means an account
card that silently renders as an empty black rectangle on the private path, and the documentation
promises the opposite.

**Required fix.** Either (a) make the private path display renderer content: rasterise it once through
the existing `protectedContentRenderer` into a `UIImageView` hosted **live** inside the shield, which the
same layer-subtree exclusion already protects (the trade-off is a refreshed snapshot, exactly as the
public path documents); or (b) refuse to engage the private strategy when no `protectedContentView` is
available, reporting a mechanism-correct failure so the host is told instead of shown a blank. Either way,
correct the claim in `ScreenGuardModifiers.swift:26-27` and `docs/api-contract.md` §6.8 — today it says
the content stays live on the private path, which is false for the only way a SwiftUI caller can use it —
and add a test for the renderer-only private combination (probe P10 is a ready-made regression).

### F-R2-2 — `low` — the normative public-API section was not updated for the symbols the repair added

**Files/lines:** `docs/api-contract.md` §6.4 (`ScreenGuardShieldView` surface) and §6.2
(`ScreenGuardProtectionFailure` cases).

**Problem.** §6 opens with *"Every symbol below is public API"* and t2's §11 bound t3 to *"implement
exactly the signatures in §6"*, but the shield's documented surface is now behind the code: `hasPushedFrame`
is public and documented in the source (`ScreenGuardShieldView.swift:146-152`) yet appears nowhere in the
contract, and `shieldMode`, `onProtectionFailure` and the now-tracked `requestedStrategy` are likewise
undocumented there. The two failure cases the repair added (`.publicPreventsCaptureLayerUnavailable`,
`.appSwitcherCoverUnavailable`, `ScreenGuardEvent.swift:78-88`) are also absent from §6.2. A reader of the
contract — which is the artefact t7 lifts its README claims from — cannot discover the property that
distinguishes "engaged" from "a frame was pushed", which is precisely the distinction the repair
introduced.

**Required fix.** Add the missing symbols to §6.4/§6.2 (with the `isProtecting` vs `hasPushedFrame`
distinction stated), or mark §6 as the non-exhaustive core surface and point at the generated interface.
Low: the code, its doc comments and the example are self-consistent; this is contract drift only.

---

## 4. The load-bearing end-to-end re-measurement (C5–C7)

The repair changed **when** the private path's content is hosted (detached at teardown, re-hosted after
the swap), so the one thing worth re-measuring is that the private path still excludes the content from
the app-side capture read while painting it on the display. I ran the example harness myself (C5) and then
re-decoded its PNGs with my own Pillow sampler and an 11×11 grid over each region's own `bodyRect`,
deliberately not the repository's `sample_regions.py` (C6):

| Region | app-side `drawHierarchy` (the only valid no-leak read) | host `CONTRAST(bypass)` — **not evidence** | Reading |
|---|---|---|---|
| `control` (unshielded, same content) | mean `(40.7,103.9,242.2)`, dom `(38,102,242)`×121/121 | `(38,102,242)` | **SENSITIVE** — the calibration control works, so the blanks below are meaningful |
| `publicShield` | `(0,0,0)`×121/121 | `(0,0,0)` | **BLACK on both** → unearned, reported `DEVICE`, never a pass |
| `privateShield` | `(200,0,160)`×121/121 → **SENTINEL (excluded)** | `(38,102,242)`×121/121 → **SENSITIVE (on the display)** | **NO-LEAK, unconfounded** — the pixels exist and are excluded only from the render-server read |

Falsification (C7): with the opt-in withheld, the same region on the same read path reads
`[38,102,242]` = **LEAKED**; with it granted it reads `[200,0,160]`. The exclusion therefore follows the
opt-in and is not an artefact of a non-rendering view. This is the same asymmetry argument round 1 used,
re-established against the repaired code.

Also reproduced by my run: `[PASS] shield self-report agrees with the measured pixels isProtecting=True`
— the F2 contradiction is gone rather than reworded — and the app-switcher section's install and
synchronous-cover checks pass, with the snapshot pixels correctly left as `DEVICE`.

---

## 5. Checks that came out clean (stated so the next reader does not re-derive them)

1. **Criterion 2, the named symbols.** Unchanged from round 1: `isCaptured` /
   `capturedDidChangeNotification` are used only inside `startLegacy`/`registerLegacy`/`publishLegacy`
   (`ScreenGuardCaptureStateObserver.swift:172-216`), which are `private` and called only from the `else`
   branch of `if #available(iOS 17.0, *)` (`:106`, `:125`); `UIScreen.main` never appears in code (two
   comments and one evidence string only: `ScreenGuardMonitor.swift:164`, `ScreenGuard.swift:78-79`,
   `ScreenGuardCaptureStateObserver.swift:17`). The iOS 26.0 deployment-target build (C3) is clean.
2. **Criterion 3, private opt-in.** `Package.swift:62-68` still declares the `PrivateAPI` trait with
   `.default(enabledTraits: [])` and `Package.swift:81` is still the only definition of
   `SCREENGUARD_PRIVATE_API`, the private file is wholly inside `#if SCREENGUARD_PRIVATE_API`, the
   fallback factory still returns `nil` (`ScreenGuardPrivateSecureLayerSupport.swift:163-179`), and
   `PrivateAPI.isEnabled` still defaults to `false` (`:69`). Two explicit acts remain required, and the
   default strategy is `.publicPreventsCaptureLayer`. **No default-on private hack.**
3. **Criterion 4, no overclaiming.** A fresh case-insensitive sweep for
   `prevents|blocks|stops|disables` across `Sources/` and `Examples/` returns only negations, refusals,
   the two `notPossible` registry rows, and the demo's warning that the private path *"may stop working in
   any iOS release"* — the honest direction. Nothing implies the user's action is blocked. There is still
   no root `README.md` (t7 owns it), so the example README, the contract and the source are what could
   overclaim, and none does.
4. **Criterion 5, per-path scoping.** The runtime registry still returns §4 row-for-row (re-read in the
   demo's own `capability-*.json` from my run): `measured` only for `noLeakSecureTextEntry` and
   `noLeakPrivateSecureLayer`, `devicePending` for the public `preventsCapture` path and the app-switcher
   cover, `notMeasured` for the recording path and the watermark, `notPossible` for the two prevention
   rows. My run printed `[DEVICE]` for the public path and the recording path and never a pass for them.
5. **Criterion 6, no vacuous tests.** The 19 new tests are the opposite of vacuous: the detach is asserted
   with a baseline-when-live control and a counterpart test that the overlay modes still show content; the
   pixel assertion has a readable-live control before the switch; the private tests skip with a stated
   reason in the default build rather than weakening the assertion, and I proved they run (and pass) in a
   trait-enabled copy; the app-switcher monitor test now skips with a reason where the host cannot answer
   instead of passing on a tautology. The default-build skip count rose from 6 to 11 (4 private + 1
   scene), each with a reason.

---

## 6. Residual uncertainty and observations (not findings)

- **F-R2-1 is a state/hierarchy measurement, not a pixel capture.** `drawHierarchy` renders nothing in a
  unit-test host (pinned by the package's own test), so probe P10 establishes that the renderer path hosts
  no view and pushes no frame; the black centre pixel is the shield's own backing. That is sufficient to
  show the content is not displayed, which is the defect; it is not a claim about a real screenshot.
- **The private path cannot self-verify its pixel effect in-process, and now says so.** The new
  postcondition asserts the arrangement, not capture exclusion, and the source states that capture
  exclusion is render-server state established by measurement (`ScreenGuardPrivateSecureLayer.swift:149-167`).
  Given the class is non-contract by definition, the honest framing (opt-in, off by default, never a
  security guarantee, verified end to end by the example) is intact; the residual risk is a future iOS
  build in which the sequence runs but excludes nothing — documented risk, not a defect.
- **`ScreenGuardPrivateLayerOwner` is deliberately non-isolated** with mutable state mutated on the main
  actor, exactly like `ScreenGuardObserverTokenStore`; it compiles only because `.swiftLanguageMode(.v5)`
  is pinned on both targets. Migrating to the Swift 6 language mode remains the deferred work recorded in
  §13 A1/A2 — unchanged, and already known.
- **The two new failure cases are not covered by the "raw values are stable" test**
  (`ScreenGuardMonitorTests.swift:272-292` checks the two original cases). Cosmetic coverage gap; the new
  cases are exercised behaviourally by the app-switcher regression tests.
- **No physical device was available**, so nothing here strengthens or weakens the `devicePending` cells.
  The public `preventsCapture` path and the whole recording path remain unmeasured, and my run reports
  them as `DEVICE`, never as a pass.

---

## Appendix — probe coverage added in this round

`/tmp/t11-review/Tests/ScreenGuardTests/T11ReviewProbeTests.swift` (deleted after the run):

| Probe | What it asserts (required behaviour) | Observed |
|---|---|---|
| P1 | `.disabled → publicPreventsCaptureLayer` detaches the content while `isProtecting` | pass |
| P2 | failed-private fallback → public detaches the content | pass |
| P3 | repeated `apply(.public…)` and assignment while already public keep it detached | pass |
| P4 | `engage(on:)` succeeds with trait + opt-in + window; the shield reports it and not a failure | pass |
| P6 | leaving the private path restores the arrangement (layer attached under its superview's layer), removes the hidden field, and paints the content again | pass |
| P7 | `requestedStrategy` tracks `apply(strategy:)` | pass |
| P8 | `init(strategy: .privateSecureLayer)` engages on joining a window, with no host-side ordering | pass |
| P9 | `isProtecting` (engaged) is distinct from `hasPushedFrame` | pass |
| P10 | renderer-only private path — recorded as the evidence for **F-R2-1** | **defect confirmed** (blank shield, `isProtecting=true`) |
