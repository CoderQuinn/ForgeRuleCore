//
//  ForgeFlowClassifier.swift
//  ForgeFlowClassifier
//
//  Created by MagicianQuinn on 2026/2/11.
//

import Foundation

public enum RouteDecision: Sendable, Equatable {
    case direct
    case proxy(String?)
    case reject
}

public final class ForgeFlowClassifier: Sendable {
    private let engine: RuleEngine

    public init(engine: RuleEngine) {
        self.engine = engine
    }

    public func classify(_ meta: FlowMeta) -> RouteDecision {
        switch engine.evaluate(meta) {
        case .direct:
            return .direct
        case let .proxy(tag):
            return .proxy(tag)
        case .reject:
            return .reject
        }
    }
}
