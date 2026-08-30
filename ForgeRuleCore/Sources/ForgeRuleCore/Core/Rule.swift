//
//  Rule.swift
//  ForgeRuleCore
//
//  Created by MagicianQuinn on 2026/2/11.
//

import Foundation

/// Routing conditions. Domain / `geoip` / `geosite` payloads should be **normalized**
/// (`FieldRoutingRuleFactory`, `normalizeDomain`, `normalizeGeoipKey`).
///
/// **Implemented (rough Surge-style coverage):** full / suffix / keyword domain match
/// (Surge `DOMAIN`, `DOMAIN-SUFFIX`, `DOMAIN-KEYWORD`), `GEOIP`-style country lists (`geoip:`),
/// v2ray/sing-box-style **geosite** category lists (`geosite:` + `GeoSiteDB`), and catch‑all `any`
/// (Surge `FINAL`-style last rule).
///
/// **Deferred toward fuller Surge parity:** `IP-CIDR` / `IP-CIDR6`, `RULE-SET`, `USER-AGENT`,
/// `PROCESS-NAME` / `PROCESS-PATH-*`, `DEST-PORT` / `OR` / `AND`, URL‑regex, script, etc.
public enum RuleCondition: Sendable, Equatable {
    case domainFull(String)
    case domainSuffix(String)
    case domainKeyword(String)
    /// v2ray `geosite:` tag (normalized), resolved via `GeoSiteDB`.
    case geosite(String)
    /// `geoip:cc`, `geoip:!cn` — key normalized with `normalizeGeoipKey`.
    case geoip(String)
    /// Matches every flow (catch‑all, typically kept last).
    case any

    /// Collect `geoip:` keys for MMDB preheat.
    public func collectGeoipKeys() -> [String] {
        switch self {
        case let .geoip(k):
            return [k]
        default:
            return []
        }
    }
}

public enum RuleAction: Sendable, Equatable {
    case direct
    case proxy(String?) // tag
    case reject
}

public struct Rule: Sendable, Equatable {
    public let condition: RuleCondition
    public let action: RuleAction

    public init(condition: RuleCondition, action: RuleAction) {
        self.condition = condition
        self.action = action
    }
}
