//
//  CountryLookup.swift
//  ForgeRuleCore
//
//  Created by MagicianQuinn on 2026/2/11.
//

import ForgeBase
import Foundation

public protocol CountryLookup: Sendable {
    func lookupCountryCode(ip: FBIPv4) -> CountryCode?
}
