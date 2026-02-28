"""Shared test fixtures for the Attic CLI test suite."""

import pytest

from attic_cli.cli_client import CLISocketClient


@pytest.fixture
def client():
    """Create a disconnected CLISocketClient for testing."""
    return CLISocketClient()
