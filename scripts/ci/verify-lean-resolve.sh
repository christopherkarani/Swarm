#!/usr/bin/env bash
# Fail if Package.resolved contains forbidden remote package identities, or
# (on lean / omit / core-only graphs) residual remotes that should not pin
# when Integrations/MCP/OpenTelemetry are off.
#
# Forbidden = hive | membrane | contextcore | conduit (and matching
# christopherkarani/* remote URLs). In-tree Sources/ modules are fine.
#
# Lean default (Integrations/MCP/OpenTelemetry off, Macros on):
#   only swift-syntax + swift-log.
# Disable Macros (`traits: []`) to drop swift-syntax — see
# scripts/ci/verify-macros-disabled-consumer.sh.
#
# Usage (after resolve):
#   swift package resolve
#   scripts/ci/verify-lean-resolve.sh
#
# Optional: SWARM_LEAN_ALLOWED_IDS=id,id  overrides the default allowlist
# (used by the macros-disabled consumer, which must pin only swift-log).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
RESOLVED="${SWARM_PACKAGE_RESOLVED:-$ROOT_DIR/Package.resolved}"

if [[ ! -f "$RESOLVED" ]]; then
  echo "verify-lean-resolve: Package.resolved missing — run 'swift package resolve' first" >&2
  exit 2
fi

export SWARM_PACKAGE_RESOLVED="$RESOLVED"
python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

path = Path(os.environ["SWARM_PACKAGE_RESOLVED"])
data = json.loads(path.read_text())
pins = data.get("pins") or []

FORBIDDEN_IDS = frozenset({"hive", "membrane", "contextcore", "conduit"})
FORBIDDEN_URL_FRAGMENTS = (
    "christopherkarani/hive",
    "christopherkarani/membrane",
    "christopherkarani/contextcore",
    "christopherkarani/conduit",
)
# Opt-in remotes that must not appear on lean resolve (trait-gated edges).
LEAN_BLOCKED_IDS = frozenset({
    "wax",
    "metalanns",
    "grdb.swift",
    "swift-crypto",
    "swift-mutex",
    "swift-asn1",
    "swiftsoup",
    "swift-sdk",
    "opentelemetry-swift-core",
    "eventsource",
    "swift-nio",
    "swift-atomics",
    "swift-system",
    "swift-collections",
})

allowed_env = os.environ.get("SWARM_LEAN_ALLOWED_IDS")
if allowed_env:
    allowed = {item.strip() for item in allowed_env.split(",") if item.strip()}
else:
    allowed = {"swift-syntax", "swift-log"}

rows = []
for pin in pins:
    identity = pin.get("identity") or ""
    location = pin.get("location") or ""
    state = pin.get("state") or {}
    version = state.get("version") or state.get("revision") or "?"
    rows.append((identity, version, location))

rows.sort(key=lambda r: r[0])
ids = {r[0] for r in rows}

print(f"verify-lean-resolve: {len(rows)} pin(s) (allow {sorted(allowed)})")
for identity, version, _location in rows:
    print(f"  {identity}@{version}")

bad_ids = sorted(FORBIDDEN_IDS & ids)
bad_urls = []
for identity, _version, location in rows:
    low = location.lower()
    for frag in FORBIDDEN_URL_FRAGMENTS:
        if frag in low:
            bad_urls.append((identity, location))
            break

blocked = sorted(LEAN_BLOCKED_IDS & ids)
unexpected = sorted(ids - allowed)

failed = False
if bad_ids:
    print(f"FAIL: forbidden package identities: {bad_ids}", file=sys.stderr)
    failed = True
if bad_urls:
    print(f"FAIL: forbidden package URLs: {bad_urls}", file=sys.stderr)
    failed = True
if blocked:
    print(
        f"FAIL: lean residual should not pin opt-in remotes: {blocked}",
        file=sys.stderr,
    )
    failed = True
if unexpected:
    print(
        f"FAIL: lean resolve allowlist is {sorted(allowed)}; unexpected pins: {unexpected}",
        file=sys.stderr,
    )
    failed = True

if failed:
    sys.exit(1)

print(
    "PASS: no hive/membrane/contextcore/conduit; "
    f"lean pins exactly {sorted(allowed)}"
)
PY
