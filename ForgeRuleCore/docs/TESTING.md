# ForgeRuleCore Unit Test Governance

> **Status**: binding for contributors and CI  
> **Last updated**: 2026-07-22  
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
| `FieldRoutingRuleFactory` accept/reject | factory tests + `C-COMPILER-DROP` / `C-OUTBOUND-MAP` |
| GeoSite full/suffix/keyword/regex ignore | GeoSite tests + `C-GEOSITE-REGEX` |
| `normalizeDomain` / `normalizeGeoipKey` | helper unit tests |
| New ARCHITECTURE §4 bullet | New `C-*` row in CONTRACT-TESTS.md **and** a regression test |

Material contract changes must update [ARCHITECTURE.md](./ARCHITECTURE.md) in the same PR.

---

## 5. How to run

```bash
# From repo root — canonical (same as CI unit-test job)
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
| **CI** | `ci.yml` | governance + build + full `swift test` |
| **Unit Tests** | `unit-tests.yml` | governance + `./Scripts/run-tests.sh` |

---

## 6. Governance gate (CI)

`Scripts/check-test-governance.sh` enforces:

1. Required test files exist (including `ContractRegressionTests.swift`).
2. No XCTest / `example()` placeholders in the test target.
3. `@Test` count ≥ `docs/test-baseline.json` → `min_test_count` (currently **43**).
4. Critical contract test symbols are present.

**To lower the baseline**: only with explicit PR rationale tied to ARCHITECTURE / CONTRACT-TESTS. Prefer never lowering; delete dead tests carefully and keep count stable or rising.

---

## 7. PR checklist (unit tests)

- [ ] New/changed behavior has a regression or assertion that would catch the bug.
- [ ] Contract / semantic changes update `ARCHITECTURE.md` and `CONTRACT-TESTS.md` when applicable.
- [ ] Still Swift Testing only (no XCTest in this package).
- [ ] `./Scripts/check-test-governance.sh` passes.
- [ ] `./Scripts/run-tests.sh` passes locally (or CI green on the PR).
- [ ] If removing tests, `min_test_count` change is explained.

---

## 8. Badges

README surfaces:

- **CI** — overall build + test workflow status
- **Unit Tests** — dedicated unit-test workflow status
- **Swift Testing** — static policy badge linking here
- **SPM** / platform — static metadata badges

Coverage percentage badge is **not** required for MVP; when added later, store summary under `docs/` or `badges/` and document the collector command here.

---

## 9. Out of scope (for now)

- Real `geoip.mmdb` / large geosite fixtures (tracked in ARCHITECTURE gaps)
- App Group / `ForgeRuleCoreBundle` I/O tests
- Process-global MMDB multi-path tests
- Mixing XCTest

---

## 10. References

- [ARCHITECTURE.md](./ARCHITECTURE.md)
- [CONTRACT-TESTS.md](./CONTRACT-TESTS.md)
- [技术文案.md](./技术文案.md)
- [README.md](../../README.md)
