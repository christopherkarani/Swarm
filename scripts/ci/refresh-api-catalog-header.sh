#!/usr/bin/env bash
set -euo pipefail

# Refresh source-file counts in docs/reference/api-catalog.md.
# This does not regenerate exhaustive public-symbol rows. After public API
# changes, update the affected high-risk rows by hand.

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

CATALOG="docs/reference/api-catalog.md"
SOURCES="Sources/Swarm"

if [[ ! -f "$CATALOG" ]]; then
  echo "refresh-api-catalog-header: missing $CATALOG" >&2
  exit 1
fi

all_count="$(find "$SOURCES" -name '*.swift' | wc -l | tr -d ' ')"
scoped_count="$(find "$SOURCES" -name '*.swift' ! -path '*/Internal/GraphRuntime/*' | wc -l | tr -d ' ')"

python3 - "$CATALOG" "$scoped_count" "$all_count" <<'PY'
from pathlib import Path
import re
import sys

catalog_path = Path(sys.argv[1])
scoped = sys.argv[2]
all_count = sys.argv[3]
text = catalog_path.read_text()
pattern = r"- Source files scanned: \d+(?: \(\d+ including `Internal/GraphRuntime/`\))?"
replacement = f"- Source files scanned: {scoped} ({all_count} including `Internal/GraphRuntime/`)"
updated, count = re.subn(pattern, replacement, text, count=1)
if count != 1:
    raise SystemExit("refresh-api-catalog-header: could not find source-file count line")
catalog_path.write_text(updated)
print(f"Updated {catalog_path}: {replacement}")
PY
