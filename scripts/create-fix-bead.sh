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

# Get PR details
echo "Fetching PR details..."
PR_TITLE=$(gh pr view "$PR_NUMBER" --json title -q '.title')
PR_AUTHOR=$(gh pr view "$PR_NUMBER" --json author -q '.author.login')
PR_BRANCH=$(gh pr view "$PR_NUMBER" --json headRefName -q '.headRefName')

echo "  PR #$PR_NUMBER: $PR_TITLE"
echo "  Author: $PR_AUTHOR"
echo "  Branch: $PR_BRANCH"

# Read config (with defaults)
ASSIGN_TO_AUTHOR="${ASSIGN_TO_PR_AUTHOR:-true}"
PRIORITY="${FIX_BEAD_PRIORITY:-1}"
BLOCK_PARENT="${BLOCK_PARENT:-true}"

# Generate description from template
DESCRIPTION=$(cat <<EOF
## 🔧 CI Auto-Remediation

**Parent Bead**: $PARENT_BEAD_ID  
**PR**: #$PR_NUMBER - $PR_TITLE  
**Failure Type**: $FAILURE_TYPE  
**Created**: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

---

## 📊 Summary

$FAILURE_SUMMARY

## 🔍 Details

$FAILURE_DETAILS

## 🔗 Resources

- **CI Run**: [View Full Logs]($CI_RUN_URL)
- **Artifacts**: [Download from Actions]($CI_RUN_URL)
- **PR Branch**: \`$PR_BRANCH\`

---

## ✅ Resolution Checklist

1. **Claim this bead**: \`bd update <bead-id> --claim\`
2. **Checkout PR branch**: \`git fetch && git checkout $PR_BRANCH\`
3. **Review failures**: Check artifacts and logs linked above
4. **Fix the issue**: Address the specific failures listed
5. **Verify locally**: Run all quality gates
   \`\`\`bash
   make lint && make test && make test-coverage && make build
   \`\`\`
6. **Push to PR branch**: 
   \`\`\`bash
   git add .
   git commit -m "$PARENT_BEAD_ID: Fix $FAILURE_TYPE"
   git push origin $PR_BRANCH
   \`\`\`
7. **Monitor CI**: Wait for all checks to pass
8. **Auto-close**: This bead will auto-close when parent PR CI passes

---

## 📝 Context

This bead was automatically created by \`poiley/bdgha\` when PR #$PR_NUMBER failed CI.

**CI Run**: $CI_RUN_URL  
**Actor**: @$PR_AUTHOR  
**Triggered**: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
EOF
)

# Build create command arguments
CREATE_ARGS=(
  "Fix CI: $FAILURE_TYPE in $PARENT_BEAD_ID"
  --parent "$PARENT_BEAD_ID"
  --type task
  --priority "$PRIORITY"
  --description "$DESCRIPTION"
  --labels "ci-failure,auto-remediation,$FAILURE_TYPE"
  --external-ref "gh-pr-$PR_NUMBER"
  --silent
)

# Conditionally add assignee
if [ "$ASSIGN_TO_AUTHOR" = "true" ]; then
  CREATE_ARGS+=(--assignee "$PR_AUTHOR")
fi

# Create child bead
echo "Creating child bead..."
CHILD_BEAD_ID=$(bd create "${CREATE_ARGS[@]}")

if [ -z "$CHILD_BEAD_ID" ]; then
  echo "::error::Failed to create fix bead"
  exit 1
fi

echo "✅ Created fix bead: $CHILD_BEAD_ID"

# Update parent status to blocked (if configured)
if [ "$BLOCK_PARENT" = "true" ]; then
  echo "Marking parent as blocked..."
  bd update "$PARENT_BEAD_ID" --status blocked
  echo "✅ Marked parent $PARENT_BEAD_ID as blocked"
fi

# Create dependency (parent depends on child)
echo "Creating dependency..."
bd dep add "$PARENT_BEAD_ID" "$CHILD_BEAD_ID"
echo "✅ Created dependency: $PARENT_BEAD_ID depends on $CHILD_BEAD_ID"

echo "bead-id=$CHILD_BEAD_ID" >> "$GITHUB_OUTPUT"
echo "skipped=false" >> "$GITHUB_OUTPUT"
echo "::endgroup::"
