//
//  ForgeFlowClassifierBundle.swift
//  ForgeFlowClassifier
//
//  Created by MagicianQuinn on 2026/2/11.
//

import Foundation

public enum ForgeFlowClassifierBundle {
    public static func make(
        appGroup: String,
        rules: [Rule]
    ) throws -> ForgeFlowClassifier {
        let base = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)!
        // TODO: temp solution
        let geositeURL = base.appendingPathComponent("geosite.json")
        let geoipURL = base.appendingPathComponent("geoip.mmdb")

        let geosite = try GeoSiteDB(jsonURL: geositeURL)
        let lookup = try MMDBCountryLookup(url: geoipURL)
        let geoip = GeoIPDB(lookup: lookup)

        let engine = RuleEngine(
            rules: rules,
            geosite: geosite,
            geoip: geoip
        )

        return ForgeFlowClassifier(engine: engine)
    }
}
