"""Pytest configuration for tests."""

import pytest


def pytest_addoption(parser):
    """Add custom command line options."""
    parser.addoption(
        "--kind",
        action="store_true",
        default=False,
        help="Run kind integration tests",
    )


def pytest_configure(config):
    """Register custom markers."""
    config.addinivalue_line(
        "markers", "kind: marks tests that require a kind cluster"
    )


def pytest_collection_modifyitems(config, items):
    """Skip kind tests unless --kind is specified."""
    if config.getoption("--kind"):
        # --kind given: don't skip kind tests
        return

    skip_kind = pytest.mark.skip(reason="need --kind option to run")
    for item in items:
        if "kind" in item.keywords:
            item.add_marker(skip_kind)
