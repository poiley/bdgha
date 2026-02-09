#!/bin/bash
set -euo pipefail

echo "::group::Parsing lint errors"

DETAILS_FILE="${FAILURE_DETAILS_FILE:-lint-results.txt}"
PR_NUMBER="${PR_NUMBER:-}"
PR_BRANCH="${PR_BRANCH:-}"
CI_RUN_URL="${CI_RUN_URL:-}"
METADATA_FILE="/tmp/ci-metadata.json"

if [ ! -f "$DETAILS_FILE" ]; then
  echo "::warning::Lint results file not found: $DETAILS_FILE"
  jq -n --arg summary "${FAILURE_SUMMARY:-Lint errors detected}" \
    --arg pr "$PR_NUMBER" --arg branch "$PR_BRANCH" --arg ci "$CI_RUN_URL" '{
    ci_failure: {
      type: "lint_error",
      summary: $summary,
      violations: [],
      files: [],
      commands: { reproduce: "golangci-lint run ./...", verify: "make lint" },
      targets: { violations: 0 },
      context: { pr_number: ($pr | tonumber? // 0), pr_branch: $branch, ci_run: $ci, artifacts: [] }
    }
  }' > "$METADATA_FILE"
  echo "metadata-file=$METADATA_FILE" >> "$GITHUB_OUTPUT"
  echo "summary=Lint errors detected" >> "$GITHUB_OUTPUT"
  echo "::endgroup::"
  exit 0
fi

# Extract lint errors (format: file:line:col: rule: message)
# golangci-lint line-number format: file.go:42:5: errcheck: Error return value...
VIOLATIONS_JSON=$(grep -E "^[^:]+:[0-9]+" "$DETAILS_FILE" 2>/dev/null | head -50 | \
  jq -R -s 'split("\n") | map(select(length > 0)) | map(
    capture("^(?<file>[^:]+):(?<line>[0-9]+):(?<col>[0-9]+):\\s*(?<rest>.*)$") // null |
    select(. != null) |
    (.rest | split(": ") | if length > 1 then {rule: .[0], message: (.[1:] | join(": "))} else {rule: "unknown", message: .[0]} end) as $parsed |
    {
      file: .file,
      line: (.line | tonumber),
      col: (.col | tonumber),
      rule: $parsed.rule,
      message: $parsed.message
    }
  )' 2>/dev/null || echo '[]')

VIOLATION_COUNT=$(echo "$VIOLATIONS_JSON" | jq 'length')
FILES_JSON=$(echo "$VIOLATIONS_JSON" | jq '[.[].file] | unique')

SUMMARY="$VIOLATION_COUNT lint violations"

jq -n \
  --arg summary "$SUMMARY" \
  --argjson violations "$VIOLATIONS_JSON" \
  --argjson files "$FILES_JSON" \
  --arg pr "$PR_NUMBER" --arg branch "$PR_BRANCH" --arg ci "$CI_RUN_URL" \
  '{
    ci_failure: {
      type: "lint_error",
      summary: $summary,
      violations: $violations,
      files: $files,
      commands: {
        reproduce: "golangci-lint run ./...",
        verify: "make lint && make test && make test-coverage && make build"
      },
      targets: { violations: 0 },
      context: {
        pr_number: ($pr | tonumber? // 0),
        pr_branch: $branch,
        ci_run: $ci,
        artifacts: ["lint-results.txt"]
      }
    }
  }' > "$METADATA_FILE"

echo "metadata-file=$METADATA_FILE" >> "$GITHUB_OUTPUT"
echo "summary=$SUMMARY" >> "$GITHUB_OUTPUT"
echo "✅ Parsed $VIOLATION_COUNT lint violations"
echo "::endgroup::"
