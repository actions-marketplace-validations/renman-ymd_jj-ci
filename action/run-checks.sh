#!/usr/bin/env bash
# Run one stage of the repository's checks over the revisions prepare-repo.sh
# resolved. Every flag is optional, which is why the argument list is built
# here rather than interpolated into a workflow.
set -euo pipefail

cd "${WORKDIR:-.}"

args=(ci --stage "${STAGE:-push}" --revisions "$REVISIONS" --jobs "${JOBS:-1}")

[ "${STRICT:-true}" != true ] || args+=(--strict)
[ "${VERBOSE:-false}" != true ] || args+=(--verbose)
[ -z "${ONLY:-}" ] || args+=(--only "$ONLY")
[ "${NO_CACHE:-false}" != true ] || args+=(--no-cache)

# Through nu rather than the shebang: an exec bit is one more thing that has to
# survive being fetched, and nushell is on PATH by the time this runs.
exec nu "$JJ_CI_ENTRY" "${args[@]}"
