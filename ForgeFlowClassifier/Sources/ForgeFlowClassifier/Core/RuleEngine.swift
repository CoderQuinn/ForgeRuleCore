//
//  RuleEngine.swift
//  ForgeFlowClassifier
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

    public func evaluate(_ meta: FlowMeta) -> RuleAction {
        let d = meta.effectiveDomain
        var finalAction: RuleAction = .direct

        for r in rules {
            switch r.condition {
            case let .domainFull(x):
                if let d, d == normalizeDomain(x) { return r.action }

            case let .domainSuffix(x):
                if let d, d.hasSuffix(normalizeDomain(x)) { return r.action }

            case let .domainKeyword(x):
                if let d, d.contains(normalizeDomain(x)) { return r.action }

            case let .geosite(name):
                if let d, geosite.contains(site: name, domain: d) { return r.action }

            case let .geoip(key):
                if geoip.match(key: key, ip: meta.resolvedIP) { return r.action }

            case .any:
                finalAction = r.action
                continue
            }
        }

        return finalAction
    }
}
