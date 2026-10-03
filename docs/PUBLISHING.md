# PUBLISHING — how a version becomes a release, and what that proves

**Status today: nothing has been published.** This repository has never been tagged, no GitHub Release
exists, and every section below that describes publishing is a procedure for a maintainer to follow
**when** versioning starts — not a description of something that already happened. The release
pipeline (`.github/workflows/release.yml`) is dormant until a `vX.Y.Z` tag is pushed, and nothing in
this document creates one.

Audience: a maintainer with write access. Contributors need [`.github/pull_request_template.md`](../.github/pull_request_template.md)
and [`CONTRIBUTING.md`](../CONTRIBUTING.md) instead.

---

## 1. The rule that governs a release: a measurement with a control

This repository's bar is that **a capability claim without a measurement and a control is a defect**
([`CONTRIBUTING.md`](../CONTRIBUTING.md) §1, [`docs/api-contract.md`](api-contract.md) §0.1). A
control is what rules out the obvious false positive: a protected region that reads *black* in a
capture looks identical whether protection worked or nothing was ever painted there, so the
measurement places a distinctly-coloured **sentinel behind** the protected band and the control
separates the two cases ([`docs/TOOLING.md`](TOOLING.md) §3).

Three consequences for publishing:

1. **Release notes may not introduce capability claims.** They are generated from the commit history
   by the pinned `git-cliff`, so they describe *changes*. What the package claims — and what it
   withholds — is owned by [`docs/api-contract.md`](api-contract.md) §4, the capability status
   table. Do not summarize that table in a release note; link to it.
2. **A green release run is a statement about the tagged commit, not about the product's limits.**
   See §5 for exactly what it does and does not prove.
3. **A device-only cell cannot be released into a claim.** `device-pending` and `notMeasured` cells
   stay unproven until the device procedure
   ([`docs/evidence/device-run-procedure.md`](evidence/device-run-procedure.md)) has actually been
   run, and its raw output — not a summary of it — is the evidence that changes the status.

---

## 2. Tag convention: `v`-prefixed

Release tags are **v-prefixed** (`v1.0.0`). Swift Package Manager accepts **both** spellings in a
requirement — `.package(url: "…/ScreenGuard.git", from: "1.0.0")` resolves `v1.0.0`, because the `v`
is stripped when the version is parsed — so the prefix is a project convention rather than a
constraint. Every tag released by `.github/workflows/release.yml` must carry it: the trigger pattern
and the CHANGELOG lookup are keyed on `vX.Y.Z`, and a tag that does not match fails **before**
anything is published.

The workflow's trigger accepts `v[0-9]*.[0-9]*.[0-9]*` and, for pre-releases,
`v[0-9]*.[0-9]*.[0-9]*-*` (for example `v1.0.0-rc.1`). Nothing else starts a release: a branch push,
a pull request and a manual dispatch cannot.

---

## 3. Before the first release: one-time repository settings

None of these can be set from a file in the repository, and skipping one produces a loud failure —
which is the good case. Check them once, when the repository is created:

| Setting | Where | Why |
|---|---|---|
| Pages source = **GitHub Actions** | Settings → Pages | Without it the DocC → Pages deploy job in `.github/workflows/docs.yml` fails; no site is published |
| Workflow permissions = **Read and write** | Settings → Actions → General | The release job declares `contents: write` for one call (`gh release create`). With a read-only default that call is rejected |
| Required checks, PR and no bypass on `main` | `Scripts/ci/branch-protection.sh apply --repo OWNER/REPO` (idempotent; `apply` re-runs `verify`) | Requires a pull request (0 approvals; stale reviews dismissed on push), the checks `pr-title`, `quality` and `build-and-test` in strict mode, and `enforce_admins`, so even the owner cannot push to `main` directly. `Scripts/ci/branch-protection.sh print-plan` shows every call and body |
| Swift Package Index indexing | opt-in on swiftpackageindex.com | `.spi.yml` in this repository only takes effect once the repository has been added there |
| Optional: Actions variable `DESTINATION` | Settings → Secrets and variables → Actions → Variables | Overrides the default Simulator destination used by CI and by the release gate. Both workflows default to `platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2` when it is unset |

---

## 4. The release procedure, once versioning starts

The order matters: **the changelog is bumped first, then the tag is pushed.** The release workflow
refuses to publish a version whose changelog section is missing, empty, or not the newest released
section — so a tag pushed first fails with a message naming the missing section.

1. **Land the work on `main` with CI green.** Every gate in
   [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) must have passed on the commit you intend to
   tag. Locally: `mise run ci:local` (it is the same blocking chain, in the same order).
2. **Curate [`CHANGELOG.md`](../CHANGELOG.md).** Move the entries that belong to the release out of
   `[Unreleased]` into a new section whose heading is exactly `## [X.Y.Z] — YYYY-MM-DD` (Keep a
   Changelog). The workflow reads the token inside the brackets, so `[1.0.0]` and `[v1.0.0]` both
   work and the date is free-form. The section must be **non-empty** and must be the **newest
   released section** in the file; an `[Unreleased]` heading above it is expected and is skipped.
3. **Commit the changelog bump and merge it** (a Conventional Commit such as
   `docs: changelog for 1.0.0`), then wait for CI to go green on that commit.
4. **Tag it and push the tag:**

   ```sh
   git tag -a v1.0.0 -m "ScreenGuard 1.0.0"
   git push origin v1.0.0
   ```

5. **Watch the run** — `gh run list --workflow=release.yml` and `gh run watch`. The `gate` job runs
   first and must pass before the `release` job exists at all.
6. **Verify what was published** — `gh release view v1.0.0`: the title, the generated notes, and the
   tag the Release points at. Confirm the notes describe *changes* and do not restate capability
   statuses (§1).
7. **If the release must be withdrawn**, do it explicitly rather than silently: delete the Release
   (`gh release delete vX.Y.Z`), delete the tag locally and on the remote, fix the problem, and only
   then tag again. Never move a published tag or reuse a version number for different content — a
   consumer may already have resolved it.

---

## 5. What the release workflow proves — and what it cannot

### It proves, on the tagged commit

* The tag matches `vX.Y.Z` (or a `-prerelease` form), and the tagged commit is an **ancestor of
  `main`** — a tag on a side branch cannot publish.
* The **whole blocking chain passed on the tagged commit itself**: the `gate` job runs the same
  sequence as `mise run ci:local` (`generate → format:check → lint → shellcheck → build → test →
  demo:build`), plus the generated-and-untracked Xcode-project proof, `shellcheck` over `Scripts/ci`
  and `actionlint` over the workflows. The release job depends on that gate.
* [`CHANGELOG.md`](../CHANGELOG.md) has a non-empty section for **exactly** that version and it is the
  newest released section, so the tag and the changelog cannot drift apart.
* The notes are generated by the **pinned** `git-cliff` from the commit history, the same version
  `mise` installs locally — not by a tool that changed under you.
* The Release is created with `gh` using `--verify-tag`, so the workflow can never invent the tag it
  publishes, and it refuses to overwrite an existing Release.
* Least privilege holds: `contents: read` at the workflow level and in the gate job; only the release
  job raises `contents: write`, for that one `gh release create` call.

### It cannot prove anything about a device-only cell

The gate is a **Simulator** gate. It cannot fire a real screenshot, the ReplayKit recording path
delivers no frames there, app-switcher snapshot pixels are not decodable, and the public
`preventsCapture` path paints nothing at all — so its blank region is unearned. A release therefore
does **not** turn any `device-pending` or `notMeasured` cell in
[`docs/api-contract.md`](api-contract.md) §4 into a measured result, and the notes must not imply
otherwise.

### It also does not prove

* **That `Scripts/verify_capture.sh` passed on the tagged commit.** The pixel-level end-to-end run
  boots a Simulator and drives the demo; it is deliberately **not** part of the release gate, and it
  runs nightly (and on demand) in `.github/workflows/verification.yml`. The release gate compiles the
  demo (`demo:build`) but does not run it.
* **That the private-API path behaves correctly at runtime.** `demo:build` is the only gate that
  compiles the trait-gated code; the test suite runs with the `PrivateAPI` trait **off**, so a green
  test run is silent about that file ([`docs/TOOLING.md`](TOOLING.md) §12). The release proves it
  *compiles*, and nothing more.
* **That a consumer can resolve the tag.** The workflow builds this repository; it does not build a
  downstream app that depends on the published tag.
* **That the documentation site is live.** That depends on the Pages source setting (§3) and on the
  separate `docs.yml` run.
* **That the runner matches this machine.** The macOS runner ships a different Xcode and SDK from a
  developer's local one; a locally green `mise run ci:local` is not a prediction of the runner's
  result. The workflows record the exact Xcode, SDK, runtimes and pinned tool versions into the job
  summary on every run ([`docs/TOOLING.md`](TOOLING.md) §11).
* **Anything about App Review.** The private path's review risk is a property of shipping it, not of
  releasing this package.

---

## 6. Pre-flight checklist

Copy this into the release pull request and tick it honestly:

```
[ ] CI is green on the commit to be tagged, and I looked at the run rather than the badge
[ ] CHANGELOG.md has a non-empty '## [X.Y.Z] — YYYY-MM-DD' section, and it is the newest released one
[ ] The section contains no capability claim: statuses live in docs/api-contract.md §4
[ ] No device-only cell is described as proven, verified or measured
[ ] The one-time settings in §3 are still in place (Pages source, workflow permissions, the protection policy: pull request + required checks + no bypass)
[ ] The tag I am about to push is exactly 'vX.Y.Z' and it does not exist yet
[ ] I know how to withdraw it (§4 step 7) and I will not move a published tag
```

---

## 7. Where the surrounding truth lives

| Document | What it owns |
|---|---|
| [`docs/api-contract.md`](api-contract.md) | The normative capability status table (§4) and the wording rules for the private path (§9) |
| [`docs/TOOLING.md`](TOOLING.md) | The pinned toolchain, the trust requirement, the runner-versus-local differences, and the trait-gated-path trap |
| [`docs/evidence/`](evidence/) | The measurements, the independent verification and the review rounds a release note must not contradict |
| [`CONTRIBUTING.md`](../CONTRIBUTING.md) | The gates, the Conventional Commit types that shape the generated notes, and the honesty bar |
| [`.github/workflows/release.yml`](../.github/workflows/release.yml) | The executable version of everything §5 claims about the release run |