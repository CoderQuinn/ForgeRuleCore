//
//  CountryLookup.swift
//  ForgeFlowClassifier
//
//  Created by MagicianQuinn on 2026/2/11.
//

import ForgeBase
import Foundation

public protocol CountryLookup: Sendable {
    ///
    /// - "cn", "us", "telegram"
    func lookupKey(ip: FBIPv4) -> String?
}
