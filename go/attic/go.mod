module github.com/attic/attic-cli

go 1.21

require github.com/attic/atticprotocol v0.0.0

// Use the local atticprotocol package during development.
replace github.com/attic/atticprotocol => ../atticprotocol
