<!--
Thanks for contributing. Three things are required, and CI will ask for them again:

  1. what changed — the behaviour a user can observe, not a file list;
  2. which gate you ran, with its RAW output ("tests pass" is not evidence);
  3. for a new claim, the measurement that backs it.

Keep the pull-request title in Conventional Commits shape — `type(scope): subject`. CI rejects a
title that does not conform, and the release notes are generated from that history
(https://github.com/mo5tone/ScreenGuard/blob/main/CONTRIBUTING.md section 4).
-->

## What changed

<!-- The observable behaviour. Which capability (or which row of the capability table) does this touch? -->

## Why

<!-- The defect it repairs, or the problem it solves. Link the issue if there is one. -->

## The gate I ran, with its raw output

<!-- Paste the command and its real output. -->

```text
$ mise run ci:local
...
```

- [ ] `mise run ci:local` passed (the blocking chain: generate → format:check → lint → shellcheck → build → test → demo:build)
- [ ] `mise run demo:verify` — run it if this touches the demo, the shield, the watermark, or any capture path

## Measurement behind any new claim

<!-- Required for a new or changed capability claim. If there is no measurement, say so and label
     the claim with its status (device-pending / notMeasured) per https://github.com/mo5tone/ScreenGuard/blob/main/docs/api-contract.md section 4,
     rather than asserting it. -->

| What | Value |
|---|---|
| Capture path (only app-side `drawHierarchy` or ReplayKit can carry a leak verdict) | |
| Command run | |
| Protected region reading | |
| Control band reading (sentinel behind the band) | |
| Artifact: PNG / samples / JSON | |

## Checklist

- [ ] Nothing in this PR (code, comments, docs, demo copy) claims a capture is prevented — protected content coming out black is the success case
- [ ] Capability wording matches [the capability table](https://github.com/mo5tone/ScreenGuard/blob/main/docs/api-contract.md) instead of being re-derived in prose
- [ ] The private-API path is still opt-in and off by default (the `PrivateAPI` trait is not enabled by default)
- [ ] Any rationale this PR replaces was deleted, not left beside the new one
