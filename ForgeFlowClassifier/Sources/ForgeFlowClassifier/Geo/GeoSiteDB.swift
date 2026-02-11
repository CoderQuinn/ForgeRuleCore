//
//  GeoSiteDB.swift
//  ForgeFlowClassifier
//
//  Created by MagicianQuinn on 2026/2/11.
//

import Foundation

public final class GeoSiteDB: Sendable {
    public struct SiteIndex: Sendable {
        public let full: DomainExactSet
        public let suffix: DomainSuffixTrie
        public let keyword: DomainKeywordMatcher
    }

    private let sites: [String: SiteIndex]

    public init(jsonURL: URL) throws {
        let data = try Data(contentsOf: jsonURL)
        let decoded = try JSONDecoder().decode(GeoSiteListJSON.self, from: data)

        var map: [String: SiteIndex] = [:]
        map.reserveCapacity(decoded.geosites.count)

        for s in decoded.geosites {
            let key = normalizeDomain(s.country_code)

            var full: [String] = []
            var suffix: [String] = []
            var keyword: [String] = []

            full.reserveCapacity(s.domains.count / 4)
            suffix.reserveCapacity(s.domains.count / 2)
            keyword.reserveCapacity(s.domains.count / 4)

            for d in s.domains {
                let v = normalizeDomain(d.value)
                guard !v.isEmpty else { continue }

                switch d.type {
                case "full":
                    full.append(v)
                case "domain":
                    suffix.append(v)
                case "plain":
                    keyword.append(v)
                case "regex":
                    #if DEBUG
                        print("GeoSite regex ignored:", v)
                    #endif
                    continue
                default:
                    continue
                }
            }

            map[key] = SiteIndex(
                full: DomainExactSet(full),
                suffix: DomainSuffixTrie(suffix),
                keyword: DomainKeywordMatcher(keyword)
            )
        }

        sites = map
    }

    public func contains(site: String, domain: String) -> Bool {
        let siteKey = normalizeDomain(site)
        guard let idx = sites[siteKey] else { return false }

        // full → suffix → keyword
        if idx.full.contains(domain) { return true }
        if idx.suffix.containsSuffix(of: domain) { return true }
        if idx.keyword.containsKeyword(in: domain) { return true }

        return false
    }
}
