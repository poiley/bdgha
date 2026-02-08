#!/bin/bash
set -euo pipefail

echo "::group::Parsing test failures"

DETAILS_FILE="${FAILURE_DETAILS_FILE:-test-results.json}"

if [ ! -f "$DETAILS_FILE" ]; then
  echo "::warning::Test results file not found: $DETAILS_FILE"
  echo "summary=Test failures - details unavailable" >> "$GITHUB_OUTPUT"
  echo "details=" >> "$GITHUB_OUTPUT"
  echo "::endgroup::"
  exit 0
fi

# Extract failed test names (limit to 10 for summary)
FAILED_TESTS=$(grep '"Action":"fail"' "$DETAILS_FILE" 2>/dev/null | jq -r 'select(.Test != null) | "\(.Package) - \(.Test)"' | sort -u | head -10 || echo "")
FAILED_COUNT=$(grep -c '"Action":"fail"' "$DETAILS_FILE" 2>/dev/null || echo "0")

if [ "$FAILED_COUNT" -eq 0 ]; then
  echo "::warning::No failed tests found in $DETAILS_FILE"
  echo "summary=${FAILURE_SUMMARY:-Test failures detected}" >> "$GITHUB_OUTPUT"
  echo "details=" >> "$GITHUB_OUTPUT"
  echo "::endgroup::"
  exit 0
fi

# Create summary
if [ "$FAILED_COUNT" -gt 10 ]; then
  SUMMARY="$FAILED_COUNT tests failed (showing first 10):"$'\n'"$FAILED_TESTS"
else
  SUMMARY="$FAILED_COUNT tests failed:"$'\n'"$FAILED_TESTS"
fi

# Create details (full list, truncated to 50)
DETAILS=$(grep '"Action":"fail"' "$DETAILS_FILE" | jq -r 'select(.Test != null) | "\(.Package) - \(.Test)"' | sort -u | head -50)

echo "summary<<EOF" >> "$GITHUB_OUTPUT"
echo "$SUMMARY" >> "$GITHUB_OUTPUT"
echo "EOF" >> "$GITHUB_OUTPUT"

echo "details<<EOF" >> "$GITHUB_OUTPUT"
echo "$DETAILS" >> "$GITHUB_OUTPUT"
echo "EOF" >> "$GITHUB_OUTPUT"

echo "✅ Parsed $FAILED_COUNT test failures"
echo "::endgroup::"
