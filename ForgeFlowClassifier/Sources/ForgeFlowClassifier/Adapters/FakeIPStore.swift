//
//  FakeIPStore.swift
//  ForgeFlowClassifier
//
//  Created by MagicianQuinn on 2026/2/11.
//

import ForgeBase
import Foundation

public protocol FakeIPStore: Sendable {
    func reverseLookup(_ ip: FBIPv4) -> String?
}
