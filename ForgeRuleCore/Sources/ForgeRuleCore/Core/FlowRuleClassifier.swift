//
//  FlowRuleClassifier.swift
//  ForgeRuleCore
//
//  Created by MagicianQuinn on 2026/2/11.
//

import Foundation

public enum RouteDecision: Sendable, Equatable {
    case direct
    case proxy(String?)
    case reject
}

public final class RuleCore: Sendable {
    private let engine: RuleEngine

    public init(engine: RuleEngine) {
        self.engine = engine
    }

    public func evaluate(_ input: RuleInput) -> RuleAction {
        engine.evaluate(input)
    }

    public func route(_ input: RuleInput) -> RouteDecision {
        switch evaluate(input) {
        case .direct:
            return .direct
        case let .proxy(tag):
            return .proxy(tag)
        case .reject:
            return .reject
        }
    }
}

/// Flow-facing adapter: resolves flow `RuleInput` (`factsResolved == false`) to match-ready input, then runs `RuleCore`.
public final class FlowRuleClassifier: Sendable {
    private let resolver: any FlowFactsResolving
    private let core: RuleCore

    public init(resolver: some FlowFactsResolving, engine: RuleEngine) {
        self.resolver = resolver
        core = RuleCore(engine: engine)
    }

    public init(resolver: some FlowFactsResolving, core: RuleCore) {
        self.resolver = resolver
        self.core = core
    }

    public func classify(_ input: RuleInput) -> RouteDecision {
        let resolved = resolver.resolve(input)
        return core.route(resolved)
    }
}
