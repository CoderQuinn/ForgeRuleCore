# ForgeRuleCore

Swift package: shared **rule kernel** for routing and DNS (`RuleCore`, `GeoSiteDB`, `GeoIPDB`, flow adapter `FlowRuleClassifier`).

- **Product:** `ForgeRuleCore`
- **Import:** `import ForgeRuleCore`
- **Assembly:** `ForgeRuleCoreBundle.makeRuleCore` / `makeFlowClassifier`

## Xray-style config (subset)

- **Routing:** decode `RoutingConfigJSON`, then `FieldRoutingRuleFactory.makeRules(from:)` → `[Rule]`. Supports `domain` (OR of `geosite:` / `full:` / `domain:` / plain suffix), `ip` (`geoip:` only), `network` (`tcp,udp` → AND with domain/ip), and `geoip:!cn` via `GeoIPDB`.
- **DNS:** decode `DNSRoutingConfigJSON` for `hosts` and mixed `servers` (string or object). DoH, `expectIPs` validation, and `skipFallback` orchestration belong in your DNS service, not in this package.
