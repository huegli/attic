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
// =============================================================================

module github.com/attic/attic-cli

go 1.21

require github.com/attic/atticprotocol v0.0.0

// Use the local atticprotocol package during development.
replace github.com/attic/atticprotocol => ../atticprotocol
