#!/bin/bash
set -euo pipefail

echo "::group::Creating fix bead"

# Check if auto-remediation is enabled in config
if [ -f ".beads/config.yaml" ]; then
  ENABLED=$(grep -A10 "ci:" .beads/config.yaml 2>/dev/null | grep "enabled:" | awk '{print $2}' || echo "true")
  if [ "$ENABLED" = "false" ]; then
    echo "::warning::CI auto-remediation disabled in config"
    echo "skipped=true" >> "$GITHUB_OUTPUT"
    echo "::endgroup::"
    exit 0
  fi
fi

METADATA_FILE="${METADATA_FILE:-/tmp/ci-metadata.json}"
BD_FLAGS="--no-db --no-daemon"

# Get PR details
echo "Fetching PR details..."
PR_TITLE=$(gh pr view "$PR_NUMBER" --json title -q '.title')
PR_AUTHOR=$(gh pr view "$PR_NUMBER" --json author -q '.author.login')
PR_BRANCH=$(gh pr view "$PR_NUMBER" --json headRefName -q '.headRefName')

echo "  PR #$PR_NUMBER: $PR_TITLE"
echo "  Author: $PR_AUTHOR"
echo "  Branch: $PR_BRANCH"

# Inject PR context into metadata if metadata file exists
if [ -f "$METADATA_FILE" ]; then
  TEMP_META=$(mktemp)
  jq --arg branch "$PR_BRANCH" --arg pr "$PR_NUMBER" --arg ci "$CI_RUN_URL" \
    '.ci_failure.context.pr_branch = $branch |
     .ci_failure.context.pr_number = ($pr | tonumber? // 0) |
     .ci_failure.context.ci_run = $ci' "$METADATA_FILE" > "$TEMP_META"
  mv "$TEMP_META" "$METADATA_FILE"
fi

# Read config (with defaults)
ASSIGN_TO_AUTHOR="${ASSIGN_TO_PR_AUTHOR:-true}"
PRIORITY="${FIX_BEAD_PRIORITY:-1}"
BLOCK_PARENT="${BLOCK_PARENT:-true}"

# --- REGRESSION DETECTION ---
# Check if a closed fix bead already exists for this failure type + PR
echo "Checking for existing fix beads..."
EXISTING_CLOSED=$(bd list --label "ci-failure" --label "$FAILURE_TYPE" --status closed --json $BD_FLAGS 2>/dev/null | \
  jq -r --arg pr "$PR_NUMBER" '.[] | select(
    (.metadata.ci_failure.context.pr_number // 0 | tostring) == $pr
  ) | .id' 2>/dev/null | head -1 || echo "")

EXISTING_OPEN=$(bd list --label "ci-failure" --label "$FAILURE_TYPE" --status open --json $BD_FLAGS 2>/dev/null | \
  jq -r --arg pr "$PR_NUMBER" '.[] | select(
    (.metadata.ci_failure.context.pr_number // 0 | tostring) == $pr
  ) | .id' 2>/dev/null | head -1 || echo "")

if [ -n "$EXISTING_OPEN" ]; then
  # Fix bead still open for this type + PR - update it with latest info
  echo "Updating existing open fix bead: $EXISTING_OPEN"
  if [ -f "$METADATA_FILE" ]; then
    bd update "$EXISTING_OPEN" --metadata "@$METADATA_FILE" $BD_FLAGS
  fi
  bd update "$EXISTING_OPEN" --append-notes "--- CI re-run $(date -u +%Y-%m-%dT%H:%M:%SZ): still failing ---" $BD_FLAGS
  CHILD_BEAD_ID="$EXISTING_OPEN"

elif [ -n "$EXISTING_CLOSED" ]; then
  # Regression: reopen the closed fix bead
  echo "Regression detected! Reopening: $EXISTING_CLOSED"
  bd reopen "$EXISTING_CLOSED" --reason "Regression: $FAILURE_TYPE failed again on PR #$PR_NUMBER" $BD_FLAGS
  if [ -f "$METADATA_FILE" ]; then
    bd update "$EXISTING_CLOSED" --metadata "@$METADATA_FILE" $BD_FLAGS
  fi
  bd update "$EXISTING_CLOSED" --append-notes "--- Regression $(date -u +%Y-%m-%dT%H:%M:%SZ): $FAILURE_TYPE failed again ---" $BD_FLAGS
  CHILD_BEAD_ID="$EXISTING_CLOSED"

  # Re-establish blocking dependency (may have been removed on close)
  if [ "$BLOCK_PARENT" = "true" ]; then
    bd dep add "$PARENT_BEAD_ID" "$CHILD_BEAD_ID" $BD_FLAGS 2>/dev/null || true
    bd update "$PARENT_BEAD_ID" --status blocked $BD_FLAGS 2>/dev/null || true
  fi

else
  # No existing fix bead - create new one
  echo "Creating new fix bead..."

  # Build description from metadata
  SUMMARY="${FAILURE_SUMMARY:-CI failure}"
  if [ -f "$METADATA_FILE" ]; then
    SUMMARY=$(jq -r '.ci_failure.summary // "CI failure"' "$METADATA_FILE")
  fi

  DESCRIPTION="## Fix CI: $FAILURE_TYPE in $PARENT_BEAD_ID

**PR**: #$PR_NUMBER - $PR_TITLE
**Branch**: \`$PR_BRANCH\`
**Failure**: $SUMMARY
**CI Run**: $CI_RUN_URL

### Resolution
1. \`bd update <this-bead> --claim\`
2. \`git fetch && git checkout $PR_BRANCH\`
3. Fix the failures (see metadata for details)
4. \`make lint && make test && make test-coverage && make build\`
5. \`git push origin $PR_BRANCH\`
6. CI will auto-close this bead when the gate passes"

  # Build create args
  CREATE_ARGS=(
    "Fix CI: $FAILURE_TYPE in $PARENT_BEAD_ID"
    --type task
    --priority "$PRIORITY"
    --description "$DESCRIPTION"
    --labels "ci-failure,auto-remediation,$FAILURE_TYPE"
    --external-ref "gh-pr-$PR_NUMBER"
    --silent
  )

  # Add blocking dependency
  if [ "$BLOCK_PARENT" = "true" ]; then
    CREATE_ARGS+=(--deps "blocks:$PARENT_BEAD_ID")
  fi

  # Conditionally add assignee
  if [ "$ASSIGN_TO_AUTHOR" = "true" ]; then
    CREATE_ARGS+=(--assignee "$PR_AUTHOR")
  fi

  CHILD_BEAD_ID=$(bd create "${CREATE_ARGS[@]}" $BD_FLAGS)

  if [ -z "$CHILD_BEAD_ID" ]; then
    echo "::error::Failed to create fix bead"
    exit 1
  fi

  echo "✅ Created fix bead: $CHILD_BEAD_ID"

  # Attach structured metadata
  if [ -f "$METADATA_FILE" ]; then
    bd update "$CHILD_BEAD_ID" --metadata "@$METADATA_FILE" $BD_FLAGS
    echo "✅ Attached metadata to $CHILD_BEAD_ID"
  fi

  # Mark parent as blocked
  if [ "$BLOCK_PARENT" = "true" ]; then
    bd update "$PARENT_BEAD_ID" --status blocked $BD_FLAGS 2>/dev/null || true
    echo "✅ Marked parent $PARENT_BEAD_ID as blocked"
  fi
fi

echo "bead-id=$CHILD_BEAD_ID" >> "$GITHUB_OUTPUT"
echo "skipped=false" >> "$GITHUB_OUTPUT"
echo "::endgroup::"
