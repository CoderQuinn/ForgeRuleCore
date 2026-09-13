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
            guard Self.isValidKey(norm) else { continue }
            let positive = norm.hasPrefix("!")
                ? String(norm.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                : norm
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
        // Validate before negation: an invalid positive condition must never
        // turn into a match. Valid lookup-miss negation keeps legacy semantics.
        guard Self.isValidKey(norm) else { return false }
        if norm.hasPrefix("!") {
            let inner = String(norm.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            return !matchPositive(key: inner, ip: ip)
        }
        return matchPositive(key: norm, ip: ip)
    }

    /// Two ASCII letters with at most one leading negation; not an ISO registry
    /// check. Shared with the field compiler so decoded and native rows agree.
    static func isValidKey(_ raw: String) -> Bool {
        let norm = normalizeGeoipKey(raw)
        let positive = norm.hasPrefix("!") ? normalizeGeoipKey(String(norm.dropFirst())) : norm
        let bytes = positive.utf8
        return bytes.count == 2 && bytes.allSatisfy { $0 >= 97 && $0 <= 122 }
    }

    private func matchPositive(key: String, ip: FBIPv4) -> Bool {
        guard let expected = parseKey(key) else { return false }
        guard let got = lookup.lookupCountryCode(ip: ip) else { return false }
        return got == expected
    }
}
