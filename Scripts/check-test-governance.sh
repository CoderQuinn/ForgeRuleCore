#!/usr/bin/env bash
# Lightweight unit-test governance gate.
# Policy: ForgeRuleCore/docs/TESTING.md
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS="$ROOT/ForgeRuleCore/Tests/ForgeRuleCoreTests"
BASELINE="$ROOT/ForgeRuleCore/docs/test-baseline.json"

die() { echo "governance FAIL: $*" >&2; exit 1; }

[[ -d "$TESTS" ]] || die "missing test directory: $TESTS"
[[ -f "$TESTS/ContractRegressionTests.swift" ]] || die "missing ContractRegressionTests.swift"
[[ -f "$TESTS/ForgeRuleCoreTests.swift" ]] || die "missing ForgeRuleCoreTests.swift"
[[ -f "$TESTS/RuleEngineAndMatchersTests.swift" ]] || die "missing RuleEngineAndMatchersTests.swift"
[[ -f "$BASELINE" ]] || die "missing baseline: $BASELINE"

# Forbid XCTest placeholders and mixed frameworks in this package.
if rg -n 'func example\s*\(|XCTest|import XCTest' "$TESTS" --glob '*.swift' >/dev/null 2>&1; then
  die "XCTest / placeholder example() is not allowed; use Swift Testing (@Test) only"
fi

# Count @Test declarations (one per line typical).
count="$(rg -c '^\s*@Test' "$TESTS" --glob '*.swift' | awk -F: '{s+=$2} END {print s+0}')"
min="$(python3 -c "import json; print(json.load(open('$BASELINE'))['min_test_count'])")"

echo "governance: @Test count=$count (min=$min)"

if (( count < min )); then
  die "@Test count $count is below baseline min_test_count=$min — update tests or intentionally bump baseline in docs/test-baseline.json with PR rationale"
fi

# Contract IDs referenced in CONTRACT-TESTS.md should appear in ContractRegressionTests.
PLAN="$ROOT/ForgeRuleCore/docs/CONTRACT-TESTS.md"
CONTRACTS="$TESTS/ContractRegressionTests.swift"
[[ -f "$PLAN" ]] || die "missing CONTRACT-TESTS.md"

missing=0
while IFS= read -r id; do
  [[ -z "$id" ]] && continue
  if ! rg -q "$id" "$CONTRACTS"; then
    echo "governance WARN: contract id $id not mentioned in ContractRegressionTests.swift" >&2
    # Soft warning for comment linkage; harden later if desired.
  fi
done < <(rg -o 'C-[A-Z0-9-]+' "$PLAN" | sort -u)

# Required contract test name prefixes.
for name in \
  contract_geoip_negation_hits_on_lookup_miss \
  contract_geoip_uses_resolved_ip_not_original \
  contract_compiler_silently_drops_unsupported_rows
do
  rg -q "func ${name}" "$CONTRACTS" || die "missing required contract test: $name"
done

echo "governance: OK"
