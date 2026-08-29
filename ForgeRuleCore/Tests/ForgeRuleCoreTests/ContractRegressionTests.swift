@testable import ForgeRuleCore
import ForgeBase
import Foundation
import Testing

// MARK: - Stubs / helpers
// Contract IDs: see docs/CONTRACT-TESTS.md
// C-GEOIP-MISS C-GEOIP-RESOLVED C-ANY-ORDER C-DEFAULT-DIRECT C-EVAL-NORMALIZE
// C-PORT-PROTO-IGNORED C-COMPILER-DIAGNOSTICS C-OUTBOUND-MAP C-GEOSITE-REGEX C-FIRST-WINS

private struct StubCountryLookup: CountryLookup {
    let codeByIP: [FBIPv4: CountryCode]

    func lookupCountryCode(ip: FBIPv4) -> CountryCode? {
        codeByIP[ip]
    }
}

@inline(__always)
private func ipv4(_ value: UInt32) -> FBIPv4 {
    FBIPv4(beValue: value)
}

private func makeEmptyGeoSiteURL() throws -> URL {
    let json = #"{"geosites":[]}"#
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ForgeRuleCore-contract-empty-\(UUID().uuidString).json")
    try json.data(using: .utf8)!.write(to: url)
    return url
}

private func makeGeoSiteURL(_ json: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ForgeRuleCore-contract-geosite-\(UUID().uuidString).json")
    try json.data(using: .utf8)!.write(to: url)
    return url
}

private func makeEngine(
    rules: [Rule],
    lookup: StubCountryLookup = StubCountryLookup(codeByIP: [:]),
    geositeURL: URL? = nil
) throws -> (RuleEngine, [URL]) {
    var cleanup: [URL] = []
    let siteURL: URL
    if let geositeURL {
        siteURL = geositeURL
    } else {
        siteURL = try makeEmptyGeoSiteURL()
        cleanup.append(siteURL)
    }
    let geosite = try GeoSiteDB(jsonURL: siteURL)
    let geoipKeys = rules.flatMap { $0.condition.collectGeoipKeys() }
    let geoip = GeoIPDB(lookup: lookup, preheatKeys: geoipKeys)
    return (RuleEngine(rules: rules, geosite: geosite, geoip: geoip), cleanup)
}

private func input(
    domain: String?,
    resolved: FBIPv4 = ipv4(1),
    original: FBIPv4 = ipv4(2),
    port: UInt16 = 443,
    proto: TransportProtocol = .tcp
) -> RuleInput {
    RuleInput(
        originalIP: original,
        resolvedIP: resolved,
        domain: domain,
        port: port,
        proto: proto
    )
}

// MARK: - C-GEOIP-MISS

@Test func contract_geoip_negation_hits_on_lookup_miss() {
    let ip = ipv4(0x0A000001) // 10.0.0.1 — no mapping
    let db = GeoIPDB(lookup: StubCountryLookup(codeByIP: [:]), preheatKeys: ["cn"])
    #expect(db.match(key: "!cn", ip: ip))
    #expect(!db.match(key: "cn", ip: ip))
}

@Test func contract_engine_geoip_negation_on_miss_selects_proxy() throws {
    let missIP = ipv4(0xC0A80001)
    let (engine, cleanup) = try makeEngine(
        rules: [Rule(condition: .geoip("!cn"), action: .proxy("non-cn"))],
        lookup: StubCountryLookup(codeByIP: [:])
    )
    defer { cleanup.forEach { try? FileManager.default.removeItem(at: $0) } }

    #expect(engine.evaluate(input(domain: "x.test", resolved: missIP)) == .proxy("non-cn"))
}

// MARK: - C-GEOIP-RESOLVED

@Test func contract_geoip_uses_resolved_ip_not_original() throws {
    let original = ipv4(0x01010101)
    let resolved = ipv4(0x02020202)
    let lookup = StubCountryLookup(codeByIP: [
        original: .us,
        resolved: .cn,
    ])
    let (engine, cleanup) = try makeEngine(
        rules: [
            Rule(condition: .geoip("cn"), action: .direct),
            Rule(condition: .any, action: .reject),
        ],
        lookup: lookup
    )
    defer { cleanup.forEach { try? FileManager.default.removeItem(at: $0) } }

    #expect(
        engine.evaluate(input(domain: nil, resolved: resolved, original: original)) == .direct
    )

    let (engineUS, cleanup2) = try makeEngine(
        rules: [
            Rule(condition: .geoip("us"), action: .proxy("us-only")),
            Rule(condition: .any, action: .direct),
        ],
        lookup: lookup
    )
    defer { cleanup2.forEach { try? FileManager.default.removeItem(at: $0) } }

    // resolved is CN, so geoip:us must not hit
    #expect(
        engineUS.evaluate(input(domain: nil, resolved: resolved, original: original)) == .direct
    )
}

// MARK: - C-ANY-ORDER / C-DEFAULT-DIRECT / C-FIRST-WINS

@Test func contract_any_before_specific_is_overridable_fallback() throws {
    let (engine, cleanup) = try makeEngine(rules: [
        Rule(condition: .any, action: .reject),
        Rule(condition: .domainSuffix("special.test"), action: .proxy("P")),
    ])
    defer { cleanup.forEach { try? FileManager.default.removeItem(at: $0) } }

    #expect(engine.evaluate(input(domain: "a.special.test")) == .proxy("P"))
    #expect(engine.evaluate(input(domain: "other.com")) == .reject)
}

@Test func contract_any_at_end_acts_as_final() throws {
    let (engine, cleanup) = try makeEngine(rules: [
        Rule(condition: .domainSuffix("special.test"), action: .proxy("P")),
        Rule(condition: .any, action: .reject),
    ])
    defer { cleanup.forEach { try? FileManager.default.removeItem(at: $0) } }

    #expect(engine.evaluate(input(domain: "a.special.test")) == .proxy("P"))
    #expect(engine.evaluate(input(domain: "other.com")) == .reject)
}

@Test func contract_empty_rules_default_direct() throws {
    let (engine, cleanup) = try makeEngine(rules: [])
    defer { cleanup.forEach { try? FileManager.default.removeItem(at: $0) } }
    #expect(engine.evaluate(input(domain: "x.com")) == .direct)
}

@Test func contract_first_matching_non_any_wins() throws {
    let (engine, cleanup) = try makeEngine(rules: [
        Rule(condition: .domainSuffix("example.com"), action: .proxy("first")),
        Rule(condition: .domainSuffix("example.com"), action: .reject),
    ])
    defer { cleanup.forEach { try? FileManager.default.removeItem(at: $0) } }
    #expect(engine.evaluate(input(domain: "www.example.com")) == .proxy("first"))
}

// MARK: - C-EVAL-NORMALIZE / C-PORT-PROTO-IGNORED

@Test func contract_evaluate_self_normalizes_domain() throws {
    let (engine, cleanup) = try makeEngine(rules: [
        Rule(condition: .domainFull("api.x.com"), action: .direct),
    ])
    defer { cleanup.forEach { try? FileManager.default.removeItem(at: $0) } }
    #expect(engine.evaluate(input(domain: "  API.X.COM  ")) == .direct)
}

@Test func contract_port_and_proto_do_not_affect_match() throws {
    let (engine, cleanup) = try makeEngine(rules: [
        Rule(condition: .domainSuffix("x.com"), action: .proxy("p")),
    ])
    defer { cleanup.forEach { try? FileManager.default.removeItem(at: $0) } }

    let a = engine.evaluate(input(domain: "a.x.com", port: 80, proto: .tcp))
    let b = engine.evaluate(input(domain: "a.x.com", port: 443, proto: .udp))
    #expect(a == .proxy("p"))
    #expect(b == .proxy("p"))
    #expect(a == b)
}

// MARK: - C-COMPILER-DIAGNOSTICS / C-OUTBOUND-MAP

@Test func contract_compiler_reports_every_rejected_row() {
    let fields: [FieldRuleJSON] = [
        FieldRuleJSON(
            type: "field",
            outboundTag: "Direct",
            domain: ["domain:a.com", "domain:b.com"],
            ip: nil,
            network: nil
        ),
        FieldRuleJSON(
            type: "field",
            outboundTag: "Direct",
            domain: ["domain:a.com"],
            ip: ["geoip:cn"],
            network: nil
        ),
        FieldRuleJSON(
            type: "field",
            outboundTag: "Direct",
            domain: ["domain:a.com"],
            ip: nil,
            network: "tcp"
        ),
        FieldRuleJSON(
            type: "field",
            outboundTag: "Direct",
            domain: ["regexp:.*\\.com"],
            ip: nil,
            network: nil
        ),
        FieldRuleJSON(
            type: "other",
            outboundTag: "Direct",
            domain: ["domain:a.com"],
            ip: nil,
            network: nil
        ),
        FieldRuleJSON(
            type: "field",
            outboundTag: nil,
            domain: ["domain:a.com"],
            ip: nil,
            network: nil
        ),
        FieldRuleJSON(
            type: "field",
            outboundTag: "   ",
            domain: ["domain:a.com"],
            ip: nil,
            network: nil
        ),
        FieldRuleJSON(
            type: "field",
            outboundTag: "Direct",
            domain: nil,
            ip: ["geoip:cn", "geoip:us"],
            network: nil
        ),
        FieldRuleJSON(
            type: "field",
            outboundTag: "Direct",
            domain: ["domain:"],
            ip: nil,
            network: nil
        ),
        FieldRuleJSON(
            type: "field",
            outboundTag: "Direct",
            domain: nil,
            ip: ["geoip:"],
            network: nil
        ),
        FieldRuleJSON(
            type: "field",
            outboundTag: "Direct",
            domain: nil,
            ip: ["10.0.0.0/8"],
            network: nil
        ),
    ]
    let compilation = FieldRoutingRuleFactory.compile(fields: fields)

    #expect(!compilation.isSuccessful)
    #expect(compilation.rules.isEmpty)
    #expect(compilation.diagnostics.map(\.fieldIndex) == Array(0..<11))
    #expect(
        compilation.diagnostics.map(\.reason) == [
            .multipleDomainEntries,
            .mixedDomainAndIP,
            .unsupportedNetwork,
            .unsupportedDomainEntry,
            .unsupportedRuleType,
            .missingOutboundTag,
            .missingOutboundTag,
            .multipleIPEntries,
            .invalidDomainEntry,
            .invalidIPEntry,
            .unsupportedIPEntry,
        ]
    )
}

@Test func contract_compiler_partial_output_is_not_success() {
    let fields: [FieldRuleJSON] = [
        FieldRuleJSON(
            type: "field",
            outboundTag: "Direct",
            domain: ["full:accepted.example"],
            ip: nil,
            network: nil
        ),
        FieldRuleJSON(
            type: "field",
            outboundTag: "Direct",
            domain: nil,
            ip: nil,
            network: nil
        ),
        FieldRuleJSON(
            type: "field",
            outboundTag: "Reject",
            domain: ["domain:blocked.example"],
            ip: nil,
            network: nil
        ),
    ]

    let compilation = FieldRoutingRuleFactory.compile(fields: fields)
    #expect(!compilation.isSuccessful)
    #expect(compilation.rules.map(\.condition) == [
        .domainFull("accepted.example"),
        .domainSuffix("blocked.example"),
    ])
    #expect(compilation.diagnostics == [
        FieldRoutingDiagnostic(fieldIndex: 1, reason: .missingCondition),
    ])
}

@Test func contract_compiler_does_not_narrow_invalid_rows_before_validation() {
    let fields: [FieldRuleJSON] = [
        FieldRuleJSON(
            type: "field",
            outboundTag: "Direct",
            domain: ["regexp:.*\\.example", "domain:accepted.example"],
            ip: nil,
            network: nil
        ),
        FieldRuleJSON(
            type: "field",
            outboundTag: "Direct",
            domain: ["domain:accepted.example"],
            ip: nil,
            network: "quic"
        ),
    ]

    let compilation = FieldRoutingRuleFactory.compile(fields: fields)
    #expect(!compilation.isSuccessful)
    #expect(compilation.rules.isEmpty)
    #expect(compilation.diagnostics.map(\.reason) == [
        .multipleDomainEntries,
        .unsupportedNetwork,
    ])
}

@Test func contract_outbound_tag_mapping() {
    let cases: [(String, RuleAction)] = [
        ("direct", .direct),
        ("Direct", .direct),
        ("reject", .reject),
        ("block", .reject),
        ("Proxy-A", .proxy("Proxy-A")),
    ]
    for (tag, expected) in cases {
        let fields = [
            FieldRuleJSON(
                type: "field",
                outboundTag: tag,
                domain: ["full:one.example"],
                ip: nil,
                network: nil
            ),
        ]
        let rules = FieldRoutingRuleFactory.makeRules(from: fields)
        #expect(rules.count == 1, "tag=\(tag)")
        #expect(rules[0].action == expected, "tag=\(tag)")
    }
}

// MARK: - C-GEOSITE-REGEX

@Test func contract_geosite_regex_entries_are_ignored() throws {
    let url = try makeGeoSiteURL(
        """
        {"geosites":[{"country_code":"re","domains":[
            {"type":"regex","value":".*ads.*"}
        ]}]}
        """
    )
    defer { try? FileManager.default.removeItem(at: url) }
    let db = try GeoSiteDB(jsonURL: url)
    #expect(!db.contains(site: "re", domain: "foo.ads.bar"))
    #expect(!db.contains(site: "re", domain: "ads"))
}
