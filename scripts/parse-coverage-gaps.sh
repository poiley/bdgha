#!/bin/bash
set -euo pipefail

echo "::group::Parsing coverage gaps"

DETAILS_FILE="${FAILURE_DETAILS_FILE:-coverage.out}"
PR_NUMBER="${PR_NUMBER:-}"
PR_BRANCH="${PR_BRANCH:-}"
CI_RUN_URL="${CI_RUN_URL:-}"
METADATA_FILE="/tmp/ci-metadata.json"

if [ ! -f "$DETAILS_FILE" ]; then
  echo "::warning::Coverage file not found: $DETAILS_FILE"
  jq -n --arg summary "${FAILURE_SUMMARY:-Coverage below threshold}" \
    --arg pr "$PR_NUMBER" --arg branch "$PR_BRANCH" --arg ci "$CI_RUN_URL" '{
    ci_failure: {
      type: "coverage_gap",
      summary: $summary,
      uncovered_functions: [],
      files: [],
      commands: { reproduce: "go test -coverprofile=coverage.out ./... && go tool cover -func=coverage.out", verify: "make test-coverage" },
      targets: { coverage: "100%" },
      context: { pr_number: ($pr | tonumber? // 0), pr_branch: $branch, ci_run: $ci, artifacts: [] }
    }
  }' > "$METADATA_FILE"
  echo "metadata-file=$METADATA_FILE" >> "$GITHUB_OUTPUT"
  echo "summary=Coverage below threshold" >> "$GITHUB_OUTPUT"
  echo "::endgroup::"
  exit 0
fi

# Parse coverage report for uncovered functions
UNCOVERED_RAW=$(go tool cover -func="$DETAILS_FILE" 2>/dev/null | grep -v "100.0%" | grep -v "^total:" | head -50 || echo "")

if [ -z "$UNCOVERED_RAW" ]; then
  echo "::warning::Could not parse coverage gaps from $DETAILS_FILE"
  jq -n --arg summary "${FAILURE_SUMMARY:-Coverage gaps detected}" \
    --arg pr "$PR_NUMBER" --arg branch "$PR_BRANCH" --arg ci "$CI_RUN_URL" '{
    ci_failure: {
      type: "coverage_gap",
      summary: $summary,
      uncovered_functions: [],
      files: [],
      commands: { reproduce: "go test -coverprofile=coverage.out ./... && go tool cover -func=coverage.out", verify: "make test-coverage" },
      targets: { coverage: "100%" },
      context: { pr_number: ($pr | tonumber? // 0), pr_branch: $branch, ci_run: $ci, artifacts: [] }
    }
  }' > "$METADATA_FILE"
  echo "metadata-file=$METADATA_FILE" >> "$GITHUB_OUTPUT"
  echo "summary=Coverage gaps detected" >> "$GITHUB_OUTPUT"
  echo "::endgroup::"
  exit 0
fi

# Build structured JSON from coverage output
# Format: "file:line:\tfunction_name\t\tcoverage%"
UNCOVERED_JSON=$(echo "$UNCOVERED_RAW" | awk '{print $1 "\t" $2 "\t" $3}' | \
  jq -R -s 'split("\n") | map(select(length > 0)) | map(
    split("\t") | {
      file: .[0],
      function: .[1],
      coverage: .[2]
    }
  )' 2>/dev/null || echo '[]')

UNCOVERED_COUNT=$(echo "$UNCOVERED_JSON" | jq 'length')
FILES_JSON=$(echo "$UNCOVERED_JSON" | jq '[.[].file | split(":")[0]] | unique')

# Build reproduce command
REPRODUCE_PKGS=$(echo "$FILES_JSON" | jq -r 'map(split("/") | .[0:-1] | join("/")) | unique | map("./" + .) | join(" ")' 2>/dev/null || echo "./...")
SUMMARY="$UNCOVERED_COUNT functions below 100% coverage"

jq -n \
  --arg summary "$SUMMARY" \
  --argjson uncovered "$UNCOVERED_JSON" \
  --argjson files "$FILES_JSON" \
  --arg reproduce "go test -coverprofile=coverage.out $REPRODUCE_PKGS && go tool cover -func=coverage.out | grep -v 100.0%" \
  --arg pr "$PR_NUMBER" --arg branch "$PR_BRANCH" --arg ci "$CI_RUN_URL" \
  '{
    ci_failure: {
      type: "coverage_gap",
      summary: $summary,
      uncovered_functions: $uncovered,
      files: $files,
      commands: {
        reproduce: $reproduce,
        verify: "make lint && make test && make test-coverage && make build"
      },
      targets: { coverage: "100%" },
      context: {
        pr_number: ($pr | tonumber? // 0),
        pr_branch: $branch,
        ci_run: $ci,
        artifacts: ["coverage.out", "coverage-summary.txt"]
      }
    }
  }' > "$METADATA_FILE"

echo "metadata-file=$METADATA_FILE" >> "$GITHUB_OUTPUT"
echo "summary=$SUMMARY" >> "$GITHUB_OUTPUT"
echo "✅ Parsed $UNCOVERED_COUNT coverage gaps"
echo "::endgroup::"
