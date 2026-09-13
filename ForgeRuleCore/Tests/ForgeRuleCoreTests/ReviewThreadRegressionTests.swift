@testable import ForgeRuleCore
import Foundation
import Testing

// C-QUERY-NORMALIZE C-PREFIX-CASE C-COMPILER-DIAGNOSTICS

@Test func review_matcher_queries_normalize_like_insertions() {
    let exact = DomainExactSet(["Example.COM"])
    let suffix = DomainSuffixTrie(["Example.COM"])
    let keyword = DomainKeywordMatcher(["Example"])
    for query in ["example.com", "EXAMPLE.COM", " \t.Example.COM.\r\n"] {
        #expect(exact.contains(query))
        #expect(suffix.containsSuffix(of: query))
        #expect(keyword.containsKeyword(in: query))
    }
    #expect(suffix.containsSuffix(of: " .WWW.Example.COM. "))
    #expect(!exact.contains("www.example.com"))
    #expect(!suffix.containsSuffix(of: "notexample.com"))
    for query in ["", " .\t\r\n", "unrelated.net"] {
        #expect(!exact.contains(query))
        #expect(!suffix.containsSuffix(of: query))
        #expect(!keyword.containsKeyword(in: query))
    }
}

@Test func review_geosite_normalizes_queries_for_every_index() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ForgeRuleCore-review-\(UUID().uuidString).json")
    let json = #"{"geosites":[{"country_code":"demo","domains":[{"type":"full","value":"exact.test"},{"type":"domain","value":"suffix.test"},{"type":"plain","value":"needle"}]}]}"#
    try Data(json.utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let db = try GeoSiteDB(jsonURL: url)
    for query in [" .EXACT.TEST. ", " .WWW.SUFFIX.TEST. ", " .HAS-NEEDLE.TEST. "] {
        #expect(db.contains(site: " .DeMo. ", domain: query))
    }
    #expect(!db.contains(site: "demo", domain: "unrelated.test"))
    #expect(!db.contains(site: "missing", domain: "EXACT.TEST"))
    #expect(!db.contains(site: "demo", domain: " . "))
}

@Test func review_rule_prefixes_are_case_insensitive_without_broadening() {
    let cases: [(String, RuleCondition)] = [
        ("GeOsItE:DeMo", .geosite("demo")),
        ("FULL:Example.COM", .domainFull("example.com")),
        ("DOMAIN:Example.COM", .domainSuffix("example.com")),
        ("KEYWORD:Example", .domainKeyword("example")),
    ]
    for (entry, condition) in cases {
        let result = FieldRoutingRuleFactory.compile(fields: [
            FieldRuleJSON(outboundTag: "direct", domain: [" \(entry) "]),
        ])
        #expect(result.isSuccessful)
        #expect(result.rules == [Rule(condition: condition, action: .direct)])
    }
    let rejected = FieldRoutingRuleFactory.compile(fields: [
        FieldRuleJSON(outboundTag: "direct", domain: ["REGEXP:.*"]),
        FieldRuleJSON(outboundTag: "direct", domain: ["DOMAIN: "]),
    ])
    #expect(rejected.rules.isEmpty)
    #expect(rejected.diagnostics.map(\.reason) == [.unsupportedDomainEntry, .invalidDomainEntry])
    let ip = FieldRoutingRuleFactory.compile(fields: [
        FieldRuleJSON(outboundTag: "direct", ip: ["GEOIP:!CN"]),
        FieldRuleJSON(outboundTag: "direct", ip: ["GEOIP:!bogus"]),
    ])
    #expect(ip.rules == [Rule(condition: .geoip("!cn"), action: .direct)])
    #expect(ip.diagnostics.map(\.reason) == [.invalidIPEntry])
}

@Test func review_network_constraint_is_never_silently_ignored() {
    for network in ["quic", " TCP ", "tcp,unknown", "unknown"] {
        let result = FieldRoutingRuleFactory.compile(fields: [
            FieldRuleJSON(outboundTag: "direct", domain: ["example.com"], network: network),
        ])
        #expect(result.rules.isEmpty)
        #expect(result.diagnostics.map(\.reason) == [.unsupportedNetwork])
    }
    for network in ["", " \t\r\n"] {
        let result = FieldRoutingRuleFactory.compile(fields: [
            FieldRuleJSON(outboundTag: "direct", domain: ["example.com"], network: network),
        ])
        #expect(result.isSuccessful)
        #expect(result.rules.count == 1)
    }
}
