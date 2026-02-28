# AtticMCP (Swift) — Archived

This directory contains the original Swift implementation of the AtticMCP server.
It has been replaced by the Python FastMCP implementation in `Python/AtticMCP/`.

The Swift source files are kept here as a reference. They are no longer built by
`Package.swift` and are not part of the active project.

## Replacement

The Python version uses [FastMCP](https://github.com/modelcontextprotocol/python-sdk)
(from the official MCP Python SDK) for automatic JSON schema generation, Pydantic
input validation, and a decorator-based tool API. It provides the same 26 tools over
the same CLI socket protocol to AtticServer, with ~1000 LOC instead of ~1500.

See `Python/AtticMCP/` and `.mcp.json` for the active MCP server configuration.
