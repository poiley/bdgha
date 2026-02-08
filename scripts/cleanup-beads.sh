#!/bin/bash
set -euo pipefail

echo "::group::Cleaning up fix beads"

# BEAD_ID is expected to be set by extract-bead-id.sh or passed in
if [ -z "${BEAD_ID:-}" ]; then
  echo "::warning::No parent bead ID provided, nothing to clean up"
  echo "::endgroup::"
  exit 0
fi

echo "Looking for fix beads for parent: $BEAD_ID"

# Find child beads with ci-failure label that are still open
CHILD_BEADS=$(bd list --json --parent "$BEAD_ID" --labels "ci-failure" --status open 2>/dev/null | jq -r '.[].id' || echo "")

if [ -z "$CHILD_BEADS" ]; then
  echo "No open fix beads found for $BEAD_ID"
  echo "::endgroup::"
  exit 0
fi

# Close each fix bead
CLOSED_COUNT=0
for CHILD_ID in $CHILD_BEADS; do
  echo "Closing fix bead: $CHILD_ID"
  bd close "$CHILD_ID" -m "Fixed: PR #$PR_NUMBER CI now passing"
  echo "✅ Closed fix bead: $CHILD_ID"
  CLOSED_COUNT=$((CLOSED_COUNT + 1))
done

echo "✅ Closed $CLOSED_COUNT fix bead(s)"
echo "::endgroup::"
