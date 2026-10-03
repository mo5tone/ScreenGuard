#!/bin/sh
# =============================================================================================
# Scripts/ci/verify-generated-projects.sh — regenerate both Xcode projects, then PROVE they are
# generated artifacts rather than repository contents.
#
# The .xcodeproj bundles are NOT tracked (see .gitignore): Examples/ScreenGuardDemo/project.yml and
# Research/CaptureMatrix/project.yml are the sources of truth. That is only safe if regeneration is
# trustworthy, so this script asserts all four of these, and fails on the first one that is false:
#
#   1. regeneration is byte-deterministic — the same pinned xcodegen produces identical bytes on a
#      second run, so a fresh clone rebuilds the same project and no per-run noise can hide a real
#      difference;
#   2. no *.xcodeproj / *.xcworkspace path is tracked by git — a generated file must never be
#      committed, because then the committed copy silently wins over project.yml;
#   3. every generated bundle is matched by .gitignore (git check-ignore) — "untracked" only stays
#      true if it is also ignored;
#   4. regeneration does not modify a single tracked file — i.e. the projects really are outputs,
#      and nothing in the tracked tree is derived from them.
#
# It also asserts the demo project still carries its shared scheme: generation must produce a
# project that can actually be built by "mise run demo:build" on a fresh clone.
#
# It calls "mise run generate" (the pinned task) rather than xcodegen directly, so generation has
# exactly one implementation.
#
# Exit codes: 0 = all four properties hold, 1 = one of them does not (the reason is printed).
# =============================================================================================
set -eu

DEMO_PROJECT="Examples/ScreenGuardDemo/ScreenGuardDemo.xcodeproj"
DEMO_SCHEME="${DEMO_PROJECT}/xcshareddata/xcschemes/ScreenGuardDemo.xcscheme"
MATRIX_PROJECT="Research/CaptureMatrix/CaptureMatrix.xcodeproj"

cd "$(git rev-parse --show-toplevel)"

fail() {
    printf '\nFAIL: %s\n' "$1" >&2
    shift
    for detail in "$@"; do
        printf '%s\n' "$detail" >&2
    done
    exit 1
}

# Content digest of a generated bundle: the sorted relative paths inside it plus their SHA-256,
# hashed again. Paths are relative to the bundle, so the digest is a fingerprint of the generated
# CONTENT and not of the directory the checkout happens to live in — two clones of the same commit
# produce the same digest.
digest() {
    (
        cd "$1" || exit 1
        find . -type f -print0 \
            | LC_ALL=C sort -z \
            | xargs -0 shasum -a 256 \
            | shasum -a 256 \
            | awk '{ print $1 }'
    )
}

tracked_status() {
    git status --porcelain --untracked-files=no
}

echo "== generated-project verification =="

status_before=$(tracked_status)

echo "-- mise run generate (first run)"
mise run generate

for project in "$DEMO_PROJECT" "$MATRIX_PROJECT"; do
    [ -d "$project" ] || fail "mise run generate did not create $project" \
        "  a fresh clone has no .xcodeproj, so generation MUST create it"
    files=$(find "$project" -type f | wc -l | tr -d ' ')
    [ "$files" -gt 0 ] || fail "$project exists but contains no files" \
        "  a generated project with no files is not a usable project (and would make the digest below meaningless)"
done
[ -f "$DEMO_SCHEME" ] || fail "the generated demo project has no shared scheme: $DEMO_SCHEME" \
    "  'mise run demo:build' needs it on a fresh clone; the scheme is declared in Examples/ScreenGuardDemo/project.yml"

demo_first=$(digest "$DEMO_PROJECT")
matrix_first=$(digest "$MATRIX_PROJECT")

echo "-- mise run generate (second run, to test determinism)"
mise run generate

demo_second=$(digest "$DEMO_PROJECT")
matrix_second=$(digest "$MATRIX_PROJECT")

if [ "$demo_first" != "$demo_second" ]; then
    fail "regenerating $DEMO_PROJECT is not byte-deterministic" \
        "  first run : $demo_first" \
        "  second run: $demo_second"
fi
if [ "$matrix_first" != "$matrix_second" ]; then
    fail "regenerating $MATRIX_PROJECT is not byte-deterministic" \
        "  first run : $matrix_first" \
        "  second run: $matrix_second"
fi
echo "   [1/4] regeneration is byte-deterministic"
echo "         $DEMO_PROJECT  $demo_first"
echo "         $MATRIX_PROJECT $matrix_first"

tracked=$(git ls-files | grep -E '\.(xcodeproj|xcworkspace)(/|$)' || true)
if [ -n "$tracked" ]; then
    fail "generated Xcode projects are tracked by git" \
        "$tracked" \
        "  they are generated from project.yml and must be removed from the index:" \
        "    git rm -r --cached <path>"
fi
echo "   [2/4] no *.xcodeproj / *.xcworkspace path is tracked"

for project in "$DEMO_PROJECT" "$MATRIX_PROJECT"; do
    if ! git check-ignore -q "$project/project.pbxproj"; then
        fail "$project/project.pbxproj is NOT matched by .gitignore" \
            "  untracked is not enough: without an ignore rule 'git add .' reintroduces a generated file" \
            "  expected rule: *.xcodeproj"
    fi
done
echo "   [3/4] both bundles are matched by .gitignore"

status_after=$(tracked_status)
if [ "$status_before" != "$status_after" ]; then
    fail "regenerating the projects changed tracked files" \
        "  git status before: ${status_before:-<clean>}" \
        "  git status after : ${status_after:-<clean>}"
fi
echo "   [4/4] regeneration left the tracked tree untouched"

echo "== generated-project verification PASSED =="
