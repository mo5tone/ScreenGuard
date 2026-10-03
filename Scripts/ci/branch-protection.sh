#!/bin/sh
# =============================================================================================
# Scripts/ci/branch-protection.sh — put `main` behind a pull request and a green CI run.
#
# WHY
#   A workflow that runs is not a gate. On GitHub, a check blocks a merge only when it is listed as a
#   required status check for the branch, and a direct push bypasses every check there is unless
#   admin enforcement is on. Three settings together are what make "green CI" mean something here:
#
#     1. required status checks   pr-title, quality, build-and-test (strict: the branch must be
#                                 up to date, so the checks ran against the merge result)
#     2. required pull request    0 required approvals — a solo maintainer must still be able to
#                                 merge their own pull request — with stale reviews dismissed when
#                                 the head is pushed to, so an approval cannot outlive the code it
#                                 approved
#     3. enforce_admins = true    the owner is not exempt: a direct push to `main` is REFUSED even
#                                 with admin rights. `main` changes through a reviewed, green pull
#                                 request, or it does not change.
#
#   It is deliberately an operator script rather than a workflow step: branch protection is a
#   repository setting that needs admin rights, and a workflow that granted its own job a longer
#   leash would be the wrong shape. Run it once after the repository is created (and after any
#   rename of the jobs in .github/workflows/ci.yml).
#
# USAGE
#   Scripts/ci/branch-protection.sh print-payload      # the required_status_checks request body
#   Scripts/ci/branch-protection.sh print-plan         # every call `apply` makes, with its body
#   Scripts/ci/branch-protection.sh apply   [--repo OWNER/REPO] [--branch main]
#   Scripts/ci/branch-protection.sh verify  [--repo OWNER/REPO] [--branch main]
#
#   apply  also re-runs verify, so "applied" and "enforced" cannot be confused.
#   --repo defaults to the repository of the current directory (`gh repo view`).
#
# WHAT IT CHANGES: the pull-request requirement, the required status checks, and admin enforcement.
# It deliberately does NOT touch restrictions (who may push), linear history, force pushes,
# deletions, conversation resolution, or dismissal restrictions.
# Exit codes: 0 = in the requested state, 1 = not (or a drift between this script and ci.yml), 2 = usage.
# =============================================================================================
set -eu

# The check contexts that must be required. These MUST match the \`name:\` of the jobs in
# .github/workflows/ci.yml; check_workflow_job_names enforces that, so a renamed job cannot silently
# un-require a check.
CONTEXTS="pr-title quality build-and-test"

# The review policy: PR required, no approval required, stale approvals dismissed on push, and code
# owner review NOT required (the repository has one maintainer; requiring the code owner's review
# would block every pull request they open themselves).
REQUIRED_APPROVALS=0
DISMISS_STALE_REVIEWS=true
REQUIRE_CODE_OWNER_REVIEWS=false

WORKFLOW=".github/workflows/ci.yml"
BRANCH="main"
REPO=""

fail() {
    printf '\nFAIL: %s\n' "$1" >&2
    shift
    for detail in "$@"; do
        printf '%s\n' "$detail" >&2
    done
    exit 1
}

usage_error() {
    printf 'usage: %s print-payload\n' "$0" >&2
    printf '       %s print-plan\n' "$0" >&2
    printf '       %s apply  [--repo OWNER/REPO] [--branch main]\n' "$0" >&2
    printf '       %s verify [--repo OWNER/REPO] [--branch main]\n' "$0" >&2
    exit 2
}

# Every required context must exist as a job name in the workflow — otherwise the branch would
# require a check that never runs, which blocks every merge.
check_workflow_job_names() {
    [ -f "$WORKFLOW" ] || fail "$WORKFLOW not found" \
        "  run this from the repository root"
    for context in $CONTEXTS; do
        if ! grep -Eq "^    name: ${context}\$" "$WORKFLOW"; then
            fail "no job named '$context' in $WORKFLOW" \
                "  the required status checks and the workflow job names have drifted apart" \
                "  fix the job's 'name:' (a check context is the job name) or update CONTEXTS in this script"
        fi
    done
    # Progress goes to stderr so that print-payload's stdout stays pipeable JSON.
    echo "workflow job names match the required contexts: $CONTEXTS" >&2
}

# The request body for PUT .../protection/required_status_checks, built from CONTEXTS.
# \`contexts\` is the long-standing field (GitHub is retiring it in favour of \`checks\`); both are sent
# so the setting survives that transition, and no app_id is pinned so the GitHub Actions app that
# reports the check is accepted.
print_payload() {
    printf '{"strict": true, "contexts": ['
    separator=""
    for context in $CONTEXTS; do
        printf '%s"%s"' "$separator" "$context"
        separator=", "
    done
    printf '], "checks": ['
    separator=""
    for context in $CONTEXTS; do
        printf '%s{"context": "%s"}' "$separator" "$context"
        separator=", "
    done
    printf ']}\n'
}

# The request body for PUT .../protection/required_pull_request_reviews.
print_pr_payload() {
    printf '{"required_approving_review_count": %s, "dismiss_stale_reviews": %s, "require_code_owner_reviews": %s}\n' \
        "$REQUIRED_APPROVALS" "$DISMISS_STALE_REVIEWS" "$REQUIRE_CODE_OWNER_REVIEWS"
}

# The endpoints take an optional repository argument so print-plan can render them for a
# placeholder repository without a network call, while apply and verify use $REPO. One builder, so
# the plan cannot describe a different call than the one that runs.
endpoint_status_checks() {
    printf '/repos/%s/branches/%s/protection/required_status_checks' "${1:-$REPO}" "$BRANCH"
}

endpoint_pr_reviews() {
    printf '/repos/%s/branches/%s/protection/required_pull_request_reviews' "${1:-$REPO}" "$BRANCH"
}

endpoint_enforce_admins() {
    printf '/repos/%s/branches/%s/protection/enforce_admins' "${1:-$REPO}" "$BRANCH"
}

endpoint_protection() {
    printf '/repos/%s/branches/%s/protection' "${1:-$REPO}" "$BRANCH"
}

# Exactly what apply does, in order, so the plan can be reviewed (and diffed against a run) without
# touching the repository.
print_plan() {
    # REPO may be unset here (print-plan must work offline), so the endpoints are rendered inside a
    # subshell that supplies a placeholder — the endpoint builders are still the ones apply uses, so
    # the plan cannot describe a different call than the one that runs.
    plan_repo="${REPO:-<repo>}"
    printf 'branch protection plan for %s@%s\n\n' "$plan_repo" "$BRANCH"
    printf '1. PUT %s\n' "$(endpoint_status_checks "$plan_repo")"
    printf '   body: %s\n' "$(print_payload)"
    printf '   -> requires pr-title, quality and build-and-test, strict (branch must be up to date)\n\n'
    printf '2. PUT %s\n' "$(endpoint_pr_reviews "$plan_repo")"
    printf '   body: %s\n' "$(print_pr_payload)"
    printf '   -> a pull request is required; %s approvals required; stale reviews dismissed on push\n\n' "$REQUIRED_APPROVALS"
    printf '3. PUT %s\n' "$(endpoint_enforce_admins "$plan_repo")"
    printf '   (no body) -> administrators are NOT exempt: a direct push to %s is refused\n\n' "$BRANCH"
    printf '4. verify: re-read %s and assert all three, then exit non-zero if any is missing\n\n' "$(endpoint_protection "$plan_repo")"
    printf 'NOT touched by this script: restrictions (who may push), linear history, force pushes,\n'
    printf 'deletions, conversation resolution, dismissal restrictions.\n'
}

require_repo() {
    command -v gh >/dev/null 2>&1 || fail "gh is not on PATH" "  install the GitHub CLI"
    if [ -z "$REPO" ]; then
        REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)
        [ -n "$REPO" ] || fail "cannot determine the repository" \
            "  there is no remote here yet: pass --repo OWNER/REPO explicitly"
    fi
    printf 'repository: %s   branch: %s\n' "$REPO" "$BRANCH" >&2
}

# Reads the settings back and asserts every part of the policy. A missing protection object is a
# failure, not an empty pass: "no protection" and "the protection we asked for" are not the same
# state, and only one of them stops a direct push.
verify_protection() {
    require_repo

    protection=$(gh api "$(endpoint_protection)" 2>&1) || fail "cannot read the branch protection of $REPO@$BRANCH" \
        "$protection" \
        "  (the endpoint needs a token with admin access to $REPO)" \
        "  if the branch has no protection at all, apply it: $0 apply --repo $REPO --branch $BRANCH"

    strict=$(gh api "$(endpoint_status_checks)" --jq '.strict' 2>/dev/null || true)
    enforced=$(gh api "$(endpoint_status_checks)" --jq '(.contexts // [])[], ((.checks // [])[] | .context)' 2>/dev/null || true)
    pr_present=$(gh api "$(endpoint_protection)" --jq 'if (.required_pull_request_reviews == null) then "no" else "yes" end' 2>/dev/null || true)
    pr_count=$(gh api "$(endpoint_protection)" --jq '.required_pull_request_reviews.required_approving_review_count // "null"' 2>/dev/null || true)
    pr_dismiss=$(gh api "$(endpoint_protection)" --jq '.required_pull_request_reviews.dismiss_stale_reviews // "null"' 2>/dev/null || true)
    admins=$(gh api "$(endpoint_protection)" --jq '.enforce_admins.enabled' 2>/dev/null || true)

    echo "   required status checks, strict .......: $strict"
    failure=0
    for context in $CONTEXTS; do
        if printf '%s\n' "$enforced" | grep -qx "$context"; then
            echo "   required check .......................: $context"
        else
            printf '   NOT REQUIRED .........................: %s\n' "$context"
            failure=1
        fi
    done
    echo "   pull request required ................: $pr_present"
    echo "   required approvals ...................: $pr_count"
    echo "   dismiss stale reviews on push ........: $pr_dismiss"
    echo "   administrators are enforced (no bypass): $admins"

    if [ "$failure" -ne 0 ]; then
        fail "not every pull-request check is required on $REPO@$BRANCH" \
            "  a failing or malformed pull-request check could be merged right now" \
            "  run: $0 apply --repo $REPO --branch $BRANCH"
    fi
    [ "$strict" = "true" ] || fail "required status checks are enforced but 'strict' is $strict" \
        "  without strict mode a branch can be merged while behind $BRANCH" \
        "  run: $0 apply --repo $REPO --branch $BRANCH"
    [ "$pr_present" = "yes" ] || fail "$BRANCH does not require a pull request" \
        "  a commit could be pushed straight to $BRANCH without any check running" \
        "  run: $0 apply --repo $REPO --branch $BRANCH"
    [ "$pr_count" = "$REQUIRED_APPROVALS" ] || fail "required approving reviews is $pr_count, expected $REQUIRED_APPROVALS" \
        "  run: $0 apply --repo $REPO --branch $BRANCH"
    [ "$pr_dismiss" = "$DISMISS_STALE_REVIEWS" ] || fail "dismiss_stale_reviews is $pr_dismiss, expected $DISMISS_STALE_REVIEWS" \
        "  an approval could outlive the commit it approved" \
        "  run: $0 apply --repo $REPO --branch $BRANCH"
    [ "$admins" = "true" ] || fail "administrator enforcement (no bypass) is $admins, expected true" \
        "  without it the owner can push directly to $BRANCH and skip every check" \
        "  run: $0 apply --repo $REPO --branch $BRANCH"

    echo "OK: $REPO@$BRANCH requires a pull request, $REQUIRED_APPROVALS approvals and the checks $CONTEXTS (strict), and admins are enforced"
}

apply_protection() {
    require_repo
    printf 'applying branch protection to %s@%s ...\n' "$REPO" "$BRANCH"

    print_payload | gh api --method PUT "$(endpoint_status_checks)" --input - >/dev/null \
        || fail "the PUT to $(endpoint_status_checks) failed" \
               "  check that the token has admin rights on $REPO and that the branch exists"
    printf '   required status checks ... applied\n'

    print_pr_payload | gh api --method PUT "$(endpoint_pr_reviews)" --input - >/dev/null \
        || fail "the PUT to $(endpoint_pr_reviews) failed" \
               "  check that the token has admin rights on $REPO and that the branch exists"
    printf '   pull request required .... applied\n'

    gh api --method PUT "$(endpoint_enforce_admins)" >/dev/null 2>&1 \
        || fail "the PUT to $(endpoint_enforce_admins) failed" \
               "  check that the token has admin rights on $REPO"
    printf '   admin enforcement ....... applied\n'

    verify_protection
}

action="${1:-}"
[ -n "$action" ] || usage_error
shift
while [ "$#" -gt 0 ]; do
    case $1 in
        --repo)
            [ "$#" -ge 2 ] || usage_error
            REPO=$2
            shift 2
            ;;
        --branch)
            [ "$#" -ge 2 ] || usage_error
            BRANCH=$2
            shift 2
            ;;
        *) usage_error ;;
    esac
done

check_workflow_job_names
case $action in
    print-payload) print_payload ;;
    print-plan)    print_plan ;;
    apply)         apply_protection ;;
    verify)        verify_protection ;;
    *)             usage_error ;;
esac
