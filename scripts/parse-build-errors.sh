#!/bin/bash
set -euo pipefail

echo "::group::Parsing build errors"

DETAILS_FILE="${FAILURE_DETAILS_FILE:-build-errors.txt}"
PR_NUMBER="${PR_NUMBER:-}"
PR_BRANCH="${PR_BRANCH:-}"
CI_RUN_URL="${CI_RUN_URL:-}"
METADATA_FILE="/tmp/ci-metadata.json"

if [ ! -f "$DETAILS_FILE" ]; then
  echo "::warning::Build errors file not found: $DETAILS_FILE"
  jq -n --arg summary "${FAILURE_SUMMARY:-Build failed}" \
    --arg pr "$PR_NUMBER" --arg branch "$PR_BRANCH" --arg ci "$CI_RUN_URL" '{
    ci_failure: {
      type: "build_error",
      summary: $summary,
      errors: [],
      files: [],
      commands: { reproduce: "go build ./...", verify: "make build" },
      targets: { build_success: true },
      context: { pr_number: ($pr | tonumber? // 0), pr_branch: $branch, ci_run: $ci, artifacts: [] }
    }
  }' > "$METADATA_FILE"
  echo "metadata-file=$METADATA_FILE" >> "$GITHUB_OUTPUT"
  echo "summary=Build failed" >> "$GITHUB_OUTPUT"
  echo "::endgroup::"
  exit 0
fi

# Extract Go compilation errors (format: file.go:line:col: message)
ERRORS_JSON=$(grep -E "^[^#][^:]*\.go:[0-9]+" "$DETAILS_FILE" 2>/dev/null | head -30 | \
  jq -R -s 'split("\n") | map(select(length > 0)) | map(
    capture("^(?<file>[^:]+):(?<line>[0-9]+):((?<col>[0-9]+):)?\\s*(?<message>.*)$") // null |
    select(. != null) |
    {
      file: .file,
      line: (.line | tonumber),
      message: .message
    }
  )' 2>/dev/null || echo '[]')

ERROR_COUNT=$(echo "$ERRORS_JSON" | jq 'length')
FILES_JSON=$(echo "$ERRORS_JSON" | jq '[.[].file] | unique')

SUMMARY="Build failed with $ERROR_COUNT errors"

jq -n \
  --arg summary "$SUMMARY" \
  --argjson errors "$ERRORS_JSON" \
  --argjson files "$FILES_JSON" \
  --arg pr "$PR_NUMBER" --arg branch "$PR_BRANCH" --arg ci "$CI_RUN_URL" \
  '{
    ci_failure: {
      type: "build_error",
      summary: $summary,
      errors: $errors,
      files: $files,
      commands: {
        reproduce: "go build ./...",
        verify: "make lint && make test && make test-coverage && make build"
      },
      targets: { build_success: true },
      context: {
        pr_number: ($pr | tonumber? // 0),
        pr_branch: $branch,
        ci_run: $ci,
        artifacts: ["build-output.txt"]
      }
    }
  }' > "$METADATA_FILE"

echo "metadata-file=$METADATA_FILE" >> "$GITHUB_OUTPUT"
echo "summary=$SUMMARY" >> "$GITHUB_OUTPUT"
echo "✅ Parsed $ERROR_COUNT build errors"
echo "::endgroup::"
