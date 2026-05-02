//
//  CountryCode.swift
//  ForgeMMDB
//
//  Created by MagicianQuinn on 2026/2/5.
//

public struct CountryCode: Hashable, Sendable {
    public let rawValue: UInt16

    @inline(__always)
    public init?(packedBE: UInt16) {
        guard packedBE != 0 else { return nil }
        rawValue = packedBE
    }

    public var string: String {
        let a = UInt8(rawValue >> 8)
        let b = UInt8(rawValue & 0xFF)
        return String(bytes: [a, b], encoding: .ascii) ?? "unknown"
    }
}

public extension CountryCode {
    static let cn: CountryCode = {
        guard let code = CountryCode(packedBE: 0x434E) else {
            fatalError("Failed to initialize CountryCode.cn from packed value 0x434E")
        }
        return code
    }()

    static let us: CountryCode = {
        guard let code = CountryCode(packedBE: 0x5553) else {
            fatalError("Failed to initialize CountryCode.us from packed value 0x5553")
        }
        return code
    }()

    static let jp: CountryCode = {
        guard let code = CountryCode(packedBE: 0x4A50) else {
            fatalError("Failed to initialize CountryCode.jp from packed value 0x4A50")
        }
        return code
    }()

    static let kr: CountryCode = {
        guard let code = CountryCode(packedBE: 0x4B52) else {
            fatalError("Failed to initialize CountryCode.kr from packed value 0x4B52")
        }
        return code
    }()

    static let hk: CountryCode = {
        guard let code = CountryCode(packedBE: 0x484B) else {
            fatalError("Failed to initialize CountryCode.hk from packed value 0x484B")
        }
        return code
    }()

    static let tw: CountryCode = {
        guard let code = CountryCode(packedBE: 0x5457) else {
            fatalError("Failed to initialize CountryCode.tw from packed value 0x5457")
        }
        return code
    }()

    static let sg: CountryCode = {
        guard let code = CountryCode(packedBE: 0x5347) else {
            fatalError("Failed to initialize CountryCode.sg from packed value 0x5347")
        }
        return code
    }()

    @inline(__always)
    init?(_ iso2: (UInt8, UInt8)) {
        let v = (UInt16(iso2.0) << 8) | UInt16(iso2.1)
        self.init(packedBE: v)
    }

    @inline(__always)
    private static func upperASCII(_ c: UInt8) -> UInt8 {
        (c >= 97 && c <= 122) ? (c - 32) : c
    }

    @inline(__always)
    init?(_ string: String) {
        guard string.utf8.count == 2 else { return nil }
        let u = Array(string.utf8)
        self.init((Self.upperASCII(u[0]), Self.upperASCII(u[1])))
    }
}
