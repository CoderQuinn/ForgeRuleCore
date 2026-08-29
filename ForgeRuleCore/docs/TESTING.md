# ForgeRuleCore Unit Test Governance

> **Status**: binding for contributors and CI
> **Last updated**: 2026-08-29
> **Package root**: `ForgeRuleCore/` (SPM lives here, not repo root)

This document defines how unit and contract-regression tests are organized, what CI enforces, and what a PR that touches matching semantics must include.

---

## 1. Goals

1. Keep `swift test` **stable and deterministic** on macOS CI and locally.
2. Lock evaluation / GeoIP / compiler **contracts** with automated regressions (see [CONTRACT-TESTS.md](./CONTRACT-TESTS.md)).
3. Prevent silent test-count or suite-structure regressions via a lightweight governance gate.
4. Make CI status visible via README badges.

---

## 2. Framework policy

| Target | Framework | Owns |
|--------|-----------|------|
| `ForgeRuleCoreTests` | **Swift Testing only** (`import Testing` / `@Test`) | Resolver, factory, matchers, Geo stubs, RuleEngine, contract regressions |

**Do not** introduce XCTest (`import XCTest`) into this target until the package deliberately migrates as a whole.

Placeholder / empty “example” tests are **forbidden**. Every `@Test` must assert a behavior or contract.

---

## 3. Layout & naming

```
ForgeRuleCore/Tests/ForgeRuleCoreTests/
  ForgeRuleCoreTests.swift           # FlowFactsResolver, field factory, DNS JSON
  RuleEngineAndMatchersTests.swift   # matchers, GeoIP/GeoSite stubs, RuleEngine basics
  ContractRegressionTests.swift      # C-* contract locks (see CONTRACT-TESTS.md)
```

**Naming**

- Files: `<Area>Tests.swift`
- Contract tests: `contract_<behavior>_...` and reference contract IDs in comments (`C-GEOIP-MISS`, …)
- Prefer table-driven cases for outbound-tag maps and compiler drop matrices

---

## 4. What must be tested when changing contracts

| Change area | Must add / update |
|-------------|-------------------|
| `RuleEngine` order / `.any` / default action | `ContractRegressionTests` + `RuleEngineAndMatchersTests` |
| `GeoIPDB` / `!cc` / miss semantics | `C-GEOIP-MISS` cases |
| Which IP field geo uses | `C-GEOIP-RESOLVED` |
| `FieldRoutingRuleFactory` accept/reject | factory tests + `C-COMPILER-DIAGNOSTICS` / `C-OUTBOUND-MAP` |
| GeoSite full/suffix/keyword/regex ignore | GeoSite tests + `C-GEOSITE-REGEX` |
| MMDB ABI / IPv4 byte order / reader lifecycle | `MMDBReaderContractTests` + `C-MMDB-*` |
| App Group bundle layout / loader errors | `ForgeRuleCoreBundleContractTests` + `C-BUNDLE-*` |
| `normalizeDomain` / `normalizeGeoipKey` | helper unit tests |
| New ARCHITECTURE §4 bullet | New `C-*` row in CONTRACT-TESTS.md **and** a regression test |

Material contract changes must update [ARCHITECTURE.md](./ARCHITECTURE.md) in the same PR.

---

## 5. How to run

```bash
# From repo root — canonical full gate (same as GitHub Actions)
./Scripts/ci.sh

# Fast Debug build/test entrypoint
./Scripts/run-tests.sh

# Governance gate only (no compile)
./Scripts/check-test-governance.sh

# Filter
./Scripts/run-tests.sh contract_
./Scripts/run-tests.sh geoip_

# Or directly inside the package
cd ForgeRuleCore && swift test
```

CI workflows (repo root `.github/workflows/`):

| Workflow | File | What it runs |
|----------|------|----------------|
| **CI / Tests** | `ci.yml` | `./Scripts/ci.sh`: governance, clean Debug/Release and strict-concurrency tests, generic iOS build, and production coverage |

The workflow grants only `contents: read`, pins every external action to a full
commit SHA, and avoids a duplicate test workflow. The scripts use standard
macOS runner tools and do not require `rg`.

---

## 6. Governance gate (CI)

`Scripts/check-test-governance.sh` enforces:

1. Required test files exist (including `ContractRegressionTests.swift`).
2. No XCTest / `example()` placeholders in the test target.
3. `@Test` count ≥ `docs/test-baseline.json` → `min_test_count` (currently **56**).
4. Critical contract test symbols are present.

**To lower the baseline**: only with explicit PR rationale tied to ARCHITECTURE / CONTRACT-TESTS. Prefer never lowering; delete dead tests carefully and keep count stable or rising.

---

## 7. PR checklist (unit tests)

- [ ] New/changed behavior has a regression or assertion that would catch the bug.
- [ ] Contract / semantic changes update `ARCHITECTURE.md` and `CONTRACT-TESTS.md` when applicable.
- [ ] Still Swift Testing only (no XCTest in this package).
- [ ] `./Scripts/check-test-governance.sh` passes.
- [ ] `./Scripts/ci.sh` passes locally (or CI is green on the PR).
- [ ] If removing tests, `min_test_count` change is explained.

---

## 8. Badges

README surfaces:

- **CI** — the single required build, test, platform, and coverage workflow
- **Swift Testing** — static policy badge linking here
- **SPM** / platform — static metadata badges

`Scripts/coverage.sh` enforces an initial 67.00% first-party production line
coverage ratchet. It includes the package's Swift sources and
`GeoMMDBBridge.c`, while excluding tests and vendored `libmaxminddb`. The
generated summary is written to
`ForgeRuleCore/.build/coverage/production-summary.md` and published in the CI
job summary. Raising the threshold is preferred; lowering it requires explicit
PR rationale.

---

## 9. Out of scope (for now)

- Large production `geoip.mmdb` / geosite fixtures (small pinned official MMDB fixtures are covered)
- Versioned bundle manifest / checksum verification
- Snapshot-provider reload and concurrent replacement tests
- Mixing XCTest

---

## 10. References

- [ARCHITECTURE.md](./ARCHITECTURE.md)
- [CONTRACT-TESTS.md](./CONTRACT-TESTS.md)
- [技术文案.md](./技术文案.md)
- [README.md](../../README.md)
