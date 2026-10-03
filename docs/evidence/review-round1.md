# ScreenGuard — independent review, round 1 (task t6)

**Reviewer:** `gate` (Review Gate) · **Attempt:** `3422f6cd-8b88-4daa-b7aa-bca508cd77fe`
**Date:** 2026-10-02 · **Repository:** `/Users/jiefu/Developer/ScreenGuarantor`
**Reviewed revision:** working tree as of this attempt — no commit exists yet (`git log` → *your current
branch 'main' does not have any commits yet*), so every finding below cites file:line as it stands on disk.
**Reviewed task:** t3 (`Sources/`, `Tests/`) with t9's trait migration and t2's contract as the bar.
**Written by the reviewer.** No implementer's summary was trusted; every claim below is either read from
the current source, produced by a command I ran myself, or a pixel/state measurement recorded in the
t1/t5 evidence files and explicitly attributed as such.

**Write scope:** this file only. No source, test, example, script or team-state file was modified.
Probe tests were run in a **throwaway copy of the package under `/tmp/t6-review`**, never in the repository.

---

## 0. Verdict

## **Verdict: `needs_revision`** — 2 open `high` findings, 3 `medium`, 4 `low`.

Nothing in the package leaks *by default*, the private path is genuinely off by default, the two named
deprecated symbols are correctly guarded, and I found **no vacuous test** and **no overclaiming wording**.
But two load-bearing implementation defects are confirmed, both by reading the source *and* by running
probe tests I wrote against a copy of the package:

1. **A real leak.** Switching the shield to the public path from a fallback/`disabled` state leaves the
   protected content **in the live view hierarchy** while the shield reports `isProtecting == true`
   (**F1**, `high`). Content in the live hierarchy is exactly what a render-server capture renders — the
   source itself states this invariant at `ScreenGuardShieldView.swift:106-110`.
2. **A capability that is delivered but permanently denied.** The opt-in private secure-layer path
   **can never report success**: its postcondition is unreachable by construction, so the shield always
   falls back, always emits a spurious `protectionDegraded`, and labels itself with a mode whose
   documentation ("removes no pixels from any capture") the measured pixels contradict (**F2**, `high`).
   This is t4's FINDING A — **confirmed**.

Both are fail-closed in the sense that they do not *under*-protect, but F1 over-reports protection while
leaking, and F2 under-reports a capability the package advertises. Neither is acceptable under the
contract's own bar (§0.1 no-leak, §6.4 "`isProtecting` … check this", §10 "failure is reported, never
silent" — a *success* reported as a failure is the same honesty defect mirrored).

### 0.1 Criterion-by-criterion

| # | Review criterion | Result |
|---|---|---|
| 1 | Review judges the actual current source, not the implementer's description | **PASS** — all 21 source files and all 8 test files read; probes run against a copy of the tree |
| 2 | No deprecated API (`UIScreen.isCaptured`, `capturedDidChangeNotification`) reachable on iOS 15–16 without a guard; `UIScreen.main` banned | **PASS for the named symbols**; **F4** (`medium`) for a third deprecated symbol the contract's §7.2 table omits |
| 3 | Private path opt-in only, off by default, documented non-contract + App Review risk; no default-on private hack | **PASS** — no default-on private hack exists |
| 4 | Package/README do not overclaim; no wording implying the user's action is blocked | **PASS** — every prevention statement is a negation or a `notPossible` row |
| 5 | No-leak guarantee scoped per capture path, not asserted as blanket | **PASS for the claims** (registry, §3/§4/§8, source doc comments are scoped honestly); the *implementation* is not consistent with its own scoping (**F1**, **F2**) |
| 6 | No vacuous tests | **PASS** — no test passes because nothing rendered; the pixel assertions all carry controls. One weak app-switcher test noted in **F7** |
| 7 | Public API drop-in usable without reading the source | **FAIL** — **F9** (`medium`), with **F1/F2/F3** as the concrete obstacles |

---

## 1. Commands I ran, with exit codes

All builds/tests used `xcodebuild` (the only usable route — `docs/TOOLING.md` §1), from a clean derived-data
directory outside the repository. `docs/TOOLING.md` was read in full first.

| # | Command | Exit | Result |
|---|---|---|---|
| C1 | `xcodebuild build -scheme ScreenGuard -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -derivedDataPath /tmp/t6-default-dd` | **0** | `** BUILD SUCCEEDED **`, `-target arm64-apple-ios15.0-simulator`, **0** `warning:` lines |
| C2 | `xcodebuild test … -derivedDataPath /tmp/t6-default-dd` | **0** | `Executed 105 tests, with 6 tests skipped and 0 failures (0 unexpected)` · `** TEST SUCCEEDED **` |
| C3 | `grep -ral _UITextLayoutCanvasView /tmp/t6-default-dd/Build/Products` (default = trait **off**) | 0/1 | **compiled code: 0** (`ScreenGuard.o`); `.swiftmodule`: 0; **`.swiftdoc`: 6** → **F5** |
| C4 | copies of `Sources/` + `Tests/` in `/tmp/t6-review`, manifest patched **in the copy only** to `.default(enabledTraits: ["PrivateAPI"])`, then 4 reviewer probe tests | 0 / 65 | reverse control: `ScreenGuard.o` = **1** occurrence (C3's grep has discriminating power). Probe run: `Executed 4 tests, with 3 failures` — **the 3 failures are the evidence** for F1, F2, F3 |
| C5 | `xcodebuild build … IPHONEOS_DEPLOYMENT_TARGET=26.0 -derivedDataPath /tmp/t6-review/ios26-dd` | **0** | `-target arm64-apple-ios26.0`; **1** deprecation warning → **F4** |
| C6 | `grep -rn 'UIScreen\.main\|isCaptured\|capturedDidChangeNotification' Sources/` | — | 6 code hits, all inside the iOS 15/16 legacy path; `UIScreen.main` only in comments and one evidence **string** |

Raw probe output (C4), verbatim:

```
PROBE-A before switch: contentIsSubiewOfShield=true isProtecting=false mode=disabled
PROBE-A after switch:  contentIsSubiewOfShield=true isDescendant=true isProtecting=true
                       mode=publicPreventsCaptureLayer effective=publicPreventsCaptureLayer
PROBE-B  isCompiledIn=true hostWindow=true engageReturned=false isEngaged=false
                       failure=privateSecureLayerSwapFailed
PROBE-B2 isProtecting=false mode=detectionAndOverlayFallback effective=disabled
                       failure=privateSecureLayerSwapFailed requested=disabled
PROBE-C  requestedStrategy=privateSecureLayer effective=publicPreventsCaptureLayer isProtecting=true
```

The probe sources are in the transcript of this attempt; the assertions encoded the **required**
behaviour, so each failure is a defect, not a broken probe. The copy was deleted at the end of the review.

---

## 2. Findings

Each finding cites the current source, states the concrete problem, and gives the required fix.
Severity reflects: `blocker` = ships a breach in the default configuration; `high` = a breach or a false
capability statement reachable through documented API; `medium` = wrong/misleading state or an inaccurate
contract claim; `low` = latent, cosmetic or documentation precision.

---

### F1 — `high` — switching to the public path leaves the protected content live in the view hierarchy while the shield reports `isProtecting == true`

**File:** `Sources/ScreenGuard/Shield/ScreenGuardShieldView.swift`
**Lines:** `216-267` (`apply(strategy:)`), `391-399` (`teardown()`), `356-362` (`installFallbackOverlay()`),
`364-373` (`hostContentLive(_:)`); invariant stated by the source itself at `106-110`.

**Problem.** `apply(strategy:)` calls `teardown()` first, and `teardown()` removes the timer, the private
engine and the display layer — **it does not remove the protected content from the view hierarchy**. A
shield that has ever been in the `disabled`/fallback state has that content added as a **live subview**
(`installFallbackOverlay` → `hostContentLive`, lines 356-373; the existing test
`ScreenGuardShieldStateTests.swift:230-238` pins exactly this behaviour). When the host then applies
`.publicPreventsCaptureLayer`, nothing detaches it: `engagePublicPath()` adds the display layer and
`refresh()` rasterises the content into it (lines 306-335), while the live subview keeps rendering into
the ordinary capture path. The result is a shield that reports

```
contentIsDescendant=true  isProtecting=true  mode=publicPreventsCaptureLayer
effective=publicPreventsCaptureLayer
```

(probe A, C4). This directly contradicts the file's own stated design at lines 106-110: *"keep it out of
the live hierarchy so it cannot leak through the ordinary render path."* A view in the live hierarchy is
rendered by a real screenshot/recording; the rasterised copy in the `preventsCapture` layer protects only
itself. So after this documented, supported transition the sensitive content appears in a capture **while
the shield says it is protecting**.

This is not hypothetical: the package's own example had to work around it by hand.
`Examples/ScreenGuardDemo/Sources/Support/DemoShieldContainer.swift:119-124` clears the content before
every strategy change with the comment *"doing it explicitly keeps a strategy change from leaving live
content behind"* — i.e. the guarantee the package's own doc comment claims is in fact delivered by the
**consumer**, not by the package.

**Required fix.** Make the detachment the package's job: in `apply(strategy:)` (or in `teardown()`),
remove the protected content from the live hierarchy unless the strategy that is about to be engaged
requires it live (`.privateSecureLayer` **when it actually engages**, and the labelled fallback, which is
explicitly a visible overlay). Then have the public path rasterise from the detached view, as it already
does. Add a regression test asserting `protectedContentView.isDescendant(of: shield) == false` after
`.disabled → .publicPreventsCaptureLayer` (and after a failed `.privateSecureLayer` attempt that then
applies the public strategy), alongside `isProtecting == true`. `ScreenGuardShieldStateTests` currently
tests every transition's *state* (`173-194`) but never the hierarchy, which is why this passed 105 tests.

---

### F2 — `high` — **FINDING A confirmed**: the opt-in private path can never report success, yet the swap takes effect; the shield then mislabels itself as the no-pixel-removing fallback and emits a spurious `protectionDegraded`

**Files/lines:**
`Sources/ScreenGuard/Shield/ScreenGuardPrivateSecureLayer.swift:139-156` (the swap and its unreachable
postcondition — restore at `:146`, check at `:151`),
`Sources/ScreenGuard/Shield/ScreenGuardShieldView.swift:240-262` (the failure branch).

**Problem.** The measured, protecting sequence is taken from the research harness verbatim
(`Research/CaptureMatrix/Sources/TechniqueViews.swift:308-314`), including the final
`canvas.setValue(original, forKey: "layer")` restore. The harness then simply records
`swapApplied = true`. The package copied the sequence but added a postcondition that the sequence cannot
satisfy:

```swift
canvas.setValue(host.layer, forKey: "layer")   // 143
field.isSecureTextEntry = false                // 144
field.isSecureTextEntry = true                 // 145
canvas.setValue(displaced, forKey: "layer")    // 146  <- canvas.layer is displaced again
guard canvas.layer === host.layer else { … }   // 151  <- can never be true
```

Probe B (C4) proves it empirically, not just by inspection: with the `PrivateAPI` trait compiled in
(`isCompiledIn=true`), `ScreenGuard.PrivateAPI.isEnabled = true`, and the host **in a window**,
`ScreenGuardPrivateSecureLayer().engage(on:)` returns **`false`** with
`failure = privateSecureLayerSwapFailed`. That case is only reachable at line 154, i.e. the canvas *was*
found, the toggle sequence *did* run, and only the postcondition failed. Through the public API (probe B2)
the shield therefore reports `isProtecting=false`, `shieldMode=detectionAndOverlayFallback`,
`protectionFailure=privateSecureLayerSwapFailed` — for a capability the package's own contract lists as
**`measured`, opt-in** (§4 row 5, §3.2.3), and whose effect the t4/t5 pixel evidence measures as real
(app-side `drawHierarchy` reads the sentinel `200,0,160` while the host display reads the sensitive
`38,102,242`).

Consequences, in order of importance:

1. **The capability is unreachable through the API.** There is no code path by which `.privateSecureLayer`
   can report `isProtecting == true`, so a host that follows §6.4 ("check this — do not assume") concludes
   its content is unprotected and may fall back to something worse, or refuse to show the content.
2. **False degradation events.** Every engagement attempt fires `onProtectionFailure` →
   `reportProtectionFailure` → a `protectionDegraded` event through `ScreenGuardDelegate`, i.e. a risk
   engine is told protection failed when the pixels say it is in effect. Note the demo's retry loop
   (`DemoShieldContainer.swift:126-148`) fires this up to 4 times per page.
3. **A documented mode is used to mean the opposite of what it says.** `shieldMode =
   .detectionAndOverlayFallback` is documented at `ScreenGuardShieldView.swift:63-68` as *"removes **no
   pixels** from any capture"*, while the measured pixels for that region are excluded from the capture
   and present on the display. A host that branches on `shieldMode` is told the exact inverse of reality.
4. **The state is unteardownable.** Because `engage` returned `false`, `privateLayer` is never assigned
   (`ScreenGuardShieldView.swift:250-254`), so `teardown()` never calls `disengage()` (`:394`). Whatever
   the toggle sequence left on the host's layer is never undone — including across a later
   `apply(.disabled)` / `apply(.publicPreventsCaptureLayer)`, and across `deinit`, which only invalidates
   the timer (`:203-207`). The package cannot presently promise to *release* the protection it engaged.

**Required fix.** Make the postcondition assert what the measured sequence actually establishes — that a
canvas was found and the secure-entry toggle sequence ran — instead of `canvas.layer === host.layer` after
the restore; keep the hidden field and the displaced canvas layer as the engine's state so `disengage()`
restores the arrangement and `teardown()` records it (assign `privateLayer` on the success path, and call
`disengage()` from `teardown()`/`deinit`). Then correct the reporting: when the effect is in place the
shield must say `.privateSecureLayer` with `isProtecting == true`, and the documented degradation
(`.privateSecureLayerUnavailable`) must remain reserved for "canvas absent / trait absent". Add a
regression test that runs with the trait enabled, a window, and the opt-in on, and asserts the reported
state matches the engine's `isEngaged` — the same class of test §11 of the contract demands ("failure is
reported, never silent" — and equally, success must not be reported as failure).

---

### F3 — `medium` — **FINDING B confirmed**: `requestedStrategy` is an immutable init-time snapshot, so it goes *stale and misleading* after `apply(strategy:)`, and the package's own SwiftUI bridge misuses it as change detection

**Files/lines:**
`Sources/ScreenGuard/Shield/ScreenGuardShieldView.swift:159-160` (`public let requestedStrategy`), `:188-197`
(init), `:216` (`apply` does not update it);
`Sources/ScreenGuard/SwiftUI/ScreenGuardModifiers.swift:130`
(`if uiView.requestedStrategy != strategy { uiView.apply(strategy: strategy) }`).

**Problem.** This is worse than "a host cannot learn what it asked for". The property **keeps answering
with the init-time value**, so after a switch it is actively wrong under a name that promises otherwise:
probe C (C4) shows `ScreenGuardShieldView(strategy: .privateSecureLayer)` followed by
`apply(strategy: .publicPreventsCaptureLayer)` reporting `requestedStrategy=privateSecureLayer` while
`effectiveStrategy=publicPreventsCaptureLayer`. Its one in-package consumer is already broken by it: the
SwiftUI bridge compares `requestedStrategy` against the incoming `strategy` to decide whether to
re-apply, and because the value never converges to the last applied strategy, **every** subsequent
`updateUIView` re-runs `apply(strategy:)` — a full teardown and re-engagement (display layer removed and
rebuilt, content re-rasterised) on every SwiftUI update pass, forever, after the first strategy change.

**Required fix.** Track the value: make it `public private(set) var requestedStrategy` and assign it at the
top of `apply(strategy:)` (keeping the init-time value as the initial state), or rename the existing
stored property to `initialStrategy` and add `requestedStrategy` as the last-requested value. Point the
SwiftUI `updateUIView` comparison at that property, and add a test asserting it follows `apply`.

---

### F4 — `medium` — an unguarded symbol deprecated in iOS 17 (`traitCollectionDidChange`) warns at an iOS 26 deployment target, contradicting §7.2's "every one, and its guard" claim

**File:** `Sources/ScreenGuard/Shield/ScreenGuardShieldView.swift:294-299` (the override; the diagnostic
lands on `:295`).

**Problem.** Contract §7.2 is a table titled *"Deprecated symbols — every one, and its guard"* and closes
with *"no deprecated symbol is reachable on iOS 15/16 (or on any OS) without an availability guard"*.
`UIView.traitCollectionDidChange(_:)` is not in that table and is not guarded. Measured (C5):

```
-target arm64-apple-ios26.0
Sources/ScreenGuard/Shield/ScreenGuardShieldView.swift:295:15: warning: 'traitCollectionDidChange' was
deprecated in iOS 17.0: Use the trait change registration APIs declared in the UITraitChangeObservable
protocol [#DeprecatedDeclaration]
```

Exactly one source warning at that target (`-warnings-as-errors` would make it an error, and a consumer
app targeting a current OS sees it too). The same class already contains the modern alternative elsewhere
(`ScreenGuardCaptureStateObserver.swift:91-98` registers for trait changes on iOS 17+), so this is a
leftover, not a necessity. The review's named symbols (`UIScreen.isCaptured`,
`capturedDidChangeNotification`) are **not** the problem — see §3 — but the contract's blanket claim is
false as written.

**Required fix.** Register for the display-scale trait on iOS 17+ the same way the observer does
(`registerForTraitChanges([UITraitDisplayScale.self])`, guarded) and keep a non-deprecated path for
iOS 15/16 (re-check the scale in `layoutSubviews`, or read it through the window scene), so no
deprecated declaration is referenced unguarded. Alternatively add this symbol to §7.2's table with the
measured warning and drop the "every one / on any OS" wording.

---

### F5 — `low` — "ZERO occurrences in build products" is imprecise: the default build's `.swiftdoc` contains the private class name 6 times

**Files/lines:**
`Sources/ScreenGuard/Shield/ScreenGuardShieldView.swift:57`,
`Sources/ScreenGuard/ScreenGuardNoLeakStrategy.swift:35`,
`Sources/ScreenGuard/ScreenGuardCapability.swift:49` (doc comments in always-compiled files mention the
literal); wording at `docs/api-contract.md` §9.4 and `Package.swift:52-53`.

**Problem.** t5's F2 is correct and I reproduce it independently (C3). Default build, trait **off**:

```
ScreenGuard.o                        0
ScreenGuard.swiftmodule              0
ScreenGuard.swiftmodule/…swiftdoc    6   <- 6 occurrences, 1 file
```

So a verifier who greps the whole build-products directory (as the criterion literally says) finds
occurrences and would conclude the claim is false. The substantively important property **does** hold:
zero occurrences in the compiled code, and the reverse control (trait **on**) shows `ScreenGuard.o` = 1,
so the search has discriminating power. Nothing in the binary references the class unless the consumer
opts in.

**Required fix.** State the claim in the measurable form — *"0 occurrences in the compiled object/binary
(`ScreenGuard.o`, the consumer's app binary)"* — in `docs/api-contract.md` §9.4, `Package.swift:52-53` and
`docs/TOOLING.md` §6.7; or remove the literal from the three always-compiled doc comments (referring to
"the private canvas class name" and citing the private file) if a whole-directory grep is to be the check.

---

### F6 — `low` — the public path's failure branch reports a private-API failure reason

**File:** `Sources/ScreenGuard/Shield/ScreenGuardShieldView.swift:232-238`
(`fail(with: .privateSecureLayerUnavailable)`); enum at `Sources/ScreenGuard/ScreenGuardEvent.swift:67-75`.

**Problem.** If `engagePublicPath()` ever returns `false`, the shield reports
`protectionFailure = .privateSecureLayerUnavailable` — a reason documented as "the private secure-layer
canvas class was not found". The public path has nothing to do with the private canvas, so a risk engine
consuming the event is told the wrong mechanism failed. Today the branch is dead (`engagePublicPath()`
unconditionally returns `true`, `:306-316`), which is precisely why it is worth fixing before it becomes
reachable.

**Required fix.** Add a mechanism-correct case (e.g. `.publicPreventsCaptureLayerUnavailable`) and use it
in that branch, or document explicitly that the branch is currently unreachable and why the reason value
is therefore unused.

---

### F7 — `low` — the app-switcher degradation seam is inert, and its monitor test cannot fail

**Files/lines:** `Sources/ScreenGuard/AppSwitcher/ScreenGuardAppSwitcherShield.swift:66-68` (the seam),
`:126-171` (`install` never reports failure) and `ScreenGuardMonitor.swift:256-257` (the wiring);
`Tests/ScreenGuardTests/ScreenGuardAppSwitcherTests.swift:140-154` (the test).

**Problem.** `onProtectionFailure` is never invoked anywhere in the shield, so the monitor's
`reportProtectionFailure` wiring is dead and the doc comment ("Called when the shield could not engage")
describes behaviour that does not exist. The test that covers it asserts only that `start()`/`stop()` are
safe and that no `protectionDegraded` event was emitted — it passes identically if the cover is never
installed at all, so it is the suite's one near-vacuous check (it does not, however, *claim* a capability
pass; the real install/synchrony coverage is in the same file at `:22-100` and in the script).

**Required fix.** Either report a real failure from `install(on:)`/`coverNow()` when there is no window or
scene to cover, or delete the seam and its monitor wiring (and the doc comment). Strengthen the test to
give the monitor a real window and assert `ScreenGuardAppSwitcherShield.isInstalled`/the cover's presence —
or rename it to say it only checks safety.

---

### F8 — `low` — the public path reports `isProtecting == true` before any frame has been enqueued, and discards the enqueue result

**File:** `Sources/ScreenGuard/Shield/ScreenGuardShieldView.swift:306-316` (`engagePublicPath`),
`:319-335` (`refresh`), `:328` (return value discarded).

**Problem.** `engagePublicPath()` returns `true` as soon as the layer object exists, so
`ScreenGuardShieldView()` reports `isProtecting = true` at `init` even though `refresh()` returned early
(bounds are `.zero`, `:324`) and nothing was ever pushed. `ScreenGuardSampleBufferFactory.enqueue`
returns `Bool` and `refresh()` ignores it, so a `CVPixelBufferCreate`/`CMSampleBufferCreate` failure also
leaves `isProtecting = true` with an empty layer. The visible result is a black region that could be
either protection or "nothing was ever pushed" — the exact ambiguity `docs/TOOLING.md` §3 and the
capability matrix §4 warn about, now inside the package's own state machine.

**Required fix.** Only set `isProtecting = true` once a frame has been successfully enqueued (or expose
`hasPushedFrame` and document that `isProtecting` means "the layer is engaged"), and use the discarded
`enqueue` result to drive it.

---

### F9 — `medium` — the private path's required engagement *order* is undocumented, so the documented call site does not work without reading the source or the example

**Files/lines:** `Sources/ScreenGuard/Shield/ScreenGuardShieldView.swift:284-299` (no `didMoveToWindow`
re-attempt), `Sources/ScreenGuard/Shield/ScreenGuardPrivateSecureLayer.swift:112-117` (refuses without a
window), `docs/api-contract.md` §6.4 (documents only `init(strategy:)` / `apply(strategy:)`).

**Problem.** The contract's documented usage is `ScreenGuardShieldView(strategy: .privateSecureLayer)`.
At `init` the view is not yet in a window, so `engage` refuses with `.privateSecureLayerSwapFailed`
(`:115`); the shield has no `didMoveToWindow` retry, so unless the host happens to call
`apply(strategy:)` after the shield joins a window, the private path never even attempts the swap. The
package's own example had to build a 130-line container and a 4-attempt retry loop to get the order right
and says so in its header: *"A SwiftUI `UIViewRepresentable` cannot order those reliably — the strategy
has to be re-applied after the view joins the window"*
(`Examples/ScreenGuardDemo/Sources/Support/DemoShieldContainer.swift:15-24`, `:103-107`, `:126-148`). That is
the definition of "not drop-in usable without reading the source" — the two concrete requirements
(joins-a-window, and F1's detach-before-switch) are enforced by the implementation but appear nowhere in
the public doc comments.

**Required fix.** Re-attempt engagement from `didMoveToWindow` inside `ScreenGuardShieldView` when
`requestedStrategy == .privateSecureLayer` and it is not yet protecting, so `init(strategy:)` behaves as
documented; and document the window requirement in the property/initialiser doc comment (and in §6.4) for
any case that is deliberately left to the host. Together with F1's detach-on-strategy-change and F3's
tracked `requestedStrategy`, the shield then behaves the way its own public documentation describes.

---

## 3. Explicit adjudication of the two reported findings

| Reported | Verdict | Basis |
|---|---|---|
| **FINDING A** — the private swap takes effect yet the shield self-reports `isProtecting=false`, `privateSecureLayerSwapFailed`, `detectionAndOverlayFallback` | **CONFIRMED — `high`** | Source: the postcondition at `ScreenGuardPrivateSecureLayer.swift:151` is unreachable after the restore at `:146`. Independent probe (C4): with the trait compiled in, the opt-in on and a window present, `engage` returns `false` / `privateSecureLayerSwapFailed` (the only reachable source of that value is `:154`, so the canvas was found and the sequence ran). Contradicted by the t4/t5 pixel evidence (sentinel in `drawHierarchy`, real colour on the display). The degradation **is** mislabelled in a way that misleads a risk engine: `shieldMode` is documented as "removes no pixels from any capture" while pixels are removed, and a spurious `protectionDegraded` is emitted on every attempt. See **F2** |
| **FINDING B** — `requestedStrategy` is a `let` fixed in`init` | **CONFIRMED — `medium`** (not merely acceptable) | Probe C (C4): after `apply(.publicPreventsCaptureLayer)` from an init-time `.privateSecureLayer`, the value still reads `.privateSecureLayer`, so it is not just uninformative but stale under a name that promises the last request. It also breaks the package's own SwiftUI bridge (`ScreenGuardModifiers.swift:130`), which then re-applies the strategy on every update pass. See **F3** |

---

## 4. Checks that came out clean (stated so the next reader does not re-derive them)

1. **Deprecated API on the iOS 15/16 path — clean.** `UIScreen.isCaptured`,
   `UIScreen.capturedDidChangeNotification` and the legacy `UIScreen` observer live only in
   `startLegacy(_:)` / `registerLegacy(_:)` / `publishLegacy(_:)` (`ScreenGuardCaptureStateObserver.swift:172-216`),
   which are `private` and are called **only** from the `else` branch of `if #available(iOS 17.0, *)`
   (`:106`, `:125`). On iOS 17+ the legacy observer is not installed at all, so no deprecated signal is
   read. This is guard-by-call-site-reachability, not a lexical `if #available`, which is correct and
   warning-free for an iOS 11.0 symbol (t5 recorded the same precision note).
2. **`UIScreen.main` — never used.** Three hits in `Sources/`, all comments or a quoted evidence string
   (`ScreenGuardMonitor.swift:164`, `ScreenGuard.swift:78`, `ScreenGuardCaptureStateObserver.swift:17`).
   The screen is always resolved via `view.window?.windowScene?.screen` / `scene.screen` (`:106`, `:125`,
   `:185`). Also confirmed by the iOS 26 deployment-target build (C5) emitting no such diagnostic.
3. **Private path opt-in — clean, and not default-on.** `Package.swift:61-67` declares the `PrivateAPI`
   trait and `.default(enabledTraits: [])`; `Package.swift:80` is the only definition of
   `SCREENGUARD_PRIVATE_API`; the private file is entirely inside `#if SCREENGUARD_PRIVATE_API`
   (`ScreenGuardPrivateSecureLayer.swift:54`) with a fallback factory that returns `nil`
   (`ScreenGuardPrivateSecureLayerSupport.swift:105-121`); the runtime gate
   `ScreenGuard.PrivateAPI.isEnabled` defaults to `false` (`:69`); the default strategy is
   `.publicPreventsCaptureLayer` (`ScreenGuardNoLeakStrategy.swift`, `ScreenGuardShieldView.swift:188`,
   `ScreenGuardConfiguration.swift:46`). Two explicit acts are required, and the docs carry §9.5's
   wording rules ("opt-in, off by default, private API, non-contract, fragile, App Review risk, not a
   security guarantee") in the file header (`ScreenGuardPrivateSecureLayer.swift:5-49`) and on every
   public touchpoint. **No default-on private hack exists.**
4. **No overclaiming.** A case-insensitive sweep for `prevents|blocks|stops|disables` over `Sources/` and
   `Examples/` returns only negations, refusals and the two `notPossible` registry rows
   (`ScreenGuard.swift:151,160`), plus the demo's explicit disclaimer
   (`Examples/.../DemoRootView.swift:80-82`, `DemoCapabilityListView.swift:29-33`). The registry returns
   `preventUserScreenshot/Recording = .notPossible` and `noLeakRecordingPath = .notMeasured`
   (`ScreenGuard.swift:117-163`), and a unit test pins the mapping (`ScreenGuardCapabilityTests.swift:37-94`).
   No wording implies the user's action is blocked. (There is no root `README.md` yet — t7 owns it — so
   there is nothing else to audit; the example README is honest, including its statement that the private
   path is opt-in and App Review risk.)
5. **No-leak scoping — honest in the claims.** §4, §8 and the registry scope each path separately
   (secure text field = measured, field's own text only; public `preventsCapture` = device-pending;
   private = measured, private/non-contract; recording = `notMeasured`; watermark = not a security
   control; app-switcher = device-pending; host-side capture and `layer.render` = not protected). Source
   doc comments repeat the scope rather than generalising it. The *implementation* defects F1/F2 are not
   claim-scoping failures, but they mean the implementation does not currently live up to its scoping.
6. **No vacuous tests.** I looked specifically for "passes because nothing rendered". Every blank/pixel
   assertion in the suite is accompanied by a control on the same image: the sentinel strip outside the
   shield (`ScreenGuardDeviceOnlyTests.swift:124-149`), the plain-field calibration and swap-disabled band
   in the t1 matrix (cited, reproduced by t5), the `layer.render` positive control next to the
   `drawHierarchy`-returns-black pin (`ScreenGuardRasterizerTests.swift:76-110`), and the app-side
   controls in the demo harness. The 6 skips all carry an explicit reason, and the device-only tests
   assert nothing they cannot substantiate. Noted weaknesses only: F7's near-vacuous app-switcher monitor
   test, and a duplicated assertion in `ScreenGuardWatermarkLayoutTests.swift:89-90`
   (`testGeometryIsIndependentOfScale` asserts the same expression twice, so it does not actually vary a
   scale — cosmetic).

---

## 5. Inherited observations (not new findings) and residual uncertainty

- **File-count drift (t5's F3).** `find Sources -name '*.swift' | wc -l` = **21**, not the "22" in t3's
  report, and `docs/api-contract.md` §1 lists 16. Normative-document drift only; no behavioural impact.
  Reported by t5 and not re-raised as a finding here.
- **`ScreenGuard.PrivateAPI.isEnabled` is a mutable public global** (`…Support.swift:69`) and compiles
  only because `.swiftLanguageMode(.v5)` is pinned on both targets — exactly the deferred Swift 6
  migration recorded in §13 A1. Verified present on both targets (`Package.swift:78`, `:90`).
- **My F1 evidence is state-level, not pixel-level.** `drawHierarchy` renders nothing in a unit-test host
  (pinned by the package's own test at `ScreenGuardRasterizerTests.swift:76-100`), so I proved the leak by
  the hierarchy invariant the source itself declares (`ScreenGuardShieldView.swift:106-110`), not by
  sampling a PNG. The conclusion follows because a subview in the live hierarchy is rendered by the
  capture path; I did not re-run the demo harness for this sequence, and the demo's own manual detach
  (`DemoShieldContainer.swift:119-124`) is independent corroboration that the package does not do it.
- **F2 rests on the combination of my probe and the t4/t5 pixel evidence.** I independently proved that
  `engage` cannot succeed (probe B); that the region is nonetheless excluded from `drawHierarchy` while
  visible on the display is t4's and t5's measurement, reproduced twice, which I did not repeat myself.
- **No physical device was available**, so nothing here strengthens or weakens the device-pending cells;
  they remain unmeasured exactly as §4 states, and I make no claim about them.
- **Nothing outside my write scope was touched.** The probe tests and the trait-patched manifest exist
  only under `/tmp/t6-review` (deleted after the run); the default-trait build used
  `/tmp/t6-default-dd`; the repository's own `.build/` was not used.

---

## Appendix A — the probe tests (evidence for F1/F2/F3)

Run **only** in a throwaway copy (`/tmp/t6-review`, manifest patched in the copy to
`.default(enabledTraits: ["PrivateAPI"])`). The copy and its derived data were deleted after the run; the
repository was never modified. The assertions encode the **required** behaviour, so their failure is the
finding.

```swift
import UIKit
import XCTest
@testable import ScreenGuard

@MainActor
final class T6ReviewProbeTests: XCTestCase {

    private func makeWindow() -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        window.rootViewController = UIViewController()
        window.isHidden = false
        window.rootViewController?.view.layoutIfNeeded()
        return window
    }

    // F1
    func testPublicPathSwitchLeavesPreviouslyHostedContentInTheLiveHierarchy() {
        let window = makeWindow()
        let content = UIView()
        let shield = ScreenGuardShieldView(strategy: .disabled)
        window.rootViewController?.view.addSubview(shield)
        shield.frame = window.bounds
        shield.layoutIfNeeded()

        shield.protectedContentView = content
        shield.layoutIfNeeded()

        shield.apply(strategy: .publicPreventsCaptureLayer)
        shield.layoutIfNeeded()

        XCTAssertFalse(content.isDescendant(of: shield),
            "the protected content must not remain live on the public path")
    }

    // F2 — the engine, directly
    func testPrivateSecureLayerEngageReportsSuccessWithOptInAndWindow() {
        let window = makeWindow()
        let host = UIView(frame: window.bounds)
        window.rootViewController?.view.addSubview(host)
        host.layoutIfNeeded()

        ScreenGuard.PrivateAPI.isEnabled = true
        defer { ScreenGuard.PrivateAPI.isEnabled = false }

        let engine = ScreenGuardPrivateSecureLayer()
        XCTAssertTrue(engine.engage(on: host),
            "engage must succeed with the trait on, the opt-in on and a window present")
    }

    // F3
    func testRequestedStrategyReflectsTheLastAppliedStrategy() {
        let shield = ScreenGuardShieldView(strategy: .privateSecureLayer)
        shield.apply(strategy: .publicPreventsCaptureLayer)
        XCTAssertEqual(shield.requestedStrategy, .publicPreventsCaptureLayer)
    }
}
```

Observed (C4): 3 of 3 failed, printing `contentIsDescendant=true isProtecting=true
mode=publicPreventsCaptureLayer`; `engageReturned=false … failure=privateSecureLayerSwapFailed`;
`requestedStrategy=privateSecureLayer effective=publicPreventsCaptureLayer`.
