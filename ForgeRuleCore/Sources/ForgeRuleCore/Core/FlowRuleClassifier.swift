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

/// Stable classification envelope for adapters that must retain facts and snapshot identity.
public struct RuleClassification: Sendable, Equatable {
    public let decision: RouteDecision
    public let revision: RuleRevision?
    public let evaluatedInput: RuleInput

    public init(
        decision: RouteDecision,
        revision: RuleRevision?,
        evaluatedInput: RuleInput
    ) {
        self.decision = decision
        self.revision = revision
        self.evaluatedInput = evaluatedInput
    }
}

public final class RuleCore: Sendable {
    private let engine: RuleEngine
    public let revision: RuleRevision?

    public init(engine: RuleEngine, revision: RuleRevision? = nil) {
        self.engine = engine
        self.revision = revision
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

    public func classify(_ input: RuleInput) -> RuleClassification {
        let evaluatedInput = input.normalizedForEvaluation()
        return RuleClassification(
            decision: route(evaluatedInput),
            revision: revision,
            evaluatedInput: evaluatedInput
        )
    }
}

/// Flow-facing adapter: resolves flow `RuleInput` (`factsResolved == false`) to match-ready input, then runs `RuleCore`.
public final class FlowRuleClassifier: Sendable {
    private let resolver: any FlowFactsResolving
    private let core: RuleCore

    public init(
        resolver: some FlowFactsResolving,
        engine: RuleEngine,
        revision: RuleRevision? = nil
    ) {
        self.resolver = resolver
        core = RuleCore(engine: engine, revision: revision)
    }

    public init(resolver: some FlowFactsResolving, core: RuleCore) {
        self.resolver = resolver
        self.core = core
    }

    public func classify(_ input: RuleInput) -> RouteDecision {
        classifyWithFacts(input).decision
    }

    public func classifyWithFacts(_ input: RuleInput) -> RuleClassification {
        let resolved = resolver.resolve(input)
        return core.classify(resolved)
    }
}
