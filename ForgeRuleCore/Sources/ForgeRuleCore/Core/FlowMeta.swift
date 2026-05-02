//
//  FlowMeta.swift
//  ForgeRuleCore
//
//  Created by MagicianQuinn on 2026/2/11.
//

import ForgeBase
import Foundation

public struct RuleInput: Sendable, Equatable {
    public let originalIP: FBIPv4
    public let resolvedIP: FBIPv4
    public let domain: String?
    public let port: UInt16
    public let proto: TransportProtocol
    /// `false` for a raw flow snapshot (domain may be absent or not yet normalized). `true` after `FlowFactsResolving` has produced match-ready facts.
    public let factsResolved: Bool

    public init(
        originalIP: FBIPv4,
        resolvedIP: FBIPv4,
        domain: String?,
        port: UInt16,
        proto: TransportProtocol,
        factsResolved: Bool = false
    ) {
        self.originalIP = originalIP
        self.resolvedIP = resolvedIP
        self.domain = domain
        self.port = port
        self.proto = proto
        self.factsResolved = factsResolved
    }
}
