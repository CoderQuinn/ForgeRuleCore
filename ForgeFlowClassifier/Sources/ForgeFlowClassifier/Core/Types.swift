//
//  Types.swift
//  ForgeFlowClassifier
//
//  Created by MagicianQuinn on 2026/2/11.
//

import Foundation

@inline(__always)
public func normalizeDomain(_ s: String) -> String {
    s.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". \t\r\n"))
}
