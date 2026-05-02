//
//  GeoIPDB.swift
//  ForgeRuleCore
//
//  Created by MagicianQuinn on 2026/2/11.
//

import ForgeBase
import Foundation

public final class GeoIPDB: Sendable {
    private let lookup: CountryLookup
    private let parsedKeyCache: [String: CountryCode?]

    public init(lookup: CountryLookup, preheatKeys: [String] = []) {
        self.lookup = lookup

        var cache: [String: CountryCode?] = [:]
        cache.reserveCapacity(preheatKeys.count)
        for raw in preheatKeys {
            let norm = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !norm.isEmpty else { continue }
            let positive = norm.hasPrefix("!")
                ? String(norm.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                : norm
            guard !positive.isEmpty else { continue }
            if cache[positive] == nil {
                cache[positive] = CountryCode(positive)
            }
        }
        parsedKeyCache = cache
    }

    @inline(__always)
    private func parseKey(_ key: String) -> CountryCode? {
        let norm = key.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let cached = parsedKeyCache[norm] { return cached }
        return CountryCode(norm)
    }

    public func match(key: String, ip: FBIPv4) -> Bool {
        let norm = key.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !norm.isEmpty else { return false }
        if norm.hasPrefix("!") {
            let inner = String(norm.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !inner.isEmpty else { return false }
            return !matchPositive(key: inner, ip: ip)
        }
        return matchPositive(key: norm, ip: ip)
    }

    private func matchPositive(key: String, ip: FBIPv4) -> Bool {
        guard let expected = parseKey(key) else { return false }
        guard let got = lookup.lookupCountryCode(ip: ip) else { return false }
        return got == expected
    }
}
