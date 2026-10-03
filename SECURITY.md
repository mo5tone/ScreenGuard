# Security Policy

## What ScreenGuard guarantees — and what it does not

ScreenGuard's promise is narrow on purpose: **sensitive content does not leak into captures; a
protected region coming out black or blank in the capture is the SUCCESS case**
([`docs/api-contract.md`](docs/api-contract.md) §0.1). iOS does not permit an app to prevent a
screenshot or a screen recording, mirroring or AirPlay, so the package does not claim prevention of
any of them.

The single source of truth for what is measured, designed-but-device-pending, not measured, or
impossible is the capability table in [`docs/api-contract.md`](docs/api-contract.md) §4. Read it
before filing: a report against a row marked `notPossible` or `device-pending` is a documented
limitation, not a defect.

| Status | Meaning |
|---|---|
| `measured` | Demonstrated by a measurement with a control that rules out the obvious false positive. |
| `device-pending` | Designed and implemented, but not measurable on Simulator; the claim is withheld until a physical-device run. **Not a working guarantee today.** |
| `notMeasured` | No measurement attempted; no claim made. |
| `notPossible` | The platform does not permit it. |

## Two bypasses that are documented, not solved

Both of these defeat the package **by construction**. They are recorded in
[`docs/api-contract.md`](docs/api-contract.md) §3.5 and [`docs/TOOLING.md`](docs/TOOLING.md) §2
and §7.2, and neither is an open defect:

1. **Host-side display capture.** `xcrun simctl io screenshot`, and sim-use's `screenshot` /
   `record-video`, read the simulator's (or device's) display surface from outside the render
   server. They bypass render-server capture protection by construction — which is why this
   repository uses a host-side capture only as *contrast*, never as evidence
   ([`docs/TOOLING.md`](docs/TOOLING.md) §3). No app-level library can close this; it is not
   something ScreenGuard can fix.
2. **A direct in-process `CALayer.render(in:)` read.** Measured to defeat **both** the secure text
   field and the private secure-layer swap: `layer.render` walks the layer tree directly, never
   goes through the render server, and does not honour capture exclusion
   ([`docs/evidence/capability-matrix.md`](docs/evidence/capability-matrix.md) §5). It is a narrow
   but real exfiltration surface, and it is **documented, not solved** — the same words the contract
   uses for it.

## What IS a vulnerability

- Sensitive content appearing in a capture on a path the contract treats as protected: the app-side
  `window.drawHierarchy(in:afterScreenUpdates: false)` read, or a ReplayKit capture.
- **Silent protection failure.** The shield reporting success while the protected region is not
  excluded, or failing to report `protectionFailure` / emit `protectionDegraded` when the private
  path cannot engage ([`docs/api-contract.md`](docs/api-contract.md) §9.2).
- **The private-API code in a build that did not opt in.** The `PrivateAPI` trait is off by
  default and a default build must not contain the private class name
  ([`docs/api-contract.md`](docs/api-contract.md) §9.4).
- **Any network activity inside the package.** The package must never perform one
  ([`docs/api-contract.md`](docs/api-contract.md) §6.4).
- A public API behaving in a way that leaks content the documentation says it protects, or a
  documented guarantee contradicted by a measurement.
- A claim in README, docs or demo copy that asserts prevention, or a capability status that
  contradicts §4.

## What is NOT a vulnerability

- **"I took a screenshot and the content was in it."** Expected. iOS exposes no public API that lets
  an app block a screenshot; the package detects, it does not prevent (capability rows 1, 9, 10).
- **"A host-side capture shows the content."** Host-side capture bypasses protection by construction
  — see bypass 1 above.
- **"The recording path leaked."** The recording/mirroring path has **no guarantee**
  (capability row 6, `notMeasured`): `RPScreenRecorder` reported success and then delivered zero
  callbacks in 30 seconds on Simulator, so no claim is made there.
- **"The app-switcher snapshot contains the content."** The snapshot is written by the system
  (`SplashBoard`); the capability is device-pending, and its pixels are not decodable on Simulator
  (capability row 8).
- **"An in-process `CALayer.render` read shows the content."** See bypass 2 above.
- The **private secure-layer path** being fragile or unavailable on a new iOS release. That is the
  documented reason it is off by default, opt-in via the `PrivateAPI` trait, and non-contract; the
  defect to report is a *silent* failure, not the absence of the private class.

## Reporting a vulnerability

Use GitHub's **private security advisory** flow — do not open a public issue, and do not attach
evidence that contains real user content:

<https://github.com/mo5tone/ScreenGuard/security/advisories/new>

(Repository **Security** tab → *Report a vulnerability*.)

Please include:

1. **The capture path** that produced the evidence — app-side `drawHierarchy` or ReplayKit are the
   paths a leak verdict can be drawn from. State it plainly if it was a host-side capture instead;
   that changes what the observation means.
2. **What you expected and what you observed**, with the protected region's reading and the control
   band's reading.
3. **A reproduction** — the smallest one you have: the code, and the command you ran.
4. **Environment** — device or Simulator model, iOS version, Xcode version, and the ScreenGuard
   version or commit.
5. **Artifacts** — the PNG and the samples/JSON output, if you can share them. Measured pixels beat
   a description.

**Response expectation.** We acknowledge a report within **3 business days**, and follow up within
**10 business days** with an assessment: accepted, in need of more information, or out of scope with
the section of the capability contract that covers it. If accepted, we agree a disclosure date with
you; the fix and the advisory are published together, and the advisory cites the measurement that
demonstrates the fix.

## Supported versions

The current release line is **1.0.x**. Security fixes are developed on the default branch
(`main`), released as a patch on that line, and recorded in [`CHANGELOG.md`](CHANGELOG.md).
