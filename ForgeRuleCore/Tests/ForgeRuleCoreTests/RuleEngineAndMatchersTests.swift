@testable import ForgeRuleCore
import ForgeBase
import Foundation
import Testing

// MARK: - Stubs

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

// MARK: - normalizeDomain / normalizeGeoipKey

@Test func normalize_domain_trims_dots_and_whitespace() {
    #expect(normalizeDomain("  Foo.BAR. ") == "foo.bar")
    #expect(normalizeDomain("..a..") == "a")
}

@Test func normalize_geoip_key_lowercases_and_trims() {
    #expect(normalizeGeoipKey("  CN ") == "cn")
    // Outer whitespace only; inner space after `!` is preserved.
    #expect(normalizeGeoipKey(" ! TW ") == "! tw")
}

// MARK: - DomainExactSet

@Test func domain_exact_set_matches_normalized_inserts() {
    let set = DomainExactSet(["  EXAMPLE.COM ", "other.test"])
    #expect(set.contains("example.com"))
    #expect(set.contains("other.test"))
    #expect(!set.contains("sub.example.com"))
}

// MARK: - DomainSuffixTrie

@Test func domain_suffix_trie_exact_and_suffix_match() {
    let trie = DomainSuffixTrie(["example.com", "co.jp"])
    #expect(trie.containsSuffix(of: "example.com"))
    #expect(trie.containsSuffix(of: "api.example.com"))
    #expect(trie.containsSuffix(of: "foo.bar.co.jp"))
    #expect(!trie.containsSuffix(of: "notexample.com"))
    #expect(!trie.containsSuffix(of: "jp"))
}

@Test func domain_suffix_trie_ignores_empty_and_malformed_inserts() {
    let trie = DomainSuffixTrie(["", "...", "  "])
    #expect(!trie.containsSuffix(of: "anything.com"))
}

// MARK: - DomainKeywordMatcher

@Test func domain_keyword_matcher_scans_in_order() {
    let m = DomainKeywordMatcher(["cdn", "bad"])
    #expect(m.containsKeyword(in: "static.cdn.example"))
    #expect(m.containsKeyword(in: "badword.example"))
    #expect(!m.containsKeyword(in: "clean.example"))
}

// MARK: - GeoIPDB

@Test func geoip_positive_match_uses_lookup() {
    let ip = ipv4(0x01020304)
    let lookup = StubCountryLookup(codeByIP: [ip: .cn])
    let db = GeoIPDB(lookup: lookup, preheatKeys: [])
    #expect(db.match(key: "cn", ip: ip))
    #expect(!db.match(key: "us", ip: ip))
}

@Test func geoip_negation_inverts_positive() {
    let ip = ipv4(0x0A0B0C0D)
    let lookup = StubCountryLookup(codeByIP: [ip: .us])
    let db = GeoIPDB(lookup: lookup, preheatKeys: [])
    #expect(db.match(key: "!cn", ip: ip))
    #expect(!db.match(key: "!us", ip: ip))
}

@Test func geoip_empty_or_unknown_key_never_matches() {
    let ip = ipv4(1)
    let lookup = StubCountryLookup(codeByIP: [ip: .cn])
    let db = GeoIPDB(lookup: lookup, preheatKeys: [])
    #expect(!db.match(key: "", ip: ip))
    #expect(!db.match(key: "   ", ip: ip))
    #expect(!db.match(key: "xx", ip: ip))
}

@Test func geoip_preheat_populates_parse_cache() {
    let ip = ipv4(2)
    let lookup = StubCountryLookup(codeByIP: [ip: .jp])
    let db = GeoIPDB(lookup: lookup, preheatKeys: ["jp", " !kr "])
    #expect(db.match(key: "jp", ip: ip))
}

// MARK: - GeoSiteDB

@Test func geosite_db_full_suffix_keyword_priority() throws {
    let json = """
    {"geosites":[{"country_code":"demo","domains":[
        {"type":"full","value":"exact.example"},
        {"type":"domain","value":"suffix.example"},
        {"type":"plain","value":"kw"}
    ]}]}
    """
    let dir = FileManager.default.temporaryDirectory
    let url = dir.appendingPathComponent("ForgeRuleCoreTests-geosite-\(UUID().uuidString).json")
    try json.data(using: .utf8)!.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let db = try GeoSiteDB(jsonURL: url)
    #expect(db.contains(site: "demo", domain: "exact.example"))
    #expect(db.contains(site: "demo", domain: "a.suffix.example"))
    #expect(db.contains(site: "demo", domain: "prefix-kw-suffix.example"))
    #expect(!db.contains(site: "demo", domain: "other.com"))
    #expect(!db.contains(site: "missing", domain: "exact.example"))
}

// MARK: - RuleEngine

@Test func rule_engine_domain_full_suffix_keyword() throws {
    let emptyURL = try makeEmptyGeoSiteFile()
    defer { try? FileManager.default.removeItem(at: emptyURL) }
    let emptyGeoSite = try GeoSiteDB(jsonURL: emptyURL)
    let geoip = GeoIPDB(lookup: StubCountryLookup(codeByIP: [:]), preheatKeys: [])
    let rules: [Rule] = [
        Rule(condition: .domainFull("api.example.com"), action: .proxy("A")),
        Rule(condition: .domainSuffix("example.org"), action: .direct),
        Rule(condition: .domainKeyword("cdn"), action: .reject),
    ]
    let engine = RuleEngine(rules: rules, geosite: emptyGeoSite, geoip: geoip)

    let hitFull = RuleInput(
        originalIP: ipv4(1),
        resolvedIP: ipv4(1),
        domain: "api.example.com",
        port: 443,
        proto: .tcp
    )
    #expect(engine.evaluate(hitFull) == .proxy("A"))

    let hitSuffix = RuleInput(
        originalIP: ipv4(1),
        resolvedIP: ipv4(1),
        domain: "x.example.org",
        port: 80,
        proto: .tcp
    )
    #expect(engine.evaluate(hitSuffix) == .direct)

    let hitKw = RuleInput(
        originalIP: ipv4(1),
        resolvedIP: ipv4(1),
        domain: "foo-cdn-bar.net",
        port: 443,
        proto: .tcp
    )
    #expect(engine.evaluate(hitKw) == .reject)
}

@Test func rule_engine_geoip_and_geosite() throws {
    let resolved = ipv4(0xC0A80101)
    let geoip = GeoIPDB(
        lookup: StubCountryLookup(codeByIP: [resolved: .cn]),
        preheatKeys: ["cn"]
    )
    let geositeURL = try makeGeoSiteFile(
        """
        {"geosites":[{"country_code":"ads","domains":[
            {"type":"domain","value":"doubleclick.net"}
        ]}]}
        """
    )
    let geosite = try GeoSiteDB(jsonURL: geositeURL)
    defer { try? FileManager.default.removeItem(at: geositeURL) }

    let rules: [Rule] = [
        Rule(condition: .geosite("ads"), action: .reject),
        Rule(condition: .geoip("cn"), action: .direct),
    ]
    let engine = RuleEngine(rules: rules, geosite: geosite, geoip: geoip)

    let ads = RuleInput(
        originalIP: ipv4(1),
        resolvedIP: resolved,
        domain: "foo.doubleclick.net",
        port: 443,
        proto: .tcp
    )
    #expect(engine.evaluate(ads) == .reject)

    let cnOnly = RuleInput(
        originalIP: ipv4(1),
        resolvedIP: resolved,
        domain: "unknown.example",
        port: 443,
        proto: .tcp
    )
    #expect(engine.evaluate(cnOnly) == .direct)
}

@Test func rule_engine_any_accumulates_until_specific_or_end() throws {
    let emptyURL = try makeEmptyGeoSiteFile()
    defer { try? FileManager.default.removeItem(at: emptyURL) }
    let emptyGeoSite = try GeoSiteDB(jsonURL: emptyURL)
    let geoip = GeoIPDB(lookup: StubCountryLookup(codeByIP: [:]), preheatKeys: [])
    let rules: [Rule] = [
        Rule(condition: .any, action: .direct),
        Rule(condition: .domainSuffix("special.test"), action: .proxy("P")),
    ]
    let engine = RuleEngine(rules: rules, geosite: emptyGeoSite, geoip: geoip)

    let specific = RuleInput(
        originalIP: ipv4(1),
        resolvedIP: ipv4(1),
        domain: "a.special.test",
        port: 1,
        proto: .tcp
    )
    #expect(engine.evaluate(specific) == .proxy("P"))

    let fallback = RuleInput(
        originalIP: ipv4(1),
        resolvedIP: ipv4(1),
        domain: "other.com",
        port: 1,
        proto: .tcp
    )
    #expect(engine.evaluate(fallback) == .direct)
}

@Test func rule_engine_domain_conditions_require_domain() throws {
    let emptyURL = try makeEmptyGeoSiteFile()
    defer { try? FileManager.default.removeItem(at: emptyURL) }
    let emptyGeoSite = try GeoSiteDB(jsonURL: emptyURL)
    let geoip = GeoIPDB(lookup: StubCountryLookup(codeByIP: [:]), preheatKeys: [])
    let rules: [Rule] = [
        Rule(condition: .domainSuffix("x.com"), action: .proxy("p")),
        Rule(condition: .any, action: .reject),
    ]
    let engine = RuleEngine(rules: rules, geosite: emptyGeoSite, geoip: geoip)

    let noDomain = RuleInput(
        originalIP: ipv4(1),
        resolvedIP: ipv4(2),
        domain: nil,
        port: 443,
        proto: .tcp
    )
    #expect(engine.evaluate(noDomain) == .reject)
}

@Test func rule_engine_normalizes_input_domain() throws {
    let emptyURL = try makeEmptyGeoSiteFile()
    defer { try? FileManager.default.removeItem(at: emptyURL) }
    let emptyGeoSite = try GeoSiteDB(jsonURL: emptyURL)
    let geoip = GeoIPDB(lookup: StubCountryLookup(codeByIP: [:]), preheatKeys: [])
    let rules: [Rule] = [
        Rule(condition: .domainFull("api.example.com"), action: .direct),
    ]
    let engine = RuleEngine(rules: rules, geosite: emptyGeoSite, geoip: geoip)

    let spaced = RuleInput(
        originalIP: ipv4(1),
        resolvedIP: ipv4(1),
        domain: "  API.Example.COM  ",
        port: 443,
        proto: .tcp
    )
    #expect(engine.evaluate(spaced) == .direct)
}

// MARK: - RuleCore / FlowRuleClassifier

@Test func rule_core_route_maps_actions() throws {
    let emptyURL = try makeEmptyGeoSiteFile()
    defer { try? FileManager.default.removeItem(at: emptyURL) }
    let emptyGeoSite = try GeoSiteDB(jsonURL: emptyURL)
    let geoip = GeoIPDB(lookup: StubCountryLookup(codeByIP: [:]), preheatKeys: [])
    let engine = RuleEngine(
        rules: [Rule(condition: .any, action: .proxy("tag"))],
        geosite: emptyGeoSite,
        geoip: geoip
    )
    let core = RuleCore(engine: engine)
    let input = RuleInput(
        originalIP: ipv4(1),
        resolvedIP: ipv4(1),
        domain: "z.test",
        port: 1,
        proto: .tcp
    )
    #expect(core.route(input) == .proxy("tag"))
}

private struct PassthroughResolver: FlowFactsResolving {
    func resolve(_ input: RuleInput) -> RuleInput { input }
}

@Test func flow_rule_classifier_resolves_then_routes() throws {
    let emptyURL = try makeEmptyGeoSiteFile()
    defer { try? FileManager.default.removeItem(at: emptyURL) }
    let emptyGeoSite = try GeoSiteDB(jsonURL: emptyURL)
    let geoip = GeoIPDB(lookup: StubCountryLookup(codeByIP: [:]), preheatKeys: [])
    let engine = RuleEngine(
        rules: [Rule(condition: .domainSuffix("tld"), action: .reject)],
        geosite: emptyGeoSite,
        geoip: geoip
    )
    let classifier = FlowRuleClassifier(resolver: PassthroughResolver(), engine: engine)
    let input = RuleInput(
        originalIP: ipv4(1),
        resolvedIP: ipv4(1),
        domain: "x.tld",
        port: 1,
        proto: .tcp,
        factsResolved: true
    )
    #expect(classifier.classify(input) == .reject)
}

// MARK: - FieldRoutingRuleFactory edge cases

@Test func field_routing_factory_skips_non_field_type() {
    let fields: [FieldRuleJSON] = [
        FieldRuleJSON(type: "other", outboundTag: "Direct", domain: ["domain:x.com"], ip: nil, network: nil),
    ]
    #expect(FieldRoutingRuleFactory.makeRules(from: fields).isEmpty)
}

@Test func field_routing_factory_plain_domain_is_suffix() {
    let fields: [FieldRuleJSON] = [
        FieldRuleJSON(type: "field", outboundTag: "Direct", domain: ["ROOT.TLD"], ip: nil, network: nil),
    ]
    let rules = FieldRoutingRuleFactory.makeRules(from: fields)
    #expect(rules.count == 1)
    #expect(rules[0].condition == .domainSuffix("root.tld"))
}

// MARK: - Temp files

private func makeEmptyGeoSiteFile() throws -> URL {
    let json = #"{"geosites":[]}"#
    let dir = FileManager.default.temporaryDirectory
    let url = dir.appendingPathComponent("ForgeRuleCore-empty-\(UUID().uuidString).json")
    try json.data(using: .utf8)!.write(to: url)
    return url
}

private func makeGeoSiteFile(_ json: String) throws -> URL {
    let dir = FileManager.default.temporaryDirectory
    let url = dir.appendingPathComponent("ForgeRuleCore-geosite-\(UUID().uuidString).json")
    try json.data(using: .utf8)!.write(to: url)
    return url
}
