@testable import ForgeRuleCore
import ForgeBase
import Foundation
import Testing

private struct StubFakeIPStore: FakeIPStore {
    let mapping: [FBIPv4: String]

    func reverseLookup(_ ip: FBIPv4) -> String? {
        mapping[ip]
    }
}

@inline(__always)
private func ip(_ value: UInt32) -> FBIPv4 {
    FBIPv4(beValue: value)
}

@Test func resolver_prefers_context_domain_when_present() throws {
    let resolver = FlowFactsResolver(
        fakeIPStore: StubFakeIPStore(mapping: [ip(2): "fallback.example"])
    )
    let ctx = RuleInput(
        originalIP: ip(1),
        resolvedIP: ip(2),
        domain: "  API.Example.COM  ",
        port: 443,
        proto: .tcp,
        factsResolved: false
    )

    let facts = resolver.resolve(ctx)
    #expect(facts.domain == "api.example.com")
    #expect(facts.factsResolved == true)
}

@Test func resolver_uses_fake_ip_lookup_on_resolved_ip_when_domain_missing() throws {
    let resolver = FlowFactsResolver(
        fakeIPStore: StubFakeIPStore(mapping: [
            ip(1): "should-not-hit.example",
            ip(2): "proxy.example",
        ])
    )
    let ctx = RuleInput(
        originalIP: ip(1),
        resolvedIP: ip(2),
        domain: nil,
        port: 80,
        proto: .tcp,
        factsResolved: false
    )

    let facts = resolver.resolve(ctx)
    #expect(facts.domain == "proxy.example")
    #expect(facts.factsResolved == true)
}

@Test func resolver_returns_nil_when_domain_missing_and_fake_ip_miss() throws {
    let resolver = FlowFactsResolver(fakeIPStore: StubFakeIPStore(mapping: [:]))
    let ctx = RuleInput(
        originalIP: ip(10),
        resolvedIP: ip(20),
        domain: nil,
        port: 53,
        proto: .udp,
        factsResolved: false
    )

    let facts = resolver.resolve(ctx)
    #expect(facts.domain == nil)
    #expect(facts.factsResolved == true)
}

@Test func resolver_treats_blank_domain_as_missing_and_falls_back_to_fake_ip() throws {
    let resolver = FlowFactsResolver(
        fakeIPStore: StubFakeIPStore(mapping: [ip(9): "  TeLeGram.Org "])
    )
    let ctx = RuleInput(
        originalIP: ip(8),
        resolvedIP: ip(9),
        domain: "   ",
        port: 443,
        proto: .tcp,
        factsResolved: false
    )

    let facts = resolver.resolve(ctx)
    #expect(facts.domain == "telegram.org")
    #expect(facts.factsResolved == true)
}

@Test func field_routing_factory_emits_one_primitive_per_field_rule() throws {
    let fields: [FieldRuleJSON] = [
        FieldRuleJSON(
            type: "field",
            outboundTag: "Reject",
            domain: ["domain:ads.example"],
            ip: nil,
            network: nil
        ),
        FieldRuleJSON(
            type: "field",
            outboundTag: "Direct",
            domain: ["full:apple.example"],
            ip: nil,
            network: nil
        ),
        FieldRuleJSON(
            type: "field",
            outboundTag: "Direct",
            domain: ["keyword:cdn"],
            ip: nil,
            network: nil
        ),
    ]
    let compilation = FieldRoutingRuleFactory.compile(fields: fields)
    #expect(compilation.isSuccessful)
    #expect(compilation.diagnostics.isEmpty)
    let rules = compilation.rules
    #expect(rules.count == 3)
    #expect(rules[0].action == .reject)
    #expect(rules[0].condition == .domainSuffix("ads.example"))
    #expect(rules[1].condition == .domainFull("apple.example"))
    #expect(rules[2].condition == .domainKeyword("cdn"))
}

@Test func field_routing_factory_accepts_geosite_rejects_multi_domain_and_network_only() throws {
    let fields: [FieldRuleJSON] = [
        FieldRuleJSON(type: "field", outboundTag: "Reject", domain: ["geosite:category-ads-all"], ip: nil, network: nil),
        FieldRuleJSON(
            type: "field",
            outboundTag: "Direct",
            domain: ["domain:a.example", "domain:b.example"],
            ip: nil,
            network: nil
        ),
        FieldRuleJSON(type: "field", outboundTag: "Direct", domain: nil, ip: nil, network: "tcp, udp"),
    ]
    let rules = FieldRoutingRuleFactory.makeRules(from: fields)
    #expect(rules.count == 1)
    #expect(rules[0].action == .reject)
    #expect(rules[0].condition == .geosite("category-ads-all"))
}

@Test func routing_json_decode_roundtrip_shape() throws {
    let json = """
    {"routing":{"rules":[
        {"type":"field","outboundTag":"Proxy","domain":["domain:example.org"]},
        {"type":"field","outboundTag":"Direct","domain":["keyword:local"]}
    ]}}
    """
    let decoded = try JSONDecoder().decode(RoutingConfigJSON.self, from: Data(json.utf8))
    let rules = FieldRoutingRuleFactory.makeRules(from: decoded.routing?.rules ?? [])
    #expect(rules.count == 2)
    #expect(rules[0].condition == .domainSuffix("example.org"))
    #expect(rules[1].condition == .domainKeyword("local"))
}

@Test func dns_json_decodes_hosts_and_mixed_servers() throws {
    let json = """
    {"dns":{
        "hosts":{"dns.google":"8.8.8.8","geosite:category-ads-all":"127.0.0.1"},
        "servers":[
            {"address":"https://1.1.1.1/dns-query","domains":["geosite:geolocation-!cn"],"expectIPs":["geoip:!cn"]},
            "8.8.8.8",
            {"address":"114.114.114.114","port":53,"domains":["geosite:cn"],"expectIPs":["geoip:cn"],"skipFallback":true}
        ]
    }}
    """
    let decoded = try JSONDecoder().decode(DNSRoutingConfigJSON.self, from: Data(json.utf8))
    #expect(decoded.dns?.hosts?["dns.google"] == "8.8.8.8")
    #expect(decoded.dns?.servers?.count == 3)
    guard case let .plain(s) = decoded.dns?.servers?[1] else {
        #expect(Bool(false))
        return
    }
    #expect(s == "8.8.8.8")
}

@Test func rule_condition_collects_geoip_key_only() {
    let c: RuleCondition = .geoip("cn")
    #expect(c.collectGeoipKeys() == ["cn"])
    #expect(RuleCondition.domainSuffix("x").collectGeoipKeys().isEmpty)
    #expect(RuleCondition.geosite("cn").collectGeoipKeys().isEmpty)
    #expect(RuleCondition.any.collectGeoipKeys().isEmpty)
}

@Test func parse_network_list_tcp_udp() {
    let s = FieldRoutingRuleFactory.parseNetworkList("tcp, udp")
    #expect(s.contains(TransportProtocol.tcp.rawValue))
    #expect(s.contains(TransportProtocol.udp.rawValue))
}

@Test func factory_normalizes_domain_and_geoip_payloads() throws {
    let fields: [FieldRuleJSON] = [
        FieldRuleJSON(
            type: "field",
            outboundTag: "proxy",
            domain: ["domain: Example.COM"],
            ip: nil,
            network: nil
        ),
        FieldRuleJSON(
            type: "field",
            outboundTag: "proxy",
            domain: nil,
            ip: ["geoip:  CN "],
            network: nil
        ),
    ]
    let rules = FieldRoutingRuleFactory.makeRules(from: fields)
    #expect(rules.count == 2)
    #expect(rules[0].condition == .domainSuffix("example.com"))
    #expect(rules[1].condition == .geoip("cn"))
}
