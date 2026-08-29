# ForgeRuleCore

<p align="center">
  <strong>English</strong> |
  <a href="README.zh-CN.md">简体中文</a>
</p>

[![CI](https://github.com/CoderQuinn/ForgeRuleCore/actions/workflows/ci.yml/badge.svg?branch=feat-0.1.0)](https://github.com/CoderQuinn/ForgeRuleCore/actions/workflows/ci.yml)
![Swift Testing](https://img.shields.io/badge/tests-Swift_Testing-orange?logo=swift)
![Status](https://img.shields.io/badge/status-mvp_kernel-blue)
![Platform](https://img.shields.io/badge/platform-iOS%2015%2B%20%7C%20macOS%2013%2B-blue)
![SPM](https://img.shields.io/badge/SPM-compatible-brightgreen)
![License](https://img.shields.io/github/license/CoderQuinn/ForgeRuleCore)

Swift package: shared **rule kernel** for routing and DNS (`RuleCore`, `GeoSiteDB`, `GeoIPDB`, flow adapter `FlowRuleClassifier`).

- **Product:** `ForgeRuleCore`
- **Import:** `import ForgeRuleCore`
- **Assembly:** `ForgeRuleCoreBundle.makeRuleCore` / `makeFlowClassifier`
- **Package path:** `ForgeRuleCore/` (run `swift test` from that directory, or `./Scripts/run-tests.sh` from repo root)

## Xray-style config (narrow subset)

- **Routing:** decode `RoutingConfigJSON`, then call `FieldRoutingRuleFactory.compile(fields:)`. The result contains ordered accepted rules plus a diagnostic with the original row index and stable reason for every rejection; require `isSuccessful` before installing the rules. `makeRule(from:)` and `makeRules(from:)` remain compatibility projections that omit diagnostics. The narrow compiler accepts one primitive per `field` row: a single `domain` entry (`geosite:` / `full:` / `domain:` / `keyword:` / plain suffix) or a single `ip` entry (`geoip:` / `geoip:!cn`). Multiple domain entries, domain+ip composition, any non-empty `network`, `regexp:`, and `IP-CIDR` are not supported yet.
- **DNS:** decode `DNSRoutingConfigJSON` for `hosts` and mixed `servers` (string or object). DoH, `expectIPs` validation, and `skipFallback` orchestration belong in your DNS service, not in this package.
- **GeoMMDB:** every `MMDBReader` owns an independent immutable database handle. Create a replacement rule snapshot to reload; there is no in-place `reopen`. Official pinned MaxMind test fixtures cover IPv4 byte order, independent databases, open failure isolation, and teardown.
- **Bundle assembly:** the App Group container must contain `Rules/geosite.json` and `Rules/geoip.mmdb` as files, matching the QuantumLink path contract. `ForgeRuleCoreBundleError` distinguishes an unresolved container, a missing resource, malformed geosite data, and MMDB open failure. Resource versioning and atomic snapshot replacement remain host responsibilities.

## Docs

- [ARCHITECTURE.md](ForgeRuleCore/docs/ARCHITECTURE.md) — stable contracts
- [TESTING.md](ForgeRuleCore/docs/TESTING.md) — unit-test governance (CI policy)
- [CONTRACT-TESTS.md](ForgeRuleCore/docs/CONTRACT-TESTS.md) — contract / regression test plan
- [技术文案.md](ForgeRuleCore/docs/技术文案.md) — code review notes

## Test locally

```bash
./Scripts/ci.sh
./Scripts/check-test-governance.sh
./Scripts/run-tests.sh
./Scripts/coverage.sh
```

`./Scripts/ci.sh` is the canonical local and GitHub Actions gate. It runs the
56-test governance floor, clean Debug and Release builds/tests, strict Swift
concurrency diagnostics as errors, a generic iOS 15 arm64 build, and
first-party production coverage. The initial coverage ratchet is 67.00%;
vendored `libmaxminddb` and tests are excluded, while the package's own Swift
sources and `GeoMMDBBridge.c` remain in scope. The resolved ForgeBase baseline
is 0.3.0, which supplies the reviewed Swift 6 `Sendable` packet contracts.

## TODO

- DOMAIN / DOMAIN-SUFFIX / DOMAIN-KEYWORD (done as primitives; expand composite)
- DOMAIN-SET
- IP-CIDR
- GEOIP / GEOSITE (subset done)
- FINAL (via `.any`; see architecture)
