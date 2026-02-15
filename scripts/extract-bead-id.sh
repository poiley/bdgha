#!/bin/bash
set -euo pipefail

echo "::group::Extracting parent bead ID"

# If explicitly provided, use it
if [ -n "${PARENT_BEAD_ID:-}" ]; then
  echo "Using provided parent bead ID: $PARENT_BEAD_ID"
  echo "bead-id=$PARENT_BEAD_ID" >> "$GITHUB_OUTPUT"
  echo "skipped=false" >> "$GITHUB_OUTPUT"
  echo "::endgroup::"
  exit 0
fi

# Auto-detect bead prefix from config
BEAD_PREFIX=$(bd config get issue_prefix 2>/dev/null || echo "")

# Fallback: infer prefix from GitHub repository name (e.g., "actual-software/kubrick" -> "kubrick")
if [ -z "$BEAD_PREFIX" ] && [ -n "${GITHUB_REPOSITORY:-}" ]; then
  BEAD_PREFIX=$(echo "$GITHUB_REPOSITORY" | cut -d'/' -f2)
  echo "::notice::No issue_prefix in bd config, inferred prefix from repo name: $BEAD_PREFIX"
fi

if [ -z "$BEAD_PREFIX" ]; then
  echo "::warning::No issue_prefix found in bd config and could not infer from repo name, skipping remediation"
  echo "bead-id=" >> "$GITHUB_OUTPUT"
  echo "skipped=true" >> "$GITHUB_OUTPUT"
  echo "::endgroup::"
  exit 0
fi

echo "Detected bead prefix: $BEAD_PREFIX"

# Strategy 1: PR title (most reliable)
echo "Trying strategy 1: PR title"
BEAD_ID=$(gh pr view "$PR_NUMBER" --json title -q '.title' | grep -oP "${BEAD_PREFIX}-[a-z0-9]+" | head -1 || true)

# Strategy 2: Branch name
if [ -z "$BEAD_ID" ]; then
  echo "Trying strategy 2: Branch name"
  BEAD_ID=$(gh pr view "$PR_NUMBER" --json headRefName -q '.headRefName' | grep -oP "${BEAD_PREFIX}-[a-z0-9]+" | head -1 || true)
fi

# Strategy 3: Recent commits (last 10)
if [ -z "$BEAD_ID" ]; then
  echo "Trying strategy 3: Recent commits"
  BEAD_ID=$(gh pr view "$PR_NUMBER" --json commits -q '.commits[].messageHeadline' | grep -oP "${BEAD_PREFIX}-[a-z0-9]+" | head -1 || true)
fi

if [ -z "$BEAD_ID" ]; then
  if [ "${SKIP_IF_NO_PARENT:-true}" = "true" ]; then
    echo "::warning::No parent bead ID found, skipping remediation"
    echo "bead-id=" >> "$GITHUB_OUTPUT"
    echo "skipped=true" >> "$GITHUB_OUTPUT"
    echo "::endgroup::"
    exit 0
  else
    echo "::error::No parent bead ID found and skip_if_no_parent=false"
    exit 1
  fi
fi

# Validate bead exists
echo "Validating bead exists: $BEAD_ID"
if ! bd show "$BEAD_ID" --json &>/dev/null; then
  echo "::error::Parent bead $BEAD_ID not found in database"
  exit 1
fi

echo "✅ Found parent bead: $BEAD_ID"
echo "bead-id=$BEAD_ID" >> "$GITHUB_OUTPUT"
echo "skipped=false" >> "$GITHUB_OUTPUT"
echo "::endgroup::"
