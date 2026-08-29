#!/usr/bin/env bash
# Canonical unit-test entrypoint for local runs and CI.
# Policy: ForgeRuleCore/docs/TESTING.md
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG="$ROOT/ForgeRuleCore"
cd "$PKG"

FILTER="${1:-}"

echo "==> cwd: $(pwd)"
echo "==> swift --version"
swift --version

echo "==> swift build"
swift build

if [[ -n "$FILTER" ]]; then
  echo "==> swift test --filter ${FILTER}"
  swift test --filter "$FILTER"
else
  echo "==> swift test (ForgeRuleCoreTests)"
  swift test
fi
