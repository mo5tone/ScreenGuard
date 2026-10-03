# TOOLING — verified environment facts, traps, and available skills

**Required reading for every team member.** Everything below was verified empirically on this
machine (Xcode 27.0, Swift 6.4, iPhone 17 Pro / iOS 26.2 Simulator, sim-use 0.14.0). Do not
re-derive it, and do not contradict it without new measurement.

If you learn a new tool fact, append it here rather than keeping it in your own head.

---

## 1. Build and test commands — `swift build` DOES NOT WORK here

This package is **iOS-only** (`platforms: [.iOS(.v15)]`, `import UIKit`). Plain SwiftPM CLI
builds resolve the **macOS** SDK and fail:

```
error: unable to resolve module dependency: 'UIKit'
```

Verified: `swift build` fails; `xcodebuild -destination` succeeds.

**Always use `xcodebuild` with an explicit iOS destination:**

```sh
# build
xcodebuild build -scheme ScreenGuard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  -derivedDataPath .build/dd

# test
xcodebuild test -scheme ScreenGuard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  -derivedDataPath .build/dd
```

Notes:
- `swift test` is likewise unusable for this package. Do not put it in a verify command.
- A `Package.swift` alone has no scheme until Xcode resolves it; building via `-scheme` works
  because Xcode auto-generates the scheme from the package manifest.
- Use a **distinct `-derivedDataPath` per task** (`.build/<task>-dd`) so parallel members do not
  fight over the same derived-data lock.

### 1.1 Scheme names change when a package has more than one product

Verified while prototyping the two-product split (§6.5/§6.6):

| Package shape | Schemes generated |
|---|---|
| One product (`ScreenGuard`) | `ScreenGuard` |
| Two products (`SGMain`, `SGPrivate`) | `SG-Package` (aggregate, runs all tests), plus one scheme per product |

Consequences for verify commands:
- The **aggregate `-Package` scheme is the one that runs the test action** across everything.
  A per-product scheme may exist but reject `test` with *"Scheme X is not currently configured
  for the test action"* — that is a scheme configuration fact, not a build failure.
- If the product list ever changes, **re-check the scheme name in the verify commands** rather
  than assuming it is unchanged. Run `xcodebuild -list` to see what actually exists.

Also verified in that prototype: a test asserting on a `@MainActor` static property must itself be
`@MainActor`. `XCTAssertFalse(SomeMainActorType.flag)` fails to compile because the assertion's
autoclosure is `nonisolated` — hoist the value into a local first:

```swift
@MainActor
func testFlag() {
    let flag = Registry.isCompiledIn   // read first
    XCTAssertFalse(flag)               // then assert
}
```


---

## 2. sim-use — a DRIVER, never EVIDENCE

Installed: `/opt/homebrew/bin/sim-use` (v0.14.0). Skill: `sim-use`
(`/Users/jiefu/.agents/skills/sim-use/SKILL.md`).

### What it is good for (use it)

| Need | Command |
|---|---|
| Background the app (real transition) | `sim-use button home --device <UDID>` |
| Read UI / accessibility tree | `sim-use ui --device <UDID>` |
| Tap an element | `sim-use tap --label 'X' --device <UDID>` |
| Record a demo GIF for the README | `sim-use record-video --output demo.gif --device <UDID>` |

`sim-use button home` is the **only reliable way to background an app headlessly**. Launching
another app via `simctl launch` does *not* background the app under test.

### What it must NEVER be used for (the trap)

**sim-use `screenshot` and `record-video` are HOST-SIDE display capture.**

Verified by inspecting the binary: it links `FBSimulatorScreenshotCommands` and
`FBSimulatorVideoRecordingCommands`. This is the same class of path as
`xcrun simctl io screenshot`, which **bypasses render-server capture protection entirely**.

Consequence, stated plainly: **if a sim-use screenshot shows protected content as visible, that
proves nothing about leakage.** It only shows that host-side capture is not protected. Recording
it as a `LEAKED` verdict would be a false finding. If used at all, label it
`CONTRAST(host-side-bypass)` and never count it toward a no-leak verdict.

### It cannot trigger a real screenshot

An iOS screenshot is **side button + volume-up** pressed together. sim-use `button` supports only
`home, lock, apple-pay, side-button, siri` — there is no volume button, and no `key-combo` or
menu path that posts `UIApplication.userDidTakeScreenshotNotification`.

Therefore **screenshot detection cannot be validated end-to-end on the Simulator.** Record it as
`not measurable on Simulator — requires device`. Do not fake it.

---

## 3. Valid vs invalid evidence paths

The whole point of this package is "sensitive pixels do not leak into a capture". A verdict is
only meaningful if the capture path is one the OS actually protects.

| Path | How | Valid as evidence? |
|---|---|---|
| App-side render | `window.drawHierarchy(in:afterScreenUpdates: false)` | ✅ Yes — the screenshot-like path |
| System capture pipeline | `RPScreenRecorder.shared().startCapture` | ✅ Yes — the recording path |
| Host display capture | `xcrun simctl io screenshot`, sim-use `screenshot`/`record-video` | ❌ No — bypasses protection |
| App-switcher snapshot | `SplashBoard/Snapshots/**/*.ktx` | ❌ Not decodable — see §4 |

### Use a sentinel behind protected bands

A black region is ambiguous: it can mean "protection worked" **or** "nothing rendered there".
Always place a distinctly-coloured sentinel *behind* a protected band so the two cases are
distinguishable. A protected band reading sentinel-colour = transparent/blanked;
reading the real colour = leaked.

---

## 4. App-switcher snapshots are not pixel-verifiable on Simulator

The system writes them to:

```
~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Library/SplashBoard/Snapshots/**/*.ktx
```

Verified: these are Apple's proprietary **`AAPL`-magic KTX variant**, not standard KTX. Both
ImageMagick and ffmpeg refuse them:

```
magick: no decode delegate for this image format `KTX'
ffmpeg: Invalid data found when processing input
```

So this artifact **cannot** be used for pixel verification with available tooling. Treat
app-switcher snapshot protection as **device-validated only**.

---

## 5. Traps already reproduced — do not rediscover

| Trap | Consequence | Correct approach |
|---|---|---|
| `drawHierarchy(afterScreenUpdates: true)` | Forces a CATransaction commit; UIKit asserts in `_UIRenderViewImageAfterCommit` (**SIGABRT**) | Keep it `false` |
| `UIGraphicsImageRenderer` output read as 8-bit | It is **16 bpc / 64 bpp**; raw byte reads yield noise | Normalize to RGBA8 first |
| Sampling at band centres | Labels / vertically-centred text cause false blacks | Sample away from text |
| `RPScreenRecorder.startCapture` with no frame | Consent prompt or stalled pipeline | Bound the wait (~10-12s) and record `not-measured` honestly |
| `CALayer.render(in:)` vs `drawHierarchy` | They **disagree** on protection (measured: the private secure-layer trick leaks via `layer.render` but blanks via `drawHierarchy`) | Report per-path; never generalize one path's result to another |

---

## 6. Platform facts that bound what we can promise

- **iOS has no public API to block screenshots.** The only public capture-protection API is
  `AVSampleBufferDisplayLayer.preventsCapture` (iOS 13+), and it only protects content rendered
  into that layer.
- **`UIScreen.isCaptured` is deprecated** (iOS 27 SDK points to `UITraitCollection.sceneCaptureState`).
  Use `sceneCaptureState` guarded by `@available(iOS 17.0, *)`, falling back to `isCaptured`
  on iOS 15/16.
- **Screenshot cannot be prevented, only detected** (`userDidTakeScreenshotNotification`) — and
  that notification is *post hoc*.
- The user's accepted success bar is **no-leak**, not action prevention: a protected region
  appearing **black** in a capture is a PASS. Never claim the package stops a user from
  screenshotting or recording.

### 6.1 `UIScreen.main` is HARD-deprecated in iOS 26.0 — it is a compile ERROR, not a warning

Added by the captain from t2's findings. **Independently re-verified:**

```
xcrun swiftc -typecheck -sdk <iPhoneOS27.0.sdk> -target arm64-apple-ios26.0 -warnings-as-errors
  error: 'main' was deprecated in iOS 26.0: Use a UIScreen instance found through context
         instead (i.e, view.window.windowScene.screen) ... [#DeprecatedDeclaration]
```

At `-target arm64-apple-ios15.0` it is silent (deployment target is below the deprecation), so
this only bites when building against a newer target — but that is exactly what an app shipping
today does. **Banned: never use `UIScreen.main`.** Reach the screen through context instead:

```swift
view.window?.windowScene?.screen
```

### 6.2 `isCaptured` is only SOFT-deprecated — but keep the guard anyway

`UIScreen.isCaptured` carries `API_TO_BE_DEPRECATED`, which produces **zero diagnostics** at
either the iOS 15 or iOS 26 target, even with `-warnings-as-errors`. So "zero deprecation
warnings at iOS 15" is an achievable acceptance criterion. Keep the `@available` guard
regardless: `API_TO_BE_DEPRECATED` means a future SDK will assign a real version.

### 6.3 `AVSampleBufferDisplayLayer` streaming members are deprecated in iOS 18

`status`, `flush`, `enqueue`, `isReadyForMoreMediaData` are deprecated in iOS 18. An
`@available(iOS 17.0, *)` guard silences them — which is why the guard boundary is **17.0, not
18.0**. Use `sampleBufferRenderer` for new code where available.

### 6.4 SwiftUI: `Text("\(someEnum)")` is a deprecation ERROR

Interpolating a non-`String` into `Text` goes through `LocalizedStringKey` and is a deprecation
error. **`CustomStringConvertible` does NOT fix it** — only `.rawValue` or `String(describing:)`
compiles. This matters because "show the live capture-detection state" is exactly that shape:

```swift
Text(state.rawValue)          // ✅
Text("\(state)")              // ❌ deprecation error
```

### 6.5 A separate library product keeps a private symbol out of the consumer's binary

Added by the captain, **independently verified** (t2 raised the concern that "off by default"
reduces runtime risk but not App Review risk, because the private class-name string is a
compile-time property of the binary).

Verified in a throwaway two-product package:

| Built product | `_UITextLayoutCanvasView` present in build products? |
|---|---|
| `SGMain` only (does not depend on the private target) | **No** — absent entirely |
| `SGPrivate` (the reverse control) | **Yes** — `SGPrivate.o` contains it |

The reverse control proves the test has discriminating power, so the absence above is real and not
an artifact of a broken search.

**Consequence for package design:** a consumer whose app does not depend on the private library
product does not carry the private string at all. This turns the App Review exposure from a
*documented warning* into an *architectural guarantee*, which matters because the default build
otherwise places review risk on **every** consumer, including those who never opt in.

Caveat: this only holds if the private implementation is never referenced from the default
product. A protocol seam plus an explicit consumer registration call is the minimal shape that
preserves it.

### 6.6 A consumer CANNOT `exclude:` a file inside a dependency — verified

Added by the captain. This is the reason §6.5's two-product split is the only consumer-actionable
way to keep a private symbol out of an app's binary.

`exclude:` and `swiftSettings:` exist **only on a package's own target declarations**. Checked
against the real SPM API surface
(`Toolchains/.../swift/pm/ManifestAPI/PackageDescription.swiftmodule/*.swiftinterface`):
`PackageDependency` exposes **no** API that configures a dependency's targets, and a consumer's
manifest has no syntax for it. Confirmed empirically by building a throwaway two-package app that
depends on a local package — there is nowhere in the consumer's manifest to express it.

**Consequence for package design:** telling a consumer to "exclude one file" of your package is
not actionable — their only options are to fork or vendor it. If a default build ships a private
symbol, every consumer carries it and cannot opt out without forking. A **separate library
product** is the only mechanism that makes opt-out work with zero forking.

| Approach | Consumer can opt out without forking? |
|---|---|
| Single product + documented `exclude:` | ❌ No — that setting lives in the author's manifest |
| Separate opt-in library product | ✅ Yes — simply do not add it to target dependencies |

This generalises beyond this package: any "drop-in" library with an opt-in risky path should make
the risk **structurally absent from the default product**, not merely documented as removable.

### 6.7 SPM package traits are the consumer-actionable opt-in — verified, with two caveats

Added by the captain. The user proposed traits (SE-0450) to let a **consumer** decide whether the
private-API code is compiled in. This is strictly better than both file-exclusion (author-only) and
a second library product (works, but forces the consumer to add a dependency). Verified end to end:

| Scenario | `_UITextLayoutCanvasView` by artifact |
|---|---|
| Default build, consumer enables nothing | **0 everywhere** — `.o`, `.swiftmodule`, `.swiftdoc`, and across the whole build directory (captain-reverified after the repair described below). |
| Consumer writes `.package(path: …, traits: ["PrivateAPI"])` | present in `.o` (= 1) and in the linked app binary |

**Wording trap (found in review, then actually fixed rather than reworded):** at first this was
written as "0 occurrences in build products", which was **false** — a `.swiftdoc` *is* a build
product, and three **always-compiled** files named the private class in **doc comments**, so it
appeared there 6 times even though `.o` and `.swiftmodule` were clean. The honest wording at the
time was "absent from the compiled object/module and from the shipped binary", and that is a real
distinction, not pedantry: a claim a reader cannot check with the obvious command is a claim that
will be challenged. The repair removed those doc-comment literals, so the private class name now
lives in exactly one place — the string literal inside the trait-gated file — and "0 across an
entire default build" is literally true with no caveat.

**Transferable lesson:** when you publish a verifiable claim, state it in the exact form the
reader's check will produce. "Not in the binary" and "0 in build products" are different claims,
and only one of them survives `grep -r` over the build directory.

So a consumer controls it from **one line in their own manifest**, with no fork and no second
dependency. `PackageDescription` in this toolchain does expose the traits API
(`Package.Trait`, `.trait(name:description:)`, `.default(enabledTraits:)`,
`.when(traits:)` build-setting conditions, and `traits:` on every `.package(...)` overload).

**Caveat 1 — traits require `swift-tools-version: 6.1` or later.** Raising the tools version
**enables the Swift 6 language mode by default**, which broke this package in two places:

```
ScreenGuardPrivateSecureLayerSupport.swift:69  error: static property 'isEnabled' is not
                                               concurrency-safe ... [#MutableGlobalVariable]
ScreenGuardObserverTokenStore.swift:86         error: sending 'teardown' risks causing data races
```

Both are **legitimate Swift 6 concurrency findings**, not false positives. They can be deferred by
pinning the language mode, which was verified to build clean with **zero code changes**:

```swift
.target(
    name: "ScreenGuard",
    path: "Sources/ScreenGuard",
    swiftSettings: [
        .swiftLanguageMode(.v5),                                   // keep Swift 5 semantics
        .define("PRIVATE_ENABLED", .when(traits: ["PrivateAPI"])), // trait-gated private code
    ]
)
```

**Caveat 2 — traits are NOT supported by the `swift build` CLI path for this package anyway**, and
`swift build` already fails here for the iOS-only reason (§1). Traits are honoured by
`xcodebuild`/Xcode, which is what this package uses. Confirm the trait actually took effect by
asserting on the compiled-in flag rather than trusting the manifest.

**Note the argument order:** `products:` must precede `traits:` in the `Package` initialiser, or
the manifest fails to parse with *"argument 'products' must precede argument 'traits'"*.

**Also note** the scheme-name trap (§1.1) applies to the consumer side too: a single-product
package generates `App-Package`, not `App`.


---

## 9. Test framework — XCTest today, Swift Testing migration facts

The user prefers **Swift Testing** over XCTest. Migration is explicitly **de-prioritised** (to be
done after the current task graph completes), so v1 ships XCTest. The facts below were verified
now so the eventual migration is a small task rather than a re-investigation.

### 9.1 Swift Testing works at an iOS 15 deployment target — verified

`Testing.framework` ships in the iPhoneSimulator platform. A package with
`platforms: [.iOS(.v15)]` and a `@Suite`/`@Test`/`#expect` test compiles and runs green:

```
◇ Test run started.
↳ Testing Library Version: 2084
↳ Target Platform: arm64-apple-ios17.0-simulator
✔ Test "value is 42" passed
** TEST SUCCEEDED **
```

**Note the version bump:** the reported target platform is **ios17.0**, not ios15.0, because
`Testing.framework`'s `Info.plist` declares `MinimumOSVersion = 17.0`. This affects **only the
test bundle**, not the shipped library — the library still builds and is consumed at iOS 15. Do
not let this number be mistaken for the package raising its floor.

### 9.2 XCTest and Swift Testing COEXIST in one target — verified

This is the fact that makes migration cheap: it can be done **file by file**, not as a rewrite.
One test target containing both ran both:

```
Executed 1 test, with 0 failures (0 unexpected) in 0.001 seconds   <- XCTest
✔ Test run with 1 test in 1 suite passed                           <- Swift Testing
```

No `Package.swift` change is needed to mix them. A migration can proceed one file at a time with
the suite green throughout.

### 9.3 Gotcha: do not import both and use the bare `value` name

A mixed file failed to compile with `cannot convert value of type '(String) -> Any?' to expected
argument type 'Int'` when `XCTAssertEqual(value, 42)` was written against a symbol named `value`
alongside `import Testing`. Qualify the symbol (e.g. `SG.value`) or the two frameworks' macro
expansions collide. Qualifying fixed it immediately.

### 9.4 Current scope of the eventual migration

| Metric | Value |
|---|---|
| Test files | 8 |
| XCTest methods | 105 |
| Files containing `XCTestCase` | 8 |

Per `docs/api-contract.md`, 6 tests skip with explicit reasons (5 DEVICE-REQUIRED, 1
SCENE-REQUIRED). Swift Testing's `.disabled("reason")` trait is the natural equivalent of those
skips, and is a strict improvement in auditability — the reason travels with the test rather than
living in an imperative `throw XCTSkip(...)`.





---

## 7. ⚠️ Capture-path facts that constrain the package's promise

Added by the captain from t1's measurements (`docs/evidence/capability-matrix.md` §4-§5).
**These are load-bearing — read them before writing any API or README claim.**

### 7.1 On Simulator, `preventsCapture = true` renders NOTHING — not even on screen

Independently re-verified by the captain by sampling `DISPLAY-ground-truth.png` from the
`renderSanity` run:

```
case 0  preventsCapture=true  (set-after-add)  display shows sentinel (200,0,160)
case 1  preventsCapture=true  (set-before-add) display shows sentinel (200,0,160)
case 2  preventsCapture=false (control)        display shows real colour (242,216,25)
```

The layers were healthy: `rendererStatus=rendering`, `enqueued=1`, `layerFrames=402x291@0,0`.
So "paints nothing" is not "the layer was not ready".

**Consequence:** on Simulator, "absent from the capture" and "absent from the screen" are
indistinguishable for this API. A protected band reading black proves nothing. The public
`preventsCapture` flag's capture behaviour is **NOT VERIFIABLE ON SIMULATOR — REQUIRES DEVICE.**
Any `NO-LEAK(black)` result for it on Simulator is **unearned** and must not be quoted.

### 7.2 `CALayer.render(in:)` is NOT a valid substitute for `drawHierarchy`

- It uses a **bottom-left** origin (must be flipped) — a scale/orientation slip silently produced
  a reported `50.87` where the truth was `3.77`.
- It **cannot see `AVSampleBufferDisplayLayer` content**, because that layer is render-server backed.
- It does **not** honour capture exclusion, so it **disagrees with `drawHierarchy`** on the private
  secure-layer trick (measured: `layer.render` leaks, `drawHierarchy` blanks).

`drawHierarchy(afterScreenUpdates: false)` is the faithful proxy — it is the path that reproduces
the documented secure-field behaviour. Report per-path; never average the two, and never
generalise one path's verdict to another. Note `layer.render` is a real (if narrow) exfiltration
surface worth calling out in a threat model.

### 7.3 `RPScreenRecorder` "available" does not mean it works

On Simulator: `isAvailable = true`, completion handler fires with **no error**, then **zero
callbacks in 30 s** (no video, no audio). `startRecording` reports `isRecording = true` and also
yields nothing. `UIScreen.main.isCaptured` stays `false`.

**Consequence:** `isAvailable == true` is not evidence the pipeline works. No recording-path
verdict — `NO-LEAK` or `LEAKED` — may be claimed from Simulator data. Recording protection is
**DEVICE-VALIDATED ONLY**.

### 7.4 Bitmaps come back in Display P3 — normalise to sRGB first

Capture bitmaps are P3. Normalise to sRGB **before both sampling and writing PNG**, or host-side
and in-app numbers disagree by 20-40 per channel.

---

## 8. Authoritative results

`docs/evidence/capability-matrix.md` (task t1) is the authoritative measured technique × path
matrix. Read it before making any claim about what protects what. Its §7 lists the
device-required cells; treat every one of those as unmeasured, not merely unverified.

---

## 10. SwiftUI traps that cost this project real time

Added by the round-3 F-R2-1 repair (`docs/api-contract.md` §13 A4).

### 10.1 A `ViewModifier`'s `content` does NOT render on its own — `ImageRenderer` gives `nil`

**Measured on iPhone 17 Pro / iOS 26.2 Simulator**, inside the test host. This is the fact that hid a
second defect behind a documented one for the whole life of the package:

```
DIAG 1  a ViewModifier's own `content`  -> ImageRenderer.uiImage != nil : false
DIAG 2  a wrapper view's STORED content -> ImageRenderer.uiImage != nil : true
```

`ViewModifier.body(content:)` receives `_ViewModifier_Content<Self>` — a **placeholder** that is
resolved by the modifier machinery at its position in the hierarchy. Handed to `ImageRenderer`
anywhere else it renders as nothing, and `uiImage` comes back `nil` at **every** size and every
scale. It is not a size problem, not an actor problem and not a timing problem; spinning the runloop
does not help.

**Rule:** if a modifier needs to hand its content to a rasteriser, a snapshot API, or any other
consumer that takes a `View` *value*, make it a **wrapper `View` that stores the content as a
property** — `struct Wrapper<C: View>: View { let content: C; … }` — and keep the `screenGuard…`
call site returning `some View`. The public API does not have to change; only the internal shape does.

### 10.2 The `preventsCapture` confound can hide an unrelated defect in the same region

`docs/TOOLING.md` §7.1 records that on Simulator `AVSampleBufferDisplayLayer.preventsCapture = true`
makes the layer paint **nothing at all**. The consequence for debugging is easy to miss: a protected
band reading `BLACK` is the *expected* result there, so a second, independent failure inside that same
band — a rasteriser that returns `nil`, so that no frame is ever pushed — produces an **identical
reading**.

**Rule:** never treat "the region is black, and black is expected here" as evidence that anything
upstream worked. Assert the upstream step directly. On the public path that step is `hasPushedFrame`,
which is driven by the real enqueue result and can therefore only be `true` when the renderer
actually produced an image; `Tests/ScreenGuardTests/ScreenGuardRendererContentTests.swift` now pins it
for the SwiftUI route.

### 10.3 A renderer-backed shield gets its size *after* its renderer

`ScreenGuardShieldRepresentable.makeUIView` sets `protectedContentRenderer` while the shield is still
zero-sized, and `ScreenGuardShieldView(strategy:)` is typically built outside any hierarchy. A
`.manual` refresh policy therefore never produces a first frame unless the shield retries from
`layoutSubviews`. Any future render-closure consumer needs that retry; without it the shield is a
permanent black card and every check that only asks "is it blank?" passes.

---

## 11. The toolchain — `mise` is the only supported way to get these tools

Added with the toolchain task (t1). Every gate in this repository is a tool invocation, so the gate is
only reproducible if the **tool version** is pinned. A Homebrew or global install drifts: SwiftLint
and SwiftFormat add rules between releases, shellcheck turns on new checks in minor versions, and a
formatter release re-indents code. An unpinned tool therefore lets an **unchanged** tree start failing
— or, worse, lets a reformat rewrite files nobody edited.

The single source is [`.mise.toml`](../.mise.toml) at the repository root:

| Tool | Pinned version | What it backs |
|---|---|---|
| SwiftLint | 0.65.1 | `mise run lint` (blocking, `--strict`) and `mise run lint:demo` (advisory) |
| SwiftFormat | 0.63.0 | `mise run format` (writes) and `mise run format:check` (CI) |
| XcodeGen | 2.46.0 | `mise run generate` — both `.xcodeproj` bundles |
| actionlint | 1.7.12 | workflow YAML linting (`mise exec -- actionlint`) |
| shellcheck | 0.11.0 | `mise run shellcheck` (`--severity=error` over `Scripts/`) |
| git-cliff | 2.14.2 | the release notes generated in `.github/workflows/release.yml` |

`xcodebuild`, `xcrun` and `swift` are deliberately **not** pinned by mise: they come from the
installed Xcode, and no `mise run …` task substitutes for `swift build`/`swift test`, which do not
work here (§1).

### 11.1 A fresh clone's config is UNTRUSTED — trust it before anything else

Measured on a fresh clone: mise refuses to read the repository config, and every task fails until it
is trusted —

```
Config files ... are not trusted. Trust them with mise trust
```

so the first three commands, in this order, are:

```sh
mise trust      # required first: records THIS repository path as trusted on this machine
mise install    # fetches the pinned versions
mise tasks      # lists the task names this repository guarantees
```

Trust is per-machine state (this machine records it under `~/.local/state/mise/trusted-configs/`), not
something the repository can carry — which is exactly why a reader's first command can fail while the
maintainer's succeeds. The CI workflows run `mise trust` explicitly, for the same reason.

### 11.2 The task names are frozen; only the repository's tasks are the contract

`mise run <task>` works from any subdirectory: every task sets `dir = "{{config_root}}"`. The eleven
names — `generate`, `lint`, `lint:demo`, `format`, `format:check`, `build`, `test`, `demo:build`,
`demo:verify`, `shellcheck`, `ci:local` — are consumed by CI, by the documentation and by the other
tasks by name. Which of them block is documented once, in [`CONTRIBUTING.md`](../CONTRIBUTING.md) §3.

**Trap, measured:** `mise tasks` also lists tasks inherited from your personal global mise config (3
on this maintainer's machine). Those are not this repository's contract and they do not exist on CI —
never depend on one in a documented command or a gate.

### 11.3 The macOS runner is not this machine — Xcode and SDK differ

| | Local (this machine) | `macos-26` GitHub runner |
|---|---|---|
| Xcode | 27.0 (27A266a), Swift 6.4 | **26.6 (17F113)** — the image's default |
| iOS SDK | `iPhoneSimulator27.0.sdk` | **iOS 26.5** (`iphonesimulator26.5`; the iOS 26.2 SDK is installed too) |
| Simulator runtimes | iOS 26.0, 26.2 and 26.5 installed | iOS **26.2**, whose device list includes iPhone 17 Pro |

Consequences, stated plainly:

* A green `mise run ci:local` here is **not** a prediction that CI is green there. The SDK difference
  can surface a diagnostic that does not appear locally — a deprecation, or a stricter availability
  check. The correct repair makes the source clean under **both** SDKs; never silence the gate.
* The workflows record the actual Xcode, SDK, runtimes and pinned tool versions into the job summary
  on every run, so a difference is visible in the run rather than guessed at.
* The default destination (`platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2`) appears on the
  runner image's installed-simulator list, and the CI preflight fails loudly when a destination cannot
  be resolved instead of falling back to a different device.
* Sources: the `macos-26` image manifest in `actions/runner-images`
  (`images/macos/macos-26-Readme.md`, image `20260824.0517.1`) for the runner column;
  `xcodebuild -version`, `swift --version` and `xcrun simctl list runtimes` on this machine for the
  local column.

---

## 12. ⚠️ The trait-gated private path is NOT covered by the test suite

Added after the code-style baseline (t2). This is the most expensive lesson of this project's tooling
work, because it makes a whole category of green signal mean less than it looks like it means.

### 12.1 The fact

`Sources/ScreenGuard/Shield/ScreenGuardPrivateSecureLayer.swift` is wrapped in
`#if SCREENGUARD_PRIVATE_API`, and `SCREENGUARD_PRIVATE_API` is defined **only** when the `PrivateAPI`
trait is enabled (`Package.swift`):

```swift
.define("SCREENGUARD_PRIVATE_API", .when(traits: ["PrivateAPI"]))
```

With the trait off — the default, and the configuration `mise run build` and `mise run test` use —
that file **is not compiled at all**. The suite does not compensate for it: 6 of the 13 skips exist
precisely because the trait is off (`PRIVATEAPI`-required), so in the default configuration they step
over the path rather than exercise it. The one gate in the chain
that compiles it is `mise run demo:build` (and therefore `demo:verify`), because the example app's
spec enables the trait — `Examples/ScreenGuardDemo/project.yml`, `traits: ["PrivateAPI"]`.

### 12.2 The worked example

During the format baseline, SwiftFormat's `redundantSelf` rule rewrote

```swift
self.canvas = canvas        // the property  <-  the located canvas view
```

into

```swift
canvas = canvas             // a self-assignment: the property is never set
```

because a local named `canvas` was in scope, which made the leading `self.` look redundant.

What stayed green: `mise run build` (**BUILD SUCCEEDED**) and the entire test suite (`Executed 131
tests, with 13 tests skipped and 0 failures`), because neither configuration compiles the file.

What caught it: `mise run demo:build` — the trait-**enabled** build — where `canvas` resolves to the
local (a `let`) and the same line is a **compile error**. The repair renamed the shadowing local to
`locatedCanvas`, which also removes the shadowing that the original rename was meant to address, so
the assignment is unambiguous again:

```swift
canvas = locatedCanvas      // ScreenGuardPrivateSecureLayer.swift, engage()
```

### 12.3 The consequence, stated plainly

* **"The tests pass" is not evidence for the private path.** No amount of green in `mise run test`
  says anything about `ScreenGuardPrivateSecureLayer.swift` — the file was not in the build.
* **`demo:build` is the only gate that compiles it**, so it is the only automated coverage that code
  has.
* **Removing `demo:build` from CI would silently remove the only coverage of that code**, and it would
  not look like a loss, because every other gate would stay green. Do not drop it, and do not "speed
  up CI" by making it conditional.
* The same reasoning applies to any file behind a build setting: a check that runs in a configuration
  where the code is not compiled is a check about something else.

**Transferable rule:** when a code path is gated by a trait, a `#if` or any other build-time switch,
keep at least one gate with the switch **on**, and make its failure visible — otherwise the green
signals you trust are silently about a different program than the one you ship.
