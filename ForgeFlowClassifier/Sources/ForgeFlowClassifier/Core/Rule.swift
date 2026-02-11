//
//  Rule.swift
//  ForgeFlowClassifier
//
//  Created by MagicianQuinn on 2026/2/11.
//

import Foundation

public enum RuleCondition: Sendable, Equatable {
    case domainFull(String)
    case domainSuffix(String)
    case domainKeyword(String)

    /// geosite:xxx
    case geosite(String)
    /// geoip:cc
    case geoip(String)
    /// FINAL
    case any
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
