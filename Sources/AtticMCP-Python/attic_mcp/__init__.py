"""AtticMCP — MCP server for the Attic Atari 800 XL emulator.

This package provides a Model Context Protocol (MCP) server that exposes
Atari 800 XL emulator tools to AI assistants like Claude Code. It communicates
with AtticServer over the CLI socket protocol (Unix domain socket, text-based).

Architecture:
    Claude Code <--stdio JSON-RPC--> attic-mcp (this package)
                                         |
                                         | Unix domain socket
                                         | /tmp/attic-<pid>.sock
                                         | Text protocol: CMD:/OK:/ERR:
                                         v
                                    AtticServer (Swift)
"""
