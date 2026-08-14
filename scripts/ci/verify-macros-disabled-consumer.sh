#!/usr/bin/env bash
# Prove a consumer can depend on Swarm with Macros disabled and resolve
# a graph that contains zero swift-syntax. Also builds and tests the fixture.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
FIXTURE_DIR="$ROOT_DIR/Fixtures/MacrosDisabledConsumer"

if [[ ! -f "$FIXTURE_DIR/Package.swift" ]]; then
  echo "verify-macros-disabled-consumer: fixture missing at $FIXTURE_DIR" >&2
  exit 2
fi

cd "$FIXTURE_DIR"
rm -rf .build Package.resolved

echo "verify-macros-disabled-consumer: resolve with Macros disabled (traits: [])"
swift package resolve

echo "verify-macros-disabled-consumer: show-dependencies"
DEPS="$(swift package show-dependencies)"
echo "$DEPS"

if echo "$DEPS" | grep -Eiq 'swift-syntax'; then
  echo "FAIL: swift-syntax is present in the Macros-disabled consumer graph" >&2
  exit 1
fi

if [[ -f Package.resolved ]]; then
  if grep -Eiq 'swift-syntax' Package.resolved; then
    echo "FAIL: swift-syntax is pinned in the Macros-disabled Package.resolved" >&2
    exit 1
  fi
fi

echo "verify-macros-disabled-consumer: build + FunctionTool smoke test"
swift test --no-parallel

echo "PASS: Macros-disabled consumer resolves without swift-syntax and tests pass"
