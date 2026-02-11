//
//  GeoIPDB.swift
//  ForgeFlowClassifier
//
//  Created by MagicianQuinn on 2026/2/11.
//

import ForgeBase
import Foundation

public final class GeoIPDB: Sendable {
    private let lookup: CountryLookup

    public init(lookup: CountryLookup) {
        self.lookup = lookup
    }

    public func match(key: String, ip: FBIPv4) -> Bool {
        guard let got = lookup.lookupKey(ip: ip) else {
            return false
        }
        return got.caseInsensitiveCompare(key) == .orderedSame
    }
}
