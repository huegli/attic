# Beads Issue Tracker Quickstart for Attic

This project uses [Beads](https://github.com/steveyegge/beads) (`bd`) for issue tracking. Beads is a distributed, git-backed graph issue tracker designed for AI agents and developers who want their issues to live alongside their code.

## Installing Beads

### macOS (Recommended)

```bash
# Install via Homebrew
brew tap steveyegge/beads
brew install bd

# Verify installation
bd version
```

### Other Installation Methods

```bash
# Linux/macOS/FreeBSD via install script
curl -fsSL https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh | bash

# npm (if you're in a Node.js environment)
npm install -g @beads/bd

# Go (if you have Go 1.24+ installed)
go install github.com/steveyegge/beads/cmd/bd@latest
```

## First-Time Setup for This Project

After installing `bd`, initialize it for this repository:

```bash
cd /path/to/attic

# Initialize beads (creates .beads/ directory, database, git hooks)
bd init

# Install git hooks for auto-sync (recommended)
bd hooks install
```

The initialization will:
- Create `.beads/` directory with SQLite database
- Set up git hooks for automatic sync
- Import any existing issues from git history

## Essential Commands

### Viewing Issues

```bash
# List all open issues
bd list

# List ready work (issues with no blockers)
bd ready

# Show details of a specific issue
bd show <issue-id>

# Show blocked issues
bd blocked

# View project statistics
bd stats
```

### Creating Issues

```bash
# Create a basic issue
bd create "Implement Phase 9: CLI Socket Protocol"

# Create with priority (P0=critical, P1=high, P2=medium, P3=low)
bd create "Fix audio crackling on startup" -p 1

# Create with type (task, bug, feature, epic)
bd create "Add joystick input support" -t feature -p 2

# Create with labels
bd create "Update documentation" -l "docs,cleanup" -p 3
```

### Working on Issues

```bash
# Start working on an issue
bd update <issue-id> --status in_progress

# Add notes to an issue
bd update <issue-id> --notes "Found root cause in AudioEngine.swift"

# Complete an issue
bd close <issue-id> --reason "Implemented and tested"
```

### Dependencies

```bash
# Make issue A depend on issue B (A blocked by B)
bd dep add <child-id> <parent-id>

# View dependency tree
bd dep tree <issue-id>

# Detect circular dependencies
bd dep cycles
```

### Syncing with Git

```bash
# Manual sync (export + commit + push)
bd sync

# Just export to JSONL without committing
bd export
```

## Workflow for AI Agents (Claude Code)

When working with Claude Code or other AI agents on this project:

### Starting a Session

```bash
# Check what's ready to work on
bd ready --json

# View current state
bd list --json
```

### During Development

```bash
# Create issues for work items discovered
bd create "Fix type error in REPL parser" -p 1

# Update status as you work
bd update bd-abc --status in_progress

# Add context and notes
bd update bd-abc --notes "Investigating Parser.swift line 245"
```

### Ending a Session ("Landing the Plane")

**IMPORTANT**: Always complete these steps before ending a session:

```bash
# 1. File issues for any remaining work
bd create "Follow-up: Add tests for new feature" -p 2

# 2. Close completed issues
bd close bd-abc --reason "Fixed and verified"

# 3. Sync everything to git
bd sync

# 4. Verify everything is pushed
git status  # Should show "up to date with origin"
```

## Hierarchical Issues (Epics)

For large features, use hierarchical IDs:

```bash
# Create an epic
bd create "AESP Protocol Implementation" -t epic -p 1
# Returns: bd-a3f8

# Create child tasks (automatically get .1, .2 suffixes)
bd create "Implement control channel" -p 1 --parent bd-a3f8    # bd-a3f8.1
bd create "Implement video channel" -p 1 --parent bd-a3f8     # bd-a3f8.2
bd create "Implement audio channel" -p 1 --parent bd-a3f8     # bd-a3f8.3

# View the hierarchy
bd dep tree bd-a3f8
```

## Configuration

Project-specific settings are in `.beads/config.yaml`:

```yaml
# Sync settings
sync:
  mode: git-portable
  export_on: push
  import_on: pull

# Conflict resolution
conflict:
  strategy: newest
```

## Troubleshooting

### "bd: command not found"

Ensure bd is in your PATH:

```bash
# If installed via go install
export PATH="$PATH:$(go env GOPATH)/bin"

# Or reinstall via Homebrew
brew install bd
```

### Database Issues

```bash
# Check database health
bd doctor

# Rebuild from JSONL
bd import --force
```

### Sync Issues

```bash
# Force import from JSONL
bd import -i .beads/issues.jsonl

# Skip daemon for direct operations
bd --no-daemon sync
```

## Key Files

- `.beads/issues.jsonl` - All issues in JSONL format (committed to git)
- `.beads/beads.db` - Local SQLite cache (gitignored)
- `.beads/config.yaml` - Project configuration (optional)

## Learn More

- [Full CLI Reference](https://github.com/steveyegge/beads/blob/main/docs/CLI_REFERENCE.md)
- [Agent Instructions](https://github.com/steveyegge/beads/blob/main/AGENT_INSTRUCTIONS.md)
- [Git Integration](https://github.com/steveyegge/beads/blob/main/docs/GIT_INTEGRATION.md)
- [Troubleshooting](https://github.com/steveyegge/beads/blob/main/docs/TROUBLESHOOTING.md)

---

*Beads: Issue tracking that moves at the speed of thought*
