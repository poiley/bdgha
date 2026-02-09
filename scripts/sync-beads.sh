#!/bin/bash
set -euo pipefail

echo "::group::Syncing beads state"

SYNC_BRANCH="${SYNC_BRANCH:-beads-sync}"

# Configure git
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"

# Fetch sync branch
echo "Fetching $SYNC_BRANCH..."
if ! git fetch origin "$SYNC_BRANCH" 2>/dev/null; then
  echo "::warning::Sync branch $SYNC_BRANCH does not exist on remote, creating it"
  git checkout --orphan "$SYNC_BRANCH"
  mkdir -p .beads
  touch .beads/issues.jsonl
  git add -f .beads/issues.jsonl
  git commit -m "chore: initialize $SYNC_BRANCH"
  git push -u origin "$SYNC_BRANCH"
  git checkout -
  echo "::endgroup::"
  exit 0
fi

# Save current branch/ref
ORIGINAL_REF=$(git rev-parse HEAD)

# Bring in the JSONL from sync branch without switching branches
echo "Importing JSONL from $SYNC_BRANCH..."
git show "origin/$SYNC_BRANCH:.beads/issues.jsonl" > .beads/issues.jsonl 2>/dev/null || {
  echo "::warning::No issues.jsonl found on $SYNC_BRANCH"
  touch .beads/issues.jsonl
}

# Import into bd (no-db mode reads JSONL directly, so this is a no-op,
# but we ensure the file is present for subsequent bd commands)
echo "Beads state imported from $SYNC_BRANCH"

# Export any local changes (in case bd daemon made changes)
echo "Exporting local beads state..."
bd sync --no-db --no-daemon 2>/dev/null || true

echo "✅ Beads synced"
echo "::endgroup::"
