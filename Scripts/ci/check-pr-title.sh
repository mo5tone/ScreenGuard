#!/bin/sh
# =============================================================================================
# Scripts/ci/check-pr-title.sh — the Conventional Commits gate for PULL-REQUEST TITLES.
#
# WHY THE TITLE IS THE THING TO GATE
#   Pull requests are squash-merged, so the pull-request TITLE becomes the commit subject on
#   `main`. The changelog / release notes are generated from those subjects (git-cliff, pinned in
#   .mise.toml), so a title that is not a Conventional Commit is a permanently malformed history
#   entry: it cannot be repaired later without rewriting `main`. That is why this gate BLOCKS
#   instead of warning, and why it is wired as a required status check on `main`
#   (see Scripts/ci/branch-protection.sh).
#
# WHAT IS ACCEPTED
#       type: subject
#       type(scope): subject
#       type!: subject                 (breaking change)
#       type(scope)!: subject          (breaking change inside a scope)
#
#   * `type` must be one of the permitted types below, lowercase and exactly as listed
#   * `scope` is optional: lowercase alphanumerics plus . _ / -
#   * exactly one space after the colon, then a non-empty subject
#   * no leading or trailing whitespace anywhere in the title
#
# WHAT IS REJECTED
#   Everything else — including GitHub's own `Revert "…"` title, which is not machine-groupable.
#   To revert a change, retitle the pull request to `revert: <subject being reverted>`.
#
# USAGE
#   Scripts/ci/check-pr-title.sh "feat(capture): block the recorder path"
#   PR_TITLE="feat(capture): block the recorder path" Scripts/ci/check-pr-title.sh
#   Scripts/ci/check-pr-title.sh --self-test      # negative control over a title table
#
# WHICH DOCUMENT OWNS THE TYPE SET
#   CONTRIBUTING.md section 4 is what contributors read, so it and this script must agree exactly:
#   a type the document allows but this gate rejects would fail a perfectly valid contribution.
#   check_documented_types() parses that section on every --self-test and fails on any mismatch, so
#   the two cannot drift apart silently.
#
# WHAT IS DELIBERATELY NOT ENFORCED
#   CONTRIBUTING.md section 4 also asks for imperative, lower-case subjects with no trailing period
#   and roughly 72 characters. Those are style guidance for humans, not a machine-checkable
#   contract, so they are not gates here — only the shape and the type set are.
#
# Exit codes: 0 = conforming, 1 = not conforming, 2 = usage error.
# =============================================================================================
set -eu

# The permitted types. This is the single source of truth: the pattern below is built from it and
# the list is printed on every failure, so a contributor never has to guess.
TYPES="build chore ci docs feat fix perf refactor revert style test"
TYPES_READABLE="build, chore, ci, docs, feat, fix, perf, refactor, revert, style, test"

# ^(type)(\(scope\))?!?: subject$ — built from TYPES so the pattern and the printed list cannot drift.
ALTERNATION=$(printf '%s' "$TYPES" | tr ' ' '|')
PATTERN="^(${ALTERNATION})(\([a-z0-9][a-z0-9._/-]*\))?!?: .+$"

TITLE=""

# The paths are resolved from this script's own location, so the cross-check works from any cwd.
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
CONTRIBUTING_DOC="$REPO_ROOT/CONTRIBUTING.md"

print_requirements() {
    cat <<EOF
  expected : type(scope): subject          -- "scope" and "!" are optional
  examples : feat(capture): block the recorder path
             fix: keep the shield armed across a rotation
             docs!: drop the iOS 14 wording
  types    : ${TYPES_READABLE}
  see      : CONTRIBUTING.md section 4 -- the type set above is the one documented there
EOF
}

reject() {
    printf 'FAIL: the pull-request title is not a Conventional Commit.\n' >&2
    printf '  title  : %s\n' "${TITLE}" >&2
    printf '  reason : %s\n' "$1" >&2
    print_requirements >&2
}

# validate <title> — 0 when conforming, 1 otherwise (printing the reason on stderr).
validate() {
    TITLE=$1
    if [ -z "$TITLE" ]; then
        reject "the title is empty"
        return 1
    fi
    trimmed=$(printf '%s' "$TITLE" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    if [ "$trimmed" != "$TITLE" ]; then
        reject "leading or trailing whitespace"
        return 1
    fi
    if ! printf '%s' "$TITLE" | grep -Eq "$PATTERN"; then
        reject "not 'type(scope): subject' with one of the permitted types"
        return 1
    fi
    subject=${TITLE#*: }
    if [ -z "$(printf '%s' "$subject" | tr -d '[:space:]')" ]; then
        reject "the subject after ': ' is empty"
        return 1
    fi
    printf 'OK: "%s" is a valid Conventional Commit title.\n' "$TITLE"
    return 0
}

# The "type" bullet of CONTRIBUTING.md section 4, as a sorted, space-separated list — the same
# shape as the enforced list. Only the bullet that starts with the bold word "type" is read, so the
# rest of the section (scopes, examples, prose) cannot contribute a bogus entry.
documented_types() {
    # The quote character is built with an escape so that no backtick appears literally in this file.
    backtick=$(printf '\140')
    awk -v q="$backtick" '
        /^[[:space:]]*-[[:space:]]+[*][*]type[*][*]/ { inside = 1 }
        inside && /^[[:space:]]*-[[:space:]]+[*][*]/ && !/[*][*]type[*][*]/ { inside = 0 }
        inside {
            line = $0
            while (match(line, q "[a-z]+" q)) {
                print substr(line, RSTART + 1, RLENGTH - 2)
                line = substr(line, RSTART + RLENGTH)
            }
        }
    ' "$CONTRIBUTING_DOC" | sort -u | tr '\n' ' '
}

# Fails when the documented type set and the enforced one are not the same set, in either direction.
check_documented_types() {
    if [ ! -f "$CONTRIBUTING_DOC" ]; then
        fail "CONTRIBUTING.md not found at $CONTRIBUTING_DOC"
    fi
    enforced=$(printf '%s' "$TYPES" | tr ' ' '\n' | sort -u | tr '\n' ' ')
    documented=$(documented_types)
    if [ -z "$(printf '%s' "$documented" | tr -d '[:space:]')" ]; then
        fail "could not read the Conventional Commit type list from CONTRIBUTING.md section 4" \
            "  expected a bullet whose text starts with the bold word 'type' and lists the permitted" \
            "  types as lowercase words in backticks, e.g. '- **type** - required, one of ...'" \
            "  documented types found: (none)"
    fi
    if [ "$documented" != "$enforced" ]; then
        fail "the documented and the enforced Conventional Commit types differ" \
            "  CONTRIBUTING.md section 4: $documented" \
            "  enforced by this script   : $enforced" \
            "  fix both together: a type the document allows but this gate rejects fails a valid PR"
    fi
    printf 'CONTRIBUTING.md section 4 and this gate agree on the %s permitted types: %s\n' \
        "$(printf '%s' "$enforced" | wc -w | tr -d ' ')" "$enforced"
}

fail() {
    printf '\nFAIL: %s\n' "$1" >&2
    shift
    for detail in "$@"; do
        printf '%s\n' "$detail" >&2
    done
    exit 1
}

# The negative control: if this table stops holding, the gate above has silently broken and the
# job fails here instead of rubber-stamping every title.
self_test() {
    check_documented_types
    total=0
    failures=0
    while IFS='|' read -r expected title; do
        case $expected in
            ''|'#'*) continue ;;
        esac
        total=$((total + 1))
        if validate "$title" >/dev/null 2>&1; then
            actual=pass
        else
            actual=fail
        fi
        if [ "$actual" != "$expected" ]; then
            printf 'SELF-TEST FAILURE: expected %s, got %s for title: %s\n' "$expected" "$actual" "$title" >&2
            failures=$((failures + 1))
        fi
    done <<'CASES'
# expected|title
pass|feat: add the capture shield
pass|fix(ci): pin every action to a full commit SHA
pass|docs(api-contract): record the trait escape hatch
pass|chore: drop the unused demonstration target
pass|revert: feat: add the capture shield
pass|docs!: drop the iOS 14 wording
pass|build(deps-dev)!: raise the pinned xcodegen
fail|Update the README
fail|feat add the capture shield
fail|Feat: add the capture shield
fail|feature: add the capture shield
fail|feat(): empty scope
fail|feat:no space after the colon
fail|feat: 
fail| feat: leading space
fail|docs: trailing space 
fail|Revert "feat: add the capture shield"
fail|chore(deps) !: space before the bang
fail|
CASES
    if [ "$failures" -eq 0 ]; then
        printf 'self-test: %d title cases behaved as specified.\n' "$total"
        return 0
    fi
    printf 'self-test: %d of %d cases behaved unexpectedly.\n' "$failures" "$total" >&2
    return 1
}

usage_error() {
    printf 'usage: %s "<pull request title>"\n' "$0" >&2
    printf '       PR_TITLE="<title>" %s\n' "$0" >&2
    printf '       %s --self-test\n' "$0" >&2
    exit 2
}

main() {
    if [ "$#" -gt 1 ]; then
        usage_error
    fi
    case "${1:-}" in
        --self-test)
            self_test
            exit $?
            ;;
        -h|--help)
            usage_error
            ;;
    esac
    title="${1:-${PR_TITLE:-}}"
    if [ -z "$title" ]; then
        usage_error
    fi
    validate "$title"
}

main "$@"
