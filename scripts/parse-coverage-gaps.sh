#!/bin/bash
set -euo pipefail

echo "::group::Parsing coverage gaps"

DETAILS_FILE="${FAILURE_DETAILS_FILE:-coverage.out}"

if [ ! -f "$DETAILS_FILE" ]; then
  echo "::warning::Coverage file not found: $DETAILS_FILE"
  echo "summary=${FAILURE_SUMMARY:-Coverage below threshold}" >> "$GITHUB_OUTPUT"
  echo "details=" >> "$GITHUB_OUTPUT"
  echo "::endgroup::"
  exit 0
fi

# Parse coverage report for uncovered functions (< 100%)
UNCOVERED=$(go tool cover -func="$DETAILS_FILE" 2>/dev/null | grep -v "100.0%" | grep -v "^total:" | head -20 || echo "")

if [ -z "$UNCOVERED" ]; then
  echo "::warning::Could not parse coverage gaps from $DETAILS_FILE"
  echo "summary=${FAILURE_SUMMARY:-Coverage below 100%}" >> "$GITHUB_OUTPUT"
  echo "details=" >> "$GITHUB_OUTPUT"
  echo "::endgroup::"
  exit 0
fi

# Count uncovered functions
UNCOVERED_COUNT=$(echo "$UNCOVERED" | wc -l | tr -d ' ')

# Create summary
SUMMARY="$UNCOVERED_COUNT functions below 100% coverage (showing first 20):"$'\n'"$UNCOVERED"

echo "summary<<EOF" >> "$GITHUB_OUTPUT"
echo "$SUMMARY" >> "$GITHUB_OUTPUT"
echo "EOF" >> "$GITHUB_OUTPUT"

echo "details<<EOF" >> "$GITHUB_OUTPUT"
echo "$UNCOVERED" >> "$GITHUB_OUTPUT"
echo "EOF" >> "$GITHUB_OUTPUT"

echo "✅ Parsed $UNCOVERED_COUNT coverage gaps"
echo "::endgroup::"
