#!/usr/bin/env bash
# Lean default lane: cold resolve proof + product-scoped build + root-package tests.
#
# Why product-scoped build / OMIT for tests?
# SPM registers in-tree Hive/Membrane/ContextCore targets whenever integration
# modules are enabled in Package.swift. Their remote product edges are
# trait-gated (so lean *resolve* stays free of MetalANNS/Wax/crypto), but a bare
# `swift build` / `swift test` on the *root* package still compiles every
# registered target — and those targets fail without Integrations. Consumers
# only build reachable targets, so they are unaffected.
#
# Phase 1 — full Package.swift, Integrations off:
#   cold resolve + deny-list + residual allowlist + product-scoped build
# Phase 2 — SWARM_OMIT_INTEGRATION_TARGETS=1:
#   bare swift test (no orphan integration targets in the graph)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

echo "lean-build-test: phase 1 — cold lean resolve (full Package.swift)"
rm -rf .build Package.resolved
swift package resolve
bash scripts/ci/verify-lean-resolve.sh

echo "lean-build-test: phase 1 — product-scoped lean build"
swift build \
  --product Swarm \
  --product SwarmMCP \
  --product SwarmOpenTelemetry \
  --product SwarmMembrane \
  --product SwarmCapabilityShowcase

echo "lean-build-test: phase 2 — root-package lean tests (omit integration targets)"
rm -rf .build Package.resolved
SWARM_OMIT_INTEGRATION_TARGETS=1 swift package resolve
SWARM_OMIT_INTEGRATION_TARGETS=1 bash scripts/ci/verify-lean-resolve.sh
SWARM_OMIT_INTEGRATION_TARGETS=1 swift test --no-parallel

echo "lean-build-test: phase 3 — Macros-disabled consumer (zero swift-syntax)"
bash scripts/ci/verify-macros-disabled-consumer.sh

echo "lean-build-test: PASS"
