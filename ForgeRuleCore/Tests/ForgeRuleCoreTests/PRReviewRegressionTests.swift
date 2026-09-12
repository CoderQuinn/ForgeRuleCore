@testable import ForgeRuleCore
import ForgeBase
import Foundation
import Testing

private struct ReviewMissingCountry: CountryLookup {
    func lookupCountryCode(ip: FBIPv4) -> CountryCode? { nil }
}

// C-FIELD-UNKNOWN C-GEOIP-INVALID: reproduced at the actual PR #1 head.
@Test func review_unknown_port_must_not_broaden_a_direct_rule() throws {
    let json = #"{"outboundTag":"direct","domain":["full:example.com"],"port":"443"}"#
    let field = try JSONDecoder().decode(FieldRuleJSON.self, from: Data(json.utf8))
    let result = FieldRoutingRuleFactory.compile(fields: [field])
    #expect(!result.isSuccessful)
    #expect(result.rules.isEmpty)
}

@Test func review_malformed_geoip_negation_must_not_match() {
    let db = GeoIPDB(lookup: ReviewMissingCountry())
    #expect(!db.match(key: "!bogus", ip: FBIPv4(beValue: 1)))
}
