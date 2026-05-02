//
//  RuleEngine.swift
//  ForgeRuleCore
//
//  Created by MagicianQuinn on 2026/2/11.
//

import Foundation

public final class RuleEngine: Sendable {
    private let rules: [Rule]
    private let geosite: GeoSiteDB
    private let geoip: GeoIPDB

    public init(
        rules: [Rule],
        geosite: GeoSiteDB,
        geoip: GeoIPDB
    ) {
        self.rules = rules
        self.geosite = geosite
        self.geoip = geoip
    }

    public func evaluate(_ input: RuleInput) -> RuleAction {
        let input = RuleInput(
            originalIP: input.originalIP,
            resolvedIP: input.resolvedIP,
            domain: input.domain.flatMap { dom in
                let n = normalizeDomain(dom)
                return n.isEmpty ? nil : n
            },
            port: input.port,
            proto: input.proto,
            factsResolved: input.factsResolved
        )

        var finalAction: RuleAction = .direct

        for r in rules {
            if matches(r.condition, input: input) {
                if case .any = r.condition {
                    finalAction = r.action
                    continue
                }
                return r.action
            }
        }

        return finalAction
    }

    private func matches(_ condition: RuleCondition, input: RuleInput) -> Bool {
        let d = input.domain

        switch condition {
        case let .domainFull(x):
            guard let d else { return false }
            return d == x

        case let .domainSuffix(x):
            guard let d else { return false }
            return d == x || d.hasSuffix("." + x)

        case let .domainKeyword(x):
            guard let d else { return false }
            return d.contains(x)

        case let .geosite(name):
            guard let d else { return false }
            return geosite.contains(site: name, domain: d)

        case let .geoip(key):
            return geoip.match(key: key, ip: input.resolvedIP)

        case .any:
            return true
        }
    }
}
