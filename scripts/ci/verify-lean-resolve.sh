#!/usr/bin/env bash
# Fail if Package.resolved contains forbidden remote package identities, or
# (on lean / omit / core-only graphs) residual integration remotes that should
# not pin when Integrations is off.
#
# Forbidden = hive | membrane | contextcore | conduit (and matching
# christopherkarani/* remote URLs). In-tree Sources/ modules are fine.
#
# Lean residual (Integrations off): always-on syntax/log/MCP/OTel (+ NIO
# transitives including swift-collections). Must NOT pin Wax, MetalANNS→GRDB,
# swift-crypto, swift-mutex, or SwiftSoup.
#
# Usage (after resolve):
#   swift package resolve
#   scripts/ci/verify-lean-resolve.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

if [[ ! -f Package.resolved ]]; then
  echo "verify-lean-resolve: Package.resolved missing — run 'swift package resolve' first" >&2
  exit 2
fi

python3 - <<'PY'
import json
import sys
from pathlib import Path

path = Path("Package.resolved")
data = json.loads(path.read_text())
pins = data.get("pins") or []

FORBIDDEN_IDS = frozenset({"hive", "membrane", "contextcore", "conduit"})
FORBIDDEN_URL_FRAGMENTS = (
    "christopherkarani/hive",
    "christopherkarani/membrane",
    "christopherkarani/contextcore",
    "christopherkarani/conduit",
)
# Integration remotes that must not appear on lean resolve (trait-gated edges).
# swift-collections may still appear as an NIO transitive — allowed.
LEAN_BLOCKED_IDS = frozenset({
    "wax",
    "metalanns",
    "grdb.swift",
    "swift-crypto",
    "swift-mutex",
    "swift-asn1",
    "swiftsoup",
})

rows = []
for pin in pins:
    identity = pin.get("identity") or ""
    location = pin.get("location") or ""
    state = pin.get("state") or {}
    version = state.get("version") or state.get("revision") or "?"
    rows.append((identity, version, location))

rows.sort(key=lambda r: r[0])
ids = {r[0] for r in rows}

print(f"verify-lean-resolve: {len(rows)} pin(s)")
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

if bad_ids or bad_urls or blocked:
    if bad_ids:
        print(f"FAIL: forbidden package identities: {bad_ids}", file=sys.stderr)
    if bad_urls:
        print(f"FAIL: forbidden package URLs: {bad_urls}", file=sys.stderr)
    if blocked:
        print(
            f"FAIL: lean residual should not pin integration remotes: {blocked}",
            file=sys.stderr,
        )
    sys.exit(1)

print(
    "PASS: no hive/membrane/contextcore/conduit; "
    "no wax/metalanns/grdb/crypto/mutex/swiftsoup on lean resolve"
)
if "swift-collections" in ids:
    print("note: swift-collections present (expected NIO/MCP transitive)")
PY
