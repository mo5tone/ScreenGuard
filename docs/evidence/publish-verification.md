# ScreenGuard — independent publish verification (task t8)

**Verifier:** `verifier` (Independent Verifier) · **Attempt:** `9b1c2db4-86a1-4a93-8f3e-5e591c0b95eb`
**Date:** 2026-10-03 · **Repository under test:** `/Users/jiefu/Developer/ScreenGuarantor` (no remote, 8 commits, **0 tags**)
**Written by the verifier.** Every number, exit code and output below comes from a command run in this attempt.
No result was copied from a teammate's summary; where a teammate's figure is repeated it is labelled as such and
marked verified or not.

---

## 0. Verdict at a glance

| # | Required check | Verdict | Where |
|---|---|---|---|
| 1 | `mise install` from the pinned file, shims resolving, untrusted-config case | **PASSED with a documentation defect** — the pinned toolchain installs and all six shims resolve; the documented "every `mise run` fails until trusted" claim does **not** reproduce (F4) | §C1 |
| 2 | `mise run format:check` + `mise run lint` — exit codes and counts | **PASSED** (0/71 formatting, 0 violations in 39 files) with one figure mismatch (F5) | §C2 |
| 3 | `mise run generate` then `git status` — no visible `.xcodeproj` | **PASSED** | §C3 |
| 4 | Package build + FULL test suite (baseline 131 executed / 13 skipped / 0 failures) | **PASSED**, baseline reproduced exactly | §C4 |
| 5 | Demo app build | **PASSED** | §C5 |
| 6 | Every command in README's build/verify sections and in CONTRIBUTING.md, run one by one | **PASSED for 15 of 16 commands**; the CONTRIBUTING destination example fails on this toolchain (F6) | §C6 |
| 7 | `actionlint` over every workflow; PR-title check exists and can fail | **PASSED** | §C7 |
| 8 | README capability table byte-for-byte against `docs/api-contract.md` §4 | **PASSED** — byte-identical | §C8 |
| 9 | Relative markdown links in README.md, CONTRIBUTING.md, Examples/ScreenGuardDemo/README.md | **PASSED** — 53/53 resolve; 104 links tree-wide, 0 broken, 0 dead anchors | §C9 |
| 10 | Grep for credentials, tokens, private keys, personal absolute paths | **PASSED with a judgement note** — no secrets; 60 `/Users/jiefu/…` occurrences in 14 published files (F7) | §C10 |
| 11 | Nothing states or implies a version has been released | **PASSED** | §C11 |
| 12 | Every published test-count figure reproducing from a run on the current tree | **FAILED** — the counts reproduce, the **skip breakdown in README.md:589-590 does not** (F1) | §C12 |
| A1 | PrivateAPI trait-ENABLED configuration built **and tested** | **PASSED** — trait-on test run: 131 executed / 7 skipped / 0 failures | §A1 |
| A2 | Public API compared against the pre-change revision (swift-api-digester) | **0 added / 0 removed reproduced; "identical" NOT reproduced** (F2) | §A2 |
| A3 | Package.swift trailing-comma delta confirmed non-functional by tokens | **PASSED** — token streams differ by exactly 5 commas | §A3 |

**Overall: the tree is publishable on the four load-bearing properties — the pinned toolchain installs from a
fresh clone, the generated Xcode project is reproducible and invisible to git, the format/lint gates are clean,
and the package builds and passes 131 tests (13 reasoned skips, 0 failures), including the trait-enabled
configuration that compiles the private path. Six deviations from the expected result were found; none of them
is a code or build failure, and five are published statements that the repository's own evidence contradicts.**

The single most important sentence in this report: **a green gate proves the gates pass — it does not make
README.md:589-590, CHANGELOG.md:27-29, README.md:129 and README.md:146-148 true, and those four statements are
false as written.**

### Findings requiring a decision (details in §F)

| ID | Severity | File:line | One line |
|---|---|---|---|
| F1 | medium | `README.md:589-590` | The 13-skip breakdown is wrong: the run reports **5** DEVICE-REQUIRED and **no** "human or hardware" group (3 claimed, 2 claimed) |
| F2 | medium | `CHANGELOG.md:27,29` | "the dumps match once build-path metadata is normalised away" is contradicted by the tool it cites: 18 declarations gained `@preconcurrency` |
| F3 | medium | `README.md:129` | "This repository does not assert a canonical remote URL" — the same file asserts `github.com/mo5tone/ScreenGuard` four times, and four other published files assert `mo5tone` |
| F4 | medium | `README.md:146-148`, `CONTRIBUTING.md:56-59` | "every `mise run …` fails with `Config files … are not trusted` until it is trusted" does not reproduce on mise 2026.9.6 — `mise run <task>` silently auto-trusts and executes |
| F5 | low | `README.md:579`, `.gitignore:67` | "3 files skipped" is 2 in the published tree, because `Research/Artifacts/README.md` is ignored and silently unpublished |
| F6 | low | `CONTRIBUTING.md:93` | The example destination `name=iPhone 16,OS=18.0` exits 70 on the Xcode the repository targets ("Unable to find a device matching the provided destination specifier") |

---

## 1. Method — how a "clean tree" was obtained before the publish commit, and its limits

Nothing is committed yet (`git log` has no commit containing the reshape), so a real clean checkout does
not exist. The method used instead is a faithful simulation of the publish commit, in three steps, all under
`/tmp/sg-verify/`:

1. **Export exactly what git would publish.** From the repository root:
   `git ls-files -z --cached --others --exclude-standard` (tracked files, plus untracked files that are
   not ignored) → **151 paths**; that list was materialised with
   `tar -C <repo> --null -c -f - -T <list> | tar -C /tmp/sg-verify/clean -xpf -`.
   Cross-checked against the publish step's own dry run in the author's tree:
   `git add --dry-run -A` → exit 0 and **no** `.xcodeproj`, `.xcworkspace`, `.pyc`,
   `__pycache__`, `.build/` or `.agent-teams/` path in the output.
2. **Make the simulated publish commit.** `git init -b main` + `git add -A` + one commit →
   `git status --porcelain -uall` is **empty**; `git ls-files` = 151.
3. **Clone it.** `git clone /tmp/sg-verify/clean /tmp/sg-verify/clone` → 151 files on disk, no
   `.xcodeproj`, no `__pycache__`, no build output, executable bits preserved
   (`Scripts/ci/*.sh` and `Scripts/verify_capture.sh` are `-rwxr-xr-x`).

**All gate commands in §C2–§C7 were run inside `/tmp/sg-verify/clone`, never in the author's working
directory.** Commands run in the author's repository are marked **[author tree]** and are read-only
(`git status`, `git add --dry-run`, `shasum`, `mise run format:check`).

**Drift check.** The publish set was recomputed after this report was written: **152** paths — the export's
151 plus this report, and nothing else. `diff` of the two sorted lists shows exactly one added path, and
per-file SHA-256 comparison over the other 151 files reported **0 new, 0 changed**. The verification therefore
applies to the exact file set that will be committed.

### What this method does **not** cover

* It is a **local** clone: no network fetch, no submodules (there are none), no LFS, no GitHub-side anything.
* It contains one commit of the current file contents. History, authorship, signed-commit behaviour, tags and
  branch protection are outside it.
* Ignored files in the author's tree are absent — exactly as in a real clone — so any claim whose only evidence
  lives in an ignored file cannot be re-checked from the clone (F5 is exactly such a case).
* The toolchain, Xcode and macOS are this machine's; "works on my machine" is not eliminated (same machine as
  the author's).
* Wall-clock figures (e.g. test seconds) are environment-dependent and are never used as a pass/fail criterion.
* No physical device exists here: every device-required cell stays unmeasured (see §NV).

## 2. Environment

```
macOS 26.6.2 (25G83) · Xcode 27.0 (27A266a) · iPhoneSimulator27.0.sdk · Apple Swift 6.4
mise 2026.9.6 macos-arm64 (2026-09-12)  — the version CI pins
Simulator iPhone 17 Pro / iOS 26.2 (DCF67420-9B92-463F-AE79-858C03C7AA38, already booted)
Available runtimes observed: iOS 26.0, iOS 26.2, iOS 26.5 (no iOS 18.x — see F6)
```

---

## C1 — `mise install` from the pinned file, shim resolution, and the untrusted-config case

**Commands and outputs**

```
$ mise --version                              # [clone]
2026.9.6 macos-arm64 (2026-09-12)             exit 0

$ mise install                                # [clone] documented step 2
mise by @jdx – installing 9 tools
mise ⇢ swiftlint@0.65.1    1ms · already installed
mise ⇢ swiftformat@0.63.0  0ms · already installed
mise ⇢ xcodegen@2.46.0     0ms · already installed
mise ⇢ actionlint@1.7.12   0ms · already installed
mise ⇢ shellcheck@0.11.0   0ms · already installed
mise ⇢ git-cliff@2.14.2    0ms · already installed
mise ⇢ flutter@3.47.0      0ms · already installed
mise ⇢ node@24.19.0        0ms · already installed
mise ⇢ ruby@4.0.6          0ms · already installed
mise ████████████████ 9/9 · installed 0 tools · 9 already installed in 4ms
mise all tools are installed                  exit 0
```

The 9 tools are the 6 the repository pins plus 3 inherited from the operator's **global** mise config
(`~/.config/mise/config.toml`: flutter, node, ruby). That is the same leakage CONTRIBUTING.md warns about
for tasks ("tasks inherited from your personal global mise config … do not exist on CI"), and it is worth
knowing that it also applies to tools.

**Shims resolving** — every pin resolves to the exact version in `.mise.toml`:

| Tool | `mise which` | `mise exec -- <tool> --version` |
|---|---|---|
| swiftlint | `…/mise/installs/swiftlint/0.65.1/swiftlint` | `0.65.1` |
| swiftformat | `…/installs/swiftformat/0.63.0/swiftformat` | `0.63.0` |
| xcodegen | `…/installs/xcodegen/2.46.0/xcodegen/bin/xcodegen` | `2.46.0` |
| actionlint | `…/installs/actionlint/1.7.12/actionlint` | `1.7.12` (go1.26.1 darwin/arm64) |
| shellcheck | `…/installs/shellcheck/0.11.0/shellcheck-v0.11.0/shellcheck` | `version: 0.11.0` |
| git-cliff | `…/installs/git-cliff/2.14.2/git-cliff-2.14.2/git-cliff` | `git-cliff 2.14.2` |

**The untrusted-config case.** Three genuinely fresh clones of the publish tree were used (A, B, C below),
because the outcome depends on which command runs first.

```
# clone A — query before trusting
$ mise trust --show                           exit 0
/private/tmp/sg-verify/cloneA: untrusted

$ mise tasks                                  exit 1        <-- the documented refusal, reproduced
mise ERROR error parsing config file: /private/tmp/sg-verify/cloneA/.mise.toml
mise ERROR Config files in /private/tmp/sg-verify/cloneA/.mise.toml are not trusted.
Trust them with `mise trust`. See https://mise.jdx.dev/cli/trust.html for more information

# clone B — the command the docs say must fail first
$ mise run format:check                       exit 0        <-- RAN. No error. See F4.
Reading config file at /tmp/sg-verify/cloneB/.swiftformat
0/71 files require formatting, 2 files skipped.
$ mise trust --show                           exit 0
/private/tmp/sg-verify/cloneB: trusted        <-- granted silently by the run itself

# clone C — same test with a pty allocated, to rule out "no TTY ⇒ auto-yes"
$ script -q /dev/null mise run format:check   exit 0
0/71 files require formatting, 2 files skipped.
$ mise trust --show
/private/tmp/sg-verify/cloneC: trusted

# the documented setup path, in order, in a fresh clone
$ mise trust                                  exit 0
mise WARN  No untrusted config files found.
$ mise install                                exit 0
$ mise tasks                                  exit 0   (14 names, see below)
```

**Verdict:** the documented setup path (trust → install → tasks) works and every pin resolves. The specific
claim that tasks **fail until trusted** does not reproduce for `mise run` — see **F4**. `mise tasks`,
`mise ls`, `mise env` and `mise current` do refuse (exit 1, the quoted error); `mise run <task>` and
`mise install` grant trust and proceed.

**`mise tasks` output (clone):** 14 names — the 11 the repository freezes
(`generate`, `format`, `format:check`, `lint`, `lint:demo`, `shellcheck`, `build`, `test`,
`demo:build`, `demo:verify`, `ci:local`) plus the 3 global ones (`derived_data`, `spm_cache`,
`spm_resolve`). CONTRIBUTING.md's gate table lists exactly those 11 and disclaims the rest — accurate.

---

## C2 — `mise run format:check` and `mise run lint`

```
$ mise run format:check                       # [clone]
[format:check] $ swiftformat --lint Package.swift Sources Tests Examples Resear…
Running SwiftFormat...
Reading config file at /tmp/sg-verify/clone/.swiftformat
SwiftFormat completed in 0.43s.
0/71 files require formatting, 2 files skipped.              exit 0

$ mise run lint                               # [clone]
Linting 39 files … (25 in Sources/, 14 in Tests/)
Done linting! Found 0 violations, 0 serious in 39 files.     exit 0

$ mise run shellcheck                         # [clone]
[shellcheck] $ shellcheck --severity=error Scripts/*.sh
(no output)                                                  exit 0

$ mise run lint:demo                          # [clone], advisory by design
Done linting! Found 257 violations, 257 serious in 31 files.
lint:demo is ADVISORY and exits 0 by design …                exit 0

$ mise run format                             # [clone], write mode — must be a no-op
[format] $ swiftformat Package.swift Sources Tests Examples Research
0/71 files formatted, 2 files skipped.                       exit 0
SHA-256 over all 71 .swift files, before/after:
  588643133721e12d61570054f97b02a827e5f0d9f3930607280d273109e9efe3 (identical)
```

**Violation counts:** format 0/71, lint 0 violations / 0 serious in 39 files, shellcheck 0 findings at
`--severity=error`, advisory `lint:demo` 257/257 in 31 files — each matches the current-measurement table
in README.md:580-581 and 586 exactly.

**One figure does not:** README.md:579 publishes `0/71 files require formatting, 3 files skipped`. In the
published tree the same command reports **2 files skipped** — see **F5**.

---

## C3 — `mise run generate`, then `git status`: is the generated project visible to git?

```
$ mise run generate                           # [clone]
Created project at /tmp/sg-verify/clone/Examples/ScreenGuardDemo/ScreenGuardDemo.xcodeproj
Created project at /tmp/sg-verify/clone/Research/CaptureMatrix/CaptureMatrix.xcodeproj
                                                             exit 0

$ git status --porcelain -uall                # [clone], immediately after generate
(empty — 0 bytes)                                            exit 0

$ git check-ignore -v Examples/ScreenGuardDemo/ScreenGuardDemo.xcodeproj
.gitignore:35:*.xcodeproj	Examples/ScreenGuardDemo/ScreenGuardDemo.xcodeproj     exit 0

$ git ls-files | grep -c '.xcodeproj'
0

# and in a pristine clone, after the headline verification regenerated the project itself:
$ git status --porcelain -uall                # [cloneC, after Scripts/verify_capture.sh]
(empty — 0 bytes)                                            exit 0
```

**Falsification attempts that failed to break it:** the project exists on disk in both clones after generation
and after `verify_capture.sh` regenerated it, yet `git status --porcelain` is empty in both; the published
path set (151 files) contains no `.xcodeproj` or `.xcworkspace`; the author-tree dry run
(`git add --dry-run -A`) adds no such path either.

---

## C4 — Package build and the full test suite

```
$ mise run build                              # [clone]
… 458 lines of xcodebuild output, 0 lines matching 'warning:' …
** BUILD SUCCEEDED **                                         exit 0

$ mise run test                               # [clone]
Resolved source packages: ScreenGuard: /tmp/sg-verify/clone
… 1032 lines …
	 Executed 131 tests, with 13 tests skipped and 0 failures (0 unexpected) in 0.303 (0.341) seconds
Test Suite 'All tests' passed at 2026-10-03 18:09:58.429.
** TEST SUCCEEDED **                                         exit 0

$ swift build                                 # [clone], documented to FAIL
error: …/Sources/ScreenGuard/AppSwitcher/ScreenGuardAppSwitcherShield.swift:20:8
       unable to resolve module dependency: 'UIKit'
error: Build failed                                           exit 1

$ swift test                                  # [clone], documented to FAIL
error: … unable to resolve module dependency: 'UIKit' … error: fatalError   exit 1
```

**Baseline:** 131 executed / 13 skipped / 0 failures — reproduced **exactly**. The 124/11 figures that appear in
README.md:565 and CHANGELOG.md:170 are labelled as historical/superseded in both places, and were not quoted as
current anywhere in this report. The two `swift build`/`swift test` failures are the *documented* behaviour
(README.md:168-171, CONTRIBUTING.md:65-68), so they count as a confirmation, not a defect.

The 13 skips, classified by the markers the tests themselves print:

```
$ grep -oE 'Test skipped - [A-Z-]+:' test.log | sort | uniq -c
   5 Test skipped - DEVICE-REQUIRED:
   6 Test skipped - PRIVATEAPI-REQUIRED:
   2 Test skipped - SCENE-REQUIRED:
```

Total 13 (5+6+2). README.md:589-590 states 6 + **3** + **2** + 2 — see **F1**.

---

## C5 — Demo app build

```
$ mise run demo:build                         # [clone]  (depends = ["generate"])
Created project at …/Examples/ScreenGuardDemo/ScreenGuardDemo.xcodeproj
… 925 lines …
** BUILD SUCCEEDED **                                         exit 0
```

**Trait gate, checked at the artifact level rather than taken on trust** (the demo's `project.yml:56-58` enables
the `PrivateAPI` trait):

```
$ grep -rl '_UITextLayoutCanvasView' .build/demo-dd/Build/Products     # trait ON
…/ScreenGuardDemo.app/ScreenGuardDemo.debug.dylib
…/ScreenGuard.o
…/ScreenGuard.swiftmodule/arm64-apple-ios-simulator.swiftdoc
…/ScreenGuardDemo.swiftmodule/arm64-apple-ios-simulator.swiftdoc
occurrences: 5

$ grep -rc '_UITextLayoutCanvasView' .build/build-dd/Build/Products   # trait OFF (mise run build)
occurrences: 0
```

So README.md:390-393's claim table ("0 occurrences anywhere" by default, "present" with the trait) is reproduced
in both directions on this machine.

---

## C6 — Every command in README's build/verify sections and in CONTRIBUTING.md, executed

The complete inventory was extracted mechanically from the shell fences of both files (README.md:150-154,
158-166, 177-179, 183-185; CONTRIBUTING.md:50-54, 92-94, 100-102) plus the two inline commands (README.md:479,
README.md:563). Every one was run:

| Command (as written) | Where run | Exit | Observed |
|---|---|---|---|
| `mise trust` | clone | 0 | `mise WARN No untrusted config files found.` |
| `mise install` | clone | 0 | 9/9 tools already installed |
| `mise tasks` | clone | 0 | 14 names (11 repo + 3 global) |
| `mise run generate` | clone | 0 | both projects regenerated |
| `mise run build` | clone | 0 | `** BUILD SUCCEEDED **` |
| `mise run test` | clone | 0 | `Executed 131 … 13 skipped … 0 failures` |
| `mise run demo:verify` | clone | 0 | `PASS 29 · FAIL 0 · FINDING 0 · SKIP 0 · DEVICE 4`, `RESULT: PASSED` |
| `mise run ci:local` | clone | 0 | all seven steps, see below |
| `mise run format` | clone | 0 | 0/71 formatted — no-op (hash unchanged) |
| `mise run format:check` | clone | 0 | 0/71, 2 skipped |
| `mise run lint` | clone | 0 | 0 violations in 39 files |
| `mise run lint:demo` | clone | 0 | 257 violations (advisory) |
| `mise run shellcheck` | clone | 0 | no findings |
| `mise run demo:build` | clone | 0 | `** BUILD SUCCEEDED **` |
| `mise run demo:verify -- --print-device-command` | clone | 0 | prints the `xcrun devicectl` procedure |
| `Scripts/verify_capture.sh --print-device-command` (README.md:479) | clone | 0 | same procedure |
| `test -s README.md && test -s LICENSE && test -s CHANGELOG.md` (README.md:563) | clone | 0 | all three non-empty |
| `DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' mise run test` (README.md:178) | cloneB | 0 | `Executed 131 tests, with 13 tests skipped and 0 failures` · `** TEST SUCCEEDED **` |
| `DESTINATION='platform=iOS Simulator,name=iPhone 16,OS=18.0' mise run test` (CONTRIBUTING.md:93) | cloneB | **70** | `xcodebuild: error: Unable to find a device matching the provided destination specifier` — **F6** |

**`ci:local`** (the whole blocking chain, in order):

```
$ mise run ci:local                           # [clone]
===== mise run generate =====
===== mise run format:check =====
===== mise run lint =====
===== mise run shellcheck =====
===== mise run build =====
===== mise run test =====
===== mise run demo:build =====
===== mise run lint:demo (advisory, never gates) =====
Done linting! Found 257 violations, 257 serious in 31 files.
== ci:local: every blocking step passed ==                                    exit 0
```

**The `DESTINATION` override is real, not decoration** (the [env] template in .mise.toml:78 claims an
external value wins):

```
$ DESTINATION='platform=iOS Simulator,name=DOES-NOT-EXIST' mise run build     # [cloneB]
    xcodebuild build -scheme ScreenGuard -destination "platform=iOS Simulator,name=DOES-NOT-EXIST" …
xcodebuild: error: Unable to find a device matching the provided destination specifier:
		{ platform:iOS Simulator, OS:latest, name:DOES-NOT-EXIST }
[build] ERROR task failed                                                     exit 70
```

A bogus override reaches `xcodebuild` and fails; had the `[env]` default silently won, the build would have
**succeeded**. That falsification attempt therefore confirms the template.

**A command that only works because of a file the reader will not have — tested and *not* found.**
In a pristine clone (no generated project) the documented direct invocation regenerates what it needs:

```
$ Scripts/verify_capture.sh --run-id fresh-clone-t8      # [cloneC], project absent
…/Examples/ScreenGuardDemo/ScreenGuardDemo.xcodeproj is missing (it is gitignored) — generating it from project.yml...
  [PASS   ] generated the missing Xcode project from project.yml       mise exec -- xcodegen
  [PASS   ] demo builds against the local package                      BUILD SUCCEEDED
…
  PASS   30   Simulator-checkable assertions that passed
  FAIL   0    Simulator-checkable assertions that failed
  FIND   0    findings reported (do not fail this run)
  SKIP   0    checks skipped for a stated reason
  DEVICE 4    checks that REQUIRE A PHYSICAL DEVICE
  RESULT: PASSED — every Simulator-checkable assertion passed.        exit 0
```

(Counted 30 rather than 29 because this run earned one extra PASS for generating the missing project — the same
variation any reader bootstrapping from a fresh clone will see. Not a defect; recorded so nobody reconciles it
as one.)

---

## C7 — `actionlint` over every workflow; the PR-title gate exists and can fail

```
$ mise exec -- actionlint --version
1.7.12 / built with go1.26.1 compiler for darwin/arm64

$ ls .github/workflows/
ci.yml  docs.yml  release.yml  verification.yml

$ mise exec -- actionlint .github/workflows/*.yml
(no output)                                                   exit 0

$ for f in .github/workflows/*.yml; do mise exec -- actionlint "$f"; done
ci.yml exit=0 · docs.yml exit=0 · release.yml exit=0 · verification.yml exit=0
```

**The PR-title gate exists, is wired into CI, and can fail:**

```
$ Scripts/ci/check-pr-title.sh --self-test
CONTRIBUTING.md section 4 and this gate agree on the 11 permitted types:
  build chore ci docs feat fix perf refactor revert style test
self-test: 19 title cases behaved as specified.               exit 0

$ Scripts/ci/check-pr-title.sh "feat(capture): block the recorder path"
OK: "feat(capture): block the recorder path" is a valid Conventional Commit title.   exit 0

$ Scripts/ci/check-pr-title.sh "Update the README"
FAIL: the pull-request title is not a Conventional Commit.
  title  : Update the README
  reason : not 'type(scope): subject' with one of the permitted types
  types  : build, chore, ci, docs, feat, fix, perf, refactor, revert, style, test   exit 1

$ Scripts/ci/check-pr-title.sh                # no title
usage: Scripts/ci/check-pr-title.sh "<pull request title>" …                        exit 2

$ PR_TITLE="docs: rewrite the publishing guide" Scripts/ci/check-pr-title.sh
OK: "docs: rewrite the publishing guide" is a valid Conventional Commit title.      exit 0
```

Wiring, from `.github/workflows/ci.yml`:

```
93:        run: Scripts/ci/check-pr-title.sh --self-test
95:      - name: Enforce Conventional Commits on the pull-request title
100:        run: Scripts/ci/check-pr-title.sh "$PR_TITLE"
```

**Supporting facts** (static, not executed): every `Scripts/*.sh` path named by a workflow exists in the
published tree (6/6); all five `uses:` actions in the four workflows are pinned to a full 40-hex commit SHA
(`actions/checkout`, `jdx/mise-action`, `actions/deploy-pages`, `actions/upload-artifact`,
`actions/upload-pages-artifact`). No workflow was executed: there is no remote and no runner (§NV).

---

## C8 — README capability table vs `docs/api-contract.md` §4

```
$ python3 (extract the block starting '| # | Capability | Mechanism | Public? | Status | Guarantee in one line |')
README table: 12 lines starting at README.md:66
contract table: 12 lines starting at docs/api-contract.md:246
BYTE-FOR-BYTE IDENTICAL: True
```

The 12 lines are the header, the separator and the ten capability rows — byte-identical, including the em-dashes
and the bold markers. The lead-in blockquote is also copied verbatim (`README.md:63-64` =
`docs/api-contract.md:243-244`). The status vocabulary table (README.md:81-86) also matches
(api-contract.md:261-266).

---

## C9 — Relative markdown links

```
$ python3 (extract [text](target) from the three files; skip absolute URLs and pure anchors;
           resolve each relative target against the containing file's directory)
relative link targets checked: 53
missing: 0

$ python3 (same sweep over every .md in the published tree + GitHub-slug anchor check)
markdown files scanned: 17
links scanned: 104
missing targets: 0
unresolved anchors: 0
```

53/53 in the three required files, 104/104 tree-wide, and every `#anchor` fragment resolves under GitHub's slug
algorithm. Note that this check ran **in the clone**, which is what makes it meaningful: any link to an ignored
or unpublishable file would have failed here.

---

## C10 — Credentials, tokens, private keys, personal absolute paths

```
$ git grep -InIE -e 'BEGIN [A-Z ]*PRIVATE KEY' -e 'AKIA[0-9A-Z]{16}' -e 'gh[pousr]_[A-Za-z0-9]{20,}' \
      -e 'github_pat_[A-Za-z0-9_]{20,}' -e 'sk-[A-Za-z0-9]{20,}' -e 'xox[baprs]-' HEAD
(no matches)                                                  exit 1

$ git grep -InIE -e '(password|passwd|api[_-]?key|access[_-]?token|client[_-]?secret)[[:space:]]*[:=][[:space:]]*["\u0027][^"\u0027]{6,}' HEAD
(no matches)                                                  exit 1

$ git grep -InIE -e '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' HEAD
HEAD:CODE_OF_CONDUCT.md:39: … may be reported … at menjiefu@gmail.com. …

$ git grep -InI -e '/Users/' HEAD | wc -l
60        (across 14 files: 10 under Research/Artifacts/**, and
           docs/TOOLING.md ×1, docs/evidence/review-round1.md ×1,
           docs/evidence/review-round2.md ×1, docs/evidence/verification-report.md ×2)
```

**Judgement.** No credentials, tokens, keys or high-entropy secrets of any kind. The one email address is the
deliberate Code-of-Conduct enforcement contact. The 60 `/Users/jiefu/…` strings are absolute paths inside
raw `xcodebuild`/simulator logs (`Research/Artifacts/…/build.log`, `unified-log.txt`) and four evidence
documents; they disclose the maintainer's local user name and directory layout. That name is already public in
this tree (the same person's mail address is the published contact, and the git author identity is
`Men, Jiefu <menjiefu@gmail.com>`), so this is **not material to a public repository** — but the paths are dead
for every other reader, and the decision to publish them should be a conscious one. Recorded as **F7**
(informational), not as a blocker.

---

## C11 — Does anything state or imply that a version has been released?

```
$ git tag -l | wc -l            # simulated publish repo
0
$ git log --oneline | wc -l     # author tree
8                               # none of them is a release

$ git grep -nI -e 'has been released' -e 'is released' -e 'releases/tag' -e 'v1\.0\.0' HEAD | …
CHANGELOG.md:8:> **No version has been released.** This repository has never been tagged and no GitHub Release
CHANGELOG.md:9:> exists. The `[1.0.0]` section below is a **development milestone** …
CHANGELOG.md:80:## [1.0.0] — 2026-10-02 — development milestone, never tagged or published
README.md:8:     has been released, so a badge implying one would be false. …
README.md:116:**No version has been tagged yet**, so `from: "1.0.0"` resolves nothing today. …
README.md:629:**There is no release history yet: no version has been tagged.** …
docs/PUBLISHING.md:3:**Status today: nothing has been published.** …
```

**Verdict: PASSED.** The `[1.0.0]` changelog section is explicitly labelled a development milestone that was
never tagged; the README omits a version badge on purpose and says so in an HTML comment (README.md:6-8); the
release workflow is documented as dormant (README.md:222, docs/PUBLISHING.md:3-7). The adjacent risk — the
compiled `ScreenGuard.version == "1.0.0"` — is disclosed in the same breath (CHANGELOG.md:83), and
`docs/api-contract.md` and `.spi.yml` make no release claim. Nothing in the published tree asserts a published
version.

---

## C12 — Every published test-count figure, reproduced against the current tree

| Figure as published | Where | Reproduced? | Evidence |
|---|---|---|---|
| `Executed 131 tests, with 13 tests skipped and 0 failures` | README.md:583, CHANGELOG.md:26, docs/TOOLING.md:635, docs/api-contract.md:1407 | **Yes** | `mise run test` → identical line, exit 0 |
| `Executed 131 tests, with 7 tests skipped and 0 failures` (trait-enabled copy) | docs/api-contract.md:1408 | **Yes** | §A1 — 131/7/0, `** TEST SUCCEEDED **` |
| `14 files, 131 test methods` | README.md:607 | **Yes** | 14 tracked `.swift` test files; 131 `func test*` |
| `25 Swift files` (library) | README.md:606 | **Yes** | 25 tracked `.swift` under `Sources/ScreenGuard/` |
| `257 violations, 257 serious in 31 files` | README.md:586, CHANGELOG.md:36 | **Yes** | `mise run lint:demo` exit 0 |
| `PASS 29 · FAIL 0 · FINDING 0 · SKIP 0 · DEVICE 4` | README.md:585 | **Yes** | `mise run demo:verify -- --run-id verify-t8` exit 0, `RESULT: PASSED` |
| `Executed 124 tests, with 11 tests skipped and 0 failures` | README.md:565, CHANGELOG.md:170, docs/api-contract.md:1258, docs/evidence/* | **Yes, as a labelled historical record** | README.md:554-559 marks the table "historical"/**Superseded**; CHANGELOG.md:170 sits inside the `[1.0.0]` milestone section; the evidence documents are dated reports of earlier attempts. Quoted as current nowhere. |
| **The 13-skip breakdown** `6 … PrivateAPI, 3 … physical device, 2 … human or hardware, 2 … UIWindowScene` | **README.md:589-590** | **NO** | The run reports 6 PRIVATEAPI + **5** DEVICE + 2 SCENE, and no "human or hardware" skip exists — **F1** |

---

## A1 — The PrivateAPI trait-ENABLED configuration, built and tested

The default configuration never compiles the private path (6 tests skip and say so), so a green default run is
**not** evidence for `Shield/ScreenGuardPrivateSecureLayer.swift`. Two independent trait-enabled runs were made.

**(a) Trait-enabled compile of the library *and* the test bundle, with the published manifest untouched:**

```
$ SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
$ swift build --build-tests --traits PrivateAPI \
      --triple arm64-apple-ios15.0-simulator --sdk "$SDK"
… ScreenGuardPrivateSecureLayer.swift compiled …
[130/134] ScreenGuardTests-product
Build complete! (6.24 sec)                                    exit 0
```

**(b) Trait-enabled test run.** `xcodebuild` exposes no trait switch (`xcodebuild -help | grep -i trait` →
nothing), so the trait was enabled the way a consumer does it, **in a throwaway copy only** — one line of the
manifest, applied to `/tmp/sg-verify/trait-on`, never to the published tree:

```
$ shasum -a 256 Package.swift      # published tree, before
45f4e821900f0d5747ee67880c54f419746a344d87d79891b4965431d1f39fb5
$ /usr/bin/sed -i '' 's/.default(enabledTraits: \[\]),/.default(enabledTraits: ["PrivateAPI"]),/' Package.swift
$ git diff --stat
 Package.swift | 2 +-
 1 file changed, 1 insertion(+), 1 deletion(-)
-        .default(enabledTraits: []),
+        .default(enabledTraits: ["PrivateAPI"]),
$ shasum -a 256 Package.swift      # scratch copy only
dc5c9edf0074c127ca0476b8724f973f25435fe2cb7c607ce7f94ce34aa34488

$ xcodebuild test -scheme ScreenGuard \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
    -derivedDataPath .build/trait-test-dd
	 Executed 131 tests, with 7 tests skipped and 0 failures (0 unexpected) in 0.302 (0.338) seconds
** TEST SUCCEEDED **                                          exit 0

$ grep -oE 'Test skipped - [A-Z-]+:' trait-test.log | sort | uniq -c
   5 Test skipped - DEVICE-REQUIRED:
   2 Test skipped - SCENE-REQUIRED:
   # the 6 PRIVATEAPI-REQUIRED skips are gone: those tests RAN
```

Published manifest identity re-checked after the experiment: repository, export and clone all report
`45f4e821…`; only the `/tmp` copy differs. Together with (a) this satisfies "the trait-enabled
configuration is built and, where the toolchain permits, tested" — **PASSED**, and the 131/7/0 figure in
docs/api-contract.md:1408 is independently reproduced.

## A2 — Public API against the pre-change revision (`swift-api-digester`)

Method: `git archive HEAD` (HEAD = `2263ac5`, the last commit, i.e. the pre-change revision) into
`/tmp/sg-verify/head`; `xcodebuild build -scheme ScreenGuard …` there (`** BUILD SUCCEEDED **`, exit 0) and in
the clone; both modules dumped with the same tool, SDK, target and `-swift-version 5`:

```
$ xcrun swift-api-digester -dump-sdk -module ScreenGuard -o dump-{head,cur}.json \
    -I <Products/Debug-iphonesimulator> -target arm64-apple-ios15.0-simulator \
    -sdk $(xcrun --sdk iphonesimulator --show-sdk-path) -swift-version 5        exit 0 (both)

nodes with declKind        head 310 · current 310
named nodes                head 1220 · current 1220
added   (current, not head)   0
removed (head, not current)   0

# determinism control: an independent second build of the same tree re-dumps identically
same-tree rebuild dumps identical: True
```

**But the dumps are not identical**, so the stronger published claim does not survive:

```
$ xcrun swift-api-digester -diagnose-sdk \
      --input-paths dump-head.json --input-paths dump-cur.json -o api-diagnose.txt
/* Removed Decls */          (empty)
/* Moved Decls */            (empty)
/* Renamed Decls */          (empty)
/* Type Changes */           (empty)
/* Protocol Conformance Change */ (empty)
/* Class Inheritance Change */    (empty)
/* Decl Attribute changes */
Class ScreenGuardShieldView is now with @preconcurrency
Constructor ScreenGuardShieldView.init(frame:) is now with @preconcurrency
… 19 entries in total, all on ScreenGuardShieldView and its 17 public members

# structural diff of the two dumps (after dropping location/file/moduleName):
differing leaves: 98 — 61 of them declAttributes, 18 of them the same
(ScreenGuardShieldView + 17 members) gaining 'Preconcurrency'; the rest are child-ordering
permutations of three members of the same class.
```

Cause, in the source: `@MainActor` sat on the class declaration at HEAD
(`Sources/ScreenGuard/Shield/ScreenGuardShieldView.swift:100`) and is absent in the current tree
(`Sources/ScreenGuard/Shield/ScreenGuardShieldView.swift:39` is now a bare `public final class`); the class is
still main-actor isolated by inheritance from `UIView`, and the digester records that inferred isolation as
`@preconcurrency`. Neither tree contains the literal string `@preconcurrency` in `Sources/`.

**Verdict:** "0 declarations added, 0 removed" — **reproduced**. "the dumps match once build-path metadata is
normalised away" (CHANGELOG.md:29) — **NOT reproduced**: see **F2**. No consumer-visible break was found, and no
symbol was added or removed.

## A3 — Package.swift: the trailing-comma delta is non-functional

Method: tokenise both revisions (block comments, line comments and all whitespace removed; then a token stream
of identifiers, numbers, string literals and punctuation) and diff the streams — not the text.

```
HEAD    Package.swift : 139 tokens, normalised length 627
current Package.swift : 145 tokens, normalised length 633

token-stream diff: 5 insertions, all of them ',' immediately before a closing ']' or ')':
    @@ … .iOS(.v15) ) + ',' ]
    @@ … targets: ["ScreenGuard"] ) + ',' ]
    @@ … .default(enabledTraits: []) + ',' ]
    @@ … .when(traits: ["PrivateAPI"]) ) + ',' ]
    @@ … .swiftLanguageMode(.v5) ) + ',' ]  and  ) + ',' ]
identical after removing ALL commas: True

tail bytes  HEAD: ' )\n    ]\n)\n\n'      current: ' ),\n    ]\n)\n'
```

**Verdict: PASSED.** Five commas and one trailing blank line; the token streams are otherwise *identical*, so the
delta cannot be functional. (The published manifest is unmodified by this attempt: repository, export and clone
all hash `45f4e821…`.)

---

## F — Deviations from the expected result, reported as findings (nothing was repaired)

### F1 — README.md:589-590: the 13-skip breakdown is wrong — **medium**

`README.md:588-590`:

> **The 13 skips are all explicit and all reasoned — none is silent:** 6 require the `PrivateAPI` trait
> (off in this build), 3 require a physical device, 2 require a human or hardware action in the loop, and
> 2 require a connected `UIWindowScene` …

The run (`mise run test`, exit 0, 131 executed) prints **5** `DEVICE-REQUIRED`, **6**
`PRIVATEAPI-REQUIRED` and **2** `SCENE-REQUIRED`, and **no** "human or hardware" category exists in the
suite's output at all. The five device skips are the five methods in
`Tests/ScreenGuardTests/ScreenGuardDeviceOnlyTests.swift` (all skipped at line 38). The table it sits under
(README.md:583) is otherwise correct, which makes the prose look like a stale count from an earlier suite.

**Required fix:** restate the breakdown as observed — 6 `PrivateAPI`, 5 physical-device, 2 window-scene — or
replace it with the categories the suite actually emits.

### F2 — CHANGELOG.md:27,29: "the dumps are identical" is contradicted by the digester — **medium**

`CHANGELOG.md:27-29` says a `swift-api-digester` dump "is identical to the pre-baseline revision's …
the dumps match once build-path metadata is normalised away". Measured: 0 added / 0 removed (true), but the
normalised dumps differ in 98 leaves, and the digester's own `-diagnose-sdk` mode prints 19 **Decl Attribute
changes** — `ScreenGuardShieldView` and its 17 public members gained `@preconcurrency` (see §A2). The
change is deterministic (a second build of the same tree re-dumps identically) and traceable to
`ScreenGuardShieldView.swift:100` at HEAD vs `:39` now.

**Required fix:** either reword the claim to what is true ("0 declarations added or removed; the only API
difference is an inferred `@preconcurrency` on `ScreenGuardShieldView` and its members, introduced when the
explicit `@MainActor` was dropped from the class declaration") or restore the explicit annotation and re-measure.
Do not leave a claim that the cited tool falsifies.

### F3 — README.md:129: the "no canonical remote URL" disclaimer contradicts the rest of the tree — **medium**

`README.md:129`: "*This repository does not assert a canonical remote URL; substitute the URL you publish
it at.*" — while the same file asserts `https://github.com/mo5tone/ScreenGuard` in the CI badge
(`:3`), the SPM dependency (`:109`), the branch form (`:120`) and the trait form (`:136`), and four
further published files assert the owner: `.github/CODEOWNERS` (`* @mo5tone`),
`.github/ISSUE_TEMPLATE/config.yml` (three `github.com/mo5tone/ScreenGuard` links),
`.github/pull_request_template.md`, `SECURITY.md`. `gh auth status` reports the authenticated account as
**mo5tone**, exit 0. The t6 hand-off claimed this disclaimer had been removed; it is still there.

**Required fix:** delete `README.md:129` (and re-check the surrounding Xcode instructions read naturally without it).

### F4 — README.md:146-148 and CONTRIBUTING.md:56-59: the untrusted-config failure does not occur for `mise run` — **medium**

Both files state that until the config is trusted, **every `mise run …` fails** with
`Config files … are not trusted`. On mise 2026.9.6, in a genuinely fresh clone: `mise tasks` **does**
fail that way (exit 1, message as documented), but `mise run format:check` **runs the task and exits 0**, and
`mise trust --show` afterwards reports `trusted` — the run silently grants trust. The same happened
with a pty allocated (`script -q /dev/null …`) and with a scrubbed environment, and `mise install` behaves
the same way. `mise ls`, `mise current`, `mise env` join `mise tasks` in refusing.

This does not break the documented setup path — trust → install → tasks all exit 0 — but it does mean the
security-relevant sentence is false as written, and a reader who believes it may think an untrusted clone cannot
execute repository-defined tasks.

**Required fix:** say what is true for the pinned version — the config must be trusted before `mise tasks`,
`mise ls`, `mise env` and `mise current` will read it, while `mise run <task>` on an untrusted config
proceeds (it grants trust itself), which is exactly why the documented `mise trust` first step exists.

### F5 — README.md:579 vs .gitignore:67: a published figure depends on a file that is not published — **low**

`README.md:579` publishes `0/71 files require formatting, 3 files skipped.` In the published tree the same
command reports `2 files skipped`. Cause, identified with `swiftformat --lint --verbose`:

```
[author tree]  Skipping …/Research/README.md · Skipping …/Examples/ScreenGuardDemo/README.md
               Skipping …/Research/Artifacts/README.md      -> 3
[published]    only the first two                           -> 2
$ git check-ignore -v Research/Artifacts/README.md
.gitignore:67:Research/Artifacts/*	Research/Artifacts/README.md     exit 0
$ git ls-files --error-unmatch Research/Artifacts/README.md
error: pathspec … did not match any file(s) known to git         exit 1
```

`.gitignore:64-70` deliberately re-includes the four canonical run directories under
`Research/Artifacts/`; the directory's own `README.md` (2.7 KB, describes what the artifacts are) is excluded by
the `Research/Artifacts/*` line and silently dropped. Nothing published links to it (the link sweep in §C9
proves that), so the practical damage is the wrong figure plus the loss of the one file that explains the
directory a reader will see.

**Required fix:** re-measure and publish `2 files skipped`, and decide explicitly whether
`Research/Artifacts/README.md` should be published (`!Research/Artifacts/README.md`) or not; either way the
number and the file must agree.

### F6 — CONTRIBUTING.md:93: the example destination is not runnable on the pinned Xcode — **low**

`CONTRIBUTING.md:93` offers `DESTINATION='platform=iOS Simulator,name=iPhone 16,OS=18.0' mise run test`.
On this machine (Xcode 27.0; installed runtimes iOS 26.0/26.2/26.5) it exits **70** with
`xcodebuild: error: Unable to find a device matching the provided destination specifier`. The README's
equivalent example (README.md:178, `OS=26.0`) **does** work (exit 0, 131 tests). This is an environment
mismatch rather than a repository defect — the sentence's point is "an external value wins", which §C6 proves
with the `DOES-NOT-EXIST` control — but a reader who copy-pastes the CONTRIBUTING example on the toolchain the
repository targets gets a failure.

**Required fix:** use a destination that ships with the targeted Xcode (e.g. `name=iPhone 17 Pro,OS=26.2` with a
different device name such as `iPhone 17`), or note that the runtime must be installed.

### F7 — informational: 60 personal absolute paths in 14 published files

See §C10. No secret; already-public user name; the paths are meaningless to other readers. Not a blocker —
recorded so that publishing them is a decision and not an accident.

---

## NV — What is NOT VERIFIED, and why

A check I could not run is not a pass. Nothing in this section should be read as verified.

1. **Any GitHub-side behaviour.** The repository has no remote (`git remote -v` is empty), nothing has been
   pushed, and no repository exists under the intended name at verification time. Therefore the CI workflow
   (`ci.yml`), the Docs/Pages workflow, the nightly verification workflow, the release workflow, Dependabot, the
   SPI build and `Scripts/ci/branch-protection.sh` have **never executed**. `actionlint` (exit 0) proves syntax
   and known-bad patterns, not behaviour; the workflow logic, the `macos-26` runner label, `jdx/mise-action`
   and the release gate's `gh release create` path are **unverified**.
2. **A real checkout from GitHub.** The clean tree here is a local clone of a local simulated commit. A network
   clone, `.gitattributes` effects on checkout (LF normalisation, binary handling), line-ending behaviour on
   other platforms, and GitHub's rendering of the markdown (badges, tables, anchors) are **unverified**.
3. **The publish commit itself — and a concrete environment risk for it.** This machine's global git config sets
   `commit.gpgsign=true` with `gpg.ssh.program=/Applications/1Password.app/Contents/MacOS/op-ssh-sign`; the
   repository adds no local override (`git config --local --list` has no signing keys). In two throwaway
   repositories with that config, `git commit` failed: `error: 1Password: failed to fill whole buffer` /
   `fatal: failed to write commit object` — **exit 128**. I did **not** create a commit in the real repository to
   confirm it there. Whoever publishes must either have the 1Password agent reachable or pass
   `-c commit.gpgsign=false`. (Every commit in this report's simulation was made with `commit.gpgsign=false`.)
4. **Any device-only capability.** No physical device is attached. The `device-pending` and `notMeasured`
   rows of the capability table (real screenshot event, capture-state delivery, recording path, app-switcher
   snapshot pixels, public `preventsCapture` capture behaviour) remain unmeasured here; every run that touched
   them printed `[DEVICE]` and said so. The repository is honest about this and this report repeats it.
5. **`Scripts/verify_capture.sh` pixel verdicts were not re-derived independently.** I ran the script
   (`PASS 29`/`30`, `RESULT: PASSED`) and read its artifacts directory, but I did not decode its PNGs
   with an independent sampler the way the t5 report did. The pixel-level no-leak claim is therefore
   **re-run, not re-derived**.
6. **Historical measurements that presuppose a different tree or configuration.** The 124/11 run of record
   (README.md:552-569), the `Executed 105` figures in `docs/evidence/verification-report.md` /
   `review-round1.md`, the `Executed 132` figure in `review-round2.md`, and CHANGELOG.md's "62 files
   required formatting before" the baseline were **not** re-run: they describe earlier trees/configurations, are
   labelled as historical where it matters, and reconstructing them would mean rebuilding revisions that no
   longer exist in the working tree.
7. **The raw logs cited as evidence for the README's measurements.** README.md:568-569 points at
   `/tmp/t7-build.log`, `/tmp/t7-test.log`, `/tmp/t7-example.log` and `.build/verify-capture/t7-final/`;
   README.md:575 points at `.build/test-dd/Logs/Test/` and `.build/verify-capture/t6-docs/`. Those paths exist on
   **this** machine (checked: `EXISTS` for all three /tmp logs and both .build paths) but none of them is in
   the published tree, so a reader of the published repository cannot re-open the evidence behind the numbers.
   Whether the numbers are trustworthy is therefore asserted, not reproducible, from the clone alone.
8. **`docs/evidence/publish-review-round1.md`** — named in this task's out-of-scope list — does not exist in
   the tree at verification time, so no cross-reading of the adversarial review was possible.
9. **The `.github/` community surfaces** (issue forms, PR template rendering, CODEOWNERS behaviour, Dependabot)
   are only checkable once the repository exists on GitHub.
10. **Trailing-comma idempotence of `mise run format` under future SwiftFormat releases** is out of scope; the
    pin is exact, and this report verified only 0.63.0 as installed.

---

## Artifacts produced by this attempt (all outside the repository, on purpose)

```
/tmp/sg-verify/publish-list.txt                  the 151 paths git would publish (the clean-tree definition)
/tmp/sg-verify/clean/                            exported publish tree + simulated publish commit
/tmp/sg-verify/clone/                            the fresh clone all gates ran in
/tmp/sg-verify/clone{A,B,C}/                     pristine clones for the untrusted-config and destination tests
/tmp/sg-verify/trait-on/                         scratch copy, Package.swift trait default flipped (one line)
/tmp/sg-verify/head/ · head-dd/                  pre-change revision (git archive HEAD) + its build
/tmp/sg-verify/logs/*.log                        raw output of every gate command quoted above
/tmp/sg-verify/dump-head.json · dump-cur.json    swift-api-digester dumps
/tmp/sg-verify/api-diagnose.txt                  -diagnose-sdk output (19 "Decl Attribute changes")
/tmp/sg-verify/logs/demo-verify.log              mise run demo:verify (PASS 29 · DEVICE 4)
/tmp/sg-verify/logs/fresh-clone-script.log       Scripts/verify_capture.sh in a pristine clone (PASS 30)
```

**Bottom line.** The tree is publishable: the pinned toolchain installs from a fresh clone, both gates are
clean, the generated Xcode project is reproducible and invisible to git, the package builds and passes 131
tests (13 reasoned skips, 0 failures) — and that includes the trait-enabled configuration that actually compiles
the private path (131 executed, 7 skipped, 0 failures). No credential, token or key is published; the capability
table is byte-identical to its normative source; and nothing claims a release that does not exist. Six
deviations remain, all of them statements or figures rather than code: the skip breakdown (F1), the
"identical dumps" claim (F2), the remote-URL disclaimer (F3), the untrusted-config sentence (F4), the
`3 files skipped` figure (F5) and one non-runnable example destination (F6). F1–F3 are claims the repository's
own evidence contradicts and should be corrected before or immediately after publication; F4 is the one that
could mislead a security-minded reader. The publish commit additionally needs a working signing path (§NV.3).
