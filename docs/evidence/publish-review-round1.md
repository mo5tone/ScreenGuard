# ScreenGuard — adversarial publish-readiness review, round 1 (task t9)

**Reviewer:** `reviewer` (Adversarial reviewer) · **Attempt:** `f699e110-7581-4fb7-97f3-5d68e49903b6`
**Date:** 2026-10-03 · **Repository under review:** `/Users/jiefu/Developer/ScreenGuarantor` (no remote, 8 commits, **0 tags**)
**Reviewed object:** the **publish set** — `git ls-files --cached --others --exclude-standard` = **152 paths**, i.e. everything a `git add -A && git commit` would publish, including the still-untracked files the publish step must add (`.github/**`, `Scripts/ci/**`, `.mise.toml`, `.swiftformat`, the root docs, `cliff.toml`, `.spi.yml`).
**Compared against:** the pre-reformat revision `2263ac5` (HEAD, the last commit), `docs/api-contract.md` §1/§4/§6/§10, `README.md`, `CHANGELOG.md`, `CONTRIBUTING.md`, `SECURITY.md`, `docs/TOOLING.md`, `.github/workflows/**`, `Scripts/ci/**`, `.mise.toml`, `.gitignore`, `.swiftformat`, `.swiftlint.yml`, `Package.swift`.
**Write scope:** this file only. **Every experiment ran in a throwaway copy under `/tmp/sg-rev/`** (the tree under review was hashed by `git status --porcelain | wc -l` = 96 before and after, and file mtimes are all pre-session). No source, test, workflow, script, config or team-state file was modified.
**Source material I did not re-derive:** t8's `docs/evidence/publish-verification.md` (its raw per-check output is quoted where I cite it); the t2/t4/t5/t6/t7 hand-offs carried in the task dependencies. Where I quote a number as mine, it came from a command in §1.

---

## 0. Verdict

## **Verdict: `needs_revision`** — 1 high finding in the tree, 1 high **operational** publish risk, 4 medium, 4 low, 1 informational.

The honesty machinery of this repository is real: the capability tables are byte-identical across README and contract, the runtime registry matches §4 row for row, every gate I tried can actually fail, the action pins are full SHAs, and there is no credential anywhere in the publish set. The change under review is, with one exception, provably inert: **Examples and Research are token-for-token identical**, `Package.swift` differs by six commas, and of 73 same-named function bodies in `Sources/`, 66 are token-sequence identical and the other 7 are explained one by one in §2.

**The exception is the high finding (F-R1-1): `@MainActor` was removed from the public class `ScreenGuardShieldView`.** That is not a formatter artefact — I ran the repository's pinned formatter, with the repository's own config, over HEAD's file and `@MainActor` survives (C1). It is an undocumented hand edit inside a change whose stated contract was *"no public symbol renamed, removed or re-signatured"*, and it is visible to consumers: the emitted module interface changes for **18 declarations** (`@preconcurrency` occurrences 6 → 24), and a Swift 6 consumer that gets a hard error for a nonisolated call against HEAD gets only a warning against the candidate tree (C8). The published contract says the opposite in two places (§1: *"all public API is `@MainActor`"*; §6.4: `@MainActor public final class ScreenGuardShieldView`). It is a one-line repair, and I verified the repair is gate-clean **and** restores the emitted interface to HEAD's exactly (C7, C21).

The four medium findings are documentation-vs-measurement defects a reader *will* hit in the first five minutes (a stale "no canonical remote URL" note, a wrong untrusted-mise claim, a wrong skip breakdown, and the CHANGELOG's "identical dumps" sentence). Three of them sit in the sections whose entire purpose is measurement honesty, which is why they are not cosmetic here.

### 0.1 Item-by-item

| # | Review item | Verdict |
|---|---|---|
| 1 | Behaviour preservation of the reformat | **FAIL on one item** — the formatter-driven change\* is inert (token-identical in Examples/Research, 66/73 bodies identical, 7 explained); but the change set also contains a non-formatting **public-API** edit (**F-R1-1**) |
| 2 | API stability vs `docs/api-contract.md` §6 | **FAIL** — no symbol renamed, removed or re-signatured, and **0 documented-but-absent symbols** (C27); but the class lost its declared `@MainActor` (**F-R1-1**) and two setters were relaxed (**F-R1-9**) |
| 3 | Claim integrity | **FAIL** — the §4 table is **byte-identical** (C28) and the runtime registry matches 10/10 (C29); four published claims do not match their own measurement (**F-R1-2**, **F-R1-3**, **F-R1-4**, **F-R1-5**) plus two low (**F-R1-6**, **F-R1-7**) |
| 4 | Gates that can actually fail | **PASS** — demonstrated by injection: format `exit 1`, lint `exit 2`, build `exit 65`, test `exit 65`, each with a green control on the same copy (C12–C16); no `continue-on-error` and no `\|\| true` on any blocking step (C31) |
| 5 | Publish hygiene | **PASS with one informational** — 0 credentials/tokens/keys/private keys; no wrongly-tracked file; no ignored-but-needed file; **70 personal absolute paths in 14 published files** (**F-R1-11**, informational) |
| 6 | Supply chain | **PASS** — all 5 action references are 40-hex commit SHAs (C30); least privilege per job; no `pull_request_target`, no `workflow_run`, no `secrets.*`; the three `if: always()` steps are verdict-preserving rather than swallowing |
| 7 | Stale rationales | **FAIL** — the remote-URL disclaimer (**F-R1-3**) and the `mise run` trust sentence (**F-R1-4**) argue for a world the tree has left; the rest of the sweep came out clean |
| A | Trait-gated coverage (acceptance) | **GAP REPORTED** — the private path **is compiled** by CI (`demo:build`) but is **executed by no required gate**; its 6 tests skip in every per-PR/release run (**F-R1-8**) |
| B | `Package.swift` delta (acceptance) | **PASSED** — 5 trailing commas + 1 blank line; token streams otherwise identical; the package builds and tests green with it (§10) |

\* I use "the reformat" for the formatter-driven part; the change set under review also contains deliberate hand edits (rule-driven rewrites and the file/type splits).

---
## 1. Commands I ran, with exit codes

Everything below is my own run unless the row says otherwise. "The copy" is always the publish set exported with `git ls-files -z --cached --others --exclude-standard | tar`; scratch copies live under `/tmp/sg-rev/`.

| # | Command | Exit | Result |
|---|---|---|---|
| C1 | `mise exec -- swiftformat --config .swiftformat <HEAD copy of ShieldView.swift>` (run from the repo so the pinned 0.63.0 and the repo config apply) | 0 | `1/1 files formatted` and **`@MainActor` is still there** — the attribute removal is **not** a formatter artefact |
| C2 | token multiset, `Examples` (HEAD formatted by the pinned formatter) vs the tree | — | **17927 vs 17927 tokens — identical multisets** |
| C3 | token multiset, `Research` | — | **11282 vs 11282 — identical** |
| C4 | token multiset, `Sources` (global, per file, and old shield file vs the 5-file union) | — | deltas enumerated in §2; nothing but structural additions and the edits listed there |
| C5 | function-body token-sequence comparison by name, `Sources` | — | 73 bodies compared: **66 identical, 7 differing**, each explained in §2.2; 15 new helper names, 0 removed |
| C6 | test-method name sets, `HEAD:Tests` vs `Tests` | — | **131 vs 131, 0 removed, 0 added** |
| C7 | `swiftc -enable-library-evolution -emit-module-interface` for HEAD / candidate / candidate + restored `@MainActor` | 0/0/0 | `@preconcurrency` occurrences **6 → 24 → 6**; the class line is byte-identical to HEAD after the restore |
| C8 | `swiftc -typecheck -swift-version 6` consumer probe against both modules (nonisolated call to `ScreenGuardShieldView()`) | **0** (candidate: *warning*) / **1** (restored: *error*) | the consumer-visible isolation diagnostic is weakened in the candidate tree |
| C9 | `git ls-files --cached --others --exclude-standard \| wc -l` | 0 | **152 paths** (t8 measured 152 = 151 + its own report) |
| C10 | secret sweep over the publish set: `gh[pousr]_`, `github_pat_`, `AKIA`, `BEGIN … PRIVATE KEY`, `xox[baprs]-`, `sk-`, `AIza`, a JWT shape, `password[:=]` | — | **0 matches** |
| C11 | `/Users/` sweep over the publish set | — | **70 occurrences in 14 files** (49 project-root paths, 21 CoreSimulator paths, plus doc examples) — **F-R1-11** |
| C12 | copy, control: `mise run format:check` / `mise run lint` | 0 / 0 | `0/71 files require formatting, 2 files skipped` · `Found 0 violations, 0 serious in 39 files` |
| C13 | copy + a badly formatted line → `mise run format:check` | **1** | `error: (consecutiveBlankLines)` … `Source input did not pass lint check. 1/71 files require formatting` |
| C14 | copy + a 160-character comment line → `mise run lint` | **2** | `error: Line Length Violation` … `Found 1 violation, 1 serious in 39 files` |
| C15 | copy + a type error → `mise run build` | **65** | `** BUILD FAILED **` (SwiftEmitModule, SwiftCompile, workspace) |
| C16 | copy + one deliberately failing XCTest → `mise run test`; then the same copy restored → `mise run test` | **65** / 0 | `SGGateProbeTests.testDeliberateFailureProbe failed` · control: `Executed 131 tests, with 13 tests skipped and 0 failures` |
| C17 | `Scripts/ci/check-pr-title.sh --self-test` | 0 | `self-test: 19 title cases behaved as specified`; prints the 11 permitted types it shares with CONTRIBUTING §4 |
| C18 | `check-pr-title.sh 'Fixed the bug'` | **1** | `FAIL: the pull-request title is not a Conventional Commit` |
| C19 | `Scripts/ci/check-destination.sh 'platform=iOS Simulator,name=iPhone 16,OS=18.0'` | **1** | `FAIL: no available device named 'iPhone 16' on runtime '18.0'` — installed runtimes are only 26.0 / 26.2 / 26.5 |
| C20 | `Scripts/ci/check-destination.sh 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2'` | 0 | `resolved: iOS 26.2 / iPhone 17 Pro (DCF67420-…)` |
| C21 | copy + `@MainActor` restored on the class → `format:check` / `lint` / `build` / `test` | 0/0/0/0 | `0/71` · `0 violations, 0 serious in 39 files` · `** BUILD SUCCEEDED **` · `Executed 131 tests, with 13 tests skipped and 0 failures` |
| C22 | fresh copy, **untrusted** `.mise.toml`: `mise tasks` | **1** | `Config files in /private/tmp/…/.mise.toml are not trusted` |
| C23 | same fresh copy, still untrusted: `mise run format:check` | **0** | runs and **silently auto-trusts** — the CONTRIBUTING claim is false for `mise run` |
| C24 | author tree: `mise run format:check` | 0 | `0/71 files require formatting, 3 files skipped` (the third is the git-ignored `Research/Artifacts/README.md`) |
| C25 | scratch repo: `git commit` | **128** | `error: 1Password: failed to fill whole buffer` / `fatal: failed to write commit object` |
| C26 | scratch repo: `git commit -c commit.gpgsign=false` | 0 | commit created |
| C27 | contract §6 "public" symbol sweep vs the emitted interface | — | 93 names; **0 genuinely missing** (the 2 misses are the prose words "path" and "primitive") |
| C28 | README lines 66–86 vs `docs/api-contract.md` lines 246–266 | — | **21/21 lines byte-identical** (`VERBATIM IDENTICAL: True`) |
| C29 | capability registry in `Sources/ScreenGuard/ScreenGuard.swift` vs §4 | — | 10 rows; statuses match §4 exactly |
| C30 | `grep 'uses:' .github/workflows/*.yml` | — | 5 distinct refs, **all 40-hex** SHAs |
| C31 | `grep -n 'continue-on-error\|\| true' .github/workflows/*.yml` | 1 (no match) | only two *comments* mention it; **no YAML key and no shell fallback** on any step |
| C32 | `Package.swift` HEAD vs tree, token streams | — | 142 → 148 tokens, **6 insertions, all commas**; identical after removing commas |
| C33 | `git status --porcelain \| wc -l` before/after the review | 96 / 96 | the tree under review was not modified by this attempt |
| C34 | `git config --get commit.gpgsign / gpg.format / gpg.ssh.program`; `git config --local --list` | 0 | `true` / `ssh` / `…/1Password.app/…/op-ssh-sign`; **no repo-local override** — **F-R1-12** |

---

## 2. Item 1 — behaviour preservation of the reformat

### 2.1 Method (three independent passes, not the test result)

1. **Isolate the non-formatter delta.** I applied the repository's pinned SwiftFormat 0.63.0, with the repository's `.swiftformat`, to a pristine `git archive HEAD` export and diffed that against the current tree. Everything the formatter does disappears from the diff; what is left is the deliberate edits and the file/type splits. Residual sizes: `ScreenGuardShieldView.swift` 616 diff lines, `ScreenGuard.swift` 264, `ScreenGuardCaptureStateObserver.swift` 122, `ScreenGuardPrivateSecureLayer.swift` 52, `ScreenGuardEventMapper.swift` 31, `ScreenGuardWatermarkView.swift` 19, `ScreenGuardObserverTokenStore.swift` 12, `ScreenGuardModifiers.swift` 12, `ScreenGuardMonitor.swift` 11; Tests: 379/198/123/56/49/24/14.
2. **Token multisets** (my own Swift lexer: comments dropped; string literals, numeric literals, identifiers, operators and punctuation tokenised) over whole trees and over the `Shield` file split.
3. **Function bodies by name**: for every function/initialiser name present in both trees, compare the **token sequence of the balanced-brace body**. This is the pass that catches reordered side effects and precedence edits, which a multiset cannot.

### 2.2 Every residual delta, and why it is not a behaviour change

| Site | Delta | Verdict |
|---|---|---|
| `Examples/**`, `Research/**` | none: **token multisets identical** (C2, C3) | inert |
| `Package.swift` | 6 commas, 1 blank line (see §10) | inert |
| `Sources/ScreenGuard/ScreenGuard.swift` | the ten-row `switch` extracted into ten `private static func ×Record()` helpers; strings and statuses preserved verbatim; helper calls in the same order; one case now passes `.screenshotDetection` literally instead of the bound `capability` | inert (C5 `statusRecord` explained; the string literals compare equal) |
| `ScreenGuardCaptureStateObserver.swift` | the two `if #available(iOS 17.0, *)` blocks extracted into `startForView`/`startForWindowScene`; `hostView = view` still precedes the call; `#available` count unchanged (6 in both) | inert |
| `ScreenGuardObserverTokenStore.swift` | an **empty `init() {}` deleted** (the implicit init replaces it) | inert |
| `ScreenGuardMonitor.swift` | `.first { $0.isKeyWindow }` → `.first(where: \.isKeyWindow)` (SwiftLint `prefer_key_path`) | inert |
| `ScreenGuardModifiers.swift` | the `Environment` attribute moved to its own line | inert |
| `ScreenGuardEventMapper` and `CaptureStateObserver` switch cases | blank lines inserted between cases (SwiftLint `vertical_whitespace_between_cases` — the formatter cannot add them) | inert |
| `ScreenGuardPrivateSecureLayer.swift` | the shadowing local `canvas` renamed `locatedCanvas`; `self.canvas = canvas` → `canvas = locatedCanvas`. The measured swap sequence (`setValue(hostLayer, forKey:"layer")`, both `isSecureTextEntry` toggles, `setValue(displaced, …)` and the three-part postcondition) is token-identical | inert, and this is the repair of the real `redundantSelf` bug t2 reported |
| `ScreenGuardWatermarkView.swift` `draw(_:)` | `lines.joined(…) as NSString` + `size(withAttributes:)` + `draw(at:withAttributes:)` → `NSAttributedString(string:attributes:)` + `size()` + `draw(at:)`. Same 300 tokens; the same `attributes` dictionary is moved into the attributed string and the origin arithmetic is unchanged | semantically equivalent (attributes now live on the string that is drawn and measured) |
| Shield split (`+Mode`, `+Content`, `+Refresh`, `SampleBufferFactory`) | `layoutSubviews` → `layoutProtectedContent()`, with the three inline conditions replaced by `needsDisplayScaleRefresh` / `needsRendererRefresh`, whose definitions are the **same operands in the same order** (an `&&` chain where the old code had a comma list); statement order (frame → scale refresh → renderer refresh → `.onLayout`) preserved. The `registerForDisplayScaleChanges` handler → `refreshIfDisplayScaleChanged()`, which is exactly the old `guard effectiveStrategy == .publicPreventsCaptureLayer else { return }` plus `refresh()`. `makeBitmapContext` is the old wrapped `CGContext(data: CVPixelBufferGetBaseAddress(…), … bitmapInfo: premultipliedFirst \| byteOrder32Little)` condition, called between the same lock/unlock | inert; all four extractions were read line by line against the HEAD-formatted original |
| `private` → `internal` on 18 members | required because Swift `private` is file-scoped and the members are now used from the extension files | not public API; see **F-R1-9** for the two that had been `private(set)` |
| `@MainActor` deleted from the class | **not** produced by the formatter (C1); not recorded in the §13 ledger | **F-R1-1** |
| Tests | 131 methods in HEAD and 131 in the tree, **0 removed / 0 added** (C6); the identifier-level deltas are closure-parameter naming (`$0` → named, SwiftLint), `XCTAssertTrue(x === y)` → `XCTAssertIdentical(x, y)` (the `xct_specific_matcher` rule — the same assertion with the specific matcher spelling) and shared fixtures moving into extension files | no assertion weakened; the suite executes 131/13/0 (C16, C21) |

**Availability guards:** `#available` 6 → 6 and `available` 4 → 4 in `Sources/`; no version operand changed. The only numeric-token delta in the whole of `Sources` was a `$0` closure shorthand, not a constant.

**Verdict for item 1:** the formatter-driven change is behaviour-preserving by token evidence, with one exception — a public-API attribute removal that the formatter did not make (**F-R1-1**). "Reading the test result alone" would have missed it, exactly as the review brief predicted.

---
## 3. Item 2 — public API stability against `docs/api-contract.md` §6

**Method.** I compiled the library three times for `arm64-apple-ios15.0-simulator` with `swiftc -enable-library-evolution -emit-module-interface` — HEAD, the candidate tree, and the candidate tree with `@MainActor` restored — and diffed the **consumer-visible** `.swiftinterface` rather than the source. I then ran a Swift 6 language-mode consumer probe against the candidate and restored modules, and swept every symbol the contract calls public against the emitted interface (C27).

**Result.**

```
HEAD      : @objc @_Concurrency::MainActor final public class ScreenGuardShieldView : UIKit::UIView
candidate : @objc @_Concurrency::MainActor @preconcurrency final public class ScreenGuardShieldView : UIKit::UIView
restored  : @objc @_Concurrency::MainActor final public class ScreenGuardShieldView : UIKit::UIView   (identical to HEAD)
@preconcurrency occurrences: HEAD 6 · candidate 24 · restored 6
```

* No symbol was renamed, removed or re-signatured: 0 declarations added, 0 removed by name, and **0 of the 93 public names in contract §6 are absent from the interface** (C27). The two "missing" hits from the sweep are the prose words *path* and *primitive*.
* The only structural move is `setNeedsContentRefresh()` appearing in an `extension ScreenGuardShieldView` (it lives in `+Refresh.swift`) with an identical signature; the class is `final`, so nothing that was overridable became non-overridable.
* What remains are **attributes and spellings**: 18 `@preconcurrency` additions (**F-R1-1**), two `private(set)` → `internal(set)` relaxations, and three parameter-name spellings (**F-R1-9**).

**Verdict for item 2:** **FAIL** on the attribute set, not on the symbol set. Everything a caller *can call* still exists with the same shape; what changed is how the compiler imports the type's isolation, which is a published part of the contract.

---

## 4. Item 3 — claim integrity

**Mechanically checked:**

| Claim | Measurement | Result |
|---|---|---|
| README §"Capability matrix" **is `docs/api-contract.md` §4 verbatim** (README:60) | extract README:66–86 and contract:246–266 and compare | **21/21 lines byte-identical** (C28) — TRUE |
| `capabilityStatuses` returns the §4 rows in order | read the ten `×Record()` helpers and their statuses | 10/10 rows, same order, same four status words (C29) — TRUE |
| the two `measured` rows are measurement-backed | `0/1068` dark, `205/1068` calibration, `19.02%` display, sentinel `200,0,160` versus `38,102,242` all appear in `docs/evidence/capability-matrix.md` §3 rows 5 and 7 | TRUE |
| `preventUserScreenshot`/`preventUserRecording` are `notPossible`, `noLeakRecordingPath` is `notMeasured`, `screenshotDetection` is `devicePending` | registry plus §4 | TRUE |
| README "Current measurement on the current tree" figures | `mise run test` in a copy → `Executed 131 tests, with 13 tests skipped and 0 failures` (C16/C21); `mise run lint` → `Found 0 violations, 0 serious in 39 files` (C12) | 131/13/0 and 39 files TRUE |

**Not true, or true only in the author's tree:**

* **F-R1-2** — `CHANGELOG.md:27-29`: "a `swift-api-digester` dump of the built module **is identical to** the pre-baseline revision's … the dumps match once build-path metadata is normalised away". "0 declarations added, 0 removed" reproduces (I confirm it by name and by interface); "identical" does not: the emitted interfaces differ for 18 declarations (C7), which is what t8's own `-diagnose-sdk` run reported as 19 Decl Attribute changes. A reader who runs the tool the sentence cites finds the opposite.
* **F-R1-3** — `README.md:129`: "This repository does not assert a canonical remote URL". The same file asserts `https://github.com/mo5tone/ScreenGuard.git` at `:109`, `:120`, `:136` and in the CI badge at `:3`; `.github/CODEOWNERS`, `.github/ISSUE_TEMPLATE/config.yml`, `SECURITY.md` and `.github/pull_request_template.md` assert the same owner.
* **F-R1-4** — `README.md:146-148` and `CONTRIBUTING.md:56-59`: "*every `mise run …` fails with `Config files … are not trusted`* until it is trusted". Measured in a fresh untrusted copy: `mise tasks` → exit 1 with that error, but `mise run format:check` → **exit 0**, and it silently auto-trusts the config (C22, C23). The instruction to run `mise trust` is still right; the stated failure mode is not.
* **F-R1-5** — `README.md:588-590`: "6 require the `PrivateAPI` trait, **3 require a physical device**, **2 require a human or hardware action in the loop**, and 2 require a connected `UIWindowScene`". The run's own output contains **6 `PRIVATEAPI-REQUIRED`, 5 `DEVICE-REQUIRED`, 2 `SCENE-REQUIRED`** and no "human or hardware" category at all (my control run, C16). The five device skips are the five methods of `ScreenGuardDeviceOnlyTests`. The table directly above it (README:583) is correct, which makes the prose look like a stale count.
* **F-R1-6** — `README.md:579`: "`3 files skipped`". In the publish set it is **2** (C12, C23); the third is `Research/Artifacts/README.md`, which `.gitignore:67` drops from the publish set.
* **F-R1-7** — `CONTRIBUTING.md:93` (and the same example at `.mise.toml:20` and `.mise.toml:234`): the `DESTINATION='platform=iOS Simulator,name=iPhone 16,OS=18.0'` example does not exist on this toolchain; the preflight fails loudly with `no available device named 'iPhone 16' on runtime '18.0'` (C19).

---
## 5. Item 4 — gates that can actually fail (**demonstrated**, not asserted)

I injected one break at a time into a copy of the publish set and ran the same task the workflow runs. Each row is `mise run <task>`, with the exit code printed by the harness:

| Gate | Injected break | Exit | Failure text (excerpt) | Control on the same copy |
|---|---|---|---|---|
| `format:check` | a line SwiftFormat must rewrite | **1** | `error: (consecutiveBlankLines)` … `Source input did not pass lint check` | exit 0 |
| `lint` | a 160-character comment line | **2** | `error: Line Length Violation` … `Found 1 violation, 1 serious in 39 files` | exit 0 |
| `build` | `let x: Int = "not an Int"` | **65** | `** BUILD FAILED **` | (the file-swap restore is itself proven: format:check returns to 0) |
| `test` | one `XCTAssertTrue(false)` test | **65** | `Test Case '-[ScreenGuardTests.SGGateProbeTests testDeliberateFailureProbe]' failed` | exit 0, `131 executed / 13 skipped / 0 failures` |
| `check-pr-title.sh` | the title `Fixed the bug` | **1** | `FAIL: … not 'type(scope): subject'` | `--self-test`: 19/19 cases behave as specified, exit 0 |
| `check-destination.sh` | `iPhone 99 Pro Max / OS 99.9` | **1** | `FAIL` plus the full list of available destinations | the documented default: exit 0, resolved |

**Failure semantics, read as well as demonstrated.** `.github/workflows/ci.yml` runs each blocking gate as its own `run:` step — `mise run format:check` (:147), `mise run lint` (:150), `mise run shellcheck` (:153), `shellcheck Scripts/ci/*.sh` (:159), `mise exec -- actionlint` (:165), `mise run build` (:217), `mise run test` (:224), `mise run demo:build` (:227) — with **no `continue-on-error` key and no `\|\| true` / `\|\| exit 0` anywhere in the workflow** (C31). The single advisory step is `mise run lint:demo` (:235), whose task definition ends in `exit 0` by design and says so in its description. The tasks themselves (`.mise.toml`) use `set -eu` and `exec xcodebuild …`, so the compiler's exit code is the task's exit code; `ci:local` runs the blocking steps in a `set -eu` loop and has exactly one `\|\| true`, on `lint:demo`.

**What this does not prove:** that GitHub Actions will run those steps green or red on `macos-26`. No workflow was executed (no remote, no runner — see §12). The claim I can support is narrower and exact: each gate's *task* fails with a non-zero exit when its input is wrong, and nothing in the workflow swallows a non-zero exit.

---

## 6. Item 5 — publish hygiene

| Check | Result |
|---|---|
| Credentials, tokens, private keys, bearer tokens, API keys, `password=` | **0 matches** across all 152 publish-set paths (C10) |
| Signing material (`Apple Development`, `DEVELOPMENT_TEAM`, `PROVISIONING_PROFILE`, `CODE_SIGN_IDENTITY`, `TeamIdentifier`) | **0** — the only `CODE_SIGN_IDENTITY` strings live in the ignored `Research/CaptureMatrix/Derived/` build cache, which is not published |
| Emails | only the deliberate conduct/enforcement contact; no third-party addresses |
| Personal absolute paths | **70 occurrences in 14 files** — 49 × `/Users/jiefu/Developer/ScreenGuarantor/…` (committed build and app logs under `Research/Artifacts/**`, plus `docs/TOOLING.md` and three evidence documents), 21 × `/Users/jiefu/Library/Developer/CoreSimulator/…` (simulator container paths in the same logs), 1 × a reference to `/Users/jiefu/.agents/skills/sim-use/SKILL.md` inside t8's own report. **No secret is exposed**; what is exposed is the maintainer's username and local layout — **F-R1-11** |
| Tracked-but-should-not-be | none found: no `.xcodeproj`/`.xcworkspace`, no `xcuserdata`, no `__pycache__`/`.pyc`, no `.DS_Store`, no `Derived/`, no `.build/`, no `.swiftpm/`, no `.orig`/`.rej`/backup/editor files, no symlink anywhere in the publish set |
| Generated projects | 3 tracked paths are staged for **deletion** (`Examples/ScreenGuardDemo/ScreenGuardDemo.xcodeproj/**`) and the two tracked `.pyc` files are staged for deletion — the index matches the new `.gitignore` |
| Ignored-but-needed | none: a fresh untrusted copy runs `mise install` then `mise run generate` / `build` / `test` / `demo:build` (I ran format, lint, build and test in copies; `build` needs no generated project, and `demo:build` declares `depends = ["generate"]`). The ignored files are build output, per-user Xcode state, the AgentTeams runtime, machine-specific bytecode and non-canonical measurement runs. The one judgement call is `Research/Artifacts/README.md`, dropped by `.gitignore:67` and referenced by no published document (**F-R1-6**) |
| File modes | the six published shell/python scripts are `100755`; no executable bit on data files |
| Size | three PNGs (~2.9 MB total) are the canonical measurement artifacts that `docs/evidence/capability-matrix.md` §1 cites; everything else is text |

**Verdict for item 5:** pass, with the personal-path note as informational.

---

## 7. Item 6 — supply chain

* **All five distinct action references are full 40-hex commit SHAs** (C30): `actions/checkout@3d3c42e5…`, `jdx/mise-action@7a4e45a5…`, `actions/upload-pages-artifact@fc324d35…`, `actions/deploy-pages@368f8252…`, `actions/upload-artifact@043fb46d…`. Each carries a version comment; `mise-action` is additionally pinned to `version: 2026.9.6`, and the six tool versions come from `.mise.toml` (no `latest` anywhere).
* **Permissions are least-privilege per job**: workflow-level `contents: read` in all four workflows; `ci.yml`'s three jobs all `contents: read`; `release.yml`'s `gate` is `contents: read` and its `release` job is `contents: write` (needed for `gh release create`), gated by `needs: [gate]`; `docs.yml`'s `build` is `contents: read` and its `deploy` job adds only `pages: write` plus `id-token: write`.
* **No untrusted code with write scope**: `ci.yml` triggers on `pull_request` (not `pull_request_target`) and on `push: [main]`, token read-only; the pull-request title reaches the script through `env:` rather than shell interpolation.
* **No `workflow_run`, no `secrets.*`, no third-party action beyond the five SHAs above**, and no `curl | sh`; the nightly `verification.yml` uploads its evidence with `if-no-files-found: error`.
* **The three `if: always()` steps in `verification.yml` (:106, :155, :181) do not swallow anything**: the first publishes the summary, the second is the *verdict* step that exits 1 when the log is missing, contains `RESULT: FAILED`, or never reached `RESULT: PASSED`, and the third uploads the evidence.

**Verdict for item 6:** pass.

---

## 8. Item 7 — stale rationales

Swept for reversed decisions, claims about a state the tree has left, and config comments that no longer describe their rule.

**Stale (findings):** `README.md:129` (**F-R1-3**); `CONTRIBUTING.md:56-59` plus `README.md:146-148` (**F-R1-4**); the `iPhone 16 / 18.0` example in `CONTRIBUTING.md:93` and `.mise.toml:20,234` (**F-R1-7**); `README.md:588-590` (**F-R1-5**); `README.md:579` (**F-R1-6**).

**Checked and *not* stale (recorded so the next reader does not re-derive them):**

* the `124 tests / 11 skips` figures still quoted in `README.md:565`, `CHANGELOG.md:170` and `docs/api-contract.md:1258` sit inside sections explicitly labelled *historical* / *Superseded* / a dated amendment ledger, while the README's live table carries 131/13; no document presents 124 as current;
* `.mise.toml:5-10` quotes the pre-existing `No version is set for shim: swiftlint` error as the *reason the file exists* — a rationale about the past, still accurate;
* `.gitignore` carries no stale rationale: the generated-project block explains the rule that replaced the tracked bundles, and the measurement-artifacts block matches the negations it lists;
* `lint:demo` is advisory in both its task definition and every document that mentions it, and `demo:verify` is documented as the slow Simulator-booting task deliberately kept out of `ci:local`;
* `docs/TOOLING.md` §1 (`swift build` does not work here) and §12 (the trait-gated path is not covered by the suite) still describe the current tree;
* the "`no remote`" strings in `docs/evidence/publish-verification.md` are dated statements inside a verification record, not live claims about the repository.

---
## 9. Acceptance item — trait-gated code coverage (the `PrivateAPI` path)

The review brief requires this to be established rather than assumed, so here is the whole chain:

| Stage | `mise run build` / `mise run test` (default) | `mise run demo:build` | `Scripts/verify_capture.sh` (`demo:verify`) | nightly `verification.yml` | release `gate` |
|---|---|---|---|---|---|
| Compiles `#if SCREENGUARD_PRIVATE_API` | **No** (trait off: `.default(enabledTraits: [])`) | **Yes** (the demo's `project.yml` sets `traits: ["PrivateAPI"]`) | Yes (it builds the demo) | Yes | Yes (via `ci:local` → `demo:build`) |
| **Executes** the private path | No | No (compile only) | **Yes** (pixel probes, with the opt-in granted) | Yes, when it runs | **No** |
| Runs in a **required** check on PR / push / tag | test yes (the path is not compiled); demo:build yes (compile only) | — | No (deliberately excluded from `ci:local` and `ci.yml`) | No (nightly/manual) | No |

* The six tests that would exercise it skip in every per-PR and release configuration (`PRIVATEAPI-REQUIRED`: 6 of the 13 skips I reproduced).
* **No code path is compiled by no gate**: the trait-off branch is the default build, the trait-on branch is `demo:build`, and the storage/fallback file compiles in both configurations. What is missing is execution: **no required gate executes the trait-on path**. The only executers are the example run and the nightly workflow, and `verification.yml` itself documents that on a GitHub-hosted runner the sim-use-dependent checks report `SKIP`/`DEVICE` rather than passing.
* The repository discloses the compile half of this honestly (`docs/TOOLING.md` §12; `README.md:239, 584, 590-592`), which lowers the severity but does not close the gap: the §4 row 5 cell still says **`measured`**, and the measurement it points at (`capability-matrix.md` §3 rows 4 and 6) came from a manual example run, not from a gate that runs on every change to the private file.

**F-R1-8** records this as a finding rather than assuming the green suite covers the path.

---

## 10. Acceptance item — the `Package.swift` delta is functionally inert

`mise run format` and `mise run format:check` cover `Package.swift` (that is the frozen task's file scope), so the formatter edited a file outside the reformat's declared paths. Independent confirmation (C32 — my own tokeniser, not the implementer's summary):

```
HEAD  Package.swift : 142 tokens
tree  Package.swift : 148 tokens
token-stream difference: 6 insertions, every one a ',' immediately before a ']'
   .iOS(.v15) ) ]      targets: ["ScreenGuard"] ) ]      .default(enabledTraits: []) ]
   .when(traits: ["PrivateAPI"]) ) ]      .swiftLanguageMode(.v5) ) ]      ) ]
identical after removing every comma: True
```

Functional tokens — `swift-tools-version`, platforms, products, the `PrivateAPI` trait block with its `.default(enabledTraits: [])`, target settings and `.swiftLanguageMode(.v5)` — are unchanged, and the candidate manifest compiles and tests green (`BUILD SUCCEEDED`, `131/13/0` in C21; `demo:build` compiles the trait-on configuration from the same manifest). **Verdict: PASSED — trailing commas and one blank line only; no functional delta.**

---

## 11. Findings

**F-R1-1 — `high` — the public class lost its declared `@MainActor`, changing the consumer-visible interface and contradicting the contract** · `Sources/ScreenGuard/Shield/ScreenGuardShieldView.swift:39` (the attribute was on HEAD `:100`) · contract `docs/api-contract.md` §6.4:555, §1:104, §10:1132

*Problem.* `@MainActor` `public final class ScreenGuardShieldView: UIView` is now a bare `public final class ScreenGuardShieldView: UIView`. This is not a formatter artefact (the pinned formatter over HEAD's file keeps the attribute — C1), it is not recorded in the §13 amendment ledger, and it is invisible to every gate in the repository: the class is still `@MainActor` by inheritance from `UIView`, so the default build, the whole test suite and the trait-enabled demo build all stay green. What it does change is what a consumer's compiler is told: 18 declarations in the emitted interface gained `@preconcurrency`, and a Swift 6 consumer that gets a hard error for calling the shield from a nonisolated context against HEAD gets only a warning against the candidate (C7, C8). The published contract states the opposite twice, and `CHANGELOG.md:27-29` claims the API dumps are identical.

*Required fix.* Add `@MainActor` back to the class declaration (one line) and re-run the interface/API comparison so the "no API change" claim is true. I verified this fix in throwaway copies: with it, `format:check` / `lint` / `build` / `test` are all exit 0 (131/13/0) **and** the emitted interface is byte-identical to HEAD's class line, with `@preconcurrency` back at 6 (C7, C21). If the removal is instead intended, §1/§6.4 and the CHANGELOG must be amended to say the class is main-actor isolated only by inheritance and imported as `@preconcurrency` — but that weakens the isolation contract for a UI type, and I recommend the restore.

**F-R1-2 — `medium` — the CHANGELOG asserts an API identity its own cited tool falsifies** · `CHANGELOG.md:27-29`

*Problem.* "a `swift-api-digester` dump … **is identical to** the pre-baseline revision's … the dumps match once build-path metadata is normalised away". "0 declarations added, 0 removed" reproduces; "identical" does not: the emitted interfaces differ for 18 declarations, and t8's own `-diagnose-sdk` run prints 19 Decl Attribute changes. A reader who runs the cited tool finds the opposite of the sentence.

*Required fix.* Either apply F-R1-1 (then re-measure and keep the sentence only if the digester agrees), or reword to what is measured: "0 declarations added or removed; the only difference is an inferred `@preconcurrency` on `ScreenGuardShieldView` and its members, introduced when the explicit `@MainActor` was dropped from the class declaration".

**F-R1-3 — `medium` — stale "no canonical remote URL" disclaimer** · `README.md:129`

*Problem.* The line tells the reader the repository does not assert a URL, while `README.md:3,109,120,136`, `.github/CODEOWNERS`, `.github/ISSUE_TEMPLATE/config.yml`, `SECURITY.md` and `.github/pull_request_template.md` all assert `github.com/mo5tone/ScreenGuard`. The t6 hand-off says this disclaimer was removed; it is still there.

*Required fix.* Delete `README.md:129` and re-read the surrounding Xcode instructions without it.

**F-R1-4 — `medium` — the untrusted-config failure is described wrongly for `mise run`** · `README.md:146-148`, `CONTRIBUTING.md:56-59` (and the comment at `.github/workflows/ci.yml:125-128`)

*Problem.* "every `mise run …` fails with `Config files … are not trusted` until it is trusted" is false on the pinned mise (2026.9.6): in a fresh untrusted copy `mise tasks` exits 1 with exactly that error, but `mise run format:check` exits **0** and silently auto-trusts the config (C22, C23). This is a falsifiable statement about behaviour that a reader hits on the first command they type — the worst place for this repository to be wrong.

*Required fix.* State what was measured: `mise trust` is required for the *discovery* commands (`mise tasks`, `mise ls`, `mise env`), while `mise run` auto-trusts the config in normal mode — which is exactly why the CI "Trust the repository mise config" step uses `mise tasks` as its check. The instruction to run `mise trust` first stays.

**F-R1-5 — `medium` — the 13-skip breakdown is wrong in the section about measurement honesty** · `README.md:588-590`

*Problem.* The prose says 6 PrivateAPI + **3 device** + **2 "human or hardware"** + 2 window-scene. The run emits 6 `PRIVATEAPI-REQUIRED` + **5 `DEVICE-REQUIRED`** + 2 `SCENE-REQUIRED`, and no "human or hardware" category exists (my control run, C16). The five device skips are the five methods of `ScreenGuardDeviceOnlyTests`. The table above it is correct, which makes the prose look like a stale count.

*Required fix.* Restate as observed: "6 require the `PrivateAPI` trait, 5 require a physical device, 2 require a connected `UIWindowScene`".

**F-R1-6 — `low` — "3 files skipped" is 2 in the published tree, and an authored file is silently unpublished** · `README.md:579`, `.gitignore:67`

*Problem.* `Research/Artifacts/*` ignores `Research/Artifacts/README.md`, which exists in the author's tree (hence 3 skipped) and not in a clone (2 skipped — C12/C23). A reader re-running the documented command sees a different number than the README, in the same table that claims to be a fresh measurement.

*Required fix.* Quote 2, or add `!Research/Artifacts/README.md` (as the four canonical run directories already are) so the figure and the published tree agree.

**F-R1-7 — `low` — a documented, copy-pasteable command uses a destination that does not exist** · `CONTRIBUTING.md:93`; the same example at `.mise.toml:20` and `.mise.toml:234`

*Problem.* `DESTINATION='platform=iOS Simulator,name=iPhone 16,OS=18.0' mise run test` fails on this toolchain (`no available device named 'iPhone 16' on runtime '18.0'`; installed runtimes are 26.0 / 26.2 / 26.5), and the SIMULATOR CONTROL instructions at `.mise.toml:234` use the same pair. The surrounding text presents it as *the* override example.

*Required fix.* Use a destination that exists on the pinned toolchain (for example `name=iPhone 17 Pro,OS=26.2`), or state explicitly that the example needs a runtime installed with `xcodebuild -downloadPlatform iOS`.

**F-R1-8 — `low` — the trait-gated private path is compiled by CI but executed by no required gate** · `Tests/ScreenGuardTests/ScreenGuardRendererContentTests.swift:41`, `Tests/ScreenGuardTests/ScreenGuardShieldRegressionTests.swift:31`, `.github/workflows/ci.yml:227`, `.github/workflows/verification.yml`, `docs/api-contract.md` §4 row 5

*Problem.* The six behavioural tests of the private path skip in every per-PR and release configuration (default traits off); `demo:build` only compiles the path; the only executers are `Scripts/verify_capture.sh` (deliberately not a required check) and the nightly workflow — which documents that sim-use-dependent checks report `SKIP`/`DEVICE` on a hosted runner. So the §4 row 5 `measured` cell is backed by a manual run, and a regression inside the private path can reach a tag without any required gate failing. (The compile-level half is already disclosed in `docs/TOOLING.md` §12.)

*Required fix.* Close the execution gap or state it where the cell is quoted: either add a trait-enabled `mise run test` (or a required `demo:verify` on `main`/tags) to the pipeline, or annotate §4 row 5 and the README's CI section with "measured by a manual example run, not by a required check".

**F-R1-9 — `low` — two documented setters were relaxed and three signatures are spelled differently** · `Sources/ScreenGuard/Shield/ScreenGuardShieldView.swift:111`, `:120`, `:212` (`init?(coder:)`), with the same internal-parameter rename in `ScreenGuardWatermarkView.swift` and `ScreenGuardSecureTextField.swift`

*Problem.* `hasPushedFrame` and `protectionFailure` are now `public internal(set)` where HEAD and contract §6.4 say `public private(set)`; `init?(coder:)` and `draw(_:)` now print with an elided internal parameter name. None of this is reachable by a consumer (internal setters and internal parameter names are not part of the imported API), so it is contract drift rather than a break — but "no API change" is imprecise without it.

*Required fix.* Restore `private(set)` (module-internal writes can go through an internal method, or the write can stay in the main file), or record the relaxation in the §13 ledger and in §6.4's quoted surface.

**F-R1-10 — `low` — a doc comment was reattached to the wrong declaration during the file split** · `Sources/ScreenGuard/Shield/ScreenGuardSampleBufferFactory.swift:22-34`

*Problem.* When `makeBitmapContext` was extracted and placed above `enqueue`, the two comment blocks became contiguous: `enqueue(_:into:)`'s documentation ("Enqueues image into layer, flushing a failed renderer first … Returns: true when a sample buffer was produced and enqueued") is now attached to `makeBitmapContext(for:width:height:)` — which has no comment of its own, and whose own sentence ("A BGRA bitmap context over the pixel buffer base address") is the last paragraph of that merged block. The factory's two helpers are documented as each other.

*Required fix.* Separate the two blocks and give `enqueue` its documentation back (the split is otherwise faithful: the body is token-equivalent to HEAD's).

**F-R1-11 — `informational` — 70 personal absolute paths in 14 published files** · `Research/Artifacts/**/{build.log,unified-log.txt,app-documents/*.log}` (the largest share), `docs/TOOLING.md`, `docs/evidence/{review-round1,review-round2,verification-report,publish-verification}.md`

*Problem.* Publishing exposes `/Users/jiefu/…`, CoreSimulator container UUID paths, and one reference to `/Users/jiefu/.agents/skills/sim-use/SKILL.md`. There is **no credential** in any of them (C10), but a stranger can read the maintainer's username, directory layout and the machine the measurements came from.

*Required fix.* Optional and non-blocking: scrub paths on the next artifact refresh (home-directory / repo-root substitution in the logged commands), or accept them and note in `docs/evidence/` that the raw logs are published verbatim. The captain is already tracking this.

**F-R1-12 — `high` (operational, publish step — not a defect of the tree) — `git commit` fails in this environment** · the global `~/.gitconfig` (no repo-local override)

*Problem.* The global config sets `commit.gpgsign=true`, `gpg.format=ssh` and `gpg.ssh.program=/Applications/1Password.app/Contents/MacOS/op-ssh-sign` with a `user.signingkey`, and there is no repository-local override. In a scratch repository `git commit` dies with exit `128` — `error: 1Password: failed to fill whole buffer` / `fatal: failed to write commit object` — while the same commit succeeds with `-c commit.gpgsign=false` (C25, C26). The publish step (t10) will hit this on its first commit unless it runs non-interactively with signing disabled, or the 1Password agent is unlocked.

*Required fix.* For the publish: `git -c commit.gpgsign=false commit …`, or `git config --local commit.gpgsign false` in the clone (and the same for tag creation), so the publish does not depend on an interactive agent. Not a reason to hold the tree.

---
## 12. What I did NOT check

Stated plainly, with the reason. Everything below is **not verified by this review**, and every verdict above applies only to what I did check.

1. **Any GitHub-side behaviour.** There is no remote, no runner and no token use: I did not execute `.github/workflows/*` on GitHub, did not create the repository, did not check branch protection (`Scripts/ci/branch-protection.sh` was read, never run — it needs an authenticated remote), did not push a tag, did not run the release workflow, and did not confirm that `pr-title` / `quality` / `build-and-test` are configured as required status checks. The workflow *files* were read, and their failure semantics were read and locally demonstrated — that is all.
2. **The runner's toolchain.** The workflows target `macos-26` (Xcode 26.6 / iOS 26.2 SDK) while every measurement here, mine included, ran on Xcode 27.0 / iPhoneSimulator27.0.sdk. The workflow file itself names this as a known risk. I did not build or test against the runner's SDK.
3. **The device-only and capture-path measurements.** No physical device was attached. I did not re-run `Scripts/verify_capture.sh` (the ~30-minute Simulator run) and did not decode any capture PNG. The private-path `measured` claim, the `PASS 29 / DEVICE 4` counts and the pixel readings are cited from `docs/evidence/capability-matrix.md`, `docs/evidence/publish-verification.md` (t8) and the committed artifacts. Concretely: **I did not independently reproduce the §4 row 5 pixel measurement.**
4. **Runtime behaviour on a device or a Simulator.** All of my behavioural checks are static (tokens, interfaces, function bodies) plus the unit suite (131 tests, Simulator, trait off). The SwiftUI route, the app-switcher cover, the DocC build (`docs.yml`) and the demo's on-screen behaviour were not exercised by me.
5. **`.spi.yml`, `cliff.toml`, `docs/PUBLISHING.md` and the release mechanics.** `cliff.toml` was not executed against the history (no tag exists); the Swift Package Index manifest's effect cannot be tested before publication; the release job's tag/CHANGELOG cross-checks were read, not run.
6. **Dependency and licence review.** `Package.swift` declares zero dependencies, so there is no lockfile or transitive supply chain to inspect; I did not audit the licence text beyond noting that `LICENSE` exists and is referenced.
7. **Content correctness of the evidence documents.** I checked that the numbers quoted by the README and CHANGELOG appear in the evidence documents, and that the capability registry matches §4; I did not audit the correctness of `capability-matrix.md`, `device-run-procedure.md`, `verification-report.md`, `review-round1/2.md` or `repair-fr2-1.md` as measurement science.
8. **The exact byte content of every file.** Priority went to the paths that carry claims (Sources, Tests, README/CHANGELOG/CONTRIBUTING, `.github`, `Scripts/ci`, `.mise.toml`, `.gitignore`, `Package.swift`, contract §1/§4/§6/§10). `docs/TOOLING.md` was read in parts (§1, §12, targeted searches); the community templates and the `Research/Scripts/*.py` analysis code were not read line by line, and the committed PNG artifacts were not inspected visually.
9. **The demo/research lint debt (257 findings).** Advisory by design; I confirmed the task exits 0 and that the blocking `lint` covers `Sources`/`Tests`, but I did not review the 257 findings individually.
10. **Anything about the published state itself.** By definition unavailable before the publish: the README badges, the Swift Package Index page, the rendered DocC site and the GitHub Release were not checked.

---

## Appendix — raw excerpts behind the load-bearing claims

**A1. The formatter does not remove `@MainActor` (C1).**

```
$ mise exec -- swiftformat --config .swiftformat /tmp/sg-rev/swiftfmt-test/x.swift   # HEAD's ShieldView
Running SwiftFormat...
SwiftFormat completed in 0.31s.
1/1 files formatted.
$ grep -B1 'public final class ScreenGuardShieldView' /tmp/sg-rev/swiftfmt-test/x.swift
@MainActor
public final class ScreenGuardShieldView: UIView {
```

**A2. The interface delta (C7).**

```
$ diff -u head/ScreenGuard.swiftinterface current/ScreenGuard.swiftinterface | grep -E '^[-+].*(preconcurrency|class ScreenGuardShieldView)'
-@objc @_Concurrency::MainActor final public class ScreenGuardShieldView : UIKit::UIView {
+@objc @_Concurrency::MainActor @preconcurrency final public class ScreenGuardShieldView : UIKit::UIView {
+  @_Concurrency::MainActor @preconcurrency final public var protectedContentView: UIKit::UIView? {
 … 17 further member lines, all gaining @preconcurrency
@preconcurrency occurrences: head 6 · current 24 · restored 6
```

**A3. The consumer probe (C8).**

```
$ swiftc -typecheck -swift-version 6 -target arm64-apple-ios15.0-simulator -sdk <iphonesimulator> -I <module> consumer.swift
  # against the candidate module:
consumer.swift:7:18: warning: call to main actor-isolated initializer 'init(strategy:)' in a synchronous nonisolated context [#ActorIsolatedCall]     exit 0
  # against the same source with @MainActor restored:
consumer.swift:7:18: error:   call to main actor-isolated initializer 'init(strategy:)' in a synchronous nonisolated context [#ActorIsolatedCall]     exit 1
```

**A4. The untrusted-config behaviour (C22, C23).**

```
$ mise tasks
mise ERROR Config files in /private/tmp/sg-rev/fresh/.mise.toml are not trusted.        exit 1
$ mise run format:check
Running SwiftFormat...
0/71 files require formatting, 2 files skipped.                                          exit 0
```

**A5. The skip categories (C16, control run).**

```
6 × PRIVATEAPI-REQUIRED: the PrivateAPI package trait is not enabled in this build …
5 × DEVICE-REQUIRED:    not measurable on Simulator … Run on a physical device.
2 × SCENE-REQUIRED:     this test host has no key window in a connected scene …
Executed 131 tests, with 13 tests skipped and 0 failures (0 unexpected)
```

**A6. Restoring `@MainActor` is gate-clean (C21).**

```
### EXIT(format:check)=0    0/71 files require formatting, 2 files skipped.
### EXIT(lint)=0            Done linting! Found 0 violations, 0 serious in 39 files.
### EXIT(build)=0           ** BUILD SUCCEEDED **
### EXIT(test)=0            Executed 131 tests, with 13 tests skipped and 0 failures (0 unexpected)
```
