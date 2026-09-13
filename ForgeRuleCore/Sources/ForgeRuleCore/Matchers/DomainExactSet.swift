//
//  DomainExactSet.swift
//  ForgeRuleCore
//
//  Created by MagicianQuinn on 2026/2/11.
//

import Foundation

public struct DomainExactSet: Sendable {
    private let set: Set<String>

    public init(_ items: [String]) {
        var set = Set<String>()
        set.reserveCapacity(items.count)
        for x in items {
            let domain = normalizeDomain(x)
            if !domain.isEmpty {
                set.insert(domain)
            }
        }
        self.set = set
    }

    @inline(__always)
    public func contains(_ domain: String) -> Bool {
        containsNormalized(normalizeDomain(domain))
    }

    /// Internal fast path for a domain already passed through normalizeDomain.
    @inline(__always)
    func containsNormalized(_ domain: String) -> Bool {
        set.contains(domain)
    }
}
