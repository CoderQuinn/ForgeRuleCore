@testable import ForgeRuleCore
import ForgeBase
import Foundation
import Testing

// Contract IDs: C-REVISION-IDENTITY C-DOMAIN-FACT-PROVENANCE C-CLASSIFICATION-ENVELOPE

private struct RevisionCountryLookup: CountryLookup {
    func lookupCountryCode(ip _: FBIPv4) -> CountryCode? {
        nil
    }
}

private struct RevisionFakeIPStore: FakeIPStore {
    let domain: String?

    func reverseLookup(_ ip: FBIPv4) -> String? {
        domain
    }
}

private func revisionIP(_ value: UInt32) -> FBIPv4 {
    FBIPv4(beValue: value)
}

private func makeRevisionEngine(rules: [Rule]) throws -> (RuleEngine, URL) {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ForgeRuleCore-revision-\(UUID().uuidString).json")
    try Data(#"{"geosites":[]}"#.utf8).write(to: url)
    let engine = RuleEngine(
        rules: rules,
        geosite: try GeoSiteDB(jsonURL: url),
        geoip: GeoIPDB(lookup: RevisionCountryLookup())
    )
    return (engine, url)
}

@Test func rule_revision_requires_an_exact_nonempty_identity() throws {
    let revision = try #require(RuleRevision(rawValue: "rules-20260830/manifest-e097"))

    #expect(revision.rawValue == "rules-20260830/manifest-e097")
    #expect(RuleRevision(rawValue: "") == nil)
    #expect(RuleRevision(rawValue: " padded") == nil)
    #expect(RuleRevision(rawValue: "padded ") == nil)
}

@Test func rule_revision_codable_shape_is_a_validated_string() throws {
    let revision = try #require(RuleRevision(rawValue: "rules-20260830"))
    let encoded = try JSONEncoder().encode(revision)

    #expect(String(decoding: encoded, as: UTF8.self) == #""rules-20260830""#)
    #expect(try JSONDecoder().decode(RuleRevision.self, from: encoded) == revision)
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(RuleRevision.self, from: Data(#"" ""#.utf8))
    }
}

@Test func resolver_preserves_dns_domain_revision_and_normalizes_the_fact() throws {
    let dnsRevision = try #require(RuleRevision(rawValue: "dns-rules-v7"))
    let input = RuleInput(
        originalIP: revisionIP(1),
        resolvedIP: revisionIP(2),
        domain: "  API.Example.TEST. ",
        domainSource: .dns,
        domainRevision: dnsRevision,
        port: 443,
        proto: .tcp
    )

    let resolved = FlowFactsResolver(fakeIPStore: nil).resolve(input)

    #expect(resolved.domain == "api.example.test")
    #expect(resolved.domainSource == .dns)
    #expect(resolved.domainRevision == dnsRevision)
    #expect(resolved.factsResolved)
}

@Test func fake_ip_fallback_replaces_stale_blank_domain_provenance() throws {
    let staleRevision = try #require(RuleRevision(rawValue: "dns-rules-stale"))
    let input = RuleInput(
        originalIP: revisionIP(3),
        resolvedIP: revisionIP(4),
        domain: "  ",
        domainSource: .dns,
        domainRevision: staleRevision,
        port: 443,
        proto: .tcp
    )

    let resolved = FlowFactsResolver(
        fakeIPStore: RevisionFakeIPStore(domain: " Fake.Example.TEST ")
    ).resolve(input)

    #expect(resolved.domain == "fake.example.test")
    #expect(resolved.domainSource == .fakeIP)
    #expect(resolved.domainRevision == nil)
    #expect(resolved.factsResolved)
}

@Test func rule_core_classification_reports_revision_and_evaluated_input() throws {
    let revision = try #require(RuleRevision(rawValue: "rules-snapshot-v8"))
    let (engine, url) = try makeRevisionEngine(rules: [
        Rule(condition: .domainFull("api.example.test"), action: .proxy("dns-proxy")),
    ])
    defer { try? FileManager.default.removeItem(at: url) }
    let core = RuleCore(engine: engine, revision: revision)
    let input = RuleInput(
        originalIP: revisionIP(5),
        resolvedIP: revisionIP(6),
        domain: " API.Example.TEST. ",
        domainSource: .dns,
        domainRevision: revision,
        port: 53,
        proto: .udp,
        factsResolved: true
    )

    let result = core.classify(input)

    #expect(result.decision == .proxy("dns-proxy"))
    #expect(result.revision == revision)
    #expect(result.evaluatedInput.domain == "api.example.test")
    #expect(result.evaluatedInput.domainSource == .dns)
    #expect(result.evaluatedInput.domainRevision == revision)
}

@Test func flow_classifier_preserves_dns_fact_revision_across_a_new_snapshot() throws {
    let dnsRevision = try #require(RuleRevision(rawValue: "rules-dns-v1"))
    let flowRevision = try #require(RuleRevision(rawValue: "rules-flow-v2"))
    let (engine, url) = try makeRevisionEngine(rules: [
        Rule(condition: .domainSuffix("example.test"), action: .direct),
    ])
    defer { try? FileManager.default.removeItem(at: url) }
    let classifier = FlowRuleClassifier(
        resolver: FlowFactsResolver(fakeIPStore: nil),
        engine: engine,
        revision: flowRevision
    )
    let input = RuleInput(
        originalIP: revisionIP(7),
        resolvedIP: revisionIP(8),
        domain: "WWW.Example.TEST",
        domainSource: .dns,
        domainRevision: dnsRevision,
        port: 443,
        proto: .tcp
    )

    let result = classifier.classifyWithFacts(input)

    #expect(result.decision == .direct)
    #expect(result.revision == flowRevision)
    #expect(result.evaluatedInput.domain == "www.example.test")
    #expect(result.evaluatedInput.domainSource == .dns)
    #expect(result.evaluatedInput.domainRevision == dnsRevision)
    #expect(result.evaluatedInput.factsResolved)
}

@Test func flow_classifier_compatibility_projection_uses_the_detailed_result() throws {
    let revision = try #require(RuleRevision(rawValue: "rules-flow-v3"))
    let (engine, url) = try makeRevisionEngine(rules: [
        Rule(condition: .any, action: .reject),
    ])
    defer { try? FileManager.default.removeItem(at: url) }
    let classifier = FlowRuleClassifier(
        resolver: FlowFactsResolver(
            fakeIPStore: RevisionFakeIPStore(domain: "resolved.example.test")
        ),
        engine: engine,
        revision: revision
    )
    let input = RuleInput(
        originalIP: revisionIP(9),
        resolvedIP: revisionIP(10),
        domain: nil,
        port: 80,
        proto: .tcp
    )

    let detailed = classifier.classifyWithFacts(input)

    #expect(classifier.classify(input) == detailed.decision)
    #expect(detailed.decision == .reject)
    #expect(detailed.revision == revision)
    #expect(detailed.evaluatedInput.domainSource == .fakeIP)
}
