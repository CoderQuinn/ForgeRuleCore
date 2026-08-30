//
//  FlowMeta.swift
//  ForgeRuleCore
//
//  Created by MagicianQuinn on 2026/2/11.
//

import ForgeBase
import Foundation

/// Opaque identity for the complete rule snapshot used by a classification.
public struct RuleRevision: RawRepresentable, Codable, Sendable, Hashable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard !rawValue.isEmpty,
            rawValue == rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            return nil
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let revision = RuleRevision(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Rule revision must be non-empty and have no surrounding whitespace"
            )
        }
        self = revision
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Provenance of a domain fact carried between DNS and flow classification.
public enum RuleDomainFactSource: String, Codable, Sendable, Equatable {
    case flowContext
    case dns
    case fakeIP
}

public struct RuleInput: Sendable, Equatable {
    public let originalIP: FBIPv4
    public let resolvedIP: FBIPv4
    public let domain: String?
    public let domainSource: RuleDomainFactSource?
    /// Rule revision that produced `domain`, if it came from an earlier classification.
    public let domainRevision: RuleRevision?
    public let port: UInt16
    public let proto: TransportProtocol
    /// `false` for a raw flow snapshot (domain may be absent or not yet normalized). `true` after `FlowFactsResolving` has produced match-ready facts.
    public let factsResolved: Bool

    public init(
        originalIP: FBIPv4,
        resolvedIP: FBIPv4,
        domain: String?,
        domainSource: RuleDomainFactSource? = nil,
        domainRevision: RuleRevision? = nil,
        port: UInt16,
        proto: TransportProtocol,
        factsResolved: Bool = false
    ) {
        self.originalIP = originalIP
        self.resolvedIP = resolvedIP
        self.domain = domain
        self.domainSource = domain == nil ? nil : domainSource
        self.domainRevision = domain == nil ? nil : domainRevision
        self.port = port
        self.proto = proto
        self.factsResolved = factsResolved
    }

    func normalizedForEvaluation() -> RuleInput {
        let normalizedDomain = domain.flatMap { domain in
            let normalized = normalizeDomain(domain)
            return normalized.isEmpty ? nil : normalized
        }
        return RuleInput(
            originalIP: originalIP,
            resolvedIP: resolvedIP,
            domain: normalizedDomain,
            domainSource: domainSource,
            domainRevision: domainRevision,
            port: port,
            proto: proto,
            factsResolved: factsResolved
        )
    }
}
