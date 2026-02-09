#!/bin/bash
set -euo pipefail

echo "::group::Cleaning up fix beads"

BD_FLAGS="--no-db --no-daemon"

# BEAD_ID = parent bead, FAILURE_TYPE = the gate that passed
if [ -z "${BEAD_ID:-}" ]; then
  echo "::warning::No parent bead ID provided, nothing to clean up"
  echo "::endgroup::"
  exit 0
fi

FAILURE_TYPE="${FAILURE_TYPE:-}"

echo "Looking for fix beads for parent: $BEAD_ID"
if [ -n "$FAILURE_TYPE" ]; then
  echo "Filtering by gate type: $FAILURE_TYPE"
fi

# Find open fix beads that match this parent + gate type
if [ -n "$FAILURE_TYPE" ]; then
  # Per-gate cleanup: only close fix beads for the gate that passed
  CHILD_BEADS=$(bd list --label "ci-failure" --label "$FAILURE_TYPE" --status open --json $BD_FLAGS 2>/dev/null | \
    jq -r --arg pr "$PR_NUMBER" '.[] | select(
      (.metadata.ci_failure.context.pr_number // 0 | tostring) == $pr
    ) | .id' 2>/dev/null || echo "")
else
  # Close all fix beads for this PR
  CHILD_BEADS=$(bd list --label "ci-failure" --status open --json $BD_FLAGS 2>/dev/null | \
    jq -r --arg pr "$PR_NUMBER" '.[] | select(
      (.metadata.ci_failure.context.pr_number // 0 | tostring) == $pr
    ) | .id' 2>/dev/null || echo "")
fi

if [ -z "$CHILD_BEADS" ]; then
  echo "No open fix beads found"
  echo "::endgroup::"
  exit 0
fi

# Close each fix bead
CLOSED_COUNT=0
for CHILD_ID in $CHILD_BEADS; do
  echo "Closing fix bead: $CHILD_ID"
  bd close "$CHILD_ID" -m "CI gate passed: ${FAILURE_TYPE:-all gates} now passing on PR #$PR_NUMBER" $BD_FLAGS
  echo "✅ Closed: $CHILD_ID"
  CLOSED_COUNT=$((CLOSED_COUNT + 1))
done

echo "Closed $CLOSED_COUNT fix bead(s)"

# Check if parent is now fully unblocked
# Query all open beads that block the parent
REMAINING=$(bd dep list "$BEAD_ID" --direction down --type blocks --json $BD_FLAGS 2>/dev/null | \
  jq '[.[] | select(.status == "open")] | length' 2>/dev/null || echo "0")

if [ "$REMAINING" -eq 0 ]; then
  echo "::notice::All fix beads for $BEAD_ID are resolved - parent is unblocked"
else
  echo "$REMAINING blocking fix bead(s) remain open for $BEAD_ID"
fi

echo "::endgroup::"
