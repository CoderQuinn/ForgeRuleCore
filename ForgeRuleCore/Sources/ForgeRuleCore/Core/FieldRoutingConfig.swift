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
//  **Rejected with diagnostics:** multiple `domain` lines, `domain` + `ip` together, non-empty
//  `network`, `regexp:` domain entries.
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

    /// Unknown constraint names survive decoding so compilation cannot silently
    /// broaden a rule. Their values are deliberately not retained or logged.
    public private(set) var unsupportedKeys: [String] = []

    public init(type: String? = nil, outboundTag: String? = nil, domain: [String]? = nil, ip: [String]? = nil, network: String? = nil) {
        self.type = type
        self.outboundTag = outboundTag
        self.domain = domain
        self.ip = ip
        self.network = network
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type, outboundTag, domain, ip, network
    }

    private struct RawKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: RawKey.self)
        let known = Set(CodingKeys.allCases.map(\.rawValue))
        unsupportedKeys = raw.allKeys.map(\.stringValue).filter { !known.contains($0) }.sorted()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        type = try values.decodeIfPresent(String.self, forKey: .type)
        outboundTag = try values.decodeIfPresent(String.self, forKey: .outboundTag)
        domain = try values.decodeIfPresent([String].self, forKey: .domain)
        ip = try values.decodeIfPresent([String].self, forKey: .ip)
        network = try values.decodeIfPresent(String.self, forKey: .network)
    }

    public func encode(to encoder: Encoder) throws {
        guard unsupportedKeys.isEmpty else {
            throw EncodingError.invalidValue(self, .init(
                codingPath: encoder.codingPath,
                debugDescription: "Cannot encode a field rule with unsupported constraints"
            ))
        }
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(type, forKey: .type)
        try values.encodeIfPresent(outboundTag, forKey: .outboundTag)
        try values.encodeIfPresent(domain, forKey: .domain)
        try values.encodeIfPresent(ip, forKey: .ip)
        try values.encodeIfPresent(network, forKey: .network)
    }
}

// MARK: - Compilation

/// Stable reason codes for field rows that cannot be lowered without changing their meaning.
public enum FieldRoutingDiagnosticReason: String, Error, Sendable, Equatable {
    case unsupportedField = "unsupported_field"
    case unsupportedRuleType = "unsupported_rule_type"
    case missingOutboundTag = "missing_outbound_tag"
    case unsupportedNetwork = "unsupported_network"
    case mixedDomainAndIP = "mixed_domain_and_ip"
    case multipleDomainEntries = "multiple_domain_entries"
    case multipleIPEntries = "multiple_ip_entries"
    case missingCondition = "missing_condition"
    case invalidDomainEntry = "invalid_domain_entry"
    case unsupportedDomainEntry = "unsupported_domain_entry"
    case invalidIPEntry = "invalid_ip_entry"
    case unsupportedIPEntry = "unsupported_ip_entry"
}

/// A rejected source row and the stable reason why it was not lowered.
public struct FieldRoutingDiagnostic: Sendable, Equatable {
    public let fieldIndex: Int
    public let reason: FieldRoutingDiagnosticReason

    public init(fieldIndex: Int, reason: FieldRoutingDiagnosticReason) {
        self.fieldIndex = fieldIndex
        self.reason = reason
    }
}

/// Ordered rules plus every rejected source row. Partial rules are never reported as successful.
public struct FieldRoutingCompilation: Sendable, Equatable {
    public let rules: [Rule]
    public let diagnostics: [FieldRoutingDiagnostic]

    public var isSuccessful: Bool { diagnostics.isEmpty }
}

/// All rejected row indexes, without any partially accepted rules to activate.
public struct FieldRoutingValidationError: Error, Sendable, Equatable {
    public let diagnostics: [FieldRoutingDiagnostic]
}

// MARK: - Factory

public enum FieldRoutingRuleFactory {
    /// All-or-nothing lowering for new integrations. This validates decoded rows,
    /// not raw JSON duplicate keys, resource limits, or complete Xray semantics.
    public static func compileValidated(fields: [FieldRuleJSON]) throws -> [Rule] {
        let result = compile(fields: fields)
        guard result.isSuccessful else {
            throw FieldRoutingValidationError(diagnostics: result.diagnostics)
        }
        return result.rules
    }

    /// Compiles Xray-style field rules while preserving accepted order and rejected row indexes.
    public static func compile(fields: [FieldRuleJSON]) -> FieldRoutingCompilation {
        var rules: [Rule] = []
        var diagnostics: [FieldRoutingDiagnostic] = []

        for (fieldIndex, field) in fields.enumerated() {
            switch compileRule(from: field) {
            case let .success(rule):
                rules.append(rule)
            case let .failure(reason):
                diagnostics.append(FieldRoutingDiagnostic(fieldIndex: fieldIndex, reason: reason))
            }
        }

        return FieldRoutingCompilation(rules: rules, diagnostics: diagnostics)
    }

    /// Compatibility projection that returns only accepted rules (order preserved).
    /// New integrations should use `compileValidated(fields:)`.
    public static func makeRules(from fields: [FieldRuleJSON]) -> [Rule] {
        compile(fields: fields).rules
    }

    /// Compatibility projection for one row. Use `compile(fields:)` to retain rejection reasons.
    public static func makeRule(from field: FieldRuleJSON) -> Rule? {
        guard case let .success(rule) = compileRule(from: field) else { return nil }
        return rule
    }

    private static func compileRule(
        from field: FieldRuleJSON
    ) -> Result<Rule, FieldRoutingDiagnosticReason> {
        guard field.unsupportedKeys.isEmpty else { return .failure(.unsupportedField) }
        let type = field.type ?? "field"
        guard type == "field" else { return .failure(.unsupportedRuleType) }
        guard let action = mapOutboundTag(field.outboundTag) else {
            return .failure(.missingOutboundTag)
        }

        if let network = field.network?.trimmingCharacters(in: .whitespacesAndNewlines),
           !network.isEmpty
        {
            return .failure(.unsupportedNetwork)
        }

        let domains = field.domain ?? []
        let ips = field.ip ?? []

        guard domains.isEmpty || ips.isEmpty else { return .failure(.mixedDomainAndIP) }
        guard domains.count <= 1 else { return .failure(.multipleDomainEntries) }
        guard ips.count <= 1 else { return .failure(.multipleIPEntries) }

        if let domain = domains.first {
            return domainEntryCondition(domain).map { Rule(condition: $0, action: action) }
        }
        if let ip = ips.first {
            return ipEntryCondition(ip).map { Rule(condition: $0, action: action) }
        }
        return .failure(.missingCondition)
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
    private static func domainEntryCondition(
        _ raw: String
    ) -> Result<RuleCondition, FieldRoutingDiagnosticReason> {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return .failure(.invalidDomainEntry) }
        if s.hasPrefix("geosite:") {
            let name = String(s.dropFirst("geosite:".count))
            let n = normalizeDomain(name)
            return n.isEmpty ? .failure(.invalidDomainEntry) : .success(.geosite(n))
        }
        if s.hasPrefix("full:") {
            let v = String(s.dropFirst("full:".count))
            let n = normalizeDomain(v)
            return n.isEmpty ? .failure(.invalidDomainEntry) : .success(.domainFull(n))
        }
        if s.hasPrefix("domain:") {
            let v = String(s.dropFirst("domain:".count))
            let n = normalizeDomain(v)
            return n.isEmpty ? .failure(.invalidDomainEntry) : .success(.domainSuffix(n))
        }
        if s.hasPrefix("keyword:") {
            let v = String(s.dropFirst("keyword:".count))
            let n = normalizeDomain(v)
            return n.isEmpty ? .failure(.invalidDomainEntry) : .success(.domainKeyword(n))
        }
        if s.hasPrefix("regexp:") {
            return .failure(.unsupportedDomainEntry)
        }
        let n = normalizeDomain(s)
        return n.isEmpty ? .failure(.invalidDomainEntry) : .success(.domainSuffix(n))
    }

    private static func ipEntryCondition(
        _ raw: String
    ) -> Result<RuleCondition, FieldRoutingDiagnosticReason> {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return .failure(.invalidIPEntry) }
        if s.hasPrefix("geoip:") {
            let k = String(s.dropFirst("geoip:".count))
            let n = normalizeGeoipKey(k)
            return GeoIPDB.isValidKey(n) ? .success(.geoip(n)) : .failure(.invalidIPEntry)
        }
        return .failure(.unsupportedIPEntry)
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
