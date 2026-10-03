#!/bin/sh
# =============================================================================================
# Scripts/ci/branch-protection.sh — put 'main' behind a pull request and a green CI run.
#
# WHY RULESETS, NOT THE CLASSIC BRANCH-PROTECTION API
#   The documented classic endpoint
#       PUT /repos/{owner}/{repo}/branches/{branch}/protection/required_status_checks
#   returns HTTP 404 "Not Found" on this repository even though the branch exists, the token has
#   admin rights and the JSON body is valid (measured on mo5tone/ScreenGuard, 2026-10-03; a minimal
#   PUT with an explicit body 404s identically). The repository is therefore protected through the
#   RULESETS API instead, which is the mechanism GitHub now steers toward where the classic
#   endpoints are unavailable.
#
#   CONSEQUENCE EVERY READER MUST KNOW: the policy lives ONLY in the ruleset, and the classic API
#   view of this branch is empty. Measured on mo5tone/ScreenGuard, 2026-10-03:
#     GET /repos/{owner}/{repo}/branches/main                      -> "protected": true
#     ... .protection                                              -> {"enabled": false,
#                                                                     "required_status_checks":
#                                                                     {"contexts": [], "enforcement_level": "off"}}
#     GET .../branches/main/protection                             -> 404 "Branch not protected"
#     GET .../branches/main/protection/required_status_checks      -> 404
#   So the classic endpoints say "not protected" while the ruleset enforces a pull request and three
#   required checks. Never conclude "unprotected" from those 404s, and never conclude "fully
#   protected" from the bare protected:true flag either — read the ruleset (verify does exactly that).
#
#   The policy, in three parts:
#     1. a pull request is required, with 0 required approvals — a solo maintainer must still be
#        able to merge their own pull request — and stale reviews are dismissed when the head is
#        pushed to, so an approval cannot outlive the code it approved;
#     2. the CI checks pr-title, quality and build-and-test are required, strictly (the branch must
#        be up to date, so the checks ran against the merge result);
#     3. nothing may bypass the ruleset: bypass_actors is empty, which GitHub reports as
#        current_user_can_bypass "never" — a direct push to 'main' is refused even for the owner.
#   Deletion and non-fast-forward (force-push) are blocked as well.
#
# USAGE
#   Scripts/ci/branch-protection.sh print-payload      # the ruleset request body
#   Scripts/ci/branch-protection.sh print-plan         # every call apply makes, with its body
#   Scripts/ci/branch-protection.sh apply   [--repo OWNER/REPO] [--branch main]
#   Scripts/ci/branch-protection.sh verify  [--repo OWNER/REPO] [--branch main]
#
#   apply is IDEMPOTENT: it looks the ruleset up by name and updates it by id, and only creates one
#   when none exists. Running it twice never produces two rulesets.
#   apply also re-runs verify, so "applied" and "enforced" cannot be confused.
#   --repo defaults to the repository of the current directory (gh repo view).
#
# Exit codes: 0 = in the requested state, 1 = not (or a drift between this script and ci.yml), 2 = usage.
# =============================================================================================
set -eu

# The check contexts that must be required. These MUST match the 'name:' of the jobs in
# .github/workflows/ci.yml; check_workflow_job_names enforces that, so a renamed job cannot silently
# un-require a check.
CONTEXTS="pr-title quality build-and-test"

# The ruleset that carries the policy, and the review parameters inside it.
RULESET_NAME="main-protection"
REQUIRED_APPROVALS=0
DISMISS_STALE_REVIEWS=true
REQUIRE_CODE_OWNER_REVIEWS=false
REQUIRE_LAST_PUSH_APPROVAL=false
REQUIRE_THREAD_RESOLUTION=false

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
        if ! grep -Eq "^    name: $context\$" "$WORKFLOW"; then
            fail "no job named '$context' in $WORKFLOW" \
                "  the required status checks and the workflow job names have drifted apart" \
                "  fix the job's 'name:' (a check context is the job name) or update CONTEXTS in this script"
        fi
    done
    # Progress goes to stderr so print-payload's stdout stays pipeable JSON.
    echo "workflow job names match the required contexts: $CONTEXTS" >&2
}

# The complete ruleset request body, used by both POST (create) and PUT (update).
print_payload() {
    printf '{'
    printf '"name": "%s", ' "$RULESET_NAME"
    printf '"target": "branch", '
    printf '"enforcement": "active", '
    printf '"conditions": {"ref_name": {"include": ["refs/heads/%s"], "exclude": []}}, ' "$BRANCH"
    printf '"bypass_actors": [], '
    printf '"rules": ['
    printf '{"type": "deletion"}, '
    printf '{"type": "non_fast_forward"}, '
    printf '{"type": "pull_request", "parameters": {'
    printf '"required_approving_review_count": %s, ' "$REQUIRED_APPROVALS"
    printf '"dismiss_stale_reviews_on_push": %s, ' "$DISMISS_STALE_REVIEWS"
    printf '"require_code_owner_review": %s, ' "$REQUIRE_CODE_OWNER_REVIEWS"
    printf '"require_last_push_approval": %s, ' "$REQUIRE_LAST_PUSH_APPROVAL"
    printf '"required_review_thread_resolution": %s}}, ' "$REQUIRE_THREAD_RESOLUTION"
    printf '{"type": "required_status_checks", "parameters": {'
    printf '"strict_required_status_checks_policy": true, '
    printf '"do_not_enforce_on_create": false, '
    printf '"required_status_checks": ['
    separator=""
    for context in $CONTEXTS; do
        printf '%s{"context": "%s"}' "$separator" "$context"
        separator=", "
    done
    printf ']}}'
    printf ']}\n'
}

rulesets_endpoint() {
    printf 'repos/%s/rulesets' "$1"
}

ruleset_endpoint() {
    printf 'repos/%s/rulesets/%s' "$1" "$2"
}

# Exactly what apply does, in order, so the plan can be reviewed without touching the repository.
print_plan() {
    plan_repo="$REPO"
    if [ -z "$plan_repo" ]; then
        plan_repo="<repo>"
    fi
    printf 'ruleset protection plan for %s@%s\n\n' "$plan_repo" "$BRANCH"
    printf '1. GET %s?per_page=100\n' "$(rulesets_endpoint "$plan_repo")"
    printf '   -> find the ruleset named "%s" (by NAME, which is what makes apply idempotent)\n\n' "$RULESET_NAME"
    printf '2a. if it exists:      PUT %s\n' "$(ruleset_endpoint "$plan_repo" "<id>")"
    printf '2b. if it does not:    POST %s\n' "$(rulesets_endpoint "$plan_repo")"
    printf '    body (identical for both): %s\n' "$(print_payload)"
    printf '    -> requires a pull request (%s approvals, stale reviews dismissed on push),\n' "$REQUIRED_APPROVALS"
    printf '       requires the checks %s strictly, blocks deletion and force-push,\n' "$CONTEXTS"
    printf '       and carries an EMPTY bypass_actors list (no bypass, not even for the owner)\n\n'
    printf '3. verify: re-read %s, assert every part above, and exit non-zero if any is missing\n\n' "$(ruleset_endpoint "$plan_repo" "<id>")"
    printf 'NOTE: this repository cannot use the classic endpoint\n'
    printf '      PUT /repos/{owner}/{repo}/branches/%s/protection/required_status_checks — it answers 404.\n' "$BRANCH"
    printf '      Because the policy lives in a ruleset, GET /repos/{owner}/{repo}/branches/%s still reports\n' "$BRANCH"
    printf '      "protected": false. That flag does not describe ruleset protection; read the ruleset.\n'
}

require_repo() {
    command -v gh >/dev/null 2>&1 || fail "gh is not on PATH" "  install the GitHub CLI"
    if [ -z "$REPO" ]; then
        REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)
        [ -n "$REPO" ] || fail "cannot determine the repository" \
            "  pass --repo OWNER/REPO explicitly"
    fi
    printf 'repository: %s   branch: %s\n' "$REPO" "$BRANCH" >&2
}

# The id of the ruleset we manage, or empty when it does not exist yet.
find_ruleset_id() {
    gh api "$(rulesets_endpoint "$REPO")" --paginate \
        --jq ".[] | select(.name == \"$RULESET_NAME\") | .id" 2>/dev/null | head -1 || true
}

# Reads the settings back and asserts every part of the policy. A missing ruleset is a FAILURE, not
# an empty pass: "no protection" and "the protection we asked for" are not the same state, and only
# one of them stops a direct push.
verify_protection() {
    require_repo

    ruleset_id=$(find_ruleset_id)
    if [ -z "$ruleset_id" ]; then
        fail "no ruleset named '$RULESET_NAME' exists on $REPO" \
            "  $BRANCH has NO protection at all: a commit could be pushed straight to it, and a red" \
            "  check could be merged, right now." \
            "  run: $0 apply --repo $REPO --branch $BRANCH" \
            "  (the classic branch-protection endpoint answers 404 on this repository, so this script" \
            "   uses the rulesets API: a missing ruleset is the state to look for. The branch's classic" \
            "   'protected' flag is always false when the policy lives in a ruleset.)"
    fi
    printf 'ruleset: %s (id %s)\n' "$RULESET_NAME" "$ruleset_id" >&2

    summary=$(gh api "$(ruleset_endpoint "$REPO" "$ruleset_id")" --jq '
        "enforcement=" + .enforcement,
        "target=" + .target,
        "include=" + ((.conditions.ref_name.include // []) | join(",")),
        "exclude_count=" + ((.conditions.ref_name.exclude // []) | length | tostring),
        "rules=" + ([.rules[].type] | join(",")),
        "approvals=" + ([.rules[] | select(.type == "pull_request") | .parameters.required_approving_review_count] | first | tostring),
        "dismiss=" + ([.rules[] | select(.type == "pull_request") | .parameters.dismiss_stale_reviews_on_push] | first | tostring),
        "strict=" + ([.rules[] | select(.type == "required_status_checks") | .parameters.strict_required_status_checks_policy] | first | tostring),
        "contexts=" + ([.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context] | join(",")),
        "bypass_actors=" + ((.bypass_actors // []) | length | tostring),
        "can_bypass=" + (.current_user_can_bypass // "unknown")
    ') || fail "cannot read ruleset $ruleset_id of $REPO" \
        "  (the endpoint needs a token with admin access to $REPO)"

    get() {
        printf '%s\n' "$summary" | sed -n "s/^$1=//p" | head -1
    }

    enforcement=$(get enforcement)
    target=$(get target)
    include=$(get include)
    exclude_count=$(get exclude_count)
    rules=$(get rules)
    approvals=$(get approvals)
    dismiss=$(get dismiss)
    strict=$(get strict)
    contexts=$(get contexts)
    bypass_actors=$(get bypass_actors)
    can_bypass=$(get can_bypass)

    echo "   enforcement ..........................: $enforcement"
    echo "   targets ..............................: $target / $include (excludes: $exclude_count)"
    echo "   rules ................................: $rules"
    echo "   required approvals ...................: $approvals"
    echo "   dismiss stale reviews on push ........: $dismiss"
    echo "   strict required status checks ........: $strict"
    echo "   required contexts ....................: $contexts"
    echo "   bypass actors ........................: $bypass_actors (current user can bypass: $can_bypass)"

    [ "$enforcement" = "active" ] || fail "the ruleset is not active (enforcement=$enforcement)" \
        "  run: $0 apply --repo $REPO --branch $BRANCH"
    [ "$target" = "branch" ] || fail "the ruleset targets '$target', expected 'branch'" \
        "  run: $0 apply --repo $REPO --branch $BRANCH"
    printf '%s\n' "$include" | tr ',' '\n' | grep -qx "refs/heads/$BRANCH" || fail \
        "the ruleset does not cover refs/heads/$BRANCH (it covers: $include)" \
        "  run: $0 apply --repo $REPO --branch $BRANCH"
    [ "$exclude_count" = "0" ] || fail "the ruleset excludes $exclude_count ref pattern(s)" \
        "  an exclusion can carve $BRANCH back out of the policy"
    for rule in deletion non_fast_forward pull_request required_status_checks; do
        printf '%s\n' "$rules" | tr ',' '\n' | grep -qx "$rule" || fail "the ruleset is missing the '$rule' rule" \
            "  run: $0 apply --repo $REPO --branch $BRANCH"
    done
    [ "$approvals" = "$REQUIRED_APPROVALS" ] || fail "required approving reviews is $approvals, expected $REQUIRED_APPROVALS" \
        "  run: $0 apply --repo $REPO --branch $BRANCH"
    [ "$dismiss" = "$DISMISS_STALE_REVIEWS" ] || fail "dismiss_stale_reviews_on_push is $dismiss, expected $DISMISS_STALE_REVIEWS" \
        "  an approval could outlive the commit it approved" \
        "  run: $0 apply --repo $REPO --branch $BRANCH"
    [ "$strict" = "true" ] || fail "required status checks are not strict (strict=$strict)" \
        "  without strict mode a branch can be merged while behind $BRANCH" \
        "  run: $0 apply --repo $REPO --branch $BRANCH"
    for context in $CONTEXTS; do
        printf '%s\n' "$contexts" | tr ',' '\n' | grep -qx "$context" || fail \
            "the check '$context' is not required by the ruleset (required: $contexts)" \
            "  a failing or malformed '$context' check could be merged right now" \
            "  run: $0 apply --repo $REPO --branch $BRANCH"
    done
    [ "$bypass_actors" = "0" ] || fail "the ruleset grants $bypass_actors bypass actor(s)" \
        "  a bypass actor can push to $BRANCH without any check running; the policy is no-bypass" \
        "  run: $0 apply --repo $REPO --branch $BRANCH"
    if [ "$can_bypass" != "never" ] && [ "$can_bypass" != "unknown" ]; then
        fail "GitHub reports current_user_can_bypass=$can_bypass for this ruleset" \
            "  expected 'never': the owner must not be able to bypass the rules either"
    fi

    echo "OK: $REPO@$BRANCH requires a pull request, $REQUIRED_APPROVALS approvals and the checks $CONTEXTS (strict), with no bypass actors"
}

apply_protection() {
    require_repo

    ruleset_id=$(find_ruleset_id)
    if [ -n "$ruleset_id" ]; then
        printf 'updating the existing ruleset "%s" (id %s) on %s@%s ...\n' "$RULESET_NAME" "$ruleset_id" "$REPO" "$BRANCH"
        print_payload | gh api --method PUT "$(ruleset_endpoint "$REPO" "$ruleset_id")" --input - >/dev/null \
            || fail "the PUT to $(ruleset_endpoint "$REPO" "$ruleset_id") failed" \
                   "  check that the token has admin rights on $REPO"
    else
        printf 'creating the ruleset "%s" on %s@%s ...\n' "$RULESET_NAME" "$REPO" "$BRANCH"
        print_payload | gh api --method POST "$(rulesets_endpoint "$REPO")" --input - >/dev/null \
            || fail "the POST to $(rulesets_endpoint "$REPO") failed" \
                   "  check that the token has admin rights on $REPO"
    fi

    count=$(gh api "$(rulesets_endpoint "$REPO")" --paginate --jq "[.[] | select(.name == \"$RULESET_NAME\")] | length" 2>/dev/null || true)
    [ "$count" = "1" ] || fail "expected exactly one ruleset named '$RULESET_NAME', found $count" \
        "  apply must update the existing ruleset by id, never create a second one"

    verify_protection
}

action="$1"
if [ -z "$action" ]; then
    usage_error
fi
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
