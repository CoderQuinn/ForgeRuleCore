//
//  MMDBReader.swift
//  ForgeMMDB
//
//  Created by MagicianQuinn on 2026/2/6.
//

import Dispatch
import ForgeBase
import Foundation
import GeoMMDBBridge

public final class MMDBReader: GeoIPProvider, @unchecked Sendable {
    private let queue = DispatchQueue(label: "ForgeRuleCore.MMDBReader")
    private let handle: UnsafeMutableRawPointer

    /// Opens an independently owned, immutable database handle.
    public init(url: URL) throws {
        var status: Int32 = 0
        guard let handle = forge_mmdb_open(url.path, &status) else {
            throw MMDBOpenError(status: status)
        }
        self.handle = handle
    }

    deinit {
        queue.sync {
            forge_mmdb_close(handle)
        }
    }

    @inline(__always)
    public func countryCode(of ip: FBIPv4) -> CountryCode? {
        let packed = queue.sync {
            forge_mmdb_country_ipv4(handle, ip.beValue)
        }
        return CountryCode(packedBE: packed)
    }
}

public struct MMDBOpenError: LocalizedError, Sendable {
    public let status: Int32

    public var errorDescription: String? {
        "MMDB open failed: status=\(status)"
    }
}
