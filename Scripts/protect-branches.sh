#!/bin/sh
# Protects mainline and every release-* branch with a repository ruleset named "Quality gate": a change goes in only
# through a pull request whose required checks passed, "Quality gate" (.github/workflows/quality.yml: `make lint` and
# `make test` on the Mac mini) and "review" (.github/workflows/review.yml's status), and nobody force-pushes to those
# branches or deletes them, admins included. No approval is required: the agent pipeline merges its own PRs once the
# checks pass, and the review is the independent one. It also turns on what the pipeline relies on: auto-merge, and
# Actions creating PRs. For the owner's integrator to run (not CI, not the pipeline), with a `gh` signed in as an admin
# of the repository; running it again updates the ruleset in place. --dry-run prints the requests instead.
#
#   Scripts/protect-branches.sh [--dry-run] [OWNER/REPO]     (default: MicroZ-LLC/AllInOneIME)
set -eu
dry=no
if [ "${1:-}" = --dry-run ]; then dry=yes; shift; fi
repo=${1:-MicroZ-LLC/AllInOneIME}

# GitHub Actions' app: only a check run from a workflow counts as "Quality gate". "review" is a commit status, any
# source (a status the job's token sets isn't tied to the app the same way).
ruleset=$(cat <<'EOF'
{
  "name": "Quality gate",
  "target": "branch",
  "enforcement": "active",
  "conditions": {"ref_name": {"include": ["refs/heads/mainline", "refs/heads/release-*"], "exclude": []}},
  "bypass_actors": [],
  "rules": [
    {"type": "deletion"},
    {"type": "non_fast_forward"},
    {"type": "pull_request", "parameters": {
      "required_approving_review_count": 0,
      "dismiss_stale_reviews_on_push": false,
      "require_code_owner_review": false,
      "require_last_push_approval": false,
      "required_review_thread_resolution": false}},
    {"type": "required_status_checks", "parameters": {
      "strict_required_status_checks_policy": false,
      "do_not_enforce_on_create": true,
      "required_status_checks": [
        {"context": "Quality gate", "integration_id": 15368},
        {"context": "review"}]}}
  ]
}
EOF
)

request() {  # METHOD PATH [JSON]
    if [ $dry = yes ]; then
        echo "gh api -X $1 $2 ${3:+--input - with:}"
        [ -z "${3:-}" ] || echo "$3"
    elif [ -n "${3:-}" ]; then
        printf '%s' "$3" | gh api -X "$1" "$2" --input - >/dev/null
    else
        gh api -X "$1" "$2" >/dev/null
    fi
}

existing=
[ $dry = yes ] || existing=$(gh api "repos/$repo/rulesets" --jq '.[] | select(.name == "Quality gate") | .id')
if [ -n "$existing" ]; then
    request PUT "repos/$repo/rulesets/$existing" "$ruleset"
else
    request POST "repos/$repo/rulesets" "$ruleset"
fi
# The pipeline's PRs merge by GitHub's auto-merge when it's allowed (else within the hour, agent-queue.yml), and the
# pipeline needs Actions to create PRs: without one nothing of it merges now.
request PATCH "repos/$repo" '{"allow_auto_merge": true}'
request PUT "repos/$repo/actions/permissions/workflow" '{"can_approve_pull_request_reviews": true}'
[ $dry = yes ] || echo "protect-branches: $repo's mainline and release-* need a PR with \"Quality gate\" and \"review\" passed"
