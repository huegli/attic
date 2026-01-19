# Beads - AI-Native Issue Tracking

This project uses **Beads** for issue tracking - a modern, AI-native tool designed to live directly in your codebase alongside your code.

## What is Beads?

Beads is issue tracking that lives in your repo, making it perfect for AI coding agents and developers who want their issues close to their code. No web UI required - everything works through the CLI and integrates seamlessly with git.

**Learn more:** [github.com/steveyegge/beads](https://github.com/steveyegge/beads)

## Quick Start

### Essential Commands

```bash
# See what's ready to work on
bd ready

# Create new issues
bd create "Add user authentication"

# View all issues
bd list

# View issue details
bd show <issue-id>

# Update issue status
bd update <issue-id> --status in_progress
bd close <issue-id> --reason "Completed"

# Sync with git remote
bd sync
```

## Key Files

| File | Description |
|------|-------------|
| `issues.jsonl` | All issues in JSONL format (version controlled) |
| `beads.db` | Local SQLite cache (gitignored) |
| `config.yaml` | Project-specific configuration |
| `.gitignore` | Excludes database and temporary files |

## For AI Agents

When working with this codebase:

1. **Start** with `bd ready` to find actionable work
2. **Track** progress with `bd update <id> --status in_progress`
3. **Document** findings with `bd update <id> --notes "..."`
4. **Close** completed work with `bd close <id> --reason "..."`
5. **Sync** before ending: `bd sync`

**WARNING**: Do not use `bd edit` - it opens an interactive editor. Use `bd update` with flags instead.

## Setup

See [BEADS-QUICKSTART.md](../BEADS-QUICKSTART.md) in the project root for installation and setup instructions.

---

*Beads: Issue tracking that moves at the speed of thought*
