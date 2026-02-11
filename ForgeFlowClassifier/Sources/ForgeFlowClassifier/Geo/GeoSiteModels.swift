//
//  GeoSiteModels.swift
//  ForgeFlowClassifier
//
//  Created by MagicianQuinn on 2026/2/11.
//

import Foundation

public struct GeoSiteListJSON: Codable, Sendable {
    public let geosites: [GeoSiteJSON]
}

public struct GeoSiteJSON: Codable, Sendable {
    public let country_code: String
    public let domains: [DomainJSON]
}

public struct DomainJSON: Codable, Sendable {
    public let type: String
    public let value: String
    public let attributes: [String: JSONValue]?
}

public enum JSONValue: Codable, Sendable, Equatable {
    case bool(Bool)
    case int(Int64)
    case string(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let b = try? container.decode(Bool.self) {
            self = .bool(b)
            return
        }

        if let i = try? container.decode(Int64.self) {
            self = .int(i)
            return
        }

        if let s = try? container.decode(String.self) {
            self = .string(s)
            return
        }

        throw DecodingError.typeMismatch(
            JSONValue.self,
            .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSONValue")
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .bool(b): try container.encode(b)
        case let .int(i): try container.encode(i)
        case let .string(s): try container.encode(s)
        }
    }
}
