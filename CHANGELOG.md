# Changelog

All notable changes to ScreenGuard are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> **No version has been released.** This repository has never been tagged and no GitHub Release
> exists. The `[1.0.0]` section below is a **development milestone** — it records where the work stood
> on that date — and must not be read as a published release. The release pipeline
> (`.github/workflows/release.yml`) is dormant until a `vX.Y.Z` tag is pushed, and nothing in this
> file creates one; the maintainer procedure is [`docs/PUBLISHING.md`](docs/PUBLISHING.md).

---

## [Unreleased]

### Changed

- **Formatting and linting are now enforced gates.** SwiftFormat and SwiftLint run in strict mode
  over the shipped library and its tests (`mise run format:check`, `mise run lint` —
  `swiftlint lint --strict`, where a warning is a failure), with every tool version pinned in
  [`.mise.toml`](.mise.toml), and both gates block in CI. Reaching a clean tree required one
  baseline commit: 62 files required formatting before it.
- **The reformat is behaviour-preserving, and that is measured rather than assumed.** On the
  reformatted tree, `mise run test` reports `Executed 131 tests, with 13 tests skipped and 0
  failures (0 unexpected)`, and the public surface is unchanged — **0 declarations added, 0
  removed** (310 declarations by `declKind`, 1220 named nodes on both revisions). The stronger
  check is the emitted library-evolution interface, not the digester dump alone: `@preconcurrency`
  appears **6 times in both revisions** and the `ScreenGuardShieldView` class line is byte-identical.
  The interface’s remaining deltas are grouping only: the order of the declaration blocks, and one
  extra extension block because setNeedsContentRefresh() now lives in the ScreenGuardShieldView+Refresh
  file rather than in the class body. Every declaration line — names, parameter names and signatures —
  is identical, so no symbol was renamed, added, removed or re-signatured.
  The one defect the reformat introduced was **not** caught by either signal: it sat in a file the
  test configuration does not compile, and only the trait-enabled demo build exposed it. The
  incident and its consequences for CI are recorded in [`docs/TOOLING.md`](docs/TOOLING.md) §12.
- **The demo and research harnesses' pre-existing lint debt is deferred explicitly, not silently
  excluded.** The blocking gate is scoped to `Sources` and `Tests`; the example app and the
  measurement harness are reported by `mise run lint:demo`, which is advisory by design and always
  exits 0 (currently `257 violations, 257 serious in 31 files`). Those files were deliberately kept
  outside the blocking gate rather than dropped from the configuration's scope, and the debt is
  enumerated rather than hidden.

### Fixed

- **The SwiftUI route now renders content on every strategy — three defects, one symptom.**
  `screenGuardProtected(...)` produced a black card with `isProtecting = true`,
  `shieldMode = .privateSecureLayer` and `protectionFailure = nil` on the private strategy, and
  nothing at all on `.disabled` and the labelled `.detectionAndOverlayFallback`, whose documented job
  is to *show* the content. Measuring the first defect surfaced two more behind it:
  - `ScreenGuardShieldView` never consumed `protectedContentRenderer`; the private path hosts a live
    view, so a renderer-fed shield had nothing to host. Render-closure output is now hosted as a live
    subview in the modes that display content, and torn down on `.publicPreventsCaptureLayer` exactly
    as a caller-supplied live view is, so the public path's no-live-content invariant is unchanged.
  - The SwiftUI rasteriser returned `nil` on **every** strategy, at every size and scale, because
    `ScreenGuardProtectedModifier` was a `ViewModifier` and a modifier's `content` is a
    `_ViewModifier_Content` placeholder that does not render on its own. It is now a wrapper `View`
    that stores the content as a property; public API and call sites are unchanged. This also affected
    the **default** public path, hidden on Simulator by the documented `preventsCapture` confound
    (`docs/TOOLING.md` §10.2).
  - With the default `.manual` refresh policy, a renderer-backed shield whose first render attempt
    happened while it was still zero-sized never tried again, so the first frame never appeared on any
    strategy. `layoutSubviews` now re-renders when the size the content was rendered at no longer
    matches.
- The `screenGuardProtected` documentation no longer claims "the content stays live" on the private
  strategy — measured false; SwiftUI content is rasterised on every strategy.

### Added

- `Scripts/verify_capture.sh` §3b measures the package's **own** SwiftUI entry point on the private
  strategy: the app-side capture read returns the sentinel while the host-side contrast still shows
  the content, and the shield must report `hostsRenderedContent = true` alongside
  `mode = .privateSecureLayer` / `isProtecting = true`, so a claim of protection over nothing fails
  the run. Backed by a new demo probe page (`-ProbeMode swiftUIPrivate`).
- `Tests/ScreenGuardTests/ScreenGuardRendererContentTests.swift` — 7 regression tests, RED on the
  pre-repair tree in every configuration where they run.

Full record, with the raw before/after output:
[`docs/evidence/repair-fr2-1.md`](docs/evidence/repair-fr2-1.md) and
[`docs/api-contract.md`](docs/api-contract.md) §13 A4.

---

## [1.0.0] — 2026-10-02 — development milestone, never tagged or published

**Never released.** This is the state of the work on that date: there is no `v1.0.0` tag and no
GitHub Release. `ScreenGuard.version == "1.0.0"` is the version string the source carried at that
point, not a snapshot anyone could download; the first tag will be the maintainer's to choose
([`docs/PUBLISHING.md`](docs/PUBLISHING.md)).

### The promise this version makes — and does not

**iOS does not allow an app to prevent the user from taking a screenshot or starting a screen
recording**, and this package does not claim to. Its guarantee is that **sensitive content does not
leak into captures; a protected region coming out black or blank in a capture is the success case**.
Capability statuses are `measured` / `device-pending` / `notMeasured` / `notPossible`, and prevention
of a screenshot or a recording is `notPossible` on every iOS version.

### Added

- **Detection (public API).** `ScreenGuardMonitor` with a unified `ScreenGuardEvent`
  (`.screenshotTaken`, `.captureBegan`, `.captureEnded`, `.protectionDegraded`), a delegate seam and a
  closure seam, plus `ScreenGuardCaptureState` (tri-state) and `ScreenGuardDetectionSource`.
  End-to-end event delivery is **device-pending** — the Simulator cannot fire a real screenshot.
- **No-leak blocking (public path).** `ScreenGuardShieldView` renders protected content into an
  `AVSampleBufferDisplayLayer` with `preventsCapture = true` over an opaque black shield.
  **Device-pending:** on Simulator the layer paints nothing at all, so a black reading is unearned;
  the strategy is fail-closed, not a proven guarantee yet.
- **No-leak blocking (measured public primitive).** `ScreenGuardSecureTextField` (enforced
  `isSecureTextEntry`, copy protection). **Measured:** the field's own text is blanked in the
  app-side capture read while its dots stay visible on the display. Scope is that field's text only.
- **No-leak blocking (opt-in private path).** The secure-layer swap gated behind the `PrivateAPI`
  package trait and an explicit runtime opt-in. **Measured** on the UIKit entry point. Private API,
  non-contract, fragile across iOS releases, App Review risk, never a security guarantee.
- **Forensic tiled watermark** — `ScreenGuardWatermarkView`,
  `ScreenGuardWatermarkConfiguration`, and pure-geometry `ScreenGuardWatermarkLayout`. A deterrent and
  attribution measure only: it removes no pixels and stops nothing.
- **App-switcher snapshot protection** — `ScreenGuardAppSwitcherShield` with synchronous cover on
  scene deactivation; `ScreenGuardAppSwitcherStyle` for blur, opaque or branded covers. The snapshot's
  pixels are **device-pending** (Apple's KTX variant is not decodable on Simulator); installation and
  synchrony are verified.
- **SwiftUI surface** — `.screenGuardProtected(strategy:refreshPolicy:onProtectionFailure:)`,
  `.screenGuardWatermarked(_:)`, `.screenGuardAppSwitcherProtected(style:)`, and
  `ScreenGuardMonitorView`. iOS 15-compatible; enum values must be displayed through `.rawValue`.
- **Runtime capability registry** — `ScreenGuard.capabilityStatuses` and `ScreenGuard.status(of:)`
  expose the ten rows of the capability contract so a host app can render the truth rather than
  restate it. A unit test pins the registry to the contract.
- **`PrivateAPI` package trait (consumer-actionable opt-out), disabled by default.** A consumer who
  must not ship the private class name simply does not enable the trait: no fork, no vendored copy, no
  second dependency. **App Review exposure is a compile-time property** — a default build contains 0
  occurrences of the private class name in any build product, including the generated `.swiftdoc`.
- **Explicit degradation reporting.** `shieldMode`, `isProtecting`, `hasPushedFrame`,
  `effectiveStrategy`, `requestedStrategy`, `protectionFailure`, `onProtectionFailure` and
  `monitor.reportProtectionFailure(_:)`. Protection never fails silently: a no-leak mechanism that
  fails silently is worse than no mechanism.
- **Example app and one-command verification** — `Examples/ScreenGuardDemo` consumes the package by
  relative path, and `Scripts/verify_capture.sh` builds it, drives scripted probe pages, samples their
  PNGs, and prints a `PASS` / `FAIL` / `DEVICE` / `SKIP` / `FINDING` verdict per capability. Device-only
  checks are printed as device-required, never as passes.
- **Evidence set** — `docs/evidence/capability-matrix.md`, `docs/evidence/verification-report.md`,
  `docs/evidence/review-round1.md`, `docs/evidence/review-round2.md`, `docs/evidence/device-run-procedure.md`,
  plus the normative `docs/api-contract.md` and the verified-environment facts in `docs/TOOLING.md`.

### Platform

- iOS 15.0+ deployment target, iOS only. Zero third-party dependencies; system frameworks only.
- `swift-tools-version: 6.1` (required by package traits); the target pins `.swiftLanguageMode(.v5)`.
- `swift build` / `swift test` **fail** for this iOS-only package (macOS SDK); build and test with
  `xcodebuild -destination 'platform=iOS Simulator,…'`.
- No networking of any kind in the package: no telemetry, no analytics, no remote configuration, no
  transmitted identifier.

### Known limitations at 1.0.0

- The public `preventsCapture` path and the whole recording / mirroring / AirPlay path are
  **device-pending** and **notMeasured** respectively. Neither carries a working guarantee yet; the
  device procedure is `Scripts/verify_capture.sh --print-device-command`.
- On the public path the shield is a **refreshed snapshot**, not a live view.
- A direct in-process `CALayer.render(in:)` read defeats both the secure text field and the
  secure-layer swap; host-side capture (`simctl io screenshot`, sim-use) bypasses protection by
  construction. Both are documented, not solved.
- Migrating the source to the Swift 6 language mode is deferred; Swift 5 semantics are pinned.
- The test suite is XCTest for 1.0.0. Migration to Swift Testing is planned and can be done file by
  file (the two frameworks coexist in one target).

### Verification

*Historical record of the run at that date, on the pre-code-style-baseline tree. The figures are
reproducible only on that revision; the current measured run is in [`Unreleased`](#unreleased) and in
the README's [current measurement](README.md#current-measurement-on-the-current-tree).*

- Build: `xcodebuild build` — succeeds with **0 source warnings** at `arm64-apple-ios15.0` (also
  verified at an iOS 26.0 deployment target, where round 1 had measured 1 warning).
- Tests: `xcodebuild test` → `Executed 124 tests, with 11 tests skipped and 0 failures`, each skip
  carrying a stated reason (6 pre-existing, 4 PRIVATEAPI-REQUIRED, 1 SCENE-REQUIRED).
- Example: `Scripts/verify_capture.sh` → `PASS 22 · FAIL 0 · FINDING 0 · SKIP 0 · DEVICE 4`, exit 0,
  including "shield self-report agrees with the measured pixels `isProtecting=True`".
- Independent review round 2: **verdict pass**, 0 high findings, 0 blockers.
