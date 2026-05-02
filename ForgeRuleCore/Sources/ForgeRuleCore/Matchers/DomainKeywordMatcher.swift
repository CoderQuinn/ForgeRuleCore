//
//  DomainKeywordMatcher.swift
//  ForgeRuleCore
//
//  Created by MagicianQuinn on 2026/2/11.
//

import Foundation

public struct DomainKeywordMatcher: Sendable {
    private let keywords: [String]

    public init(_ items: [String]) {
        keywords = items
            .map(normalizeDomain)
            .filter { !$0.isEmpty }
    }

    @inline(__always)
    public func containsKeyword(in domain: String) -> Bool {
        for key in keywords {
            if domain.contains(key) {
                return true
            }
        }
        return false
    }
}
