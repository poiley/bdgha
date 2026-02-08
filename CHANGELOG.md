# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-02-08

### Added
- Initial release of BD CI Auto-Remediation GitHub Action
- Auto-detection of parent bead from PR title, branch, or commits
- Support for 4 failure types: test_failure, coverage_gap, lint_error, build_error
- Create mode: Creates child fix bead with structured description
- Cleanup mode: Auto-closes fix beads when PR CI passes
- Automatic sync to beads-sync branch
- Configurable behavior via .beads/config.yaml
- Comprehensive documentation and examples
- Support for bd CLI installation from GitHub releases

### Features
- Marks parent bead as blocked (configurable)
- Assigns fix beads to PR author (configurable)
- Creates dependency between parent and child beads
- Structured fix bead description with resolution checklist
- Graceful handling of missing parent beads
- Automatic conflict resolution for sync branch

[1.0.0]: https://github.com/poiley/bdgha/releases/tag/v1.0.0
