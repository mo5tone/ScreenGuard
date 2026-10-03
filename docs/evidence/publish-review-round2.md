# ScreenGuard — adversarial publish-readiness review, round 2 (task t12)

**Reviewer:** `reviewer` (Adversarial reviewer) · **Attempt:** `cdfb50de-edd2-4153-b014-b366c5f0a029`
**Date:** 2026-10-03 · **Repository under review:** `/Users/jiefu/Developer/ScreenGuarantor` (HEAD still `2263ac5`, **0 tags**, still no remote)
**Reviewed object:** the tree **after the t11 repair**, as the **publish set** (`git ls-files --cached --others --exclude-standard`, 153 paths) — i.e. what a `git add -A && git commit` would publish. Reviewed **against round 1** (`docs/evidence/publish-review-round1.md`, verdict `needs_revision`, findings F-R1-1 … F-R1-12), the pre-reformat revision `2263ac5`, and `docs/api-contract.md` §1/§4/§6/§10.
**The repair delta, computed by content, not by mtime:** exporting the round-1 publish set to `/tmp/sg-rev/fresh` and diffing it against the current tree gives **10 changed files** — `README.md`, `CHANGELOG.md`, `CONTRIBUTING.md`, `docs/evidence/capability-matrix.md`, `.github/workflows/ci.yml`, and five under `Sources/ScreenGuard/` (`Shield/ScreenGuardShieldView.swift`, `Shield/ScreenGuardShieldView+Refresh.swift`, `Shield/ScreenGuardSampleBufferFactory.swift`, `Watermark/ScreenGuardWatermarkView.swift`, `AppSwitcher/ScreenGuardAppSwitcherShield.swift`) — with `Tests/`, `Examples/` and `Research/` untouched. `.mise.toml` (the 11th) changed later and separately (task t13, the captain's concurrent fix of the last F-R1-7 copy) — verified as the only post-snapshot change.
**Deliverable note (contract ambiguity, stated rather than assumed):** the tool record for t12 has an empty `In scope` field and its acceptance list carries round 1's line *"No file outside docs/evidence/publish-review-round1.md was modified"*. That file is the terminal artifact of t9 and already contains round 1's verdict, so I treated it as append-forbidden and wrote **this** file instead, matching the task's own `round: 2` subject and the repository's existing `review-round1.md`/`review-round2.md` convention. Round 1's report is **unchanged**. If the captain wants a single file, this report is self-contained and can be appended.
**Write scope:** this file only; every experiment ran in copies under `/tmp/sg-rev/`.

---

## 0. Verdict

## **Verdict: `pass`** — 0 blockers, 0 high, 0 medium, **2 low** open, both cosmetic; every round-1 finding is closed and independently re-derived.

The one high finding of round 1 is gone in the strongest sense available: the emitted **library-evolution interface of the repaired module is identical to HEAD's**, declaration line for declaration line. I re-emitted it myself rather than accepting the repair's numbers — `@preconcurrency` occurrences are **6 in HEAD and 6 here** (round 1's tree had 24), all **157 public declaration lines compare equal**, and every `init?(coder: NSCoder)` and `draw(_ rect: CGRect)` line is byte-identical to HEAD. The only remaining differences between the two interfaces are **grouping**: one block (`ScreenGuard.PrivateAPI`) moved position, and `setNeedsContentRefresh()` now sits in an `extension ScreenGuardShieldView` block because it lives in the `+Refresh.swift` file. The repair's claim is not just plausible; it is exactly what the compiler prints.

The repair's code changes are behaviour-preserving by token evidence: the 18 restored annotations, two `private(set)` restorations routed through two internal recorders, four restored parameter names (each referenced with a documented `_ =` no-op), and a moved doc comment. Of 73 same-named function bodies, 61 are token-sequence identical to HEAD-formatted and the 12 that differ are each explained in §3: five are the recorder substitution (`x = v` → `recordX(v)`) and seven are round 1's rule-driven rewrites, one of which (the watermark `draw(_:)`) also gained the documented `_ = rect` no-op. The three `init?(coder:)` bodies, which my body comparator does not match, were read directly — each is exactly the commented `_ = coder` followed by `fatalError`.

Every gate still fails when it should: on a copy of the repaired tree I injected a formatting break (`format:check` **exit 1**), a lint break (`lint` **exit 2**), a build break (`build` **exit 65**) and a test break (`test` **exit 65**), each with a green control (C12–C18). The CI workflow's actions, permissions and blocking steps are unchanged from round 1 (C20), so its failure semantics are unchanged too.

The two low findings are **new and cosmetic**: six `…@BT@…@BT@` escape markers left in a comment block of the published `ci.yml` (F-R2-1), and one sentence in the new `capability-matrix.md` §9 whose "no account identifier" clause is in tension with its own admission that the logs carry `user`-local paths (F-R2-2). Neither misleads about a capability; both are one-line fixes. Per the acceptance rule — `pass` only when nothing above `low` is open — the verdict is **`pass`**, with those two recorded for the publish step to sweep if it wants a spotless comment set.

### 0.1 Item-by-item

| # | Review item | Verdict |
|---|---|---|
| 1 | Behaviour preservation of the reformat (and of the repair) | **PASS** — round 1's token analysis stands for the untouched files; the repair's 10 changed files are re-analysed in §3, and the interface is identical to HEAD (§2.1) |
| 2 | API stability vs `docs/api-contract.md` §6 | **PASS** — 157/157 public declaration lines identical to HEAD; 0 added, 0 removed, 0 re-signatured; 0 documented-but-absent symbols; F-R1-1 and F-R1-9 closed |
| 3 | Claim integrity | **PASS** — every figure the repair changed is one I re-measured: `2 files skipped`, 6/5/2 skips, `mise run` auto-trust, the interface claim in the CHANGELOG, the interface grouping claim. The two new low findings are wording, not figures |
| 4 | Gates that can actually fail | **PASS** — re-demonstrated by injection on the repaired tree (exit 1 / 2 / 65 / 65) with green controls; no `continue-on-error`, no `\|\| true` on a blocking step; actions and permissions unchanged |
| 5 | Publish hygiene | **PASS** — 0 credentials/tokens/keys in all 153 paths; no wrongly-tracked file; no ignored-but-needed file; personal paths 82 in 17 files (informational, +12 because round 1's own report and §9's example are now in the set) |
| 6 | Supply chain | **PASS** — unchanged from round 1: all 5 action refs 40-hex SHAs, least privilege per job, the only `ci.yml` delta is a comment block (C20) |
| 7 | Stale rationales | **PASS** — the two stale claims are fixed with measured replacements; the round-1 sweep is otherwise clean; the `iPhone 16 / 18.0` copies are gone from CONTRIBUTING and .mise.toml |
| A | Trait-gated coverage | **PASS as recorded** — the gap is now stated in `ci.yml` and the README CI section; I verified the "no supported mechanism" evidence myself (C24) |
| B | `Package.swift` delta | **PASS** — untouched by the repair; round 1's six-comma token result still applies |

---
## 1. Commands I ran, with exit codes

Everything is my own run, in copies under `/tmp/sg-rev/`. "The copy" is the repaired publish set exported with `git ls-files -z --cached --others --exclude-standard | tar`.

| # | Command | Exit | Result |
|---|---|---|---|
| C1 | `diff -rq` round-1 snapshot vs current publish set | 0 | exactly **11 files** differ (the 10 repair targets + `.mise.toml` from t13); nothing added or deleted except this round's report |
| C2 | `swiftc -enable-library-evolution -emit-module-interface` for the repaired sources | 0 | built clean |
| C3 | `diff` HEAD interface vs repaired interface | 1 (expected) | **9 `–` lines / 11 `+` lines, all block movement** (see C4); no attribute, signature or parameter-name change |
| C4 | sorted `public …` declaration lines, HEAD interface vs repaired interface | 0 | **157 lines, identical** — `PUBLIC DECLARATION LINES IDENTICAL` |
| C5 | `@preconcurrency` count: HEAD / round-1 tree / repaired tree | — | **6 / 24 / 6** |
| C6 | `grep 'init?(coder\|func draw'` in both interfaces | — | all four `init?(coder: Foundation::NSCoder)` and the `draw(_ rect: CoreFoundation::CGRect)` line byte-identical to HEAD |
| C7 | function-body token-sequence comparison (73 bodies by name), HEAD-formatted vs repaired | — | **61 identical, 12 differing**, each explained in §3; 17 new helper names, 0 removed |
| C8 | global token multiset, HEAD-formatted `Sources` vs repaired `Sources` | — | A 8383 / B 8685 tokens; every delta is a recorder call, a restored parameter name, or a known round-1 rewrite |
| C9 | copy, control: `mise run format:check` / `mise run lint` | 0 / 0 | `0/71 files require formatting, 2 files skipped` · `Found 0 violations, 0 serious in 39 files` |
| C10 | copy + formatting break → `mise run format:check` | **1** | `Source input did not pass lint check. 1/71 files require formatting` |
| C11 | copy + 160-char line → `mise run lint` | **2** | `Found 1 violation, 1 serious in 39 files` |
| C12 | copy + type error → `mise run build` | **65** | `** BUILD FAILED **` |
| C13 | copy, control: `mise run test` | 0 | `** TEST SUCCEEDED **` — `Executed 131 tests, with 13 tests skipped and 0 failures` |
| C14 | copy + one failing XCTest → `mise run test` | **65** | `R2GateProbeTests.testDeliberateFailureProbe failed` … `Executed 132 tests, with 13 tests skipped and 1 failure` → `** TEST FAILED **` |
| C15 | each break reverted and the gate re-run | 0 | `restored-format` 0, `restored-lint` 0, `restored-test` 0 (the injections, not the tree, caused the reds) |
| C16 | skip categories in the control run: `grep -oE '(PRIVATEAPI\|DEVICE\|SCENE)-REQUIRED'` | — | **6 / 5 / 2** per run (18/15/6 across three runs) — exactly the README's new prose |
| C17 | `mise exec -- actionlint` / `mise run shellcheck` / `shellcheck Scripts/ci/*.sh` | 0 / 0 / 0 | the repaired workflow still lints; the scripts still lint |
| C18 | fresh untrusted copy: `mise tasks` / `mise ls` / `mise env` / `mise run format:check` | **1 / 1 / 1 / 0** | CONTRIBUTING's new asymmetry is exact: all three discovery commands exit 1 with `are not trusted`, `mise run` auto-trusts and prints `2 files skipped` |
| C19 | AUTHOR TREE `mise run format:check` | 0 | `3 files skipped` — the README's parenthetical ("a working tree that still has that file reports 3") is the number I measure here |
| C20 | `diff` of every `uses:` / `permissions:` / `contents:` / `pages:` / `id-token:` line of `ci.yml` | 0 | **identical to round 1** — the repair added a comment block only |
| C21 | secret sweep over all 153 publish-set paths | — | **0 credentials, tokens or keys** (the only hits are prose in the two review/verification documents that quotes the patterns) |
| C22 | `/Users/` sweep over the publish set | — | **82 occurrences in 17 files** — 70/14 before this round plus 4 in round 1's report and 1 in the new §9 note |
| C23 | `git status --porcelain \| wc -l` and the untracked list | — | 98 lines = 70 modified + 23 untracked + 5 staged deletions; the +1 modified vs round 1 is `docs/evidence/capability-matrix.md` (clean before, +11 lines now) and the +1 untracked is round 1's report |
| C24 | `xcodebuild -help \| grep -ci trait`; `xcodebuild … -traits PrivateAPI`; `swift test --traits PrivateAPI` | 0 / **64** / **1** | zero mentions of "trait"; `invalid option '-traits'`; `unable to resolve module dependency: 'UIKit'` — the ci.yml comment's evidence, verified word for word |
| C25 | `diff -u` of the 11 repaired files | 0 | the repair delta read line by line (§3) |

---

## 2. The twelve round-1 findings, re-adjudicated

Each row was re-derived from the current file, not from the repair summary.

| Round-1 finding | Status | Evidence in this attempt (mine) |
|---|---|---|
| **F-R1-1** `high` — `@MainActor` removed from the public class | **CLOSED** | `@MainActor` is back **with** the class doc comment (`ScreenGuardShieldView.swift:39-63`); the interface's `@preconcurrency` count is **6 = HEAD** and the class line is byte-identical (C2–C6). The formatter is not involved: round 1's control run (SwiftFormat 0.63.0 + the repo config over HEAD's file) already showed the attribute survives formatting |
| **F-R1-2** `medium` — CHANGELOG claimed an API identity the digester falsifies | **CLOSED** | The sentence is replaced by measured claims: `0 declarations added, 0 removed`, `@preconcurrency` **6 times in both revisions**, the class line byte-identical, and "the remaining deltas are grouping only: the order of the declaration blocks, and one extra extension block because setNeedsContentRefresh() now lives in the +Refresh file". **Every clause reproduces** (C3–C5); the old "normalised away" wording is gone (verified by grep) |
| **F-R1-3** `medium` — stale "no canonical remote URL" disclaimer | **CLOSED** | `README.md:129` deleted; the local URL assertions are now the only ones in the file |
| **F-R1-4** `medium` — untrusted-config failure described wrongly | **CLOSED** | README and CONTRIBUTING now state the measured asymmetry: discovery commands fail, `mise run` auto-trusts. I measured all four commands (C18): `mise tasks`/`ls`/`env` exit **1**, `mise run format:check` exits **0** |
| **F-R1-5** `medium` — 13-skip breakdown wrong | **CLOSED** | README now says 6 PrivateAPI / 5 physical-device / 2 window-scene. My control run emits exactly 6 / 5 / 2 (C16) |
| **F-R1-6** `low` — "3 files skipped" is 2 in the published tree | **CLOSED** | README now quotes **2** and explains the difference in the same cell; I measured **2** in the publish set (C9, C18) and **3** in the author tree (C19). The excluded file is not needed by any documented clone path (round 1 established that; unchanged) |
| **F-R1-7** `low` — documented destination that does not exist | **CLOSED** | `CONTRIBUTING.md:93` now uses `name=iPhone 17 Pro,OS=26.2` with `xcrun simctl list devices available` and `xcodebuild -downloadPlatform iOS` beside it; `.mise.toml` (t13) no longer contains the `iPhone 16 / 18.0` pair anywhere — verified by grep; both are destinations the preflight accepts (round 1, C20) |
| **F-R1-8** `low` — trait-gated path executed by no required gate | **CLOSED AS RECORDED** (captain decision) | `ci.yml` carries a new comment block stating the gap and the two closest achievable gates; the README CI section states it too. I verified the supporting evidence independently (C24) and re-confirmed the coverage matrix is unchanged: compiled by `demo:build`, executed only by `demo:verify`/nightly, 6 tests skip in every PR/release configuration. Per the captain, §4 row 5 keeps `measured` — the gap is a coverage property, and it is now stated where a reader will see it |
| **F-R1-9** `low` — setters relaxed and three signatures re-spelled | **CLOSED** | `hasPushedFrame` and `protectionFailure` are `public private(set)` again, with module-internal writes routed through `recordPushedFrame(_:)` / `recordProtectionFailure(_:)` (whose bodies are exactly the assignments); all four `init?(coder: NSCoder)` and `draw(_ rect: CGRect)` lines match HEAD byte for byte (C6). The interface delta is now grouping only |
| **F-R1-10** `low` — doc comment reattached to the wrong declaration | **CLOSED** | `enqueue(_:into:)` owns its doc comment and `@discardableResult` again; `makeBitmapContext` moved below `makeSampleBuffer` with its own comment restored |
| **F-R1-11** `informational` — personal absolute paths in published files | **CLOSED BY DECISION** | `docs/evidence/capability-matrix.md` §9 now states that the artifacts are published verbatim and therefore carry machine-local paths, with no credential among them. My sweep confirms: 0 credentials; the paths are still there by design. One wording nit remains — **F-R2-2** |
| **F-R1-12** `high` (operational) — `git commit` fails under 1Password signing | **CLOSED AT THE DOCUMENTATION LEVEL** | CONTRIBUTING has a new "Signing is not required for commits or tags" section naming `git -c commit.gpgsign=false commit …` / `git config --local commit.gpgsign false`, which is the workaround I measured in round 1 (exit 128 → 0). The environment itself is unchanged, so t10 must actually use it |

---

## 3. What the repair changed, verified line by line

The 11-file delta (C1), read in full (C25):

* **`ScreenGuardShieldView.swift`** — the class doc comment and `@MainActor` restored; the two properties back to `private(set)`; two new **internal** recorders (`recordPushedFrame(_ pushed: Bool)` → `hasPushedFrame = pushed`; `recordProtectionFailure(_ failure:)` → `protectionFailure = failure`); every internal write site in the class body converted to a recorder call; `init?(coder:)` restored with a commented `_ = coder`.
* **`ScreenGuardShieldView+Refresh.swift`** — five write sites converted to recorder calls (`engagePublicPath`, `refresh`, `teardown`, `fail`, and the frame-result assignment). No other change.
* **`ScreenGuardWatermarkView.swift`** — `init?(coder:)` with `_ = coder`; `draw(_ rect: CGRect)` with a commented `_ = rect` (the tiles are laid out over `bounds`, so the parameter really is unused; the no-op keeps the name the interface documents).
* **`ScreenGuardAppSwitcherShield.swift`** — `init?(coder:)` with `_ = coder`. (The fourth site, `ScreenGuardSecureTextField.swift`, needed no change: it has always used its parameter via `super.init(coder: coder)` — my round-1 note named the wrong third file.)
* **`ScreenGuardSampleBufferFactory.swift`** — comment blocks separated; `makeBitmapContext` moved below `makeSampleBuffer`; the body unchanged.
* **`README.md` / `CHANGELOG.md` / `CONTRIBUTING.md` / `docs/evidence/capability-matrix.md` / `ci.yml`** — documentation and comments only, adjudicated in §2 and §5.

**Behaviour preservation of the repair itself:** the global token multiset (C8) differs only by recorder calls (`hasPushedFrame` ×8 and `protectionFailure` ×2 become `recordPushedFrame`/`recordProtectionFailure`), the restored parameter names (`coder` +3), the `_` tokens they add (+5), and the trailing commas/blank-line deltas round 1 already enumerated. The 12 differing function bodies (C7) are: `apply`, `engagePublicPath`, `fail`, `refresh`, `teardown` (recorder substitution, first difference at the exact write site), `draw` (`_ = rect` prepended), plus round 1's rule-driven rewrites (`engage`, `layoutSubviews`, `makeSampleBuffer`, `registerForDisplayScaleChanges`, `resolvedWindow`, `statusRecord` — the other six, two of which are inside the ShieldView split). `_ = coder` and `_ = rect` are no-ops placed before the existing first statement; neither can change control flow. No function name was removed (17 new helpers, all present in the tree).

**The interface, re-derived rather than accepted:** C2–C6. `@preconcurrency` **6 vs 6**; **157 sorted public declaration lines identical**; the only diff lines are one moved extension block and `setNeedsContentRefresh()` moving into an `extension ScreenGuardShieldView` block. That is the strongest statement available short of a byte-identical file, and it is exactly what the repair claims — with the qualification that the interface is *grouped* differently, so "byte-identical" applies to every declaration line, not to the file as a whole.

---
## 4. The remaining review items, re-checked against the repaired tree

**Item 4 — gates that can actually fail (demonstrated, not asserted).** Same method as round 1, re-run on a copy of the repaired publish set: one injected break at a time, the same task the workflow runs, with a green control on the same copy (C9–C16).

| Gate | Injected break | Exit | Control on the same copy |
|---|---|---|---|
| `format:check` | a line SwiftFormat must rewrite | **1** | 0 |
| `lint` | a 160-character line | **2** | 0 |
| `build` | a Swift type error | **65** (`** BUILD FAILED **`) | control build after revert: **0**, `** BUILD SUCCEEDED **`, 0 warnings |
| `test` | one `XCTAssertTrue(false)` test | **65** (`** TEST FAILED **`, 132 executed / 1 failure) | 0 (`131 executed, 13 skipped, 0 failures`) |
| `check-pr-title.sh` / `check-destination.sh` | round 1's injections still stand; both scripts are untouched by the repair | 1 / 1 | 0 / 0 |

**Failure semantics:** the workflow's `uses:` and `permissions:` lines and all eight blocking `run:` steps are **identical to round 1** (C20); the only `ci.yml` change is a comment block. `actionlint` still passes (C17), so the new comments did not break the YAML. What this does not prove is unchanged from round 1: no GitHub runner executed any of it (§6).

**Item 5 — publish hygiene.** 0 credentials/tokens/keys across all 153 publish-set paths (C21); no `__pycache__`, `.DS_Store`, backup or editor file; no symlink; the three tracked deletions (generated project) and two `.pyc` deletions are still staged; the generated projects are still ignored and regenerable. Personal absolute paths: **82 in 17 files** (C22) — the same defect class as round 1 (70/14), now documented on purpose in `capability-matrix.md` §9, and increased by my own round-1 report being part of the published set. No credential; informational, as adjudicated.

**Item 6 — supply chain.** Unchanged: five action references, all full 40-hex SHAs; workflow-level `contents: read` with `release` as the only writer (`contents: write`, `needs: [gate]`); `docs` deploy adds only `pages: write` + `id-token: write`; no `pull_request_target`, no `workflow_run`, no `secrets.*`; the three `if: always()` steps in `verification.yml` are the evidence/verdict steps and the verdict step still fails an inconclusive run.

**Item 7 — stale rationales.** The two stale claims are gone (F-R1-3, F-R1-4) and the third copy of the dead destination example is gone from `.mise.toml` (t13). Re-swept: the `124 tests / 11 skips` figures remain only in sections labelled historical; the `.mise.toml` shim rationale still describes the past correctly; `.gitignore`'s generated-project and artifact comments still match their rules; `lint:demo` is still described as advisory everywhere. One new wording issue: **F-R2-2**.

**Acceptance item A — trait-gated coverage.** Re-established: the trait-off branch is the default build and is covered by `mise run test` (131 executed, 6 skips are `PRIVATEAPI-REQUIRED`); the trait-on branch is **compiled** by `mise run demo:build` in CI and **executed** only by `Scripts/verify_capture.sh` (`demo:verify`, opt-in default GRANTED, and the private-path pixel assertion is not sim-use gated — I checked `HAVE_SIM_USE` is used only for the app-switcher backgrounding). No path is compiled by no gate; the execution gap is now stated in `ci.yml` and the README. The three evidence lines in the new comment are true as written (C24).

**Acceptance item B — `Package.swift`.** Unchanged by the repair (C1). Round 1's result stands: 142 → 148 tokens, six inserted commas, identical after removing commas, and the manifest builds and tests green.

---

## 5. New findings

**F-R2-1 — `low` — six unexpanded escape markers left in a published workflow comment** · `%.github/workflows/ci.yml` lines 233–241 (six occurrences: 233, 234, 235, 237, 241)

*Problem.* The repair's new comment block renders code fragments as `…@BT@xcodebuild -help@BT@…`, `…@BT@xcodebuild test … -traits PrivateAPI@BT@…`, `…@BT@xcodebuild: error: invalid option '-traits'@BT@` and `…@BT@mise run demo:build@BT@…` — the backticks the comment intended were replaced by a tooling escape marker that was never expanded. The comment is otherwise true and useful, and YAML does not care (actionlint passes), but this is a published file and the marker is an artefact of the repository's own tooling, which is the class of thing a stranger notices first.

*Required fix.* Replace each `…@BT@…` pair with a backtick-quoted fragment (or plain quotes), then re-run `mise exec -- actionlint` and `mise run format:check` (comment-only change: both stay green). Six replacements in one file.

**F-R2-2 — `low` — the new artifacts note claims "no account identifier" while the same sentence admits user-local paths** · `docs/evidence/capability-matrix.md` §9 (appended block)

*Problem.* The note says: "No credential, token or account identifier appears in any of them, and the machine-local paths are the only content of that kind". The logs it describes contain 49 + 21 occurrences of `…/Users/jiefu/…`, i.e. the machine's user name is part of the path content being disclosed, and the note's own example is written `…/Users/<user>/…`. The credential half is true (0 matches, C21); the "account identifier" half is in tension with the clause that follows it, and a careful reader will notice.

*Required fix.* Either drop "or account identifier", or say what is true: "no credential or token; the logs do carry the machine's user name inside absolute paths, which is the only machine-local content of that kind". One sentence.

*(The two `_ =` references added to keep the formatter from renaming `coder` and `rect` are **not** findings: both are documented at the site, both are no-ops placed before the existing first statement, and the alternative was a formatter configuration change. Recorded here so the next reader does not re-derive it.)*

---

## 6. What I did NOT check (round 2)

1. **Any GitHub-side execution.** Still no remote and no runner: the workflows were not run, branch protection is not configured, the release and docs pipelines are unexercised, and I cannot claim the `macos-26` runner (Xcode 26.6 / iOS 26.2 SDK) behaves like this machine (Xcode 27.0).
2. **The device and pixel measurements.** No device; I did not re-run `Scripts/verify_capture.sh` or decode any PNG. The private path's `measured` status, the `PASS 29 / DEVICE 4` counts and the pixel readings are cited, not re-measured.
3. **The nightly workflow's runner environment.** I verified the private-path assertion is not sim-use gated *in the script* and that the opt-in defaults to GRANTED, but I did not observe a hosted runner boot a Simulator and complete that check.
4. **Runtime behaviour on a device or Simulator.** All behavioural evidence here is static plus the unit suite; the SwiftUI route, the app-switcher cover and the DocC build were not exercised.
5. **`Package.swift` beyond the token comparison**, `cliff.toml`, `docs/PUBLISHING.md` and `release.yml` mechanics: unchanged this round, not re-run.
6. **Evidence-document correctness as measurement science.** I checked that quoted numbers exist and that the new claims match my own measurements; I did not audit the underlying capture experiments.
7. **The two new findings' blast radius.** `@BT@` appears only in `ci.yml` (I swept every other publish-set path for the pattern, plus a generic marker scan); the "account identifier" sentence is prose in one appended block. No other copy of either exists as far as those sweeps can tell.

---
## Appendix — raw excerpts behind the load-bearing claims

**A1. The interface delta is grouping only (C3, C4, C5).**

```
$ diff -u HEAD.interface repaired.interface | grep -E '^[-+][^-+]'
-extension ScreenGuard::ScreenGuard {
-  public enum PrivateAPI {
-    public static var isEnabled: Swift::Bool
-    @_Concurrency::MainActor public static var isCompiledIn: Swift::Bool {
-      get
-    }
-  }
-}
-  @_Concurrency::MainActor final public func setNeedsContentRefresh()
+  }
+}
+extension ScreenGuard::ScreenGuardShieldView {
+  @_Concurrency::MainActor final public func setNeedsContentRefresh()
+}
+extension ScreenGuard::ScreenGuard {
+  public enum PrivateAPI {
+    …
+
+$ grep -o 'public [a-zA-Z].*' HEAD.interface | sort > h.pub
+$ grep -o 'public [a-zA-Z].*' repaired.interface | sort > c.pub
+$ diff h.pub c.pub && echo 'PUBLIC DECLARATION LINES IDENTICAL'
+PUBLIC DECLARATION LINES IDENTICAL          # 157 lines
+
+$ grep -c '@preconcurrency' HEAD.interface repaired.interface round1.interface
+HEAD.interface:6
+repaired.interface:6
+round1.interface:24
```

**A2. Gate exits on a copy of the repaired publish set (C9–C16).**

```
### EXIT(control-format)=0        0/71 files require formatting, 2 files skipped.
### EXIT(control-lint)=0          Done linting! Found 0 violations, 0 serious in 39 files.
### EXIT(broken-format)=1         Source input did not pass lint check. 1/71 files require formatting
### EXIT(restored-format)=0       0/71 files require formatting, 2 files skipped.
### EXIT(broken-lint)=2           1 violation, 1 serious in 39 files (line_length)
### EXIT(restored-lint)=0         0 violations, 0 serious in 39 files
### EXIT(broken-build)=65         ** BUILD FAILED **
### EXIT(control-test)=0          ** TEST SUCCEEDED ** · Executed 131 tests, with 13 tests skipped and 0 failures
### EXIT(broken-test)=65          R2GateProbeTests.testDeliberateFailureProbe failed · 1 failure · ** TEST FAILED **
### EXIT(restored-test)=0         ** TEST SUCCEEDED **
(control build, separate run: EXIT(control-build)=0 · ** BUILD SUCCEEDED ** · 0 warnings)
```

**A3. Skip categories and the untrusted-config asymmetry (C16, C18, C19).**

```
6 × PRIVATEAPI-REQUIRED · 5 × DEVICE-REQUIRED · 2 × SCENE-REQUIRED   (per run; 18/15/6 over three runs)

$ mise tasks      -> exit 1  mise ERROR Config files … are not trusted.
$ mise ls         -> exit 1  mise ERROR Config files … are not trusted.
$ mise env        -> exit 1  mise ERROR Config files … are not trusted.
$ mise run format:check -> exit 0  0/71 files require formatting, 2 files skipped.
$ mise run format:check   (author tree, the ignored Research/Artifacts/README.md present)
                        -> exit 0  0/71 files require formatting, 3 files skipped.
```

**A4. The trait-enabled test suite is not achievable on this toolchain (C24) — verified, not accepted.**

```
$ xcodebuild -help | grep -ci trait
0
$ xcodebuild test -scheme ScreenGuard -destination '…iPhone 17 Pro,OS=26.2' -traits PrivateAPI
exit=64        (xcodebuild: error: invalid option '-traits')
$ swift test --traits PrivateAPI
error: …/ScreenGuardAppSwitcherShield.swift:20:8 unable to resolve module dependency: 'UIKit'
error: Build failed
exit=1
```

**A5. The published comment block that carries the marker artefact (F-R2-1).**

```
      #   * @BT@xcodebuild -help@BT@ mentions "trait" zero times, and
      #     @BT@xcodebuild test ... -traits PrivateAPI@BT@ exits 64 with
      #     @BT@xcodebuild: error: invalid option '-traits'@BT@.
```

**A6. The repaired screen-guard class head (F-R1-1 closed).**

```
/// Hosts content that must not leak into captures.
/// …
@MainActor
public final class ScreenGuardShieldView: UIView {
    …
    public private(set) var hasPushedFrame: Bool = false
    public private(set) var protectionFailure: ScreenGuardProtectionFailure?

    /// Records whether a protected frame was pushed. Internal, so the extension files in this
    /// directory can write it while the public surface stays read-only (private setter).
    func recordPushedFrame(_ pushed: Bool) {
        hasPushedFrame = pushed
    }
```
