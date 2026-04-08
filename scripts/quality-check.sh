#!/bin/bash
# Quality check script for the project
# Called by /commit/merge and /issue/auto workflows
#
# Exit codes:
#   0: All checks passed
#   1: One or more checks failed
#
# Customize this script for your project's needs.

set -e

echo "=== Running quality checks ==="

# Ensure all optional dependencies are installed for testing
echo ">>> uv sync --all-extras (first run may take time)"
uv sync --all-extras --quiet

# Lint
echo ">>> ruff check"
uv run ruff check src/

# Format
echo ">>> ruff format --check"
uv run ruff format --check src/

# Type check
echo ">>> mypy"
uv run mypy src/

# Tests
echo ">>> pytest"
uv run pytest

echo "=== All quality checks passed ==="
