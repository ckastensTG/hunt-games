#!/usr/bin/env bash
# Runs the core and title tests headless.
#   tools/run_tests.sh [--include-slow] [--filter=name]
# GODOT defaults to `godot` on PATH.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
# Build the global class cache (class_name lookups) before running scripts.
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . -s res://addons/timeless_core/testing/test_runner.gd -- \
  --dir=res://addons/timeless_core/tests --dir=res://tests "$@"
