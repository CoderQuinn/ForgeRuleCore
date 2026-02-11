//
//  DomainSuffixTrie.swift
//  ForgeFlowClassifier
//
//  Created by MagicianQuinn on 2026/2/11.
//

import Foundation

public struct DomainSuffixTrie: Sendable {
    private struct Node: Sendable {
        var children: [Substring: Int] = [:]
        var isEnd: Bool = false // suffix
    }

    // root
    private var nodes: [Node] = [Node()]

    public init(_ suffixes: [String]) {
        var tire = DomainSuffixTrie()
        for s in suffixes {
            tire.insertSuffix(s)
        }
        self = tire
    }

    private init() {}

    private mutating func insertSuffix(_ raw: String) {
        let s = normalizeDomain(raw)
        guard !s.isEmpty else {
            return
        }

        let labels = s.split(separator: ".", omittingEmptySubsequences: true)
        guard !labels.isEmpty else {
            return
        }

        var cur = 0
        for label in labels.reversed() {
            if let next = nodes[cur].children[label] {
                cur = next
            } else {
                let idx = nodes.count
                nodes.append(Node())
                nodes[cur].children[label] = idx
                cur = idx
            }
        }
        nodes[cur].isEnd = true
    }

    @inline(__always)
    public func containsSuffix(of domain: String) -> Bool {
        let labels = domain.split(separator: ".", omittingEmptySubsequences: true)
        guard !labels.isEmpty else { return false }

        var cur = 0
        for (i, label) in labels.reversed().enumerated() {
            guard let next = nodes[cur].children[label] else {
                return false
            }
            cur = next
            if nodes[cur].isEnd && i == labels.count - 1 {
                return true
            }
        }

        return nodes[cur].isEnd
    }
}
