# Contributing to ScreenGuard

ScreenGuard is an iOS package whose promise is deliberately narrow: sensitive content does not leak
into captures, and a protected region coming out black or blank in the capture is the **success**
case. It never claims to prevent a screenshot or a recording, and every capability claim is tied to a
measurement, a control, and the capture path it was measured on.
[`docs/api-contract.md`](docs/api-contract.md) is the normative specification and
[`docs/TOOLING.md`](docs/TOOLING.md) records the verified environment facts and traps. Read both
before you change behaviour a user can observe.

Thanks for considering a contribution.

---

## 1. The honesty bar (binding on every contribution)

These are not style preferences. A pull request that breaks one of them is a defect, not a
difference of opinion.

1. **A capability claim without a measurement and a control is a defect.** If a change makes the
   package do something new in a capture, the pull request must carry the measurement that shows it
   and the control band that rules out the obvious false positive — "the region is black" means
   nothing unless an unshielded region beside it reads the content colour.
2. **The capability table is owned by [`docs/api-contract.md`](docs/api-contract.md) §4.** Copy it;
   never re-derive it in prose, in a README, in a doc comment or in demo copy. Each row carries one
   of four statuses — `measured`, `device-pending`, `notMeasured`, `notPossible` — and the
   status must survive any rewrite of the sentence around it.
3. **Never claim that a capture is prevented.** iOS does not permit an app to block a screenshot or a
   screen recording, mirroring or AirPlay, and the package never claims otherwise
   ([`docs/api-contract.md`](docs/api-contract.md) §0.2). The promise is *no leakage*: a protected
   region coming out black or blank in the capture is the **success** case.
4. **Evidence comes from a valid capture path only.** An app-side `window.drawHierarchy(in:afterScreenUpdates: false)` read or a ReplayKit capture can carry a no-leak verdict. A host-side
   capture (`xcrun simctl io screenshot`, sim-use `screenshot` / `record-video`) bypasses
   capture protection by construction and can never produce one — it is usable as contrast, never as
   evidence ([`docs/TOOLING.md`](docs/TOOLING.md) §3).
5. **A blank region is ambiguous, so a control is mandatory.** Put a distinctly coloured sentinel
   *behind* every protected band: reading sentinel-colour means the pixels were excluded; reading the
   content colour means they leaked; reading black may mean the region never painted at all
   ([`docs/TOOLING.md`](docs/TOOLING.md) §3).

## 2. Set up the toolchain

Every gate runs through [mise](https://mise.jdx.dev). The repository pins exact tool versions in
[`.mise.toml`](.mise.toml) — SwiftLint 0.65.1, SwiftFormat 0.63.0, XcodeGen 2.46.0, actionlint
1.7.12, shellcheck 0.11.0 and git-cliff 2.14.2. A pin is never `latest`: a gate whose tool version
floats is not a gate, because the same unchanged tree can start failing.

Run these three commands, **in this order**, once per clone:

```bash
mise trust      # required first: a fresh clone's .mise.toml is untrusted
mise install    # fetches the pinned versions
mise tasks      # lists the task names you may rely on
```

`mise trust` is not optional and not cosmetic, but the failure mode is narrower than "every task
fails". Measured on an untrusted clone: the *discovery* commands exit 1 — `mise tasks`, `mise ls` and
`mise env` all fail with `Config files ... are not trusted. Trust them with mise trust` — while
`mise run <task>` auto-trusts the repository config in normal mode, prints the task banner and runs.
That asymmetry is why the CI "trust the repository mise config" step checks with `mise tasks`: it is
the command that actually fails when trust is missing, so the step cannot pass vacuously. Run
`mise trust` first anyway, from the repository root.

> **Only the tasks defined in [`.mise.toml`](.mise.toml) are the contract.** Your local
> `mise tasks` may also list tasks inherited from your personal global mise config; they are not
> part of this repository and they do not exist on CI. Do not depend on them in a contribution.

**Never run `swift build` or `swift test`.** This package is iOS-only
(`platforms: [.iOS(.v15)]`, `import UIKit`); the plain SwiftPM CLI resolves the macOS SDK and
fails. Build and test go through `xcodebuild` with an explicit iOS Simulator destination, which is
what `mise run build` and `mise run test` do ([`docs/TOOLING.md`](docs/TOOLING.md) §1).

## 3. The gates

| Task | What it runs | In the blocking chain? |
|---|---|---|
| `mise run generate` | Regenerates both `.xcodeproj` bundles from their `project.yml` specs. The generated bundles are never committed. | dependency of `demo:build` |
| `mise run format` | SwiftFormat in **write** mode over every Swift file. It rewrites your working tree. | no — run it before `format:check` |
| `mise run format:check` | The same scope with `--lint`: fails if any file would change. | **yes** |
| `mise run lint` | `swiftlint lint --strict` over `Sources` and `Tests`; warnings are failures. | **yes** |
| `mise run lint:demo` | SwiftLint over `Examples` and `Research`. Advisory by design: it reports intentionally deferred debt and always exits 0. | no, by design |
| `mise run shellcheck` | `shellcheck --severity=error` over `Scripts/*.sh`. | **yes** |
| `mise run build` | `xcodebuild build -scheme ScreenGuard` for the Simulator destination. | **yes** |
| `mise run test` | `xcodebuild test -scheme ScreenGuard`. | **yes** |
| `mise run demo:build` | Builds the example app from its generated project. | **yes** |
| `mise run demo:verify` | [`Scripts/verify_capture.sh`](Scripts/verify_capture.sh): builds the demo, boots a Simulator, runs the probes and prints a PASS/FAIL verdict per capability. The slowest task — run it whenever you touch the demo, the shield, the watermark or any capture path. | no (needs a Simulator) |
| `mise run ci:local` | The whole blocking chain in CI's order, failing fast: `generate` → `format:check` → `lint` → `shellcheck` → `build` → `test` → `demo:build`, then advisory `lint:demo`. | it **is** the chain |

**Run `mise run ci:local` before you push.** It is the exact local equivalent of the CI validation
job, and the first failing step aborts the run with its own exit code.

**Choosing a Simulator.** Build and test default to
`platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2`. Override it in the environment:

```bash
DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' mise run test
# the value must name a device and runtime that exist on your machine:
#   xcrun simctl list devices available
# if the iOS runtime is missing, install it with: xcodebuild -downloadPlatform iOS
```

**Device-only checks.** A real screenshot cannot be triggered on the Simulator, the recording path
delivers no frames there, and app-switcher snapshot pixels are not decodable. Those checks are
printed as device-required and are never faked. Print the physical-device procedure with:

```bash
mise run demo:verify -- --print-device-command
```

## 4. Commit and pull-request titles: Conventional Commits (enforced)

Pull-request titles are validated by CI against the
[Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) shape, and a non-conforming
title fails that check. The same history is what the release notes in
[`CHANGELOG.md`](CHANGELOG.md) are generated from (Keep a Changelog format, `git-cliff` pinned by
mise), so the title is not cosmetic either way.

The shape is `type(scope): subject`:

- **type** — required, one of `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`,
  `build`, `ci`, `chore`, `revert`.
- **scope** — optional, the area touched: `examples`, `research`, `shield`, `watermark`,
  `swiftui`, `tooling` …
- **subject** — imperative, lower-case, no trailing period; keep the whole title to about 72
  characters.
- **breaking change** — mark it with `!` after the type or scope (`feat(api)!: …`) and explain it
  in a `BREAKING CHANGE:` footer.

Real examples from this repository's own history:

```text
feat(examples): rebuild the demo so a user verifies the library instead of viewing it
fix(examples): stop disabling code signing for device builds
docs: capability contract, tooling facts and review evidence
test(research): capture-protection measurement harness and device procedure
chore(xcode): commit the shared scheme and ignore per-user Xcode state
```

### Signing is not required for commits or tags

The publish procedure runs `git -c commit.gpgsign=false commit …` and the same for `git tag`, or sets
it once per clone with `git config --local commit.gpgsign false`. The repository carries no signature
requirement, and the publish must never stall on an interactive pinentry or signing agent — the CI
and release jobs run headless, and an unsigned commit or tag is accepted here.

## 5. Pull requests

Fill in [`.github/pull_request_template.md`](.github/pull_request_template.md). It asks for three
things, and all three are required:

1. **What changed and why** — the behaviour a user can observe, not a list of files.
2. **Which gate you ran, with its raw output** — paste the command and its result. "Tests pass" is
   not evidence; `mise run ci:local` output is.
3. **The measurement behind any new claim** — the capture path, the command, the artifact, and the
   control band that rules out the false positive. A claim with no measurement must ship with the
   status that says so (`device-pending`, `notMeasured`) rather than as an assertion.

Keep a pull request to one logical change; separate a refactor from a behaviour change so the
measurement is about the behaviour.

## 6. The private-API path — do not "fix" it into the default build

`ScreenGuardNoLeakStrategy.privateSecureLayer` reparents content into a private UIKit class
(`_UITextLayoutCanvasView`) and is the only mechanism measured to exclude arbitrary content from a
capture while still painting it on the display. It is also **opt-in, off by default, non-contract,
fragile across iOS releases, and an App Review risk — never a security guarantee**
([`docs/api-contract.md`](docs/api-contract.md) §9).

The opt-in is an SPM **package trait named `PrivateAPI`**, and it is **not** in
`default(enabledTraits:)`: a default build must not contain the private class name anywhere. A
contribution that enables the trait by default, removes the trait gate, or describes the path as
secure, guaranteed, recommended, production-ready or App-Store-safe will be rejected
([`docs/api-contract.md`](docs/api-contract.md) §9.5). The path must keep degrading loudly — if it
cannot engage, the shield reports `protectionFailure = .privateSecureLayerUnavailable` and emits
`protectionDegraded` rather than failing silently.

## 7. Reporting a security issue

Do **not** open a public issue for a leak or a protection bypass. Use the private advisory flow
described in [`SECURITY.md`](SECURITY.md) — it also lists the bypasses that are documented
limitations rather than defects, so a report is not spent on one of them.

## 8. Code of conduct

Participation is covered by [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) (Contributor Covenant
v2.1). Report unacceptable behaviour to the contact address in that file.

## 9. Where the truth lives

| Document | What it is |
|---|---|
| [`docs/api-contract.md`](docs/api-contract.md) | Normative specification: public API, capability table §4, wording rules, private-path rules. |
| [`docs/TOOLING.md`](docs/TOOLING.md) | Verified environment facts and traps (build commands, capture paths, deprecations, Simulator limits). |
| [`docs/evidence/capability-matrix.md`](docs/evidence/capability-matrix.md) | The measurements the capability table cites, with their controls. |
| [`CHANGELOG.md`](CHANGELOG.md) | Keep a Changelog, generated from Conventional Commit history. |

If a change makes one of these documents wrong, update the document in the same pull request. A
stale rationale is a defect in this repository, in comments as much as in prose.
