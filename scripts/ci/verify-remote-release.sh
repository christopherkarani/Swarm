#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

BUILD_LOG="${BUILD_LOG:-/tmp/swarm-release-build.log}"
TEST_LOG="${TEST_LOG:-/tmp/swarm-release-test.log}"
EXAMPLE_LOG="${EXAMPLE_LOG:-/tmp/swarm-release-codereviewer-test.log}"

echo "release-check: remote-only resolve/build/test for Swarm"

AISTACK_USE_LOCAL_DEPS=0 swift package resolve
AISTACK_USE_LOCAL_DEPS=0 swift build 2>&1 | tee "$BUILD_LOG"
AISTACK_USE_LOCAL_DEPS=0 swift test 2>&1 | tee "$TEST_LOG"
SWARM_CORE_ONLY=1 AISTACK_USE_LOCAL_DEPS=0 swift test --package-path Examples/CodeReviewer 2>&1 | tee "$EXAMPLE_LOG"

if rg -n '\bwarning:|\berror:' "$BUILD_LOG" >/dev/null; then
  echo "release-check: compiler diagnostics found in build log" >&2
  rg -n '\bwarning:|\berror:' "$BUILD_LOG" >&2 || true
  exit 1
fi

if rg -n '\bwarning:' "$TEST_LOG" >/dev/null; then
  echo "release-check: compiler warnings found in test log" >&2
  rg -n '\bwarning:' "$TEST_LOG" >&2 || true
  exit 1
fi

if rg -n '\bwarning:' "$EXAMPLE_LOG" >/dev/null; then
  echo "release-check: compiler warnings found in CodeReviewer test log" >&2
  rg -n '\bwarning:' "$EXAMPLE_LOG" >&2 || true
  exit 1
fi

echo "release-check: Swarm remote verification passed"
