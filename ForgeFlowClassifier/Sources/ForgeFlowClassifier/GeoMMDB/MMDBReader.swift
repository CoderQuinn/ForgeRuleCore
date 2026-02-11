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
    private static let queue = DispatchQueue(label: "ForgeMMDB.reader")

    private let path: String

    public init(url: URL) throws {
        path = url.path
        try Self.queue.sync {
            let status = forge_mmdb_open(path)
            guard status == 0 else { throw MMDBOpenError(status: status) }
        }
    }

    deinit {
        Self.queue.sync {
            forge_mmdb_close()
        }
    }

    /// hot reload support
    public func reopen() throws {
        try Self.queue.sync {
            forge_mmdb_close()
            let status = forge_mmdb_open(path)
            guard status == 0 else { throw MMDBOpenError(status: status) }
        }
    }

    @inline(__always)
    public func countryCode(of ip: FBIPv4) -> CountryCode? {
        let packed = Self.queue.sync {
            forge_mmdb_country_ipv4(ip.beValue)
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
