#!/bin/bash
set -euo pipefail

echo "::group::Parsing test failures"

DETAILS_FILE="${FAILURE_DETAILS_FILE:-test-results.json}"
PR_NUMBER="${PR_NUMBER:-}"
PR_BRANCH="${PR_BRANCH:-}"
CI_RUN_URL="${CI_RUN_URL:-}"
METADATA_FILE="/tmp/ci-metadata.json"

if [ ! -f "$DETAILS_FILE" ]; then
  echo "::warning::Test results file not found: $DETAILS_FILE"
  # Write minimal metadata
  jq -n --arg summary "${FAILURE_SUMMARY:-Test failures - details unavailable}" \
    --arg pr "$PR_NUMBER" --arg branch "$PR_BRANCH" --arg ci "$CI_RUN_URL" '{
    ci_failure: {
      type: "test_failure",
      summary: $summary,
      failed_tests: [],
      files: [],
      commands: { reproduce: "go test -v -race ./...", verify: "make test" },
      targets: { failures: 0 },
      context: { pr_number: ($pr | tonumber? // 0), pr_branch: $branch, ci_run: $ci, artifacts: [] }
    }
  }' > "$METADATA_FILE"
  echo "metadata-file=$METADATA_FILE" >> "$GITHUB_OUTPUT"
  echo "summary=Test failures - details unavailable" >> "$GITHUB_OUTPUT"
  echo "::endgroup::"
  exit 0
fi

# Extract failed tests as JSON array
FAILED_TESTS_JSON=$(grep '"Action":"fail"' "$DETAILS_FILE" 2>/dev/null | \
  jq -s '[.[] | select(.Test != null) | {package: .Package, test: .Test, elapsed: (.Elapsed // 0 | tostring)}] | unique_by(.package + .test) | .[0:50]' 2>/dev/null || echo '[]')

FAILED_COUNT=$(echo "$FAILED_TESTS_JSON" | jq 'length')

# Extract unique files from packages (convert Go package to relative path)
FILES_JSON=$(echo "$FAILED_TESTS_JSON" | jq '[.[].package] | unique | map(
  gsub("github.com/[^/]+/[^/]+/"; "")
)' 2>/dev/null || echo '[]')

# Build reproduce command from failed test names
REPRODUCE_PKGS=$(echo "$FAILED_TESTS_JSON" | jq -r '[.[].package] | unique | join(" ")' 2>/dev/null || echo "./...")
REPRODUCE_TESTS=$(echo "$FAILED_TESTS_JSON" | jq -r '[.[].test] | unique | join("|")' 2>/dev/null || echo "")

if [ -n "$REPRODUCE_TESTS" ]; then
  REPRODUCE_CMD="go test -v -race $REPRODUCE_PKGS -run '$REPRODUCE_TESTS'"
else
  REPRODUCE_CMD="go test -v -race ./..."
fi

SUMMARY="$FAILED_COUNT tests failed"

# Build full metadata JSON
jq -n \
  --arg summary "$SUMMARY" \
  --argjson failed_tests "$FAILED_TESTS_JSON" \
  --argjson files "$FILES_JSON" \
  --arg reproduce "$REPRODUCE_CMD" \
  --arg pr "$PR_NUMBER" \
  --arg branch "$PR_BRANCH" \
  --arg ci "$CI_RUN_URL" \
  '{
    ci_failure: {
      type: "test_failure",
      summary: $summary,
      failed_tests: $failed_tests,
      files: $files,
      commands: {
        reproduce: $reproduce,
        verify: "make lint && make test && make test-coverage && make build"
      },
      targets: { failures: 0 },
      context: {
        pr_number: ($pr | tonumber? // 0),
        pr_branch: $branch,
        ci_run: $ci,
        artifacts: ["test-results.json"]
      }
    }
  }' > "$METADATA_FILE"

echo "metadata-file=$METADATA_FILE" >> "$GITHUB_OUTPUT"
echo "summary=$SUMMARY" >> "$GITHUB_OUTPUT"
echo "✅ Parsed $FAILED_COUNT test failures"
echo "::endgroup::"
