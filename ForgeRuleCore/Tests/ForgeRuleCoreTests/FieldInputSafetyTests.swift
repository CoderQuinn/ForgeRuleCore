@testable import ForgeRuleCore
import ForgeBase
import Foundation
import Testing

// C-FIELD-UNKNOWN C-FIELD-ATOMIC C-GEOIP-INVALID; preserves C-GEOIP-MISS.

private struct SafetyCountryLookup: CountryLookup {
    let code: CountryCode?

    func lookupCountryCode(ip: FBIPv4) -> CountryCode? { code }
}

@Test(arguments: ["port", "source", "protocol", "inboundTag", "futureConstraint"])
func field_unknown_constraints_are_rejected(key: String) throws {
    let json = """
    {"outboundTag":"direct","domain":["full:example.com"],"\(key)":null}
    """
    let field = try JSONDecoder().decode(FieldRuleJSON.self, from: Data(json.utf8))
    let result = FieldRoutingRuleFactory.compile(fields: [field])
    #expect(!result.isSuccessful)
    #expect(result.rules.isEmpty)
    #expect(result.diagnostics == [FieldRoutingDiagnostic(fieldIndex: 0, reason: .unsupportedField)])
    #expect(field.unsupportedKeys == [key])
}

@Test func field_unknown_constraints_cannot_be_laundered_by_encoding() throws {
    let json = #"{"outboundTag":"direct","domain":["example.com"],"z":{"secret":"canary"},"a":443}"#
    var field = try JSONDecoder().decode(FieldRuleJSON.self, from: Data(json.utf8))
    #expect(field.unsupportedKeys == ["a", "z"])
    field.domain = ["full:safe.example"]
    #expect(throws: EncodingError.self) { try JSONEncoder().encode(field) }
    #expect(!FieldRoutingRuleFactory.compile(fields: [field]).isSuccessful)
}

@Test func field_known_properties_round_trip_and_preserve_type_errors() throws {
    let field = FieldRuleJSON(type: "field", outboundTag: "proxy", domain: ["full:example.com"], ip: [], network: "")
    let decoded = try JSONDecoder().decode(FieldRuleJSON.self, from: JSONEncoder().encode(field))
    #expect(decoded.type == field.type)
    #expect(decoded.outboundTag == field.outboundTag)
    #expect(decoded.domain == field.domain)
    #expect(decoded.ip == field.ip)
    #expect(decoded.network == field.network)
    #expect(decoded.unsupportedKeys.isEmpty)
    let empty = try JSONDecoder().decode(FieldRuleJSON.self, from: JSONEncoder().encode(FieldRuleJSON()))
    #expect(empty.domain == nil)
    #expect(empty.unsupportedKeys.isEmpty)
    for json in [#"{"domain":443}"#, #"{"ip":[1]}"#, #"{"network":true}"#, #"{"outboundTag":{}}"#, #"{"type":[]}"#, "[]"] {
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(FieldRuleJSON.self, from: Data(json.utf8)) }
    }
}

@Test func field_validated_compilation_never_returns_partial_rules() throws {
    let good = FieldRuleJSON(outboundTag: "proxy", domain: ["full:example.com"])
    let bad = FieldRuleJSON(outboundTag: "direct", ip: ["geoip:!bogus"])
    let unknown = try JSONDecoder().decode(FieldRuleJSON.self, from: Data(#"{"port":443}"#.utf8))
    let diagnostics = [
        FieldRoutingDiagnostic(fieldIndex: 1, reason: .invalidIPEntry),
        FieldRoutingDiagnostic(fieldIndex: 3, reason: .unsupportedField),
    ]
    do {
        _ = try FieldRoutingRuleFactory.compileValidated(fields: [good, bad, good, unknown])
        Issue.record("Expected all-or-nothing validation to throw")
    } catch let error as FieldRoutingValidationError {
        #expect(error.diagnostics == diagnostics)
    }
    let accepted = try FieldRoutingRuleFactory.compileValidated(fields: [good, good])
    #expect(accepted == FieldRoutingRuleFactory.compile(fields: [good, good]).rules)
    #expect(accepted.count == 2)
    #expect(try FieldRoutingRuleFactory.compileValidated(fields: []).isEmpty)
}

@Test(arguments: ["cn", " CN ", "!cn", " ! CN ", "xx", "!xx"])
func geoip_valid_keys_keep_legacy_lookup_miss_semantics(key: String) throws {
    let field = FieldRuleJSON(outboundTag: "direct", ip: ["geoip:\(key)"])
    #expect(try FieldRoutingRuleFactory.compileValidated(fields: [field]).count == 1)
    let db = GeoIPDB(lookup: SafetyCountryLookup(code: nil), preheatKeys: [key])
    #expect(db.match(key: key, ip: FBIPv4(beValue: 1)) == key.contains("!"))
}

@Test(arguments: ["!bogus", "!!cn", "!12", "!é", "12", "!", " "])
func field_malformed_geoip_is_rejected(key: String) {
    let field = FieldRuleJSON(type: "field", outboundTag: "direct", domain: nil, ip: ["geoip:\(key)"], network: nil)
    let result = FieldRoutingRuleFactory.compile(fields: [field])
    #expect(result.rules.isEmpty)
    #expect(result.diagnostics == [FieldRoutingDiagnostic(fieldIndex: 0, reason: .invalidIPEntry)])
}

@Test(arguments: ["!bogus", "!!cn", "!12", "!é", "!", " "])
func geoip_malformed_negation_never_matches(key: String) {
    for code in [CountryCode.cn, nil] {
        for preheat in [[], [key]] {
            let db = GeoIPDB(lookup: SafetyCountryLookup(code: code), preheatKeys: preheat)
            #expect(!db.match(key: key, ip: FBIPv4(beValue: 1)))
        }
    }
}
