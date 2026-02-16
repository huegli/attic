// =============================================================================
// go.mod - Go Module Definition
// =============================================================================
//
// GO CONCEPT: Modules
// -------------------
// Every Go project needs a go.mod file at its root. This is similar to
// package.json (Node.js), Cargo.toml (Rust), or Package.swift (Swift).
// It defines:
//   - The module path (a unique name for your project, usually a URL)
//   - The minimum Go version required
//   - Dependencies on other modules
//
// The "module" line declares this project's import path. Other Go code
// would import it as: import "github.com/attic/attic-cli"
//
// The "require" block lists external dependencies. Each entry has a
// module path and a version. Go uses semantic versioning for modules.
//
// The "replace" directive is a development convenience: it tells Go to
// use a local directory instead of downloading the module from the
// internet. This is how we depend on our sibling atticprotocol package
// without publishing it to a registry. In production, you'd remove the
// replace and point to a real version.
//
// To add a new dependency:   go get github.com/some/package@latest
// To tidy unused deps:       go mod tidy
// To verify checksums:       go mod verify
//
// Compare with Python: Python uses `pyproject.toml` (modern) or
// `requirements.txt` / `setup.py` (legacy) for dependency management.
// `pip install -e ../atticprotocol` is the equivalent of Go's `replace`
// directive for local development. Virtual environments (`venv`) isolate
// dependencies per project, similar to Go modules' per-project scope.
//
// GO CONCEPT: Multiple require and replace Directives
// ---------------------------------------------------
// When a project has multiple dependencies, they're listed in a "require"
// block with parentheses. Each dependency specifies a module path and a
// minimum version. Go uses "minimum version selection" (MVS) — unlike
// npm or pip, Go always uses the MINIMUM version that satisfies all
// constraints, not the latest. This makes builds more reproducible.
//
// The "indirect" comment marks dependencies that aren't imported directly
// by your code but are needed by your dependencies (transitive deps).
// Go tracks these explicitly in go.mod for reproducibility.
//
// Compare with Swift: Package.swift lists dependencies with version ranges:
//   .package(url: "...", from: "1.0.0")
// Swift Package Manager resolves to the latest compatible version, whereas
// Go resolves to the minimum compatible version. Both approaches have
// trade-offs: latest gets bug fixes sooner, minimum is more predictable.
//
// Compare with Python: pip resolves to the latest compatible version by
// default. `pip freeze > requirements.txt` pins exact versions for
// reproducibility, similar to Go's go.sum file. Poetry and PDM support
// lock files for deterministic resolution.
//
// =============================================================================

module github.com/attic/attic-cli

go 1.24.0

toolchain go1.24.7

require (
	github.com/attic/atticprotocol v0.0.0
	github.com/ergochat/readline v0.1.3
	golang.org/x/term v0.40.0
)

require (
	golang.org/x/sys v0.41.0 // indirect
	golang.org/x/text v0.9.0 // indirect
)

// Use the local atticprotocol package during development.
replace github.com/attic/atticprotocol => ../atticprotocol
