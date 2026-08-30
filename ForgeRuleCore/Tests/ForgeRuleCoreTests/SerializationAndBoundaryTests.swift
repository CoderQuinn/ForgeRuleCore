@testable import ForgeRuleCore
import ForgeBase
import Foundation
import GeoMMDBBridge
import Testing

private struct FixedGeoIPProvider: GeoIPProvider {
    let code: CountryCode?

    func countryCode(of _: FBIPv4) -> CountryCode? {
        code
    }
}

private struct IdentityResolver: FlowFactsResolving {
    func resolve(_ input: RuleInput) -> RuleInput {
        input
    }
}

private func temporaryGeoSiteFile(_ json: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ForgeRuleCore-boundary-\(UUID().uuidString).json")
    try Data(json.utf8).write(to: url)
    return url
}

@Test func dns_server_references_encode_plain_and_advanced_shapes() throws {
    let values: [DNSServerRefJSON] = [
        .plain("8.8.8.8"),
        .advanced(
            DNSServerObjectJSON(
                address: "https://1.1.1.1/dns-query",
                port: 443,
                domains: ["geosite:geolocation-!cn"],
                expectIPs: ["geoip:!cn"],
                skipFallback: true
            )
        ),
    ]

    let encoded = try JSONEncoder().encode(values)
    let decoded = try JSONDecoder().decode([DNSServerRefJSON].self, from: encoded)

    guard case let .plain(address) = decoded[0] else {
        Issue.record("Expected a plain DNS server reference")
        return
    }
    #expect(address == "8.8.8.8")

    guard case let .advanced(server) = decoded[1] else {
        Issue.record("Expected an advanced DNS server reference")
        return
    }
    #expect(server.address == "https://1.1.1.1/dns-query")
    #expect(server.port == 443)
    #expect(server.domains == ["geosite:geolocation-!cn"])
    #expect(server.expectIPs == ["geoip:!cn"])
    #expect(server.skipFallback == true)
}

@Test func json_value_roundtrips_every_supported_scalar() throws {
    let source = Data(#"{"flag":true,"count":7,"label":"stable"}"#.utf8)
    let decoded = try JSONDecoder().decode([String: JSONValue].self, from: source)

    #expect(decoded == [
        "flag": .bool(true),
        "count": .int(7),
        "label": .string("stable"),
    ])

    let encoded = try JSONEncoder().encode(decoded)
    let roundTrip = try JSONDecoder().decode([String: JSONValue].self, from: encoded)
    #expect(roundTrip == decoded)
}

@Test func json_value_rejects_unsupported_json_kinds() {
    for json in ["[]", "null", "1.5", "{}"] {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        }
    }
}

@Test func country_code_constants_and_string_projection_are_stable() throws {
    let cases: [(CountryCode, String)] = [
        (.cn, "CN"),
        (.us, "US"),
        (.jp, "JP"),
        (.kr, "KR"),
        (.hk, "HK"),
        (.tw, "TW"),
        (.sg, "SG"),
    ]

    for (code, expected) in cases {
        #expect(code.string == expected)
        #expect(CountryCode(expected.lowercased()) == code)
    }

    let nonASCII = try #require(CountryCode(packedBE: 0xFFFF))
    #expect(nonASCII.string == "unknown")
    #expect(CountryCode(packedBE: 0) == nil)
    #expect(CountryCode("USA") == nil)
}

@Test func geoip_provider_cn_projection_reports_matches_and_misses() {
    let address = FBIPv4(a: 1, b: 1, c: 1, d: 1)

    #expect(FixedGeoIPProvider(code: .cn).isCN(address))
    #expect(!FixedGeoIPProvider(code: .us).isCN(address))
    #expect(!FixedGeoIPProvider(code: nil).isCN(address))
}

@Test func mmdb_bridge_rejects_null_arguments_and_keeps_null_operations_safe() {
    #expect(forge_mmdb_open(nil, nil) == nil)

    var status: Int32 = 0
    #expect(forge_mmdb_open(nil, &status) == nil)
    #expect(status == Int32(FORGE_MMDB_STATUS_INVALID_ARGUMENT))

    forge_mmdb_close(nil)
    #expect(forge_mmdb_country_ipv4(nil, 0) == 0)
}

@Test func localized_errors_preserve_actionable_context() {
    let errors: [(any LocalizedError, String)] = [
        (
            ForgeRuleCoreBundleError.invalidAppGroupIdentifier("group.invalid"),
            "No App Group container URL for identifier: group.invalid"
        ),
        (
            ForgeRuleCoreBundleError.missingResource(resource: .geosite, path: "/Rules/geosite.json"),
            "Missing geosite.json at path: /Rules/geosite.json"
        ),
        (
            ForgeRuleCoreBundleError.invalidResource(
                resource: .geosite,
                path: "/Rules/geosite.json",
                failure: .unreadableOrMalformed
            ),
            "Unreadable or malformed geosite.json at path: /Rules/geosite.json"
        ),
        (
            ForgeRuleCoreBundleError.invalidResource(
                resource: .geoIP,
                path: "/Rules/geoip.mmdb",
                failure: .mmdbOpenFailed(status: 7)
            ),
            "Invalid geoip.mmdb at path: /Rules/geoip.mmdb (MMDB status=7)"
        ),
        (MMDBOpenError(status: 9), "MMDB open failed: status=9"),
    ]

    for (error, expected) in errors {
        #expect(error.errorDescription == expected)
    }
}

@Test func public_bundle_entry_points_reject_blank_app_group() {
    let blank = "  "

    #expect(throws: ForgeRuleCoreBundleError.self) {
        _ = try ForgeRuleCoreBundle.makeRuleCore(appGroup: blank, rules: [])
    }
    #expect(throws: ForgeRuleCoreBundleError.self) {
        _ = try ForgeRuleCoreBundle.makeFlowClassifier(appGroup: blank, rules: [])
    }
}

@Test func classifier_accepts_preassembled_core_and_maps_direct() throws {
    let geoSiteURL = try temporaryGeoSiteFile(#"{"geosites":[]}"#)
    defer { try? FileManager.default.removeItem(at: geoSiteURL) }
    let engine = RuleEngine(
        rules: [Rule(condition: .any, action: .direct)],
        geosite: try GeoSiteDB(jsonURL: geoSiteURL),
        geoip: GeoIPDB(lookup: FixedCountryLookup(code: nil))
    )
    let classifier = FlowRuleClassifier(
        resolver: IdentityResolver(),
        core: RuleCore(engine: engine)
    )
    let input = RuleInput(
        originalIP: FBIPv4(a: 1, b: 1, c: 1, d: 1),
        resolvedIP: FBIPv4(a: 1, b: 1, c: 1, d: 1),
        domain: nil,
        port: 443,
        proto: .tcp,
        factsResolved: true
    )

    #expect(classifier.classify(input) == .direct)
}

private struct FixedCountryLookup: CountryLookup {
    let code: CountryCode?

    func lookupCountryCode(ip _: FBIPv4) -> CountryCode? {
        code
    }
}

@Test func compatibility_factory_projects_single_row_success_and_failure() {
    let accepted = FieldRuleJSON(
        type: "field",
        outboundTag: "Direct",
        domain: ["full:one.example"],
        ip: nil,
        network: nil
    )
    let rejected = FieldRuleJSON(
        type: "field",
        outboundTag: "Direct",
        domain: nil,
        ip: nil,
        network: nil
    )

    #expect(FieldRoutingRuleFactory.makeRule(from: accepted)?.condition == .domainFull("one.example"))
    #expect(FieldRoutingRuleFactory.makeRule(from: rejected) == nil)
}

@Test func geosite_ignores_unknown_types_and_empty_values() throws {
    let geoSiteURL = try temporaryGeoSiteFile(
        """
        {"geosites":[{"country_code":"custom","domains":[
            {"type":"future","value":"ignored.example"},
            {"type":"full","value":"   "}
        ]}]}
        """
    )
    defer { try? FileManager.default.removeItem(at: geoSiteURL) }

    let database = try GeoSiteDB(jsonURL: geoSiteURL)
    #expect(!database.contains(site: "custom", domain: "ignored.example"))
}

@Test func suffix_trie_reuses_shared_suffix_nodes() {
    let trie = DomainSuffixTrie(["example.com", "api.example.com"])

    #expect(trie.containsSuffix(of: "www.api.example.com"))
    #expect(!trie.containsSuffix(of: ""))
}
