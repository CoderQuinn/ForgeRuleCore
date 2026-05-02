//
//  FieldRoutingConfig.swift
//  ForgeRuleCore
//
//  Subset of Xray `routing.rules` (`type: field`) → `Rule` rows for `RuleEngine`.
//
//  **One primitive per field row:** a single `domain` entry (`full:` / `domain:` / `keyword:` /
//  `geosite:` / plain suffix) **or** a single `geoip:`. Additional Surge-style rule types
//  (`IP-CIDR`, `RULE-SET`, …) are not parsed here yet.
//
//  **Rejected (`nil`):** multiple `domain` lines, `domain` + `ip` together, non-empty `network`,
//  `regexp:` domain entries.
//

import ForgeBase
import Foundation

// MARK: - JSON

public struct RoutingConfigJSON: Codable, Sendable {
    public var routing: RoutingSectionJSON?
}

public struct RoutingSectionJSON: Codable, Sendable {
    public var rules: [FieldRuleJSON]?
}

public struct FieldRuleJSON: Codable, Sendable {
    public var type: String?
    public var outboundTag: String?
    public var domain: [String]?
    public var ip: [String]?
    public var network: String?
}

// MARK: - Factory

public enum FieldRoutingRuleFactory {
    /// Builds `Rule` list from Xray-style field rules (order preserved).
    public static func makeRules(from fields: [FieldRuleJSON]) -> [Rule] {
        fields.compactMap(makeRule)
    }

    public static func makeRule(from field: FieldRuleJSON) -> Rule? {
        let type = field.type ?? "field"
        guard type == "field" else { return nil }
        guard let action = mapOutboundTag(field.outboundTag) else { return nil }

        if let net = field.network {
            let protos = parseNetworkList(net)
            if !protos.isEmpty { return nil }
        }

        let domainConds = (field.domain ?? []).compactMap { domainEntryCondition($0) }
        let ipConds = (field.ip ?? []).compactMap { ipEntryCondition($0) }

        guard domainConds.count <= 1, ipConds.count <= 1 else { return nil }
        guard domainConds.count + ipConds.count == 1 else { return nil }

        if let c = domainConds.first {
            return Rule(condition: c, action: action)
        }
        if let c = ipConds.first {
            return Rule(condition: c, action: action)
        }
        return nil
    }

    // MARK: - Internals

    private static func mapOutboundTag(_ tag: String?) -> RuleAction? {
        guard let t = tag?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        switch t.lowercased() {
        case "direct": return .direct
        case "reject", "block": return .reject
        default: return .proxy(t)
        }
    }

    /// `geosite:name`, `full:`, `domain:`, `keyword:`, or plain hostname (suffix).
    private static func domainEntryCondition(_ raw: String) -> RuleCondition? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if s.hasPrefix("geosite:") {
            let name = String(s.dropFirst("geosite:".count))
            let n = normalizeDomain(name)
            return n.isEmpty ? nil : .geosite(n)
        }
        if s.hasPrefix("full:") {
            let v = String(s.dropFirst("full:".count))
            let n = normalizeDomain(v)
            return n.isEmpty ? nil : .domainFull(n)
        }
        if s.hasPrefix("domain:") {
            let v = String(s.dropFirst("domain:".count))
            let n = normalizeDomain(v)
            return n.isEmpty ? nil : .domainSuffix(n)
        }
        if s.hasPrefix("keyword:") {
            let v = String(s.dropFirst("keyword:".count))
            let n = normalizeDomain(v)
            return n.isEmpty ? nil : .domainKeyword(n)
        }
        if s.hasPrefix("regexp:") {
            return nil
        }
        let n = normalizeDomain(s)
        return n.isEmpty ? nil : .domainSuffix(n)
    }

    private static func ipEntryCondition(_ raw: String) -> RuleCondition? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if s.hasPrefix("geoip:") {
            let k = String(s.dropFirst("geoip:".count))
            let n = normalizeGeoipKey(k)
            return n.isEmpty ? nil : .geoip(n)
        }
        return nil
    }

    /// Parses `"tcp,udp"` into raw `TransportProtocol` values (reserved for future `network` support).
    public static func parseNetworkList(_ raw: String) -> Set<UInt8> {
        var out: Set<UInt8> = []
        for part in raw.split(separator: ",") {
            let p = part.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch p {
            case "tcp": out.insert(TransportProtocol.tcp.rawValue)
            case "udp": out.insert(TransportProtocol.udp.rawValue)
            case "icmp": out.insert(TransportProtocol.icmp.rawValue)
            default: break
            }
        }
        return out
    }
}
