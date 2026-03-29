"""PyInstaller entry point for the Attic CLI.

This wrapper uses an absolute import so that PyInstaller can resolve the
package correctly in one-file mode (where relative imports inside
__main__.py would fail).
"""

from attic_cli.main import cli

cli()
