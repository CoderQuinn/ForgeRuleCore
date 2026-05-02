//
//  DNSRoutingConfig.swift
//  ForgeRuleCore
//
//  Decodable subset of Xray `dns` for Echo Forge / DNS service.
//  DoH transport, fallback chains, and `expectIPs` validation stay outside this package.
//

import Foundation

public struct DNSRoutingConfigJSON: Codable, Sendable {
    public var dns: DNSRoutingSectionJSON?
}

public struct DNSRoutingSectionJSON: Codable, Sendable {
    /// Static overrides (`dns.google` → `8.8.8.8`, `geosite:…` → `127.0.0.1`, etc.).
    public var hosts: [String: String]?
    public var servers: [DNSServerRefJSON]?
}

public enum DNSServerRefJSON: Codable, Sendable {
    case plain(String)
    case advanced(DNSServerObjectJSON)

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            self = .plain(s)
            return
        }
        self = .advanced(try DNSServerObjectJSON(from: decoder))
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case let .plain(s):
            var c = encoder.singleValueContainer()
            try c.encode(s)
        case let .advanced(o):
            try o.encode(to: encoder)
        }
    }
}

public struct DNSServerObjectJSON: Codable, Sendable {
    public var address: String?
    public var port: Int?
    public var domains: [String]?
    public var expectIPs: [String]?
    public var skipFallback: Bool?
}
