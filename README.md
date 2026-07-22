# ForgeRuleCore

Swift package: shared **rule kernel** for routing and DNS (`RuleCore`, `GeoSiteDB`, `GeoIPDB`, flow adapter `FlowRuleClassifier`).

- **Product:** `ForgeRuleCore`
- **Import:** `import ForgeRuleCore`
- **Assembly:** `ForgeRuleCoreBundle.makeRuleCore` / `makeFlowClassifier`

## Xray-style config (narrow subset)

- **Routing:** decode `RoutingConfigJSON`, then `FieldRoutingRuleFactory.makeRules(from:)` → `[Rule]`. Current compiler accepts one primitive per `field` row: a single `domain` entry (`geosite:` / `full:` / `domain:` / `keyword:` / plain suffix) or a single `ip` entry (`geoip:` / `geoip:!cn`). Multiple domain entries, domain+ip composition, recognized `network`, `regexp:`, and `IP-CIDR` are not supported yet.
- **DNS:** decode `DNSRoutingConfigJSON` for `hosts` and mixed `servers` (string or object). DoH, `expectIPs` validation, and `skipFallback` orchestration belong in your DNS service, not in this package.

## Docs

- [ARCHITECTURE.md](ForgeRuleCore/docs/ARCHITECTURE.md) — stable contracts
- [CONTRACT-TESTS.md](ForgeRuleCore/docs/CONTRACT-TESTS.md) — contract / regression test plan
- [技术文案.md](ForgeRuleCore/docs/技术文案.md) — code review notes

## TODO: 
- **DOMAIN
- **DOMAIN-SUFFIX
- **DOMAIN-KEYWORD
- **DOMAIN-SET
- **IP-CIDR
- **GEOIP
- **GEOSITE
- **FINAL

