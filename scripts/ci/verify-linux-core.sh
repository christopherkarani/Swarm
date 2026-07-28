#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

JOBS="${SWIFT_BUILD_JOBS:-1}"

echo "linux-core: build Swarm with default traits disabled"
SWARM_CORE_ONLY=1 swift build -j "$JOBS" --disable-default-traits --target Swarm

echo "linux-core: build SwarmMCP with default traits disabled"
SWARM_CORE_ONLY=1 swift build -j "$JOBS" --disable-default-traits --target SwarmMCP
