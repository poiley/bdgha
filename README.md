# BD CI Auto-Remediation GitHub Action

Automatically create and manage fix beads when CI fails in repositories using [bd (beads)](https://github.com/steveyegge/beads) issue tracking.

## Features

- 🔍 **Auto-detects parent bead** from PR title, branch name, or commits
- 📝 **Creates child fix bead** with structured failure details
- 🔗 **Links parent and child** with dependency relationship
- 🚫 **Marks parent as blocked** (configurable)
- ✅ **Auto-closes fix beads** when PR CI passes
- 🔄 **Syncs to git** for distributed team/agent access
- 🎯 **Supports 4 failure types**: test, coverage, lint, build

## Quick Start

### 1. Setup bd in Your Repository

```bash
cd your-repo
bd init
git checkout -b beads-sync
bd sync
git add .beads/issues.jsonl
git commit -m "chore: initialize beads"
git push -u origin beads-sync
git checkout main
```

### 2. Configure CI Auto-Remediation

Add to `.beads/config.yaml`:

```yaml
ci:
  auto-remediation:
    enabled: true
    assign-to-pr-author: true
    fix-bead-priority: 1
    block-parent: true

sync-branch: beads-sync
```

### 3. Add to Your Workflow

```yaml
name: Test

on:
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      # ... your test steps ...

  create-fix-bead:
    if: failure()
    needs: test
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: read
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      
      - uses: poiley/bdgha@v1
        with:
          mode: create
          failure-type: test_failure
          failure-summary: "Tests failed"
          github-token: ${{ secrets.GITHUB_TOKEN }}

  cleanup-fix-beads:
    if: success()
    needs: test
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: read
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      
      - uses: poiley/bdgha@v1
        with:
          mode: cleanup
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

## Inputs

### Required Inputs

| Input | Description |
|-------|-------------|
| `github-token` | GitHub token for API access (use `${{ secrets.GITHUB_TOKEN }}`) |

### Mode-Specific Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `mode` | Action mode: `create` or `cleanup` | No | `create` |
| `failure-type` | Type of failure (see below) | Yes (for create) | - |
| `failure-summary` | Brief summary of failures | Yes (for create) | - |
| `failure-details-file` | Path to detailed failure output | No | - |

**Failure Types**:
- `test_failure` - Test failures
- `coverage_gap` - Coverage below threshold
- `lint_error` - Lint violations
- `build_error` - Compilation errors

### Optional Configuration

| Input | Description | Default |
|-------|-------------|---------|
| `parent-bead-id` | Parent bead ID (auto-detected if not provided) | Auto-detect |
| `pr-number` | Pull request number | Auto-detect |
| `assign-to-pr-author` | Assign fix bead to PR author | `true` |
| `fix-bead-priority` | Priority for fix bead (0-4) | `1` |
| `block-parent` | Mark parent bead as blocked | `true` |
| `skip-if-no-parent` | Skip gracefully if no parent found | `true` |
| `sync-branch` | Git branch for beads sync | `beads-sync` |
| `bd-version` | BD CLI version | `latest` |

## Outputs

| Output | Description |
|--------|-------------|
| `fix-bead-id` | ID of created fix bead (mode=create only) |
| `parent-bead-id` | ID of the parent bead |
| `skipped` | `true` if remediation was skipped |

## How It Works

### Create Mode

1. **Detect Parent Bead**: Searches PR title, branch name, and commits for bead ID pattern
2. **Parse Failures**: Extracts specific failure details from CI output
3. **Create Fix Bead**: Creates child bead with structured description
4. **Update Parent**: Marks parent as blocked and creates dependency
5. **Sync to Git**: Commits changes to `beads-sync` branch

### Cleanup Mode

1. **Detect Parent Bead**: Same as create mode
2. **Find Fix Beads**: Queries child beads with `ci-failure` label
3. **Close Beads**: Closes all open fix beads when CI passes
4. **Sync to Git**: Commits changes to `beads-sync` branch

### Fix Bead Structure

Each fix bead contains:
- **Summary**: Brief overview of failures
- **Details**: Specific test names, coverage gaps, etc.
- **Resources**: Links to CI logs, artifacts, and PR branch
- **Resolution Checklist**: Step-by-step guide for fixing
- **Context**: PR info, actor, timestamps

## Examples

See [examples/](./examples/) directory for complete workflow examples:
- [test-failure.yml](./examples/test-failure.yml) - Test failures
- [coverage-gap.yml](./examples/coverage-gap.yml) - Coverage enforcement
- [lint-error.yml](./examples/lint-error.yml) - Lint violations
- [build-error.yml](./examples/build-error.yml) - Build failures
- [complete.yml](./examples/complete.yml) - All gates integrated

## Agent Workflow

When a fix bead is created:

1. **Discovery**: Your `bd daemon` auto-pulls from `beads-sync` branch
2. **Finding Work**: Run `bd ready` or filter by `ci-failure` label
3. **Claiming**: `bd update <fix-bead-id> --claim`
4. **Fixing**: Follow the resolution checklist in the bead description
5. **Pushing**: Push fixes to the same PR branch
6. **Auto-close**: Bead closes automatically when CI passes

## Troubleshooting

### No Parent Bead Found

**Symptom**: Action logs "No parent bead ID found, skipping remediation"

**Solutions**:
- Ensure PR title, branch name, or commits contain bead ID (e.g., `kubrick-abc`)
- Set `parent-bead-id` input explicitly
- Check bead prefix in `.beads/config.yaml`

### BD CLI Installation Failed

**Symptom**: "Could not find bd release for linux_amd64"

**Solutions**:
- Check [beads releases](https://github.com/steveyegge/beads/releases) for available platforms
- Specify `bd-version` input with known working version

### Sync Branch Conflicts

**Symptom**: "git merge failed" or "sync conflicts"

**Solutions**:
- Action automatically uses `--theirs` strategy
- Manually resolve if conflicts persist: `bd sync --resolve --manual`

### Permission Denied

**Symptom**: "refusing to allow a GitHub App to create or update workflow"

**Solutions**:
- Ensure workflow has `contents: write` permission
- Use default `${{ secrets.GITHUB_TOKEN }}`, not PAT

## Configuration

### Repository Settings

In `.beads/config.yaml`:

```yaml
# CI Auto-Remediation Configuration
ci:
  auto-remediation:
    # Enable/disable CI auto-remediation
    enabled: true
    
    # Assign fix beads to PR author?
    assign-to-pr-author: true
    
    # Priority for auto-created fix beads (0-4, 0=highest)
    fix-bead-priority: 1
    
    # Mark parent bead as blocked when child created?
    block-parent: true

# Sync branch configuration (required for bdgha)
sync-branch: beads-sync
```

### Workflow Settings

Configure per-workflow using inputs:

```yaml
- uses: poiley/bdgha@v1
  with:
    mode: create
    failure-type: test_failure
    failure-summary: "Custom summary"
    assign-to-pr-author: false  # Override config
    fix-bead-priority: 0        # P0 (highest)
    block-parent: false         # Don't block parent
```

## Requirements

- **bd (beads)**: Issue tracking must be initialized (`bd init`)
- **GitHub Actions**: Repository with PR-based CI workflows
- **Git**: Sync branch for beads JSONL files
- **Permissions**: `contents: write` and `pull-requests: read`

## Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

MIT License - see [LICENSE](./LICENSE) for details

## Links

- [bd (beads)](https://github.com/steveyegge/beads) - Issue tracking CLI
- [GitHub Actions](https://docs.github.com/en/actions) - CI/CD platform
- [Issues](https://github.com/poiley/bdgha/issues) - Report bugs or request features

## Author

Created by [@poiley](https://github.com/poiley)
