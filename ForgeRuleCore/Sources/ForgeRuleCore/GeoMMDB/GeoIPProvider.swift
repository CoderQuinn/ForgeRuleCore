//
//  GeoIPProvider.swift
//  ForgeMMDB
//
//  Created by MagicianQuinn on 2026/2/6.
//

import ForgeBase

public protocol GeoIPProvider: Sendable {
    /// Returns alpha-2 country code if found. nil if not found.
    func countryCode(of ip: FBIPv4) -> CountryCode?
}

public extension GeoIPProvider {
    func isCN(_ ip: FBIPv4) -> Bool { countryCode(of: ip) == .cn }
}
