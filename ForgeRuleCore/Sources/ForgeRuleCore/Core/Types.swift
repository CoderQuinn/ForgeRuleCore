//
//  Types.swift
//  ForgeRuleCore
//
//  Created by MagicianQuinn on 2026/2/11.
//

import Foundation

@inline(__always)
public func normalizeDomain(_ s: String) -> String {
    s.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". \t\r\n"))
}

/// Lowercase + trim whitespace. Used for `geoip:` keys at rule build time (e.g. `cn`, `!cn`).
@inline(__always)
public func normalizeGeoipKey(_ s: String) -> String {
    s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
}
