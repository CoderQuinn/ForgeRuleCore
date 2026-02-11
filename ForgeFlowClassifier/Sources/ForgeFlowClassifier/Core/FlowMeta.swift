//
//  FlowMeta.swift
//  ForgeFlowClassifier
//
//  Created by MagicianQuinn on 2026/2/11.
//

import ForgeBase
import Foundation

public struct FlowMeta: Sendable {
    public let originalIP: FBIPv4
    public let resolvedIP: FBIPv4
    public let domain: String?
    public let port: UInt16
    public let proto: TransportProtocol

    public let fakeIPStore: FakeIPStore?

    public init(originalIP: FBIPv4, resolvedIP: FBIPv4, domain: String?, port: UInt16, proto: TransportProtocol, fakeIPStore: FakeIPStore?) {
        self.originalIP = originalIP
        self.resolvedIP = resolvedIP
        self.domain = domain
        self.port = port
        self.proto = proto
        self.fakeIPStore = fakeIPStore
    }

    public var effectiveDomain: String? {
        if let domain = domain {
            return normalizeDomain(domain)
        }

        guard let store = fakeIPStore, let d = store.reverseLookup(resolvedIP) else {
            return nil
        }

        return normalizeDomain(d)
    }
}
