//
//  MMDBCountryLookup.swift
//  ForgeFlowClassifier
//
//  Created by MagicianQuinn on 2026/2/11.
//

import ForgeBase
import Foundation

public final class MMDBCountryLookup: CountryLookup {
    private let reader: MMDBReader

    public init(url: URL) throws {
        reader = try MMDBReader(url: url)
    }

    public func lookupKey(ip: FBIPv4) -> String? {
        reader.countryCode(of: ip)?.string.lowercased()
    }
}
