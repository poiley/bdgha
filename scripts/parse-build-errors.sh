#!/bin/bash
set -euo pipefail

echo "::group::Parsing build errors"

DETAILS_FILE="${FAILURE_DETAILS_FILE:-build-errors.txt}"

if [ ! -f "$DETAILS_FILE" ]; then
  echo "::warning::Build errors file not found: $DETAILS_FILE"
  echo "summary=${FAILURE_SUMMARY:-Build failed}" >> "$GITHUB_OUTPUT"
  echo "details=" >> "$GITHUB_OUTPUT"
  echo "::endgroup::"
  exit 0
fi

# Extract compilation errors (Go format: file:line:col: message)
BUILD_ERRORS=$(grep -E "^#|^[^:]+:[0-9]+:[0-9]+:" "$DETAILS_FILE" 2>/dev/null | head -30 || echo "")

if [ -z "$BUILD_ERRORS" ]; then
  echo "::warning::Could not parse build errors from $DETAILS_FILE"
  echo "summary=${FAILURE_SUMMARY:-Compilation errors}" >> "$GITHUB_OUTPUT"
  echo "details=" >> "$GITHUB_OUTPUT"
  echo "::endgroup::"
  exit 0
fi

# Count errors
ERROR_COUNT=$(echo "$BUILD_ERRORS" | grep -c ":" | tr -d ' ')

# Create summary
SUMMARY="Build failed with $ERROR_COUNT errors (showing first 30 lines):"$'\n'"$BUILD_ERRORS"

echo "summary<<EOF" >> "$GITHUB_OUTPUT"
echo "$SUMMARY" >> "$GITHUB_OUTPUT"
echo "EOF" >> "$GITHUB_OUTPUT"

echo "details<<EOF" >> "$GITHUB_OUTPUT"
echo "$BUILD_ERRORS" >> "$GITHUB_OUTPUT"
echo "EOF" >> "$GITHUB_OUTPUT"

echo "✅ Parsed build errors"
echo "::endgroup::"
