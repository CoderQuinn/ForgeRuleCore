# ForgeRuleCore

[![CI](https://github.com/CoderQuinn/ForgeRuleCore/actions/workflows/ci.yml/badge.svg)](https://github.com/CoderQuinn/ForgeRuleCore/actions/workflows/ci.yml)
[![Unit Tests](https://github.com/CoderQuinn/ForgeRuleCore/actions/workflows/unit-tests.yml/badge.svg)](https://github.com/CoderQuinn/ForgeRuleCore/actions/workflows/unit-tests.yml)
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

- **Routing:** decode `RoutingConfigJSON`, then `FieldRoutingRuleFactory.makeRules(from:)` → `[Rule]`. Current compiler accepts one primitive per `field` row: a single `domain` entry (`geosite:` / `full:` / `domain:` / `keyword:` / plain suffix) or a single `ip` entry (`geoip:` / `geoip:!cn`). Multiple domain entries, domain+ip composition, recognized `network`, `regexp:`, and `IP-CIDR` are not supported yet.
- **DNS:** decode `DNSRoutingConfigJSON` for `hosts` and mixed `servers` (string or object). DoH, `expectIPs` validation, and `skipFallback` orchestration belong in your DNS service, not in this package.

## Docs

- [ARCHITECTURE.md](ForgeRuleCore/docs/ARCHITECTURE.md) — stable contracts
- [TESTING.md](ForgeRuleCore/docs/TESTING.md) — unit-test governance (CI policy)
- [CONTRACT-TESTS.md](ForgeRuleCore/docs/CONTRACT-TESTS.md) — contract / regression test plan
- [技术文案.md](ForgeRuleCore/docs/技术文案.md) — code review notes

## Test locally

```bash
./Scripts/check-test-governance.sh
./Scripts/run-tests.sh
```

## TODO

- DOMAIN / DOMAIN-SUFFIX / DOMAIN-KEYWORD (done as primitives; expand composite)
- DOMAIN-SET
- IP-CIDR
- GEOIP / GEOSITE (subset done)
- FINAL (via `.any`; see architecture)
