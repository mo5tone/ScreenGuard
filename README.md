# ScreenGuard

**Keep sensitive content out of screenshots, screen recordings and the app-switcher snapshot — and report honestly where iOS will not let any app do that.**

ScreenGuard is a zero-dependency, iOS 15+, drop-in Swift package for financial and other sensitive
apps. It **detects** captures (public API), **keeps content out of** them where the platform permits,
**covers** the app-switcher snapshot, and **watermarks** what it cannot remove. Every claim it makes
carries a measured status, and the capabilities it does **not** have are stated as plainly as the ones
it does.

---

## ⚠️ The promise — read this first

> **iOS does not allow an app to prevent the user from taking a screenshot or starting a screen
> recording.** There is no public API for it, on any iOS version. A screenshot already exists by the
> time the app is told about it (`UIApplication.userDidTakeScreenshotNotification` is *post hoc*), and
> a recording is started by the user or by ReplayKit, which an app cannot veto. Any library that
> claims it "blocks screenshots" on iOS is wrong.
>
> **ScreenGuard's guarantee is the one the platform actually permits: sensitive content does not leak
> into captures. A protected region coming out black or blank in the capture is the SUCCESS case, not
> a failure.** The package *detects* captures and *keeps sensitive content out of* them. It never
> blocks, stops or disables the user's action, and no part of this README, the API or the demo says
> otherwise.

The rest of this document is written to that bar. Where a capability is designed but not yet proven,
it is marked **device-pending**; where the platform makes something impossible, it is marked
**notPossible**. Device-only claims are never presented as passes (see
[Capability matrix](#capability-matrix) and [What is not proven yet](#what-is-not-proven-yet)).

---

## Which capability is which

Four layers, with deliberately different strengths and different honesty labels.

| Layer | Capability | Mechanism | Public API? | Status today |
|---|---|---|---|---|
| **DETECT** — reliable, public API | Screenshot detection | `UIApplication.userDidTakeScreenshotNotification` | ✅ public | **device-pending** (API is public and stable; the event was never observed end-to-end — the Simulator cannot fire it) |
| **DETECT** — reliable, public API | Capture-state detection (recording / mirroring / AirPlay; **not** which kind) | iOS 17+: `UITraitCollection.sceneCaptureState`; iOS 15/16: `UIScreen.isCaptured` + `capturedDidChangeNotification` | ✅ public | **device-pending** (wiring is public and unit-tested; `isCaptured` stayed `false` with 0 callbacks while ReplayKit was started) |
| **NO-LEAK BLOCK** — public path | A text field's **own** content (PIN, password, OTP) | `isSecureTextEntry` | ✅ public | **measured** — the field's text is blanked in the app-side capture read (`0/1068` dark) while its dots are visible on the display (`19.02%`), with a calibration band proving the path images text (`205/1068`). **Scope: that field's text only.** |
| **NO-LEAK BLOCK** — public path | Arbitrary content, **screenshot-like path only** | `AVSampleBufferDisplayLayer.preventsCapture` + opaque black shield | ✅ public | **device-pending — not a working guarantee today.** Designed for the screenshot-like render path; on Simulator the layer paints **nothing at all**, so a black reading is unearned, and the recording path carries **no claim at all** (see row 6 of the table below). Requires a device run before it can be relied on. |
| **NO-LEAK BLOCK** — opt-in **private** path | Arbitrary content, on the **UIKit** entry point | secure-layer swap into a private `_UITextLayoutCanvasView` descendant | ❌ **private** | **measured** (sentinel `200,0,160` excluded from the app-side read while the display shows the real colour `38,102,242`), **off by default, non-contract, App Review risk, never a security guarantee**. See the [SwiftUI caveat](#known-limitations). |
| **DETECT-ONLY** — iOS cannot prevent it | Screenshot | — | — | **notPossible.** The package detects it *after* it happened. |
| **DETECT-ONLY** — iOS cannot prevent it | Recording / mirroring / AirPlay | — | — | **notPossible** to prevent; and the recording path is **notMeasured** in this repo — ReplayKit delivered **0 callbacks in 30 s** on Simulator. |
| **DETERRENT / FORENSIC** | Attribution of a leak | tiled watermark overlay | ✅ public | **notMeasured as a security control — because it is not one.** It removes **no pixels** and stops nothing. |
| **COVER** | App-switcher snapshot | scene-deactivation cover / SwiftUI `privacySensitive()` | ✅ public | **device-pending** — snapshot pixels are not decodable on Simulator. |

### Capability matrix — the quotable status table

This is `docs/api-contract.md` §4, lifted **verbatim**. It is the single source of truth for the
package's public claims; do not re-derive it in prose.

> This table is the single source of truth for the package's public claims. Copy it; do not
> re-derive it in prose.

| # | Capability | Mechanism | Public? | Status | Guarantee in one line |
|---|---|---|---|---|---|
| 1 | Screenshot **detection** | `UIApplication.userDidTakeScreenshotNotification` | ✅ public | **device-pending** | Tells you a screenshot was taken, **after** it was taken. The API is public and long-stable, but **the event was never observed end-to-end** — the Simulator cannot fire it. |
| 2 | Capture **detection** (recording / mirroring / AirPlay) | iOS 17+: `UITraitCollection.sceneCaptureState`; iOS 15/16: `UIScreen.isCaptured` + `capturedDidChangeNotification` | ✅ public | **device-pending** | Tells you the screen is being captured, and when that changes. Does **not** say which kind. |
| 3 | **No-leak** — a text field's own content | `isSecureTextEntry` | ✅ public | **measured** | The field's text is blanked in captures (user sees dots). **Text-field content only.** |
| 4 | **No-leak** — arbitrary content, public path | `AVSampleBufferDisplayLayer.preventsCapture` + opaque black shield | ✅ public | **device-pending** | Designed to blank arbitrary content in captures. **On Simulator the layer paints nothing at all, so this is unverified — requires a device.** |
| 5 | **No-leak** — arbitrary content, private path | secure-layer swap into private `_UITextLayoutCanvasView` | ❌ **private** | **measured**, opt-in, off by default | Blanks arbitrary content in captures. **Non-contract, fragile, App Review risk. Never a security guarantee.** |
| 6 | **No-leak** — recording path, *any* technique | — | — | **notMeasured** — requires device | **None claimed.** `RPScreenRecorder.startCapture` reported success then delivered **0 callbacks in 30 s**. |
| 7 | Forensic **watermark** | tiled overlay | ✅ public | **notMeasured** — **not a security control** | Makes a leak **attributable**. Removes **no** pixels. Deterrent/forensic only. |
| 8 | **App-switcher snapshot** protection | scene-deactivation cover + SwiftUI `privacySensitive()` | ✅ public | **device-pending** | Covers content before the system snapshots it. Snapshot pixels are not decodable on Simulator. |
| 9 | **Prevent** a screenshot | — | — | **notPossible** | **iOS does not permit an app to block a screenshot.** |
| 10 | **Prevent** a recording | — | — | **notPossible** | **iOS does not permit an app to block a recording.** |

Status vocabulary, defined once:

| Status | Meaning |
|---|---|
| `measured` | Demonstrated by a measurement in `docs/evidence/capability-matrix.md`, with a control that rules out the obvious false positive. |
| `device-pending` | Designed and implemented, but **not measurable on Simulator**; the claim is withheld until a physical device run. **Not a working guarantee today.** |
| `notMeasured` | No measurement attempted; no claim made. |
| `notPossible` | The platform does not permit it. |

The same ten rows are available **at runtime**, so an app can render the truth instead of
transcribing it:

```swift
ScreenGuard.capabilityStatuses          // [ScreenGuardCapabilityStatus]
ScreenGuard.status(of: .noLeakPrivateSecureLayer)   // .measured
ScreenGuard.status(of: .preventUserScreenshot)      // .notPossible
```

---

## Install

ScreenGuard is **iOS 15.0+**, **iOS-only**, and has **zero third-party dependencies** (UIKit,
AVFoundation, CoreMedia, CoreGraphics, SwiftUI, Combine, Foundation — nothing else).

### Swift Package Manager

```swift
// In your own Package.swift
dependencies: [
    .package(url: "https://github.com/YOUR-ORG/ScreenGuard.git", from: "1.0.0"),
],
targets: [
    .target(name: "YourApp", dependencies: ["ScreenGuard"]),
]
```

### Xcode — "Add Package"

**File ▸ Add Package Dependencies…**, paste the repository URL, add the **ScreenGuard** library
product to your app target, then `import ScreenGuard`. No capabilities, entitlements, Info.plist keys
or build settings are required.

> This repository does not assert a canonical remote URL; substitute the URL you publish it at.

### To also compile in the opt-in private path

Add the `PrivateAPI` **package trait** to the same dependency line — one line, no fork:

```swift
.package(url: "https://github.com/YOUR-ORG/ScreenGuard.git", from: "1.0.0", traits: ["PrivateAPI"])
```

Leave the trait out (the default) and the private code is **never compiled** into your build. See
[The `PrivateAPI` trait](#the-privateapi-trait--a-consumer-actionable-opt-out).

### Building this repository

`swift build` and `swift test` **do not work** for this iOS-only package — plain SwiftPM resolves the
macOS SDK and fails with `unable to resolve module dependency: 'UIKit'`. Use `xcodebuild` with an iOS
destination:

```sh
# build the package
xcodebuild build -scheme ScreenGuard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  -derivedDataPath .build/dd

# run the test suite
xcodebuild test -scheme ScreenGuard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  -derivedDataPath .build/dd

# the whole end-to-end example verification (builds the demo, drives it, samples its PNGs)
Scripts/verify_capture.sh
```

`swift-tools-version` is **6.1** (required for package traits); the library target pins
`.swiftLanguageMode(.v5)` so the Swift 6 language mode is not imposed on the source. See
`docs/TOOLING.md` for the verified environment facts and traps.

---

## Minimal example

### UIKit

```swift
import ScreenGuard
import UIKit

final class AccountViewController: UIViewController {

    private let monitor = ScreenGuardMonitor()
    private let shield = ScreenGuardShieldView()   // .publicPreventsCaptureLayer (the default)

    override func viewDidLoad() {
        super.viewDidLoad()

        // 1. DETECT — public API, no opt-in. Events arrive on the main actor, after the fact.
        monitor.delegate = self
        monitor.start()

        // 2. NO-LEAK — hand the shield the view that must not appear in a capture.
        let card = AccountCardView(account: account)
        shield.protectedContentView = card
        shield.onProtectionFailure = { reason in
            // Never let protection fail silently — surface `reason` to your risk engine.
            print("ScreenGuard protection degraded: \(reason.rawValue)")
        }
        shield.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(shield)
        NSLayoutConstraint.activate([
            shield.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            shield.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            shield.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            shield.heightAnchor.constraint(equalToConstant: 220),
        ])

        // 3. CHECK, do not assume. `isProtecting` means the mechanism engaged;
        //    `hasPushedFrame` means a protected frame was actually produced.
        assert(shield.isProtecting)                       // default public path engages immediately
        shield.setNeedsContentRefresh()                   // after the first layout pass
    }
}

extension AccountViewController: ScreenGuardDelegate {
    func screenGuard(_ monitor: ScreenGuardMonitor, didDetect event: ScreenGuardEvent) {
        switch event.kind {
        case .screenshotTaken:
            riskEngine.recordScreenshot(at: event.timestamp)          // the image already exists
        case .captureBegan:
            riskEngine.recordCaptureBegan(state: event.captureState)  // recording OR mirroring OR AirPlay
        case .captureEnded:
            riskEngine.recordCaptureEnded()
        case .protectionDegraded(let reason):
            riskEngine.alertProtectionDegraded(reason)
        }
    }
}
```

For a secret the **user types** (PIN, password, one-time code), use the one mechanism in the package
that is simultaneously public API, measured and unconfounded:

```swift
let pin = ScreenGuardSecureTextField(frame: .zero)   // isSecureTextEntry is enforced `true`
pin.isCopyProtected = true                           // no copy / cut / paste / loupe
```

Its limit is its scope: it protects **the field's own text**, nothing else, and it masks on screen
(the user sees dots). Use it for values the user *enters*, never for a value the user must *read*.

### SwiftUI

```swift
import ScreenGuard
import SwiftUI

struct AccountScreen: View {
    @StateObject private var monitor = ScreenGuardMonitor()
    let userID: String

    var body: some View {
        VStack(spacing: 16) {
            // Display enum values through `.rawValue`.
            // `Text("\(monitor.state.captureState)")` is a DEPRECATION ERROR at an iOS 15 target.
            Text("Capture: \(monitor.state.captureState.rawValue)")

            AccountCard()
                .screenGuardProtected(
                    strategy: .publicPreventsCaptureLayer,   // default; DEVICE-PENDING
                    refreshPolicy: .onLayout,
                    onProtectionFailure: { reason in
                        print("degraded: \(reason.rawValue)")
                    }
                )
                .screenGuardWatermarked(.init(
                    text: "CONFIDENTIAL",
                    secondaryText: userID
                ))
        }
        .screenGuardAppSwitcherProtected()
        .onAppear { monitor.start() }
    }
}
```

`ScreenGuardMonitorView` reads the monitor and rebuilds on state changes if you prefer not to hold
the object yourself.

---

## iOS availability: what a caller gets on 17+ and what is lost on 15/16

| | **iOS 17.0+** | **iOS 15 / 16** |
|---|---|---|
| Capture-state signal | `UITraitCollection.sceneCaptureState` (`.unspecified` / `.inactive` / `.active`), delivered through `registerForTraitChanges` | `UIScreen.isCaptured` (`Bool`) + `UIScreen.capturedDidChangeNotification`, resolved from `window.windowScene?.screen` |
| Granularity | **Per scene**, tri-state (`unspecified` is distinguishable from `inactive`) | **Per screen**, two-state — `.unspecified` and `.inactive` both collapse to `false` |
| Delivery | Trait change (event-driven, no polling) | Notification (event-driven), **plus** a re-registration when the view moves to a window because the screen may not exist yet at `start()` |
| SwiftUI protected content | `ImageRenderer` — the supported, layout-accurate rasterisation route | Best-effort: the content is laid out off-hierarchy in a `UIHostingController`. A detached hosting view has no window, so **SwiftUI resolves its own sizing rather than inheriting your layout** — the protected image can differ in size from the live content |
| Deprecated symbols | None used | `UIScreen.isCaptured` is *soft*-deprecated (`API_TO_BE_DEPRECATED`) and is used **only** inside the `else` branch of `if #available(iOS 17.0, *)`; `UIScreen.main` is banned outright (hard-deprecated in iOS 26.0) |

**What a caller loses on iOS 15/16:** per-scene capture state (a multi-scene app sees the *screen's*
state, not the *scene's*), the distinction between "undetermined" and "not captured", and
layout-accurate SwiftUI rasterisation of protected content. Nothing is lost in prevention terms —
there was never anything to lose: **no iOS version permits blocking a screenshot or a recording.**

The public API is identical on both paths; `ScreenGuardDetectionSource` tells you which signal
produced an event (`.sceneCaptureState`, `.screenIsCaptured`, `.screenshotNotification`).

---

## The `PrivateAPI` trait — a consumer-actionable opt-out

The private secure-layer swap is the only mechanism measured to keep **arbitrary** content out of the
app-side capture read while still painting it on the display. It depends on a **private UIKit class
name**, which is why it is opt-in and off by default.

> ### App Review exposure is a COMPILE-TIME property, not a runtime one.
>
> The private class name is matched **by string**, so the string literal is in the compiled binary
> whether or not the runtime flag is ever set. Turning the flag off at runtime does **not** remove the
> exposure, and turning it on does not add any. The only thing that removes it is **not compiling the
> code**.

**You opt out by doing nothing.** The `PrivateAPI` package trait is deliberately **not** in
`default(enabledTraits:)`. A consumer who must not ship the private class name simply does not enable
the trait — **no fork, no vendored copy, no second dependency, no change to this package**:

| Your manifest | `_UITextLayoutCanvasView` in your build |
|---|---|
| Nothing enabled (**the default**) | **0 occurrences anywhere** — `.o`, `.swiftmodule`, `.swiftdoc`, test bundle, whole build directory |
| `.package(url: …, traits: ["PrivateAPI"])` | present (compiled in) |

This matters because telling a consumer to "exclude one file" of a dependency is **not actionable**:
`exclude:` and `swiftSettings:` exist only on a package's *own* target declarations, and
`PackageDependency` exposes no API that configures a dependency's targets. A separate library product
would work but would force a second dependency. The trait is the mechanism that makes the choice
yours in one line of your own manifest.

**Two explicit acts are required to use the private path** — enabling the trait (compile time) and
granting the runtime opt-in:

```swift
// 1. Your Package.swift:  traits: ["PrivateAPI"]
// 2. Your app, before creating the shield:
ScreenGuard.PrivateAPI.isEnabled = true          // default `false`
assert(ScreenGuard.PrivateAPI.isCompiledIn)      // proves the trait took effect

let shield = ScreenGuardShieldView(strategy: .privateSecureLayer)
shield.protectedContentView = accountCard        // a UIView; see the SwiftUI caveat below
// The private path needs a WINDOW before it can engage; the shield re-attempts from
// `didMoveToWindow`, so setting it up before adding it to the hierarchy is supported.
```

If the trait is absent, or the opt-in is not granted, or the private canvas class disappears in a
future iOS release, the shield **does not fail silently**: it falls back to a labelled
detection-and-overlay mode that removes **no** pixels, sets
`protectionFailure = .privateSecureLayerUnavailable`, and (through `ScreenGuardMonitor`)
emits `ScreenGuardEvent.Kind.protectionDegraded`. **A no-leak mechanism that fails silently is worse
than no mechanism**, because the host would believe it is protected.

⚠️ The private path must never be described as secure, guaranteed, safe, recommended,
production-ready or App-Store-safe. It is opt-in, off by default, a private API, non-contract,
fragile across iOS releases, an App Review risk, and **never a security guarantee**
(`docs/api-contract.md` §9).

---

## Check this, do not assume it

The shield tells you what actually happened. A financial app should treat every one of these as
load-bearing:

| Symbol | What it means |
|---|---|
| `shieldMode` | What the shield is **actually** doing: `.disabled`, `.publicPreventsCaptureLayer`, `.privateSecureLayer`, or `.detectionAndOverlayFallback` (which is **not a no-leak control** — it removes no pixels) |
| `isProtecting` | The selected mechanism is **engaged**. It does **not** mean a frame has been produced |
| `hasPushedFrame` | At least one frame was successfully rasterised and enqueued on the public path. `false` + blank region = "nothing has been pushed yet", a different and diagnosable condition from "the pixels were excluded" |
| `effectiveStrategy` / `requestedStrategy` | What is in effect vs what you last asked for — they can differ after a failed private engagement |
| `protectionFailure` | Non-nil when protection could not engage — `.publicPreventsCaptureLayerUnavailable`, `.privateSecureLayerUnavailable`, `.privateSecureLayerSwapFailed`, `.appSwitcherCoverUnavailable` |
| `onProtectionFailure` (shield, app-switcher) | The closure seam so degradation reaches your risk engine instead of being swallowed |
| `monitor.reportProtectionFailure(_:)` | Turns a reported failure into a `protectionDegraded` event on the monitor |

**Public API, as the code exposes it** (the generated interface is authoritative; this list is the
map, not the contract):

- `ScreenGuard`: `version`, `capabilityStatuses`, `status(of:)`, `capabilityStatus(for:)`, `shared`,
  `start(delegate:)`, `stop()`
- `ScreenGuardMonitor`: `configuration`, `state` (`@Published`), `delegate` (weak), `onEvent`,
  `start()`, `stop()`, `isMonitoring`, `reportProtectionFailure(_:)`
- `ScreenGuardShieldView` and the properties above, plus `protectedContentView`,
  `protectedContentRenderer`, `shieldColor` (default `.black`), `refreshPolicy`,
  `apply(strategy:)`, `setNeedsContentRefresh()`
- `ScreenGuardSecureTextField`: `isSecureTextEntry` (enforced `true`), `isCopyProtected`,
  `onTextChanged`, `refusedInsecureEntryAttempts`
- `ScreenGuardWatermarkView` + `ScreenGuardWatermarkConfiguration` (`text`, `secondaryText`,
  `tileSize`, `angle`, `opacity`, `color`, `font`, `includesTimestamp`, `timestampFormat`,
  `timeZone`, `timestampProvider`, `tileLines(at:)`) and `ScreenGuardWatermarkLayout`
  (`tileOrigins(in:tileSize:)`, `tileCount(in:tileSize:)`)
- `ScreenGuardAppSwitcherShield`: `style`, `isInstalled`, `onProtectionFailure`, `install(on:)`,
  `uninstall()`, `coverNow()`, `uncoverNow()`
- SwiftUI: `.screenGuardProtected(strategy:refreshPolicy:onProtectionFailure:)`,
  `.screenGuardWatermarked(_:)`, `.screenGuardAppSwitcherProtected(style:)`,
  `ScreenGuardMonitorView(monitor:content:)`
- `ScreenGuard.PrivateAPI`: `isEnabled`, `isCompiledIn`

---

## Known limitations

Stated up front rather than discovered in production.

1. **The public `preventsCapture` path is device-pending.** With `preventsCapture = true` the layer
   paints **nothing at all on Simulator — not even on screen** (`rendererStatus = rendering`,
   `enqueued = 1`, correct frame). "Absent from the capture" and "absent from the screen" are
   therefore indistinguishable there, and a black protected region on Simulator is **unearned**. That
   is *fail-closed* — nothing leaks — but it is not proof. Run the device procedure
   (`Scripts/verify_capture.sh --print-device-command`) before relying on it.
2. **The recording / mirroring / AirPlay path is unmeasured — no guarantee claimed.**
   `RPScreenRecorder.startCapture` reported `isAvailable = true` and fired its completion with no
   error, then delivered **zero callbacks in 30 s** (no video, no audio), and `UIScreen.isCaptured`
   stayed `false`. Nothing may be claimed for the recording path from Simulator data.
3. **Screenshot detection is post hoc, and its end-to-end delivery is device-pending.** The
   Simulator has no volume button and no key-combination path, so the real notification cannot be
   fired. The wiring is unit-tested with a deliberately synthetic post, labelled as wiring-only.
4. **The SwiftUI private path used to render nothing — repaired, and kept here as a worked example.**
   `screenGuardProtected(strategy: .privateSecureLayer)` supplied its content only as a render
   closure, and the private path hosted no renderer output: the shield reported
   `isProtecting = true`, `shieldMode = .privateSecureLayer` and `protectionFailure = nil` while
   showing only its own black backing (reviewer probe P10: `contentView = nil`,
   `centrePixel = (0,0,0)`, `hasPushedFrame = false`). The round-3 repair hosts the rendered content
   as a live subview under the same exclusion, and it is now measured end to end by
   `Scripts/verify_capture.sh` §3b — the app-side capture read returns the sentinel while the display
   still shows the content, and the shield reports `hostsRenderedContent = true`. Measuring it also
   exposed the deeper cause, which was **not** in the shield at all: the SwiftUI rasteriser returned
   `nil` on every strategy, at every size, because a `ViewModifier`'s `content` is a placeholder that
   does not render on its own (`docs/TOOLING.md` §10.1). See
   [`docs/api-contract.md`](docs/api-contract.md) §13 A4 and
   [`docs/evidence/repair-fr2-1.md`](docs/evidence/repair-fr2-1.md).
5. **The shield displays a refreshed snapshot, not a live view, on the SwiftUI route.** Whenever the
   content arrives as a render closure — which is every `screenGuardProtected` call site, because
   SwiftUI content is not a `UIView` — it is rasterised and either pushed through the
   `CMSampleBuffer → layer` pipeline (public path) or hosted as a `UIImageView` (every other mode), so
   animations and direct interaction inside a protected region do not update unless the refresh
   policy, `setNeedsContentRefresh()` or a size change causes a re-render. Only a shield given a
   `protectedContentView` hosts genuinely live content — which the UIKit private entry point does, and
   it remains the measured one. Measured cost on the public path: enqueue median 4.0–6.5 ms/frame,
   CPU 4.2–7.1 ms/frame, footprint +0.03–0.17 MB per 60 frames; the achieved 42–47 fps is a **floor**
   set by the harness's own 16 ms pacing — no maximum is claimed, and on-screen latency / dropped
   frames are not measurable in-process.
6. **The watermark is a deterrent, not a control.** It removes no pixels from any capture and stops
   nothing. It makes a leak attributable; it does not survive cropping, blurring or downscaling as a
   guarantee. Never describe it as protection.
7. **App-switcher snapshot pixels are not verifiable on Simulator** (the system writes Apple's
   proprietary `AAPL`-magic KTX variant, which ImageMagick and ffmpeg refuse). The cover's
   installation and its required **synchrony** on `UISceneWillDeactivateNotification` are checked; the
   snapshot's pixels are device-validated only. SwiftUI's own `privacySensitive()` is the
   zero-configuration alternative and is worth preferring where it is sufficient.
8. **A direct in-process `CALayer.render(in:)` read defeats both protections** — it walks the layer
   tree, never goes through the render server, and does not honour capture exclusion. It is a narrow
   but real exfiltration surface, documented rather than solved. It is also why the package's own
   verification uses `drawHierarchy(afterScreenUpdates: false)` as its capture proxy, never
   `layer.render`.
9. **Host-side capture is not protected, by construction.** `xcrun simctl io screenshot` and sim-use
   `screenshot` / `record-video` read the simulator's or device's display surface from the host,
   bypassing render-server protection entirely. Such a capture is a **contrast**, never evidence, and
   it is never allowed to produce a no-leak pass in this repository's verification.

---

## Verification and evidence

Every claim above is auditable. This repository separates **drivers** from **evidence**: a tool that
merely shows a picture is never counted as proof of leakage (see `docs/TOOLING.md` §2).

| Document | What it establishes |
|---|---|
| [`docs/evidence/capability-matrix.md`](docs/evidence/capability-matrix.md) | The authoritative measured technique × capture-path matrix: 8 colour bands (5 techniques + 3 controls) through the app-side render path, the ReplayKit path and a host contrast path. Source of every number quoted here |
| [`docs/evidence/verification-report.md`](docs/evidence/verification-report.md) | Independent verification (task t5): clean-room build and test, the no-leak claim re-derived from raw pixels with its control bands, deliberate falsification attempts, availability and private-gating checks, and the list of what is **not** earned |
| [`docs/evidence/review-round1.md`](docs/evidence/review-round1.md) | Independent review, round 1 (task t6): the findings that were open, including the two `high` findings (a live-hierarchy leak and a private path that could never report success) that were subsequently repaired |
| [`docs/evidence/review-round2.md`](docs/evidence/review-round2.md) | Independent review, round 2 (task t11): **verdict pass** — all round-1 findings closed, re-derived from source and probes; the load-bearing end-to-end re-measurement; and the one open `medium` finding (F-R2-1, the SwiftUI private path) recorded in [Known limitations](#known-limitations) |
| [`docs/api-contract.md`](docs/api-contract.md) | The normative public API contract and honest capability guarantees; §4 is the table lifted verbatim above |
| [`docs/TOOLING.md`](docs/TOOLING.md) | Verified environment facts, valid-vs-invalid evidence paths, and reproduced traps |
| [`docs/evidence/device-run-procedure.md`](docs/evidence/device-run-procedure.md) | The one-command device validation procedure that converts the `device-pending` cells into measured results |

The honest division of labour: `capability-matrix.md` is the measurement, `verification-report.md` is
the independent check of it, the two review rounds are the adversarial check of the package, and
`docs/api-contract.md` is the contract the other three bound.

### Final end-to-end verification

Run after all writers stopped, with a dedicated derived-data path (`.build/final-dd`), on the
verified environment (Xcode 27.0, Swift 6.4, iPhone 17 Pro simulator, iOS 26.2). `swift build` /
`swift test` are expected to **fail** for this iOS-only package and are not part of the gate.

| Check | Command | Result |
|---|---|---|
| Release artifacts exist | `test -s README.md && test -s LICENSE && test -s CHANGELOG.md` | **exit 0** — all three files exist and are non-empty |
| Package library build | `xcodebuild build -scheme ScreenGuard -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -derivedDataPath .build/final-dd` | **exit 0 · `** BUILD SUCCEEDED **`** — `arm64-apple-ios15.0-simulator`, `deployment-target 15.0`, iPhoneSimulator27.0.sdk (Xcode 27A266a), **0 warnings** |
| Test suite | `xcodebuild test -scheme ScreenGuard -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -derivedDataPath .build/final-dd` | **exit 0 · `** TEST SUCCEEDED **`** — `Executed 124 tests, with 11 tests skipped and 0 failures (0 unexpected) in 0.388 (0.433) seconds`; each skip carries a stated reason (6 pre-existing, 4 `PRIVATEAPI`-required, 1 scene-required). The only `warning:` in the log is the toolchain's `appintentsmetadataprocessor` note — **0 source warnings** |
| Example app + end-to-end pixel verification | `Scripts/verify_capture.sh --run-id t7-final` | **exit 0 · `RESULT: PASSED`** — `PASS 22 · FAIL 0 · FIND 0 · SKIP 0 · DEVICE 4`, including `[PASS] shield self-report agrees with the measured pixels  isProtecting=True` and `[PASS] no-leak: private path excludes the region from the capture  app-side=200,0,160 -> SENTINEL` with the region still `[PASS] still VISIBLE on the display`. The public `preventsCapture` path, the recording path, the real screenshot event and the app-switcher snapshot pixels were reported `[DEVICE]`, never as passes |

Raw logs: `/tmp/t7-build.log`, `/tmp/t7-test.log`, `/tmp/t7-example.log`; example artifacts in
`.build/verify-capture/t7-final/`. `swift build` / `swift test` were **not** run: they fail by design
for this iOS-only package (`unable to resolve module dependency: 'UIKit'`), which `docs/TOOLING.md` §1
records and this repository does not treat as a gate.

---

## Repository layout

```
Package.swift                 swift-tools-version 6.1; one product; zero dependencies; the PrivateAPI trait
Sources/ScreenGuard/          the library — 21 Swift files, one module, `import ScreenGuard`
Tests/ScreenGuardTests/       XCTest suite (unit + regression; private/scene tests skip with a reason)
Examples/ScreenGuardDemo/     a real app target that consumes the package by relative path
Scripts/verify_capture.sh     the one-command example verification (PASS / FAIL / DEVICE / SKIP / FINDING)
Research/CaptureMatrix/       the measurement harness behind docs/evidence/capability-matrix.md
docs/                         the contract, the tooling facts and the evidence
```

## Privacy

The package contains **no networking of any kind** — no `URLSession`, no `Network`, no sockets, no
analytics, no telemetry, no remote configuration, no transmitted identifier. It collects nothing and
reports to no one. Forwarding a detection event to a risk engine is the host app's job, and the only
seams for it are `ScreenGuardDelegate` and `ScreenGuardMonitor.onEvent`.

## License

MIT — see [`LICENSE`](LICENSE). Release history: [`CHANGELOG.md`](CHANGELOG.md).
