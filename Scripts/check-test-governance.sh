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
[[ -f "$TESTS/MMDBReaderContractTests.swift" ]] || die "missing MMDBReaderContractTests.swift"
[[ -f "$TESTS/ForgeRuleCoreBundleContractTests.swift" ]] || die "missing ForgeRuleCoreBundleContractTests.swift"
[[ -f "$TESTS/SerializationAndBoundaryTests.swift" ]] || die "missing SerializationAndBoundaryTests.swift"
[[ -f "$TESTS/RevisionAndFactsContractTests.swift" ]] || die "missing RevisionAndFactsContractTests.swift"
[[ -f "$BASELINE" ]] || die "missing baseline: $BASELINE"

# Forbid XCTest placeholders and mixed frameworks in this package.
if grep -En 'func example[[:space:]]*\(|XCTest|import XCTest' "$TESTS"/*.swift >/dev/null 2>&1; then
  die "XCTest / placeholder example() is not allowed; use Swift Testing (@Test) only"
fi

# Count @Test declarations (one per line typical).
count="$(awk '/^[[:space:]]*@Test/{count++} END {print count+0}' "$TESTS"/*.swift)"
min="$(python3 -c "import json; print(json.load(open('$BASELINE'))['min_test_count'])")"

echo "governance: @Test count=$count (min=$min)"

if (( count < min )); then
  die "@Test count $count is below baseline min_test_count=$min — update tests or intentionally bump baseline in docs/test-baseline.json with PR rationale"
fi

# Contract IDs referenced in CONTRACT-TESTS.md should appear in ContractRegressionTests.
PLAN="$ROOT/ForgeRuleCore/docs/CONTRACT-TESTS.md"
[[ -f "$PLAN" ]] || die "missing CONTRACT-TESTS.md"

while IFS= read -r id; do
  [[ -z "$id" ]] && continue
  if ! grep -Fq "$id" "$TESTS"/*.swift; then
    echo "governance WARN: contract id $id not mentioned in a test source" >&2
    # Soft warning for comment linkage; harden later if desired.
  fi
done < <(grep -Eo 'C-[A-Z0-9-]+' "$PLAN" | sort -u)

# Required contract test name prefixes.
for name in \
  contract_geoip_negation_hits_on_lookup_miss \
  contract_geoip_uses_resolved_ip_not_original \
  contract_compiler_reports_every_rejected_row \
  mmdb_reader_reads_official_country_fixture \
  mmdb_readers_own_independent_database_handles \
  mmdb_reader_teardown_does_not_invalidate_another_reader \
  bundle_app_group_assembly_loads_real_geosite_and_geoip_fixtures \
  bundle_assembly_reports_missing_geosite \
  bundle_assembly_reports_malformed_geoip \
  rule_revision_requires_an_exact_nonempty_identity \
  resolver_preserves_dns_domain_revision_and_normalizes_the_fact \
  flow_classifier_preserves_dns_fact_revision_across_a_new_snapshot
do
  grep -Fq "func ${name}" "$TESTS"/*.swift || die "missing required contract test: $name"
done

echo "governance: OK"
