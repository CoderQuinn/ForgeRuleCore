//
//  FlowFactsResolver.swift
//  ForgeRuleCore
//
//  Created by MagicianQuinn on 2026/3/5.
//

import ForgeBase
import Foundation

public protocol FakeIPStore: Sendable {
    func reverseLookup(_ ip: FBIPv4) -> String?
}

public protocol FlowFactsResolving: Sendable {
    func resolve(_ input: RuleInput) -> RuleInput
}

public final class FlowFactsResolver: FlowFactsResolving {
    private let fakeIPStore: FakeIPStore?

    public init(fakeIPStore: FakeIPStore?) {
        self.fakeIPStore = fakeIPStore
    }

    public func resolve(_ input: RuleInput) -> RuleInput {
        if let d0 = input.domain.map(normalizeDomain), !d0.isEmpty {
            return RuleInput(
                originalIP: input.originalIP,
                resolvedIP: input.resolvedIP,
                domain: d0,
                domainSource: input.domainSource ?? .flowContext,
                domainRevision: input.domainRevision,
                port: input.port,
                proto: input.proto,
                factsResolved: true
            )
        }

        let d1 = fakeIPStore?.reverseLookup(input.resolvedIP).map(normalizeDomain)
        let eff = d1.flatMap { $0.isEmpty ? nil : $0 }

        return RuleInput(
            originalIP: input.originalIP,
            resolvedIP: input.resolvedIP,
            domain: eff,
            domainSource: eff == nil ? nil : .fakeIP,
            domainRevision: nil,
            port: input.port,
            proto: input.proto,
            factsResolved: true
        )
    }
}
