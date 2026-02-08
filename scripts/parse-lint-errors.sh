#!/bin/bash
set -euo pipefail

echo "::group::Parsing lint errors"

DETAILS_FILE="${FAILURE_DETAILS_FILE:-lint-results.txt}"

if [ ! -f "$DETAILS_FILE" ]; then
  echo "::warning::Lint results file not found: $DETAILS_FILE"
  echo "summary=${FAILURE_SUMMARY:-Lint errors detected}" >> "$GITHUB_OUTPUT"
  echo "details=" >> "$GITHUB_OUTPUT"
  echo "::endgroup::"
  exit 0
fi

# Extract lint errors (format: file:line:col: message)
LINT_ERRORS=$(grep -E "^[^:]+:[0-9]+:[0-9]+:" "$DETAILS_FILE" 2>/dev/null | head -20 || echo "")

if [ -z "$LINT_ERRORS" ]; then
  echo "::warning::Could not parse lint errors from $DETAILS_FILE"
  echo "summary=${FAILURE_SUMMARY:-Lint violations found}" >> "$GITHUB_OUTPUT"
  echo "details=" >> "$GITHUB_OUTPUT"
  echo "::endgroup::"
  exit 0
fi

# Count errors
ERROR_COUNT=$(echo "$LINT_ERRORS" | wc -l | tr -d ' ')

# Create summary
SUMMARY="$ERROR_COUNT lint errors found (showing first 20):"$'\n'"$LINT_ERRORS"

echo "summary<<EOF" >> "$GITHUB_OUTPUT"
echo "$SUMMARY" >> "$GITHUB_OUTPUT"
echo "EOF" >> "$GITHUB_OUTPUT"

echo "details<<EOF" >> "$GITHUB_OUTPUT"
echo "$LINT_ERRORS" >> "$GITHUB_OUTPUT"
echo "EOF" >> "$GITHUB_OUTPUT"

echo "✅ Parsed $ERROR_COUNT lint errors"
echo "::endgroup::"
