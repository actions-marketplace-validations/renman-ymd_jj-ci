#!/usr/bin/env bash
# Turn the checkout into a jj repository and work out which revisions to check.
#
# Writes `revisions` to $GITHUB_OUTPUT and JJ_CI_BIN to $GITHUB_ENV.
set -euo pipefail

WORKDIR=${WORKDIR:-.}
INPUT_REVISIONS=${INPUT_REVISIONS:-}
EVENT_NAME=${EVENT_NAME:-}
ZERO=0000000000000000000000000000000000000000

die() {
  printf '::error::%s\n' "$*" >&2
  exit 1
}

warn() { printf '::warning::%s\n' "$*"; }

cd "$WORKDIR" || die "working-directory does not exist: $WORKDIR"

[ -d .git ] || die "$PWD is not a git checkout — this action runs after actions/checkout"

# A runner has no identity, and jj wants one before it will build a working-copy
# commit. These are never written to anything.
export JJ_USER=${JJ_USER:-jj-ci}
export JJ_EMAIL=${JJ_EMAIL:-jj-ci@users.noreply.github.com}

if [ -d .jj ]; then
  printf 'already a jj repository\n'
else
  jj git init >/dev/null 2>&1 || die "jj git init failed in $PWD"
  printf 'colocated a jj repository onto the checkout\n'
fi

shallow=$(git rev-parse --is-shallow-repository)

# Number of revisions a revset names, or nothing at all if it does not parse.
revision_count() {
  jj log --no-graph --revisions "$1" --template '"x\n"' 2>/dev/null | wc -l | tr -d ' '
}

derive_revset() {
  case "$EVENT_NAME" in
    pull_request | pull_request_target)
      # The checkout is the merge commit; the pull request's own commits are
      # the range between its base and its head.
      if [ -n "${PR_BASE_SHA:-}" ] && [ -n "${PR_HEAD_SHA:-}" ]; then
        printf '%s..%s' "$PR_BASE_SHA" "$PR_HEAD_SHA"
      fi
      ;;
    merge_group)
      if [ -n "${MERGE_BASE_SHA:-}" ] && [ -n "${MERGE_HEAD_SHA:-}" ]; then
        printf '%s..%s' "$MERGE_BASE_SHA" "$MERGE_HEAD_SHA"
      fi
      ;;
    push)
      # `before` is all zeroes when the branch is new, and names a commit that
      # no longer exists after a force push.
      if [ -n "${PUSH_BEFORE:-}" ] && [ "$PUSH_BEFORE" != "$ZERO" ] && [ -n "${PUSH_AFTER:-}" ]; then
        printf '%s..%s' "$PUSH_BEFORE" "$PUSH_AFTER"
      fi
      ;;
  esac
}

if [ -n "$INPUT_REVISIONS" ]; then
  revset=$INPUT_REVISIONS
  [ "$(revision_count "$revset")" != 0 ] ||
    die "the revisions input names nothing in this repository: $revset"
elif [ "$shallow" = true ]; then
  # actions/checkout fetches one commit unless told otherwise, and a checkout
  # with no history has no range to reason about. Checking the state that was
  # checked out is what such a job means, so this is normal, not a problem.
  revset='@-'
  printf 'shallow checkout: checking the checked-out state only\n'
else
  revset=$(derive_revset)
  if [ -n "$revset" ] && [ "$(revision_count "$revset")" = 0 ]; then
    warn "$EVENT_NAME gave a range this full checkout cannot resolve ($revset); falling back to the checked-out commit. A force push is the usual cause."
    revset=
  fi
  # `@` is the empty working-copy commit jj adds on top, so the commit that was
  # checked out is its parent.
  [ -n "$revset" ] || revset='@-'
fi

# mod.nu, never the bin/jj-ci symlink beside it. Whatever fetches an action
# materialises that symlink as a *copy*, and a copy resolves `path self` to
# bin/, where there are no modules to import. The copy is executable, so testing
# for that proves nothing; the file that is always right is the real one.
entry=$ACTION_ROOT/mod.nu
[ -f "$entry" ] || die "$entry is missing — the action was not fetched whole"

printf 'revisions=%s\n' "$revset" >>"$GITHUB_OUTPUT"
printf 'JJ_CI_ENTRY=%s\n' "$entry" >>"$GITHUB_ENV"
printf 'checking %s revision(s) in %s\n' "$(revision_count "$revset")" "$revset"
