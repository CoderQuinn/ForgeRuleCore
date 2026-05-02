//
//  ForgeRuleCoreBundle.swift
//  ForgeRuleCore
//
//  Created by MagicianQuinn on 2026/2/11.
//

import Foundation

public enum ForgeRuleCoreBundleError: Error, Sendable, Equatable {
    /// No shared container URL for this App Group (invalid id, entitlements, or simulator setup).
    case invalidAppGroupIdentifier(String)
}

extension ForgeRuleCoreBundleError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .invalidAppGroupIdentifier(id):
            return "No App Group container URL for identifier: \(id)"
        }
    }
}

public enum ForgeRuleCoreBundle {
    public static func makeRuleCore(
        appGroup: String,
        rules: [Rule]
    ) throws -> RuleCore {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            throw ForgeRuleCoreBundleError.invalidAppGroupIdentifier(appGroup)
        }
        let geositeURL = base.appendingPathComponent("geosite.json")
        let geoipURL = base.appendingPathComponent("geoip.mmdb")

        let geosite = try GeoSiteDB(jsonURL: geositeURL)
        let lookup = try MMDBCountryLookup(url: geoipURL)
        let geoipKeys: [String] = rules.flatMap { $0.condition.collectGeoipKeys() }
        let geoip = GeoIPDB(lookup: lookup, preheatKeys: geoipKeys)

        let engine = RuleEngine(rules: rules, geosite: geosite, geoip: geoip)

        return RuleCore(engine: engine)
    }

    public static func makeFlowClassifier(
        appGroup: String,
        rules: [Rule],
        fakeIPStore: FakeIPStore? = nil
    ) throws -> FlowRuleClassifier {
        let core = try makeRuleCore(appGroup: appGroup, rules: rules)
        let resolver = FlowFactsResolver(fakeIPStore: fakeIPStore)
        return FlowRuleClassifier(resolver: resolver, core: core)
    }
}
