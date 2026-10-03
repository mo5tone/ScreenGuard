# ScreenGuard — public API contract and honest capability guarantees

**Status:** normative specification. `Sources/` (t3), `Examples/` (t4), verification (t5), review (t6) and
the README (t7) are all bound by this document.
**Derived from:** `docs/evidence/capability-matrix.md` (t1, measured) and `docs/TOOLING.md` (verified
environment facts). Where this document states a guarantee, it cites the measurement that earns it.
Where no measurement exists, the guarantee is labelled, not asserted.
**Target:** iOS 15.0+, iOS-only, zero third-party dependencies, single library product.

---

## 0. How to read this document

Three words carry the whole honesty of the package. They are used with exactly these meanings
everywhere below.

| Term | Meaning |
|---|---|
| **Detection** | The package *observes and reports* that a capture happened or is in progress. It changes nothing about the capture. |
| **No-leak** | Sensitive content **does not appear in the captured result**. The protected region coming out **black/blank is the SUCCESS case**. This is the user's accepted bar. |
| **Prevention** | The user is *stopped* from taking a screenshot or recording. **The package never claims this, because iOS does not permit it.** |

### 0.1 The accepted bar (binding)

> The package's promise is **no leakage of sensitive content into captures**. A protected region
> appearing **black or blank in the capture is a PASS**, not a failure.

### 0.2 What the package must never claim (binding on README, docs, comments, and demo copy)

The package **must not** state or imply that it prevents, blocks, disables, or stops the user from
taking a screenshot, starting a screen recording, mirroring the screen, or AirPlaying it.

- iOS exposes **no public API** that blocks a screenshot. The screenshot is taken by the system and
  the app is *told afterwards* (`UIApplication.userDidTakeScreenshotNotification`, post hoc).
- A screen recording is started by the user (Control Center) or by ReplayKit; an app cannot veto it.
- The only capture-protection primitive Apple publishes is `AVSampleBufferDisplayLayer.preventsCapture`
  (iOS 13+), and it protects **only the content rendered into that layer**.

Phrasing that is allowed: *"sensitive content does not leak into captures; protected regions come out
black."* Phrasing that is forbidden: *"prevents screenshots", "blocks screen recording", "disables
screen capture", "stops the user from recording."*

---

## 1. Package and module layout

```
Package.swift                              swift-tools-version: 6.1 (package traits; §13 A1)
Sources/ScreenGuard/                       21 Swift files
  ScreenGuard.swift                        namespace, version, capability registry
  ScreenGuardCapability.swift              capability + verification-status model (§5)
  ScreenGuardConfiguration.swift           configuration value type
  ScreenGuardEvent.swift                   unified detection event (§6.3)
  ScreenGuardDelegate.swift                callback seam
  ScreenGuardMonitor.swift                 detection engine, ObservableObject
  ScreenGuardNoLeakStrategy.swift          the no-leak strategy enum
  Detection/
    ScreenGuardCaptureStateObserver.swift  iOS 17 trait path + iOS 15/16 legacy path (§7)
    ScreenGuardScreenshotObserver.swift    screenshot notification observer
    ScreenGuardEventMapper.swift           capture state -> unified event mapping
    ScreenGuardObserverTokenStore.swift    thread-safe observer token bookkeeping
  Shield/
    ScreenGuardShieldView.swift            the no-leak container (public path)
    ScreenGuardSecureTextField.swift       the measured public primitive
    ScreenGuardContentRasterizer.swift     renders content into the protected layer
    ScreenGuardPrivateSecureLayer.swift    OPT-IN, PRIVATE API, off by default (§9)
    ScreenGuardPrivateSecureLayerSupport.swift  opt-in gate + seam/factory (§9.4)
  Watermark/
    ScreenGuardWatermarkView.swift
    ScreenGuardWatermarkLayout.swift       pure geometry (unit-tested)
  AppSwitcher/
    ScreenGuardAppSwitcherShield.swift
  SwiftUI/
    ScreenGuardModifiers.swift             .screenGuardProtected / Watermarked / AppSwitcherProtected
    ScreenGuardMonitorView.swift
Tests/ScreenGuardTests/
```

**Layout rules.**

1. **Exactly one library product, one module: `ScreenGuard`.** A consumer writes `import ScreenGuard`
   and nothing else. No second product, no sub-module, no plugin. The opt-in private path is
   controlled by an SPM **package trait**, not by a second product (§9.4).
2. **Zero third-party dependencies.** Only system frameworks: `UIKit`, `AVFoundation`, `CoreMedia`,
   `CoreGraphics`, `SwiftUI`, `Combine` (for `ObservableObject`), `Foundation`. `Package.swift`
   declares `dependencies: []`.
3. `platforms: [.iOS(.v15)]`. No macOS, tvOS, watchOS or visionOS support is claimed or tested.
4. The private-API code is gated behind a **package trait named `PrivateAPI`, disabled by default**
   (§9.4). A consumer who must not ship the private class name simply does not enable the trait, so
   the private code is not compiled into their build at all. This is consumer-actionable with no
   fork and no second dependency — which file-exclusion is not.

---

## 2. Platform, availability and dependency contract

| Item | Value |
|---|---|
| Minimum deployment target | **iOS 15.0** |
| Platforms | **iOS only** |
| Third-party dependencies | **none** |
| Swift tools version | **6.1 or later** — required for package traits (§9.4). The target pins `.swiftLanguageMode(.v5)` so the Swift 6 language mode is not forced on the source (see §9.4 note). |
| Package traits | `PrivateAPI` — **not** in `default(enabledTraits:)`. Gates all private-API code. |
| Concurrency model | all public API is `@MainActor` (main-thread), matching UIKit delivery |
| Network code inside the package | **none, ever** (§6.4) |
| Build/test commands | `xcodebuild` only — `swift build`/`swift test` **fail** for this iOS-only package (`docs/TOOLING.md` §1) |

---

## 3. The capability contract

The package offers **four capabilities**. For each one, this section states plainly what it
guarantees and what it does not.

### 3.1 Capability 1 — Detection

**Guarantee.** While `ScreenGuardMonitor` is started, the host app is told (a) when a screenshot was
taken, and (b) when the scene's capture state changes, through one unified event type (§6.3).

**Does not guarantee.** That the capture was prevented — it was not, and cannot be. Screenshot
delivery is **post hoc**: the screenshot already exists by the time the event arrives. On iOS 15/16 the
legacy signal is a coarse boolean. Detection also **does not distinguish** recording from mirroring
from AirPlay — see §3.1.1.

**Measured status.** The *API* is public and available. **End-to-end event delivery is
device-pending**: the Simulator cannot fire `userDidTakeScreenshotNotification` (no volume button;
`docs/TOOLING.md` §2), and `UIScreen.main.isCaptured` stayed `false` with **0** observed
`capturedDidChangeNotification` callbacks while `RPScreenRecorder` was started
(`docs/evidence/capability-matrix.md` §7).

#### 3.1.1 Detection granularity — an honest limit

`UIScreen.isCaptured` is documented as *"True if this screen is being captured (e.g. recorded,
AirPlayed, mirrored, etc.)"*, and `UISceneCaptureState` has exactly three values
(`unspecified`, `inactive`, `active`). **Neither tells the app *what kind* of capture is happening.**
Screen recording, AirPlay and mirroring are all simply `.active`.

Therefore the API exposes a tri-state `ScreenGuardCaptureState`, **not** a
"recording / mirroring / AirPlay" enum. Inventing that distinction would be a fabrication.

### 3.2 Capability 2 — No-leak blocking

Split into two paths with **different statuses and different risk**. They must never be described
together as "the blocking feature".

#### 3.2.1 Path A — secure text field (`isSecureTextEntry`), public API

**Guarantee (measured).** A `UITextField` with `isSecureTextEntry = true` keeps **its own text** out of
the app-side screenshot-like render path. Measured: `TEXT-BLANKED 0/1068` dark pixels in
`drawHierarchy`, while the same field's dots are visible on the display (`19.02%` dark) and the
plain-field calibration band proves that path *can* image text (`205/1068`). This is the only result
in the matrix that is simultaneously **public API, measured, and unconfounded**.

**Does not guarantee.** Protection of anything except that text field's own text. It is **not** a
general-purpose shield and must not be presented as one. It also **masks on screen**: the user sees
dots, not the real value. It is therefore suitable for secrets the user *enters* (PIN, password,
one-time code) — **not** for displaying an account number the user must read.

**Status: measured** (app-side render path only).

#### 3.2.2 Path B — public `AVSampleBufferDisplayLayer.preventsCapture`

**Guarantee.** *Designed:* arbitrary content rendered into an `AVSampleBufferDisplayLayer` with
`preventsCapture = true`, placed over an opaque black shield, comes out black/blank in captures while
remaining visible on screen.

**Status: DESIGNED, DEVICE-PENDING — not a working guarantee today.** On Simulator,
`preventsCapture = true` makes the layer **paint nothing at all, including on screen**: the
`renderSanity` run shows the sentinel magenta on the bypass host display for both set-before-add and
set-after-add, while `preventsCapture = false` paints its real colour, with
`rendererStatus=rendering`, `enqueued=1` and a correct frame (`capability-matrix.md` §4). Row 8's
`NO-LEAK(black)` is therefore **UNEARNED** — it is a black shield behind a non-painting layer.
Because "absent from the capture" and "absent from the screen" are indistinguishable on Simulator,
**the public path's capture behaviour is not measurable there and must be settled on hardware.**

**Does not guarantee (any platform).** Protection of content *not* rendered into that layer. It is not
a window-wide shield, and it does not protect the app's other views.

**Fidelity, if it holds on device.** Hosting arbitrary content through the
`CMSampleBuffer → layer` pipeline is mechanically feasible and faithful on the *unprotected*
reference layer: `meanAbsChannelError = 3.77/255` (host-side re-measurement 8.31, alignment search
found no better offset), enqueue median `4.0–6.5 ms` (p95 `6.1–8.0 ms`), CPU `4.2–7.1 ms`/frame,
footprint `+0.03–0.17 MB` per 60 frames. The `42–47 fps` achieved is a **floor set by the harness's
own 16 ms pacing, not a ceiling** — no maximum sustainable rate is claimed, and on-screen latency and
dropped frames are **not measurable in-process** (`capability-matrix.md` §6).

#### 3.2.3 Path C — private secure-layer swap (opt-in)

**Guarantee (measured).** Arbitrary content reparented into a private `_UITextLayoutCanvasView`
descendant is **excluded from the render-server-backed read while still painting on the display** —
the only mechanism measured to achieve this for arbitrary content. Measured: sentinel `(200,0,160)` in
`drawHierarchy` while the host display capture reads the real colour `(38,102,242)`; the
swap-disabled control band reads `LEAKED` on both paths, proving the blank is protection and not a
broken view (`capability-matrix.md` §3 rows 4 and 6, §4).

**Does not guarantee.** Stability. This is a **private API**: the class name is not contract, is not
documented, and **any iOS release may rename or remove it**, at which point the protection silently
stops. It is **off by default**, reachable only through an explicit opt-in (§9), and carries
**App Review risk** (§9.3). It is **never** described as a security guarantee.

**Status: measured** on the app-side render path. Private. Non-contract.

### 3.3 Capability 3 — Forensic tiled watermark

**Guarantee.** A repeating tile (text, optional identifier, optional timestamp) is drawn over a view,
so that a leaked image of that view is **attributable** to a session, user or time.

**Does not guarantee — and this is the important part.** The watermark is **not a no-leak control**.
It removes **no pixels** from any capture. It is a **deterrent and forensic** measure only. It does not
survive cropping, blurring, downscaling or occlusion, and it does not stop anything.

**Status: not a security control.** Its tile geometry is deterministic and unit-tested; its forensic
efficacy is **not measured** and is not claimed. The watermark must be documented as
"deterrent/forensic", never as protection.

### 3.4 Capability 4 — App-switcher snapshot protection

**Guarantee.** When the scene deactivates (which is when the system takes the app-switcher snapshot),
the package covers the app's content so the **snapshot** does not contain it.

**Does not guarantee.** That the cover is installed in time on every device or iOS version, or that
the snapshot is redacted — the snapshot is written by the system (`SplashBoard`). It also does not
protect against a real screenshot or recording.

**Status: device-pending.** App-switcher snapshots land in
`data/Library/SplashBoard/Snapshots/**/*.ktx` in Apple's proprietary `AAPL`-magic KTX variant, which
**neither ImageMagick nor ffmpeg can decode** (`docs/TOOLING.md` §4). **Snapshot pixels are not
pixel-verifiable on Simulator**; this capability is device-validated only.

### 3.5 Capabilities the package explicitly does **not** have

| Not provided | Why |
|---|---|
| Preventing a screenshot | **iOS does not permit it.** No public API. Detect-only, post hoc. |
| Preventing a screen recording / mirroring / AirPlay | **iOS does not permit it.** Detect-only. |
| Protecting against host-side capture (`simctl io screenshot`, sim-use `screenshot`/`record-video`) | These read the simulator/device display surface **outside the render server** and bypass capture protection by construction. **Contrast only, never evidence** (`docs/TOOLING.md` §2). |
| Protecting against an in-process `CALayer.render(in:)` read | Measured to **defeat both** the secure text field and the secure-layer swap: `layer.render` walks the layer tree directly, never goes through the render server, and does not honour capture exclusion (`capability-matrix.md` §5). A narrow but real exfiltration surface. Documented, not solved. |

---

## 4. Capability status table — **quotable, for t7's README**

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

---

## 5. Capability status as a runtime API

The status model above is exposed in code so a host app (and the package's own demo) can render the
truth rather than restate it. **These symbols are iOS 15-compatible** — no availability guard is
needed.

```swift
/// The capabilities the package does or does not provide. One case per row of §4.
public enum ScreenGuardCapability: String, CaseIterable, Equatable, Sendable {
    case screenshotDetection
    case captureStateDetection
    case noLeakSecureTextEntry
    case noLeakPublicPreventsCapture
    case noLeakPrivateSecureLayer
    /// No-leak on the recording/mirroring path by any technique. Exists so the absence of a
    /// guarantee is itself reportable, rather than being an omission a consumer cannot see.
    /// Must resolve to `.notMeasured`.
    case noLeakRecordingPath
    case watermark
    case appSwitcherSnapshotProtection
    case preventUserScreenshot
    case preventUserRecording
}

/// How well a capability is established. See docs/api-contract.md §4.
public enum ScreenGuardVerificationStatus: String, Equatable, Sendable {
    /// Demonstrated by measurement with a control band that rules out the obvious false positive.
    case measured
    /// Designed and implemented, but not measurable on Simulator. Requires device validation.
    case devicePending
    /// No measurement attempted; no claim made.
    case notMeasured
    /// The platform does not permit it.
    case notPossible
}

/// A capability, its status, and the evidence for that status.
public struct ScreenGuardCapabilityStatus: Equatable, Sendable {
    public let capability: ScreenGuardCapability
    public let status: ScreenGuardVerificationStatus
    /// One-line guarantee, or the reason there is none.
    public let summary: String
    /// The measurement or reasoning that earns the status; cites docs/evidence/capability-matrix.md.
    public let evidence: String
}
```

```swift
public enum ScreenGuard {
    /// Semantic version of the package.
    public static let version: String

    /// Every capability the package models, with its honest status. Backs the README's claim table.
    public static var capabilityStatuses: [ScreenGuardCapabilityStatus] { get }

    /// Convenience lookup.
    public static func status(of capability: ScreenGuardCapability) -> ScreenGuardVerificationStatus
}
```

**Requirement.** `capabilityStatuses` must return exactly the rows of §4, with the same statuses, in
the same order — one case per row, so the enum has exactly 10 entries. `preventUserScreenshot` and
`preventUserRecording` must return `.notPossible`; `noLeakRecordingPath` must return `.notMeasured`;
`screenshotDetection` must return `.devicePending` (the API is public and stable, but the event was
never observed end-to-end — see §3.1). A unit test asserts this mapping, including that the number of
entries equals the number of §4 rows, so the code cannot drift from the contract.

---

## 6. Public API surface

Every symbol below is public API. Availability is stated per symbol; the full guard strategy is §7.

### 6.1 Configuration

```swift
/// Configuration for the ScreenGuard monitor. Value type; safe to copy.
/// iOS 15-compatible.
public struct ScreenGuardConfiguration: Equatable, Sendable {

    /// Detect screenshot events. Default `true`.
    public var isScreenshotDetectionEnabled: Bool

    /// Detect capture-state changes (recording / mirroring / AirPlay). Default `true`.
    public var isCaptureStateDetectionEnabled: Bool

    /// Install the app-switcher snapshot cover on the app's key window. Default `true`.
    public var isAppSwitcherShieldEnabled: Bool

    /// Which mechanism protects views marked with the no-leak shield. Default
    /// `.publicPreventsCaptureLayer`. See §9 for why `.privateSecureLayer` is not the default.
    public var noLeakStrategy: ScreenGuardNoLeakStrategy

    public init(
        isScreenshotDetectionEnabled: Bool = true,
        isCaptureStateDetectionEnabled: Bool = true,
        isAppSwitcherShieldEnabled: Bool = true,
        noLeakStrategy: ScreenGuardNoLeakStrategy = .publicPreventsCaptureLayer
    )
}
```

`isAppSwitcherShieldEnabled` defaults to `true` because it is the one capability that needs no host
action to be useful, and it is the same behaviour SwiftUI's `privacySensitive()` provides. It is
documented, and it is switchable off in one line for hosts that manage their own scenes.

### 6.2 Detection state, events and the callback seam

```swift
/// Whether the scene is being captured. Mirrors UISceneCaptureState on iOS 17+ and the
/// UIScreen.isCaptured boolean on iOS 15/16. iOS 15-compatible.
///
/// Raw-valued and String-backed ON PURPOSE — see the ergonomics note in §6.9. A consumer
/// displaying live capture state writes `Text(state.rawValue)`.
public enum ScreenGuardCaptureState: String, Equatable, Sendable {
    /// The platform could not determine the state (iOS 17+ `.unspecified`; legacy `false`).
    case unspecified
    /// Not being captured.
    case inactive
    /// Being captured. NOTE: this covers recording, mirroring and AirPlay alike — the platform
    /// does not distinguish them. See docs/api-contract.md §3.1.1.
    case active
}

/// Which signal produced an event. Lets a host app reason about confidence and OS coverage.
/// iOS 15-compatible.
public enum ScreenGuardDetectionSource: String, Equatable, Sendable {
    /// UITraitCollection.sceneCaptureState — iOS 17.0 and later only.
    case sceneCaptureState
    /// UIScreen.isCaptured / UIScreen.capturedDidChangeNotification — iOS 15/16 path.
    case screenIsCaptured
    /// UIApplication.userDidTakeScreenshotNotification.
    case screenshotNotification
}

/// A reason the no-leak shield could not engage. Reported so protection never fails silently.
/// iOS 15-compatible.
public enum ScreenGuardProtectionFailure: Equatable, Sendable {
    /// The private secure-layer canvas class was not found on this OS build. The shield is NOT
    /// protecting. See docs/api-contract.md §9.
    case privateSecureLayerUnavailable
    /// The private layer swap was attempted and did not take effect.
    case privateSecureLayerSwapFailed
}

/// The single unified detection event. Every detection seam delivers exactly this type.
/// iOS 15-compatible.
public struct ScreenGuardEvent: Equatable, Sendable {

    public enum Kind: Equatable, Sendable {
        /// A screenshot was taken. Delivered AFTER the fact — the image already exists.
        case screenshotTaken
        /// Capture began (recording, mirroring or AirPlay).
        case captureBegan
        /// Capture ended.
        case captureEnded
        /// A protection mechanism failed to engage. Emitted so the host can react.
        case protectionDegraded(reason: ScreenGuardProtectionFailure)
    }

    public let kind: Kind
    /// The capture state at the moment of the event.
    public let captureState: ScreenGuardCaptureState
    /// Which signal produced this event.
    public let detectionSource: ScreenGuardDetectionSource
    public let timestamp: Date
}

/// A snapshot of the monitor's current knowledge. iOS 15-compatible.
public struct ScreenGuardState: Equatable, Sendable {
    public var captureState: ScreenGuardCaptureState
    /// `nil` until the first detection.
    public var detectionSource: ScreenGuardDetectionSource?
    /// When the most recent screenshot was detected, if any.
    public var lastScreenshotAt: Date?
    public var isMonitoring: Bool
}
```

```swift
/// The callback seam. A host app forwards these events to its own risk engine.
/// Called on the main actor. iOS 15-compatible.
@MainActor
public protocol ScreenGuardDelegate: AnyObject {
    func screenGuard(_ monitor: ScreenGuardMonitor, didDetect event: ScreenGuardEvent)
}
```

```swift
/// Observes capture state and screenshot events and republishes them as ScreenGuardEvent values.
/// iOS 15-compatible.
@MainActor
public final class ScreenGuardMonitor: ObservableObject {

    public init(configuration: ScreenGuardConfiguration = ScreenGuardConfiguration())

    /// Current knowledge. Observable from SwiftUI via @ObservedObject / @StateObject.
    @Published public private(set) var state: ScreenGuardState

    /// Delegate seam. Held weakly.
    public var delegate: ScreenGuardDelegate?

    /// Closure seam, for callers that prefer it. Called on the main actor, after `delegate`.
    public var onEvent: ((ScreenGuardEvent) -> Void)?

    /// Begins observation. Idempotent. Safe to call from `viewDidLoad` / `onAppear`.
    public func start()

    /// Stops observation and removes every observer and trait registration. Idempotent.
    public func stop()

    public var isMonitoring: Bool { get }
}
```

```swift
extension ScreenGuard {
    /// Process-wide monitor using the default configuration.
    @MainActor public static let shared: ScreenGuardMonitor

    /// Starts the shared monitor, optionally installing a delegate, and returns it.
    @MainActor @discardableResult
    public static func start(delegate: ScreenGuardDelegate? = nil) -> ScreenGuardMonitor

    /// Stops the shared monitor.
    @MainActor public static func stop()
}
```

### 6.3 The no-network invariant

The package contains **no networking of any kind** — no `URLSession`, no `Network`, no sockets, no
analytics, no telemetry, no remote configuration, no identifier transmitted anywhere. It collects no
data and reports to no one. Forwarding an event to a risk engine is **the host app's job**, and the
only seam for it is `ScreenGuardDelegate` / `ScreenGuardMonitor.onEvent`. A source-level check that
the module contains no `URLSession`/`Network`/`import` of a networking framework is part of the
verification gate (t5).

### 6.4 No-leak strategy and the shield

```swift
/// Which mechanism protects content marked as sensitive. iOS 15-compatible.
public enum ScreenGuardNoLeakStrategy: String, Equatable, Sendable {

    /// No protection. The shield renders content normally. For debugging and layout work only.
    case disabled

    /// DEFAULT. Renders protected content into an AVSampleBufferDisplayLayer with
    /// `preventsCapture = true`, over an opaque black shield.
    ///
    /// ⚠️ DEVICE-PENDING. On Simulator this strategy makes the layer paint NOTHING AT ALL,
    /// including on screen — protected regions appear empty. That is a fail-closed behaviour,
    /// not a leak, and it is the expected Simulator result. See docs/api-contract.md §3.2.2.
    case publicPreventsCaptureLayer

    /// OPT-IN, OFF BY DEFAULT. Reparents the protected content's layer into a private
    /// `_UITextLayoutCanvasView` descendant.
    ///
    /// ⚠️ PRIVATE API. Non-contract. Fragile across iOS releases. App Review risk.
    /// Read docs/api-contract.md §9 before enabling. Never a security guarantee.
    case privateSecureLayer
}
```

```swift
/// How often the shield re-rasterises its protected content. iOS 15-compatible.
public enum ScreenGuardRefreshPolicy: Equatable, Sendable {
    /// Refresh only when `setNeedsContentRefresh()` is called. Cheapest. Default.
    case manual
    /// Refresh on bounds or trait changes.
    case onLayout
    /// Refresh on a timer. Measured cost on the public path: enqueue median 4.0–6.5 ms per frame,
    /// CPU 4.2–7.1 ms per frame (docs/evidence/capability-matrix.md §6). The measured achieved rate
    /// was 42–47 fps as a FLOOR; no maximum is claimed.
    case periodic(TimeInterval)
}
```

```swift
/// Hosts content that must not leak into captures.
///
/// The shield is the no-leak container. Content is supplied either as a live view or as a render
/// closure. On `.publicPreventsCaptureLayer` the content is RASTERISED and pushed to the protected
/// layer, so it is a refreshed snapshot rather than a live view — see the note below.
/// iOS 15-compatible.
@MainActor
public final class ScreenGuardShieldView: UIView {

    public init(strategy: ScreenGuardNoLeakStrategy = .publicPreventsCaptureLayer)

    /// Live content to protect. Rasterised on refresh when the strategy is
    /// `.publicPreventsCaptureLayer`; hosted directly when it is `.privateSecureLayer`.
    public var protectedContentView: UIView? { get set }

    /// Alternative content source for content that is not a UIView (e.g. SwiftUI).
    /// Called on the main actor with the target size and screen scale.
    public var protectedContentRenderer: ((CGSize, CGFloat) -> UIImage?)? { get set }

    /// Colour behind the protected layer. Default `.black` — this is what turns "pixels removed"
    /// into the "region is black" the product promise is written in.
    public var shieldColor: UIColor { get set }

    public var refreshPolicy: ScreenGuardRefreshPolicy { get set }

    /// `true` only when the selected strategy is actually engaged. `false` when `.disabled`, and
    /// `false` when a private-path swap failed. Check this — do not assume.
    public private(set) var isProtecting: Bool { get }

    /// The strategy actually in effect, which may differ from the requested one if the requested
    /// strategy is unavailable on this OS build.
    public private(set) var effectiveStrategy: ScreenGuardNoLeakStrategy { get }

    /// Non-nil when protection failed to engage. Also emitted as
    /// `ScreenGuardEvent.Kind.protectionDegraded`.
    public private(set) var protectionFailure: ScreenGuardProtectionFailure?

    /// Re-rasterises the protected content. Required after content changes under `.manual`.
    public func setNeedsContentRefresh()
}
```

> **Rasterisation limit (must be documented wherever the shield is described).** On
> `.publicPreventsCaptureLayer`, the protected content is rendered to an image and pushed through the
> `CMSampleBuffer → layer` pipeline. It is therefore a **refreshed snapshot**, not a live view:
> animations and direct interaction inside a protected region do not update unless the refresh policy
> or `setNeedsContentRefresh()` causes a re-render. The `.privateSecureLayer` path keeps the content
> live. This is a real trade-off between the public and private paths and must be stated, not hidden.

### 6.5 The measured public primitive — secure text field

```swift
/// A UITextField hardened for secrets the user ENTERS (PIN, password, one-time code).
///
/// This is the only mechanism in the package that is simultaneously public API, measured, and
/// unconfounded: its text is blanked in the app-side capture path while the field's dots remain
/// visible on the display (docs/evidence/capability-matrix.md §3 row 5).
///
/// SCOPE LIMIT — it protects THE FIELD'S OWN TEXT ONLY, never other views, and the on-screen
/// presentation is masked (dots). Do not use it to display a value the user must read.
/// iOS 15-compatible.
@MainActor
open class ScreenGuardSecureTextField: UITextField {

    /// Enforced `true`. Assigning `false` is ignored; use a plain UITextField if you need that.
    public override var isSecureTextEntry: Bool { get set }

    /// When `true` (default), copy / cut / paste / selection menus and the text-selection loupe
    /// are disabled, so the secret cannot be exfiltrated through the editing UI.
    public var isCopyProtected: Bool { get set }

    public override init(frame: CGRect)
    public required init?(coder: NSCoder)
}
```

### 6.6 Watermark

```swift
/// Pure tiling geometry. Separated from the view so it is unit-testable without a window.
/// iOS 15-compatible.
public struct ScreenGuardWatermarkLayout: Equatable, Sendable {

    /// Top-left origins of every tile needed to cover `bounds`, including the partial tiles on the
    /// right and bottom edges. Deterministic; independent of screen scale.
    public static func tileOrigins(in bounds: CGRect, tileSize: CGSize) -> [CGPoint]

    /// Number of tiles `tileOrigins(in:tileSize:)` returns.
    public static func tileCount(in bounds: CGRect, tileSize: CGSize) -> Int
}
```

```swift
/// Appearance and content of the forensic watermark.
///
/// A watermark is a DETERRENT AND FORENSIC measure. It removes no pixels from any capture and
/// prevents nothing. See docs/api-contract.md §3.3.
/// iOS 15-compatible.
public struct ScreenGuardWatermarkConfiguration {

    /// Primary mark, e.g. "CONFIDENTIAL".
    public var text: String

    /// Optional second line, e.g. a session or user identifier used for attribution.
    public var secondaryText: String?

    /// Tile pitch in points. Default `CGSize(width: 180, height: 120)`.
    public var tileSize: CGSize

    /// Tile rotation in radians. Default `-.pi / 6`.
    public var angle: CGFloat

    /// Tile opacity. Default `0.12`. Low values stay legible under the content.
    public var opacity: CGFloat

    public var color: UIColor
    public var font: UIFont

    /// Include a timestamp in each tile. Default `true`.
    public var includesTimestamp: Bool

    /// Date format for the timestamp. Default `"yyyy-MM-dd HH:mm:ss zzz"`.
    public var timestampFormat: String

    /// Supplies "now". Injectable so the layout is testable.
    public var timestampProvider: () -> Date

    public init(
        text: String,
        secondaryText: String? = nil,
        tileSize: CGSize = CGSize(width: 180, height: 120),
        angle: CGFloat = -.pi / 6,
        opacity: CGFloat = 0.12,
        color: UIColor = .label,
        font: UIFont = .systemFont(ofSize: 11, weight: .medium),
        includesTimestamp: Bool = true,
        timestampFormat: String = "yyyy-MM-dd HH:mm:ss zzz",
        timestampProvider: @escaping () -> Date = Date.init
    )
}
```

```swift
/// Draws a tiled forensic watermark over its own bounds. Non-interactive.
/// iOS 15-compatible.
@MainActor
public final class ScreenGuardWatermarkView: UIView {

    public init(configuration: ScreenGuardWatermarkConfiguration)

    /// Changing this re-draws the watermark.
    public var configuration: ScreenGuardWatermarkConfiguration { get set }

    /// Forces a re-draw (e.g. to advance the timestamp).
    public func refresh()
}
```

### 6.7 App-switcher snapshot protection

```swift
/// What is shown in place of the app's content while the scene is inactive.
/// iOS 15-compatible.
public enum ScreenGuardAppSwitcherStyle {
    /// A blur of the covered content. Default.
    case blur(style: UIBlurEffect.Style)
    /// A solid colour.
    case opaque(color: UIColor)
    /// A brand cover, e.g. a logo on the app's background colour.
    case branded(image: UIImage?, backgroundColor: UIColor)
}
```

```swift
/// Covers the window while the scene is inactive, so the system's app-switcher snapshot does not
/// contain app content.
///
/// ⚠️ DEVICE-PENDING. Snapshot pixels cannot be decoded on Simulator (docs/TOOLING.md §4), so this
/// capability is device-validated only. See docs/api-contract.md §3.4.
/// iOS 15-compatible.
@MainActor
public final class ScreenGuardAppSwitcherShield: UIView {

    public init(style: ScreenGuardAppSwitcherStyle = .blur(style: .systemMaterial))

    public var style: ScreenGuardAppSwitcherStyle { get set }

    /// Installs the shield on `window` and begins observing scene lifecycle notifications
    /// (UISceneWillDeactivateNotification / UISceneDidActivateNotification). Idempotent.
    public func install(on window: UIWindow)

    /// Removes the shield and every observer.
    public func uninstall()

    public private(set) var isInstalled: Bool
}
```

**Mechanism requirement.** The cover must be installed **synchronously** on
`UISceneWillDeactivateNotification` — the system snapshots immediately afterwards. An asynchronous or
deferred cover is a defect. Where the host uses SwiftUI, `.screenGuardAppSwitcherProtected()` and
SwiftUI's own `privacySensitive()` are both available; `privacySensitive()` is the system-supported
hint and must be mentioned in the docs as the zero-configuration alternative.

### 6.8 SwiftUI surface

All modifiers are **iOS 15-compatible** — no availability guard is required.

```swift
extension View {

    /// Marks this view's content as sensitive and shields it from leaking into captures.
    ///
    /// SwiftUI content is not a `UIView`, so this modifier supplies the shield with a **render
    /// closure** and the content is rasterised on every strategy: it is a refreshed snapshot, not a
    /// live view (§13 A3). For content that must stay genuinely live, give `ScreenGuardShieldView` a
    /// `protectedContentView` — a live view is the only content source the shield does not rasterise.
    ///
    /// With `.publicPreventsCaptureLayer` (default) the rendered image is pushed into the protected
    /// display layer — see ScreenGuardShieldView's rasterisation note. With `.privateSecureLayer` the
    /// image is hosted as a **live subview inside the shield**, which is what places it under the
    /// private exclusion; §9 applies in full (opt-in, non-contract, App Review risk, never a security
    /// guarantee).
    ///
    /// ⚠️ History, because it is the reason §13 A3 exists: this route used to report
    /// `isProtecting = true` / `shieldMode = .privateSecureLayer` / `protectionFailure = nil` while
    /// rendering NOTHING on the private strategy — a blank card with a success claim on top. The
    /// wording here claimed "the content stays live", which was measured FALSE. Both are repaired;
    /// the route is now measured end to end by `Scripts/verify_capture.sh` §3b.
    ///
    /// - Parameter onProtectionFailure: Called when the mechanism could not be engaged, so the caller
    ///   can surface the degraded state instead of believing the content is protected.
    public func screenGuardProtected(
        strategy: ScreenGuardNoLeakStrategy = .publicPreventsCaptureLayer,
        refreshPolicy: ScreenGuardRefreshPolicy = .manual,
        onProtectionFailure: ((ScreenGuardProtectionFailure) -> Void)? = nil
    ) -> some View

    /// Overlays a tiled forensic watermark. DETERRENT AND FORENSIC ONLY — removes no pixels.
    public func screenGuardWatermarked(
        _ configuration: ScreenGuardWatermarkConfiguration
    ) -> some View

    /// Covers this view (or the window) while the scene is inactive, protecting the
    /// app-switcher snapshot. Device-pending — see §3.4.
    public func screenGuardAppSwitcherProtected(
        style: ScreenGuardAppSwitcherStyle = .blur(style: .systemMaterial)
    ) -> some View
}
```

```swift
/// Reads the shared (or supplied) monitor and rebuilds when its state changes.
/// iOS 15-compatible.
public struct ScreenGuardMonitorView<Content: View>: View {

    /// Pass `nil` to use `ScreenGuard.shared`.
    public init(
        monitor: ScreenGuardMonitor? = nil,
        @ViewBuilder content: @escaping (ScreenGuardState) -> Content
    )

    public var body: some View
}
```

**Design note.** The `monitor` parameter is optional rather than defaulted to `ScreenGuard.shared`
deliberately: a default argument referencing a `@MainActor` global is not usable from a nonisolated
initializer. Resolving it inside `body` (which is main-actor isolated) keeps the call site clean.

**Explicit non-goal.** The package does **not** vend `EnvironmentValues` keys. State reaches SwiftUI
through `ScreenGuardMonitor` (`@ObservedObject` / `@StateObject` / `ScreenGuardMonitorView`), which is
the idiomatic seam and avoids duplicating the state machine.

### 6.9 SwiftUI display ergonomics — a verified trap (binding on t4)

`ScreenGuardCaptureState`, `ScreenGuardDetectionSource` and `ScreenGuardProtectionFailure` are
`String`-raw-valued and **do not conform to `CustomStringConvertible`**, because conforming does not
help: SwiftUI's `Text("\(value)")` uses `LocalizedStringKey.StringInterpolation`, and any interpolated
value that is not a `String` (or another type `LocalizedStringKey` supports) produces a
**deprecation error** at the deployment target:

```
error: 'appendInterpolation' is deprecated: Localized string interpolation produces an unlocalized,
debug description for this type of value. Use a type supported by LocalizedStringKey.StringInterpolation…
```

Verified by compiling both forms against the iOS 27.0 SDK at `-target arm64-apple-ios15.0` with
`-warnings-as-errors`:

| Form | Result |
|---|---|
| `Text("Capture: \(state)")` | ❌ deprecation **error** |
| `Text("\(state.rawValue)")` | ✅ clean |
| `Text(String(describing: state))` | ✅ clean |
| `Text("\(state.isMonitoring)")` (a `Bool`) | ❌ deprecation **error** |
| `Text(state.isMonitoring ? "ON" : "OFF")` | ✅ clean |

**Rule for t4 and every SwiftUI consumer:** display these values through `.rawValue` (or an explicit
`String`), never by bare interpolation. This matters because the demo's headline requirement is to
show *live capture-detection state* — the most natural way to write that is the one that does not
compile cleanly.

---

## 7. Availability strategy

### 7.1 Detection: iOS 17+ primary, iOS 15/16 fallback

`UITraitCollection.sceneCaptureState` is the modern signal. It is **iOS 17.0+**, so it is used inside
a guard, and the deprecated-adjacent legacy signal is used only in the `else` branch.

```swift
// ScreenGuardCaptureStateObserver — the shape every implementation must follow.
// VERIFIED: this file compiles clean with -warnings-as-errors at BOTH -target arm64-apple-ios15.0
// and -target arm64-apple-ios26.0 against the iOS 27.0 SDK.

@MainActor
final class ScreenGuardCaptureStateObserver {

    // NOTE: `any UITraitChangeRegistration` is itself iOS 17.0+, so it CANNOT be the type of a
    // stored property at an iOS 15 deployment target. Store it as `Any?` and cast at use site.
    private var registration: Any?
    private var legacyObserver: NSObjectProtocol?
    private weak var view: UIView?

    func start(view: UIView) {
        self.view = view
        if #available(iOS 17.0, *) {
            // PRIMARY (iOS 17+). Registers for the scene-capture trait; no polling, no notification.
            registration = view.registerForTraitChanges(
                [UITraitSceneCaptureState.self]
            ) { (env: UIView, _: UITraitCollection) in
                MainActor.assumeIsolated { self.publish(env.traitCollection.sceneCaptureState) }
            }
        } else {
            // FALLBACK (iOS 15/16). Used ONLY here. The screen comes from the window scene —
            // never UIScreen.main, which is hard-deprecated in iOS 26.0.
            let screen = view.window?.windowScene?.screen
            legacyObserver = NotificationCenter.default.addObserver(
                forName: UIScreen.capturedDidChangeNotification,
                object: screen,
                queue: .main
            ) { [weak self] _ in
                // The closure is nonisolated; hop back explicitly to keep actor isolation honest.
                MainActor.assumeIsolated { self?.publishLegacy(screen?.isCaptured ?? false) }
            }
            publishLegacy(screen?.isCaptured ?? false)
        }
    }

    func stop() {
        if #available(iOS 17.0, *), let reg = registration as? any UITraitChangeRegistration {
            view?.unregisterForTraitChanges(reg)
        }
        registration = nil
        if let legacyObserver { NotificationCenter.default.removeObserver(legacyObserver) }
        legacyObserver = nil
    }

    @available(iOS 17.0, *)
    private func publish(_ state: UISceneCaptureState) {
        switch state {
        case .active, .inactive, .unspecified: break
        @unknown default: break          // never crash on a future OS value
        }
    }

    private func publishLegacy(_ isCaptured: Bool) {
        publish(isCaptured ? .active : .inactive)
    }
}
```

**Two traps in this snippet, both verified by compiling it.** They are called out because they are the
natural way to write this code and both fail:

1. **`any UITraitChangeRegistration` cannot be a stored property** at an iOS 15 deployment target —
   the type itself is iOS 17.0+ (`error: 'UITraitChangeRegistration' is only available in iOS 17.0 or
   newer`). Store `Any?` and cast inside the guard.
2. **A notification closure is nonisolated.** Calling a `@MainActor` method from it is a warning
   (an error under `-warnings-as-errors`): *"call to main actor-isolated instance method … in a
   synchronous nonisolated context"*. Even with `queue: .main`, the closure is not actor-isolated, so
   hop explicitly (`MainActor.assumeIsolated`, or `Task { @MainActor in … }`).

**Rules.**

1. On iOS 17+, the legacy `UIScreen` observer is **not installed at all** — one signal, one event,
   no double-reporting.
2. `UISceneCaptureState` is switched **exhaustively with `@unknown default`** so a future OS value
   degrades to `.unspecified` instead of crashing.
3. `UIScreen.capturedDidChangeNotification`'s `object` is a `UIScreen`; the observer is registered with
   that specific object, and the `UIScreen` instance comes from `window.windowScene?.screen`
   (**never** `UIScreen.main` — see §7.3).
4. Every observer and trait registration is removed in `stop()`. No retain cycles: the trait
   registration token is stored and passed to `unregisterForTraitChanges(_:)`.
5. **`view.window` may be `nil` at `start()` time** (the view is not yet in a hierarchy). If the
   resolved screen is `nil`, registering with `object: nil` would observe *every* screen — a
   correctness bug on multi-scene apps. The observer must therefore re-resolve the screen when the
   view moves to a window (`didMoveToWindow`) and re-register if it changed. Do not silently fall
   back to `object: nil`.
6. The iOS 17 trait registration is made against the **view** (a `UITraitEnvironment`). If no view is
   available, register against the `UIWindowScene`, which also conforms to `UITraitChangeObservable`.

### 7.2 Deprecated symbols — every one, and its guard

Verified by compiling the exact idioms at `-target arm64-apple-ios15.0` and
`arm64-apple-ios26.0` with `-warnings-as-errors` (Xcode 27.0 / iOS 27.0 SDK).

| Symbol | Availability | Deprecation (from the SDK headers) | Guard required | Verified |
|---|---|---|---|---|
| `UITraitCollection.sceneCaptureState` | iOS 17.0+ | — | `if #available(iOS 17.0, *)` | ✅ |
| `UISceneCaptureState` (+ `.unspecified/.inactive/.active`) | iOS 17.0+ | — | same guard | ✅ |
| `UITraitSceneCaptureState` | iOS 17.0+ | — | same guard | ✅ |
| `registerForTraitChanges(_:handler:)` | iOS 17.0+ | — | same guard | ✅ (also `@MainActor`) |
| `UIScreen.isCaptured` | iOS 11.0+ | **soft**: `API_DEPRECATED(..., ios(11.0, API_TO_BE_DEPRECATED))` | used **only** in the `else` branch | ✅ **no warning** at iOS 15 *or* iOS 26 deployment target |
| `UIScreen.capturedDidChangeNotification` | iOS 11.0+ | **not deprecated** | used only in the `else` branch | ✅ |
| `UIScreen.main` | iOS 2.0+ | **HARD-deprecated iOS 26.0** — *"Use a UIScreen instance found through context instead (i.e, view.window.windowScene.screen)"* | **FORBIDDEN — do not use at all** | ✅ **warns** at an iOS 26 target |
| `UIWindowScene.screen` | iOS 13.0+ | not deprecated | none needed at iOS 15 | ✅ |
| `AVSampleBufferDisplayLayer.preventsCapture` | iOS 13.0+ | **not deprecated** | none needed at iOS 15 | ✅ |
| `AVSampleBufferDisplayLayer.sampleBufferRenderer` | iOS 17.0+ | — | `if #available(iOS 17.0, *)` | ✅ |
| `…DisplayLayer.status` / `.error` / `.flush()` / `.enqueueSampleBuffer(_:)` / `.isReadyForMoreMediaData` / `.requiresFlushToResumeDecoding` / `.timebase` | iOS 8.0–14.5+ | **HARD-deprecated iOS 18.0** — *"Use sampleBufferRenderer's … instead"* | used **only** in the `else` branch of the iOS 17 guard | ✅ **no warning** at an iOS 26 target *when guarded* |
| `UIApplication.userDidTakeScreenshotNotification` | iOS 7.0+ | not deprecated | none needed | ✅ |
| `UISceneWillDeactivateNotification` / `UISceneDidActivateNotification` | iOS 13.0+ | not deprecated | none needed | ✅ |
| `View.privacySensitive()` / `.redacted(reason:)` | iOS 15.0+ | not deprecated | none needed | ✅ |
| `EnvironmentValues.scenePhase` | iOS 14.0+ | not deprecated | none needed | ✅ |

**Conclusion, stated explicitly:** no deprecated symbol is reachable on iOS 15/16 (or on any OS) without
an availability guard. `UIScreen.isCaptured` and `UIScreen.capturedDidChangeNotification` appear only
inside the `else` branch of `if #available(iOS 17.0, *)`; the deprecated `AVSampleBufferDisplayLayer`
members appear only inside the `else` branch of the same guard. `UIScreen.main` is banned outright.

### 7.3 Two findings that extend `docs/TOOLING.md`

These were measured while writing this contract and are **not** recorded in `docs/TOOLING.md` §6 or
§7 (the latter, added by the captain, independently re-verifies the `preventsCapture` and
`CALayer.render` findings — see §7.1/§7.2 there, and §4/§5 of the capability matrix). They should be
appended to `docs/TOOLING.md` by a member who owns that file.

1. **`UIScreen.main` is hard-deprecated as of iOS 26.0.** `TOOLING.md` §6 correctly identifies
   `isCaptured` as the legacy signal, but the canonical way to *reach* it — `UIScreen.main` — now
   warns: `'main' was deprecated in iOS 26.0: Use a UIScreen instance found through context instead
   (i.e, view.window.windowScene.screen)`. The package must obtain the screen from
   `window.windowScene?.screen`.
2. **`isCaptured` itself is only *soft*-deprecated.** Its header says
   `API_DEPRECATED("Use the sceneCaptureState in UITraitCollection instead.", ios(11.0, API_TO_BE_DEPRECATED))`.
   Verified: compiling `screen.isCaptured` produces **no diagnostic** at either an iOS 15 or an iOS 26
   deployment target, including with `-warnings-as-errors`. So the t3 acceptance criterion "zero
   deprecation warnings at deployment target iOS 15" is satisfiable — but the guard must stay, because
   `API_TO_BE_DEPRECATED` means a future SDK will assign a version.

A third, related fact: **the iOS 17 availability guard also silences the iOS 18 deprecations.**
`AVSampleBufferDisplayLayer.status` and friends are deprecated in iOS 18.0, but using them inside the
`else` branch of `if #available(iOS 17.0, *)` compiles clean at an iOS 26 deployment target with
`-warnings-as-errors`. This is why the guard boundary is 17.0 and not 18.0.

---

## 8. Per-capture-path technique table

Derived from `docs/evidence/capability-matrix.md` §3, §4 and §5 — **not from assumption**. "Which
technique delivers the no-leak guarantee" has a different answer per path, and the differences must
not be averaged away.

| Capture path | How it is observed | Technique delivering no-leak | Status | Confidence |
|---|---|---|---|---|
| **Screenshot** (system render-server read; proxied app-side by `window.drawHierarchy(in:afterScreenUpdates: false)`) | `drawHierarchy` | **Secure `UITextField`** — `TEXT-BLANKED 0/1068`, dots visible on display (`19.02%`), calibration band proves the path images text (`205/1068`). **Public, but the field's own text only.** | **measured** | High |
| **Screenshot**, arbitrary content | `drawHierarchy` | **Private secure-layer swap** — sentinel `(200,0,160)` in the capture while the display shows the real colour `(38,102,242)`; swap-disabled control band leaks on both paths. **The only measured mechanism for arbitrary content.** | **measured**, private | High |
| **Screenshot**, arbitrary content, public path | `drawHierarchy` | `AVSampleBufferDisplayLayer.preventsCapture` + black shield | **device-pending** | **None — unmeasurable on Simulator** |
| **Screen recording** (`RPScreenRecorder.startCapture`) | ReplayKit callbacks | **None claimed.** `startCapture` returned `isAvailable=true` and fired its completion with no error, then delivered **zero callbacks in 30 s** (`video=0 audioApp=0 audioMic=0`). `startRecording` reported `isRecording=true` with no frames. | **not measured — requires device** | **None** |
| **Mirroring / AirPlay** | `UIScreen.isCaptured` / `sceneCaptureState` | **None claimed.** Same signal as recording; never observed true on Simulator. | **not measured — requires device** | **None** |
| **App-switcher snapshot** | `SplashBoard/Snapshots/**/*.ktx` | Scene-deactivation cover; SwiftUI `privacySensitive()` | **device-pending** | None — KTX not decodable |
| **Host-side capture** (`xcrun simctl io screenshot`, sim-use `screenshot`/`record-video`) | Host display read | **Nothing. Not protected by design** — bypasses the render server entirely. | **not possible** | High (this is the documented bypass) |
| **In-process `CALayer.render(in:)`** | Direct layer-tree walk | **Nothing.** Measured to defeat *both* the secure text field (`TEXT-LEAKED 184/1068`) and the secure-layer swap (`LEAKED (38,102,242)`), because it never goes through the render server and does not honour capture exclusion. | **known gap** | High |

**Reading rule.** `drawHierarchy` and `layer.render` disagree on bands 3, 4 and 5
(`capability-matrix.md` §5). `drawHierarchy` is the faithful screenshot proxy because it goes through
the render server and therefore reproduces the documented secure-field behaviour. **Never generalise
one path's result to another, and never average them.**

---

## 9. The private secure-layer path

### 9.1 What it is

`ScreenGuardNoLeakStrategy.privateSecureLayer` reparents the protected content's layer into a private
`_UITextLayoutCanvasView` descendant — the canvas UIKit uses to keep a secure text field's content out
of captures. It is the **only mechanism measured to exclude arbitrary content from a capture while
still painting it on the display**.

### 9.2 Why it is off by default

Because it depends on a **private UIKit class name**. `_UITextLayoutCanvasView` is not contract. Apple
may rename, restructure or remove it in any iOS release. When that happens the swap silently fails —
which is exactly why the shield must report `protectionFailure = .privateSecureLayerUnavailable` and
emit `ScreenGuardEvent.Kind.protectionDegraded`. **A no-leak mechanism that fails silently is worse
than no mechanism**, because the host app will believe it is protected.

The default is `.publicPreventsCaptureLayer`. A caller reaches the private path only by naming it
explicitly at the call site, where its doc comment carries the warning.

### 9.3 App Review risk

Using a private API can cause **App Review rejection** and, in the worst case, removal from the App
Store. The class name is matched by string, so the string literal is present in the compiled binary
regardless of whether the runtime flag is ever set. **App Review exposure is a compile-time property,
not a runtime one** — enabling the flag at runtime does not add exposure, and leaving it off does not
remove it. This must be stated in the README and in the file header, not buried.

### 9.4 Escape hatch — a package trait, disabled by default

**Primary mechanism (consumer-actionable).** All private-API code is gated behind an SPM package
trait named `PrivateAPI`, which is **not** in `default(enabledTraits:)`. A consumer who must not
ship the private class name enables nothing and the private code is never compiled:

```swift
// Consumer's own Package.swift — opt IN to the private path:
.package(url: "…/ScreenGuard.git", from: "1.0.0", traits: ["PrivateAPI"])

// Or leave the trait out entirely (the default) and no private code is compiled at all.
```

Verified behaviour of this mechanism:

| Consumer manifest | `_UITextLayoutCanvasView` in the compiled module |
|---|---|
| Trait not enabled (default) | **0 everywhere** — `.o`, `.swiftmodule`, `.swiftdoc`, and across the entire build directory (captain-reverified after the §13 A2 repair). The name now exists in exactly one place: a string literal inside the trait-gated file. |
| `traits: ["PrivateAPI"]` | present (`.o` = 1) |

A whole-directory grep for the private class name in a default build is therefore honest with no
caveat — which it was **not** before A2, when three always-compiled files named the class in doc
comments and those comments reached the generated `.swiftdoc`.

This is the property the previous revision could not deliver. `exclude:` and `swiftSettings:` exist
**only on a package's own target declarations**; `PackageDependency` exposes no API that configures
a dependency's targets. So instructing a consumer to exclude a file inside this package was **not
actionable** for a normal SPM consumer — their only recourse would have been to fork or vendor it.
The trait makes the choice theirs, in one line of their own manifest.

**Secondary mechanism (author-side only).** When building this package from a checkout — i.e. a
fork, a vendored copy, or this repository's own CI — the private file can additionally be excluded:

```
exclude: ["Shield/ScreenGuardPrivateSecureLayer.swift"],
swiftSettings: [.define("SCREENGUARD_NO_PRIVATE_SECURE_LAYER")]
```

Both halves are required, because Swift has no "this file was excluded" conditional. This path is
**not available to a normal SPM consumer** and must never be documented as though it were.

**Requirements and consequences of the trait approach.**

- `swift-tools-version` must be **6.1 or later**; package traits do not exist in 5.9.
- Raising the tools version **enables the Swift 6 language mode by default**, which surfaced two
  genuine concurrency errors in this codebase (a nonisolated mutable global in
  `ScreenGuardPrivateSecureLayerSupport.swift`, and a `sending`-region data-race risk in
  `ScreenGuardObserverTokenStore.swift`). The target therefore pins
  `.swiftLanguageMode(.v5)` to keep Swift 5 semantics; this was verified to build clean with no
  source changes. Migrating the source to the Swift 6 language mode is separate, future work and is
  not required by this contract.
- In the `Package` initialiser, `products:` must precede `traits:` or the manifest fails to parse.
- Enabling the trait must be **observable at runtime** so a host app can prove the private code is
  or is not in its binary: `ScreenGuard.PrivateAPI.isCompiledIn` reports it, and the shield degrades
  to the labelled detection-and-overlay fallback with
  `protectionFailure = .privateSecureLayerUnavailable` when the trait is absent.

Whichever mechanism is used, the degradation behaviour is identical: the private strategy becomes
unavailable, the shield reports `protectionFailure = .privateSecureLayerUnavailable`, and it falls
back to the labelled detection-and-overlay path rather than failing silently.

### 9.5 Non-negotiable wording rules

The private path must **never** be described as: secure, guaranteed, safe, recommended, production-ready,
or App-Store-safe. It **must** be described as: opt-in, off by default, private API, non-contract,
fragile across iOS releases, App Review risk, not a security guarantee.

---

## 10. Threading, lifecycle and safe defaults

| Rule | Requirement |
|---|---|
| Main actor | Every public type is `@MainActor`. `ScreenGuardMonitor`, all views, and the delegate protocol deliver on the main thread. No public API may be called off the main thread. |
| Idempotence | `start()`, `stop()`, `install(on:)`, `uninstall()` and `setNeedsContentRefresh()` are idempotent and safe to call repeatedly. |
| Cleanup | `stop()` / `uninstall()` remove **every** observer and trait registration. `deinit` must not require manual cleanup. |
| No retain cycles | The delegate is held **weakly**. Trait registrations and notification tokens are stored and released. |
| Safe default — protection | `noLeakStrategy` defaults to `.publicPreventsCaptureLayer`. The private path is **never** the default. |
| Safe default — failure | Failure to engage protection is **reported** (`isProtecting == false`, `protectionFailure`, `protectionDegraded` event), never silent. |
| Safe default — fail closed | On Simulator, `.publicPreventsCaptureLayer` makes protected regions paint nothing. That is **fail-closed and expected**; it must be documented so it is not mistaken for a bug or a leak. |
| No global mutation without opt-out | The app-switcher cover is installed on the key window when `isAppSwitcherShieldEnabled` is `true` (default). Hosts that manage scenes themselves disable it explicitly. |
| Availability | Every symbol follows §7.2. No deprecated symbol without a guard. |
| Dependencies | Zero third-party dependencies; system frameworks only. |
| Network | None, ever (§6.3). |

---

## 11. What each downstream task must honour

- **t3 (implementation).** Implement exactly the signatures in §6, the guards in §7.2, the defaults in
  §10. Every public symbol gets a doc comment. `capabilityStatuses` must return §4. The private file
  carries a header stating: private UIKit class name, not contract, App Review risk. **Copy §7.1's
  observer shape as written** — its two traps (the iOS 17-only `UITraitChangeRegistration` type and the
  nonisolated notification closure) are verified compile failures, not stylistic preferences.
- **t4 (example + scripts).** The demo must show the no-leak outcome **and** the capability status
  table from §4, so the demo cannot imply prevention. `verify_capture.sh` must not report a PASS from a
  host-side capture (`docs/TOOLING.md` §2) and must print the device-required checks as device-required.
  **Display live state via `.rawValue`, never bare interpolation** (§6.9) — the obvious
  `Text("\(state)")` form is a deprecation error.
- **t5 (verification).** The no-leak claim is tested from `drawHierarchy` or `RPScreenRecorder` only. A
  deliberate falsification attempt is required — the secure-layer swap's own disabled control band is
  the natural one, since it must read `LEAKED`. Confirm §7.2's guards by reading the source, and
  confirm the package contains no networking.
- **t6 (review).** A blocking finding if any wording claims prevention, if the private path is on by
  default, if a deprecated symbol is unguarded, or if the no-leak guarantee is asserted as blanket
  rather than scoped per capture path.
- **t7 (README).** Lift §4 verbatim as the capability matrix. State prominently that iOS does not allow
  an app to prevent a screenshot or recording, and that the guarantee is no leakage (protected regions
  appear black). Link `docs/evidence/capability-matrix.md` so the claims are auditable.

---

## 12. Source of every claim in this document

| Claim | Source |
|---|---|
| Secure text field blanks its text in `drawHierarchy`; dots visible on display; calibration band images text | `docs/evidence/capability-matrix.md` §3 row 5, row 7 |
| Private secure-layer swap blanks arbitrary content, unconfounded | `capability-matrix.md` §3 row 4, row 6; §4 |
| `preventsCapture = true` paints nothing at all on Simulator; row 8's NO-LEAK is unearned | `capability-matrix.md` §4 |
| Recording path delivered zero frames in 30 s; `isCaptured` stayed false | `capability-matrix.md` §7 |
| Pipeline fidelity 3.77/255; enqueue 4.0–6.5 ms; CPU 4.2–7.1 ms/frame; 42–47 fps is a floor | `capability-matrix.md` §6 |
| `drawHierarchy` vs `layer.render` disagree; `layer.render` defeats both protections | `capability-matrix.md` §5 |
| App-switcher KTX not decodable; host-side capture bypasses protection; screenshot cannot be triggered on Simulator | `docs/TOOLING.md` §2, §4 |
| `swift build` fails for this iOS-only package | `docs/TOOLING.md` §1 |
| Availability, deprecation and guard behaviour of every symbol in §7.2 | Compiled directly against the iOS 27.0 SDK at `-target arm64-apple-ios15.0` and `-target arm64-apple-ios26.0` with `-warnings-as-errors` (this document) |

---

## 13. Amendment ledger

### A1 — Escape hatch changed from file-exclusion to a package trait

**Date:** 2026-10-02 · **Author:** captain (not the contract's original author, `architect`)

**What changed:** §1 rule 1, §1 rule 4, §2 dependency table, §9.4.

**Why:** The original §9.4 told a consumer to exclude
`Sources/ScreenGuard/Shield/ScreenGuardPrivateSecureLayer.swift`. That instruction is **not
actionable** for a normal SPM consumer. Verified against the real SPM API surface
(`PackageDescription.swiftinterface`): `exclude:` and `swiftSettings:` exist only on a package's
**own** target declarations, and `PackageDependency` exposes no API that configures a dependency's
targets. A consumer's only recourse would have been to fork or vendor the package — and the users
who most need the private string absent (regulated/financial apps) are exactly the ones for whom
forking is least acceptable.

**Replacement:** an SPM package trait `PrivateAPI`, **not** enabled by default. Verified end to end:

| Consumer manifest | `_UITextLayoutCanvasView` in the compiled module |
|---|---|
| Trait not enabled (default) | **0 everywhere** (`.o`, `.swiftmodule`, `.swiftdoc`, whole build directory) — see §13 A2 for the later repair that removed the doc-comment literals. |
| `.package(…, traits: ["PrivateAPI"])` | present (`.o` = 1) |

File-exclusion is retained only as an **author-side** mechanism (fork / vendored / CI builds), with
the contract now stating explicitly that it is not consumer-actionable.

**Consequence accepted:** `swift-tools-version` rises from 5.9 to **6.1** (traits require it), which
by default enables the Swift 6 language mode. That surfaced two genuine concurrency errors, so the
target pins `.swiftLanguageMode(.v5)` to preserve Swift 5 semantics. Verified to build clean with
**zero source changes**. Migrating the source to the Swift 6 language mode is explicitly deferred.

**Provenance of the verification:** captain, in throwaway packages, not in this repository's source.
The measurements are recorded in `docs/TOOLING.md` §6.7 (and §1.1 for the scheme-name consequence).
This amendment is **normative for t3-follow-up work**; the implementation in `Sources/` still
reflects the pre-amendment single-configuration design and must be updated to match.

### A2 — Repair round 2: the findings from independent review (t6)

**Date:** 2026-10-02 · **Author:** `examples` (repair, task t10); ledger entry and the doc-side
corrections by the captain.

**What changed:** `Sources/ScreenGuard/` (Shield + AppSwitcher + event model) and
`Tests/ScreenGuardTests/`. Two HIGH, three medium and four low findings from
`docs/evidence/review-round1.md` were closed.

**The two HIGH findings, and why they mattered:**

- **A real leak.** Switching strategy away from a live-content strategy left the protected content
  in the **live** view hierarchy while the shield still reported `isProtecting = true`. On a device
  that means sensitive content appearing in a real screenshot while the shield claims protection —
  the exact failure this package exists to prevent. `teardown()` now always detaches, and content is
  re-hosted only when `shieldMode` actually requires it live. Five tests cover it, including a pixel
  assertion and a counterpart test so the detach cannot be satisfied by never showing anything.
- **The private path could never report success, and could not be torn down.** The postcondition
  `canvas.layer === host.layer` was evaluated *after* the canvas layer had been restored, so it was
  unreachable on the working path; the shield then reported the inverse of the truth
  (`detectionAndOverlayFallback`, documented as "removes no pixels") plus a spurious
  `protectionDegraded` on every attempt, and because the engaged state was never recorded,
  `disengage()` could never restore the arrangement. The check now asserts what the measured
  sequence actually establishes, and a deinit-safe owner guarantees `teardown()`/`deinit` restore.

**Correction to A1's own claim.** A1 stated the default build contained "0 occurrences in build
products". That wording was wrong: `.swiftdoc` is a build product, and three **always-compiled**
files named the private class in doc comments, so it appeared 6 times there. The substantive claim
was always true (absent from `.o`, `.swiftmodule` and the shipped binary), but the wording was not,
and it was correctly flagged in review. The repair removed those doc-comment literals, so the
private class name now exists in exactly one place — a string literal inside the trait-gated file —
and **0 occurrences across an entire default build is now literally true, with no caveat.** The
captain re-verified this independently after the repair.

**Measured outcome:** build exit 0 with **0 warnings**; `xcodebuild test` → `Executed 124 tests,
with 11 tests skipped and 0 failures` (105 pre-existing unchanged + 19 new regression tests; the 11
skips are 6 pre-existing + 4 PRIVATEAPI-REQUIRED + 1 SCENE-REQUIRED, each with a stated reason).
`Scripts/verify_capture.sh` → `PASS 22 · FAIL 0 · FINDING 0 · SKIP 0 · DEVICE 4`, exit 0 — the
shield's self-report now reads `isProtecting=True`, and the previously reported FINDING is **gone
rather than reworded**, with the private path's pixels unchanged (app-side sentinel `200,0,160`
while the display reads the sensitive colour `38,102,242`).

**Falsification, so the new tests are demonstrably not vacuous:** against the pre-repair tree with
the trait enabled, **6 of 6** assertions fail — content live while `isProtecting == true`; the
ordinary layer-tree read returning the secret colour after switching to the public path;
`engage` = false with `.privateSecureLayerSwapFailed`; a stale `requestedStrategy`; the bridge
re-applying on every update; and `init(strategy: .privateSecureLayer)` never engaging on joining a
window.

**Accepted residual limitations, stated rather than implied:** the `install(on:)`-with-no-scene
branch is asserted only through its extracted predicate (`canCover(window:)`), because this test
host gives even a bare `UIWindow(frame:)` a scene; the four PRIVATEAPI tests skip inside the gate
(trait off by default) and were proven to run in a trait-enabled throwaway copy.

**Amendment-ledger note:** A1's own inScope handling had a defect — the auto-generated repair
contract lost `Sources/ScreenGuard/AppSwitcher/ScreenGuardAppSwitcherShield.swift`, which the F7
fix necessarily edits. The file was changed and declared in the task output; the omission was the
captain's contract error, not a scope violation by the implementer.

### A3 — Review round 2 outcome, and TWO OPEN findings recorded so they cannot be lost

**Date:** 2026-10-02 · **Author:** captain (recording `gate`'s t11 result).

**t11 verdict: pass.** 0 high, 0 blocker, 1 medium, 1 low; report at
`docs/evidence/review-round2.md`. **All nine round-1 findings are closed**, each re-derived from the
current source and, where an in-process check exists, from probes run against a throwaway
trait-enabled copy — including the two HIGHs: the strategy-switch leak (F1) and the private path
that could never report success nor be torn down (F2). End-to-end re-measurement by the reviewer:
`Scripts/verify_capture.sh` → `PASS 22 · FAIL 0 · FINDING 0 · SKIP 0 · DEVICE 4`, exit 0, with the
private path still reading NO-LEAK unconfounded and a withheld-opt-in falsification run reading
LEAKED.

**⚠️ OPEN FINDING F-R2-1 (medium) — the SwiftUI private path claims protection while rendering nothing.**
`screenGuardProtected(strategy: .privateSecureLayer)` supplies content only through
`protectedContentRenderer`, and the private strategy never displays renderer output. Probe P10
measured `isProtecting = true`, `mode = privateSecureLayer`, `failure = nil` with a **blank shield**
(centrePixel `0,0,0`). It is fail-closed — no leak and no false capture claim — which is why the
review passed. But a host app following the docs gets an empty card and **no signal**, and the
modifier doc plus §6.8 both promised "the content stays live", which is false on the only SwiftUI
route. **This contract's §6.8 and the modifier's doc comment have been annotated as false; the
README is barred from repeating the claim (see t7 acceptance criterion 6).** Recommended fix:
host the rasterised image live under the same exclusion, or refuse with a reported failure; correct
the doc claim; add a regression test. **✅ CLOSED — repaired in the round-3 repair recorded in §13 A4;
the recommended fix (host the rasterised image live under the same exclusion) is the one taken, and
the doc claim is corrected rather than reworded.**

**Two locations still carry the false claim and must be corrected in that repair** (deliberately
NOT edited here, because t7's final end-to-end verification must run on a frozen tree):
`Sources/ScreenGuard/SwiftUI/ScreenGuardModifiers.swift:27` — the `screenGuardProtected` doc
comment — and the SwiftUI route's behaviour itself. **✅ Both corrected in the round-3 repair (§13 A4).**

**⚠️ OPEN FINDING F-R2-2 (low) — §6.4/§6.2 lag the repaired public surface.**
`hasPushedFrame`, `shieldMode`, `onProtectionFailure`, `requestedStrategy` and the two new failure
cases (`.publicPreventsCaptureLayerUnavailable`, and the corrected private-path reporting) exist in
the source but are not described in the API-surface sections. Consumers reading §6 as the contract
will see an out-of-date surface. Not yet corrected. **Still open after the round-3 repair; the
round-3 repair widened `hasPushedFrame`'s doc comment in the source (it now says explicitly that it
stays `false` on `.privateSecureLayer` even when rendered content IS hosted, and that it answers only
"has a frame been pushed into the protected layer?"), but §6.4 still does not describe it.**

---

### A4 — F-R2-1 repaired: the SwiftUI private route now hosts the rendered content under the exclusion

**Date:** 2026-10-03 · **Author:** round-3 repair · **Closes:** F-R2-1 (§13 A3).

**The defect, re-derived from the source before any change was made.** `protectedContentRenderer` was
the SwiftUI bridge's ONLY content source (`ScreenGuardModifiers.swift`, `makeUIView`), while the
private path's hosting mechanism only ever consumed a live view
(`ScreenGuardShieldView.synchronizeContentHosting()` began with `guard let protectedContentView else
{ return }`). The `renderer × privateSecureLayer` cell of the support matrix was implemented by
neither side and reported by neither side, so the shield claimed `isProtecting = true` over an empty
region. The same hole covered `.disabled` and `.detectionAndOverlayFallback`, whose documented job is
to **show** the content: a renderer-fed shield was an opaque black card in those modes too.

**Route taken: host the render closure's output as a live subview.** The alternative — refusing with
a reported failure — was rejected as the primary fix because it is strictly worse for the consumer
(no protection where protection is available) and because it would not repair the
`.disabled`/fallback blank. `protectedContentView` still wins when supplied, and the hosting is torn
down on `.publicPreventsCaptureLayer` exactly as the live view is, so the public path's invariant
(review round 1, F1) is untouched.

**A SECOND DEFECT WAS UNCOVERED WHILE MEASURING THE FIRST — `protectedContentRenderer` returned
`nil`. Always. On every strategy.**

The shield change alone made the unit-test-shaped reproduction pass while the **real** route still
produced a black card. A probe against the real modifier measured the exact stage:

```
DIAG A shield bounds=(0.0, 0.0, 320.0, 178.0)  mode=disabled
DIAG B subviews=[]                                    <- nothing hosted
DIAG C renderer(bounds.size=(320.0, 178.0), 2) -> false
DIAG D renderer(100x50, 2) -> false
DIAG E renderer(100x50, 1) -> false
DIAG F renderer(100x50, 3) -> false
DIAG G direct rasteriser with Color(uiColor:) -> true   <- same rasteriser, called directly
DIAG H direct rasteriser with Color.red       -> true
```

The cause is a SwiftUI rule the modifier was written against:

```
DIAG 1  a ViewModifier's own `content`  -> ImageRenderer.uiImage != nil : false
DIAG 2  a wrapper view's STORED content -> ImageRenderer.uiImage != nil : true
```

`ScreenGuardProtectedModifier` was a `ViewModifier`, and a modifier's `body(content:)` hands back a
`_ViewModifier_Content` **placeholder**. That placeholder does not render on its own: `ImageRenderer`
produced no image from it at any size or scale. So `screenGuardProtected` never rasterised anything —
on `.publicPreventsCaptureLayer` too, which is the DEFAULT route.

**Why the public path never showed it on Simulator:** `preventsCapture = true` already makes that
layer paint nothing at all there (`docs/TOOLING.md` §7.1), so "the GPU layer is blank by design" and
"no frame was ever pushed" are indistinguishable in that region's pixels. The demo has reported that
band as `BLACK` since before this repair, and it is still reported as `DEVICE`-required rather than as
a pass, so nothing that was previously claimed is withdrawn — but the public path's rasterisation is
now measurable in-process for the first time, and it is asserted
(`testTheRealSwiftUIModifierRasterisesOnTheDefaultPublicStrategy`).

**The fix:** `screenGuardProtected` now builds a `ScreenGuardProtectedView` — a real `View` that
**stores** the content as a property — instead of a `ViewModifier`. Public API and call sites are
unchanged; the modifier type was internal.

**A third, smaller defect on the same path:** with `.manual` (the default) refresh policy, a
renderer-backed shield whose first render attempt happened while it was still zero-sized never tried
again, because only `.onLayout` re-rasterised. `layoutSubviews` now re-renders when
`lastRenderedSize != bounds.size`, which covers both "no render has succeeded yet" and "the size
changed". This is what makes the very first frame appear on BOTH the private path and the public one.

**Falsification — the new tests are RED before the repair, on the unfixed tree, with the FINAL test
file.** Two pristine copies of the pre-repair sources were kept for this (`/tmp/fr21-base` with the
trait off, `/tmp/fr21-trait` with it on); the final test file was copied into both:

```
default configuration (trait OFF):   Executed 7 tests, with 2 tests skipped and 7 failures
                                     -> all 5 running tests FAILED
trait-enabled configuration:         Executed 7 tests, with 10 failures
                                     -> all 7 tests FAILED
```

**After the repair:**

```
default configuration:   Executed 131 tests, with 13 tests skipped and 0 failures   TEST SUCCEEDED
trait-enabled copy:      Executed 131 tests, with  7 tests skipped and 0 failures   TEST SUCCEEDED
```

(the two private-path tests in this file RUN in the second configuration rather than skipping.)

**End-to-end pixel measurement, `Scripts/verify_capture.sh` §3b (new).** The documented route is now
measured with the package's own modifier, over a sentinel, with an unshielded SwiftUI control:

```
[PASS] SwiftUI control reads the sensitive colour (calibration)   app-side=38,102,242
[PASS] no-leak: the SwiftUI private route excludes the region from the capture
       app-side=200,0,160 -> SENTINEL (readable, and not the content colour)
[PASS] the SwiftUI route's excluded region is still VISIBLE on the display
       contrast=SENSITIVE — exclusion, not a non-painting layer
[PASS] the shield shows rendered content AND reports the private path engaged
       requested=privateSecureLayer mode=privateSecureLayer isProtecting=True hostsRenderedContent=True

PASS 29 · FAIL 0 · FINDING 0 · SKIP 0 · DEVICE 4 · exit 0
```

The unconfounded asymmetry is the same one `docs/evidence/capability-matrix.md` §3 row 4 uses to
credit the secure-layer swap: the region reads the SENTINEL in the app-side `drawHierarchy` read
while the host-side contrast — never evidence, `docs/TOOLING.md` §2 — still reads the sensitive
colour. "Not the content colour" alone would have been satisfied by a blank region; the third and
fourth checks are what rule that out. The pre-repair run of this section failed exactly those two.

**Deliberately NOT changed, and why.** A shield that is given NEITHER a live view NOR a render
closure still engages the private path and reports `isProtecting = true` while there is nothing to
protect. That is a different condition from F-R2-1 (it drops no supplied content — it has none), it is
the state `testShieldReattemptsPrivateEngagementWhenItJoinsAWindow` pins as the documented
`init(strategy: .privateSecureLayer)` behaviour, and changing it would make the shield refuse during
the legitimate "content arrives a moment later" window that `DemoShieldContainer.sync()` occupies.
It is recorded here as a residual rather than silently changed.


