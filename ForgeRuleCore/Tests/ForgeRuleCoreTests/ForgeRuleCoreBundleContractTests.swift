import CryptoKit
import ForgeBase
import Foundation
import Testing

@testable import ForgeRuleCore

// Contract IDs: C-BUNDLE-ASSEMBLY C-BUNDLE-LAYOUT C-BUNDLE-ERRORS

private enum BundleFixtureError: Error {
    case missing(String)
}

private func makeTemporaryBundleDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ForgeRuleCore-bundle-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func installBundleFixture(
    _ name: String,
    extension fileExtension: String,
    subdirectory: String = "Fixtures/Bundle",
    as destinationName: String,
    in directory: URL
) throws {
    guard
        let source = Bundle.module.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: subdirectory
        )
    else {
        throw BundleFixtureError.missing(name)
    }
    try FileManager.default.copyItem(
        at: source,
        to: directory.appendingPathComponent(destinationName)
    )
}

@Test func forge_rules_geosite_fixture_matches_pinned_provenance() throws {
    guard
        let fixtureURL = Bundle.module.url(
            forResource: "geosite-valid",
            withExtension: "json",
            subdirectory: "Fixtures/Bundle"
        )
    else {
        throw BundleFixtureError.missing("geosite-valid")
    }

    let fixture = try Data(contentsOf: fixtureURL)
    let digest = SHA256.hash(data: fixture)
        .map { String(format: "%02x", $0) }
        .joined()
    let expectedDigest = "0f224dfb0a0ef20db3033aeb588523c733518d6c82d06f8f393bc967e1d212e3"

    #expect(digest == expectedDigest)
}

private func bundleInput(domain: String?, ip: FBIPv4) -> RuleInput {
    RuleInput(
        originalIP: ip,
        resolvedIP: ip,
        domain: domain,
        port: 443,
        proto: .tcp,
        factsResolved: true
    )
}

private func expectBundleError(
    _ expected: ForgeRuleCoreBundleError,
    performing operation: () throws -> Void
) {
    do {
        try operation()
        Issue.record("Expected ForgeRuleCoreBundleError")
    } catch let error as ForgeRuleCoreBundleError {
        #expect(error == expected)
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test func bundle_app_group_assembly_loads_real_geosite_and_geoip_fixtures() throws {
    let container = try makeTemporaryBundleDirectory()
    defer { try? FileManager.default.removeItem(at: container) }
    let rulesDirectory = container.appendingPathComponent(
        ForgeRuleCoreBundle.rulesSubdirectory,
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: rulesDirectory, withIntermediateDirectories: true)

    try installBundleFixture(
        "geosite-valid",
        extension: "json",
        as: ForgeRuleCoreBundleResource.geosite.rawValue,
        in: rulesDirectory
    )
    try installBundleFixture(
        "GeoIP2-Country-Test",
        extension: "mmdb",
        subdirectory: "Fixtures",
        as: ForgeRuleCoreBundleResource.geoIP.rawValue,
        in: rulesDirectory
    )

    let appGroup = "group.com.coderquinn.forge-rule-core.tests"
    let core = try ForgeRuleCoreBundle.makeRuleCore(
        appGroup: appGroup,
        rules: [
            Rule(condition: .geosite("category-test"), action: .proxy("geosite")),
            Rule(condition: .geoip("us"), action: .proxy("geoip")),
        ],
        containerURLResolver: { identifier in
            identifier == appGroup ? container : nil
        }
    )

    #expect(
        core.route(bundleInput(domain: "www.example.test", ip: FBIPv4(a: 1, b: 1, c: 1, d: 1)))
            == .proxy("geosite")
    )
    #expect(
        core.route(bundleInput(domain: "unlisted.test", ip: FBIPv4(a: 214, b: 78, c: 120, d: 1)))
            == .proxy("geoip")
    )
}

@Test func bundle_app_group_assembly_rejects_an_unresolved_container() {
    let appGroup = "group.com.coderquinn.missing"
    expectBundleError(.invalidAppGroupIdentifier(appGroup)) {
        _ = try ForgeRuleCoreBundle.makeRuleCore(
            appGroup: appGroup,
            rules: [],
            containerURLResolver: { _ in nil }
        )
    }
}

@Test func bundle_assembly_reports_missing_geosite() throws {
    let directory = try makeTemporaryBundleDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent(ForgeRuleCoreBundleResource.geosite.rawValue).path

    expectBundleError(.missingResource(resource: .geosite, path: path)) {
        _ = try ForgeRuleCoreBundle.makeRuleCore(resourceDirectory: directory, rules: [])
    }
}

@Test func bundle_assembly_rejects_a_resource_directory() throws {
    let directory = try makeTemporaryBundleDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let geositeURL = directory.appendingPathComponent(
        ForgeRuleCoreBundleResource.geosite.rawValue,
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: geositeURL, withIntermediateDirectories: true)

    expectBundleError(.missingResource(resource: .geosite, path: geositeURL.path)) {
        _ = try ForgeRuleCoreBundle.makeRuleCore(resourceDirectory: directory, rules: [])
    }
}

@Test func bundle_assembly_reports_missing_geoip() throws {
    let directory = try makeTemporaryBundleDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try installBundleFixture(
        "geosite-valid",
        extension: "json",
        as: ForgeRuleCoreBundleResource.geosite.rawValue,
        in: directory
    )
    let path = directory.appendingPathComponent(ForgeRuleCoreBundleResource.geoIP.rawValue).path

    expectBundleError(.missingResource(resource: .geoIP, path: path)) {
        _ = try ForgeRuleCoreBundle.makeRuleCore(resourceDirectory: directory, rules: [])
    }
}

@Test func bundle_assembly_reports_malformed_geosite() throws {
    let directory = try makeTemporaryBundleDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try installBundleFixture(
        "geosite-malformed",
        extension: "json",
        as: ForgeRuleCoreBundleResource.geosite.rawValue,
        in: directory
    )
    try installBundleFixture(
        "GeoIP2-Country-Test",
        extension: "mmdb",
        subdirectory: "Fixtures",
        as: ForgeRuleCoreBundleResource.geoIP.rawValue,
        in: directory
    )
    let path = directory.appendingPathComponent(ForgeRuleCoreBundleResource.geosite.rawValue).path

    expectBundleError(
        .invalidResource(
            resource: .geosite,
            path: path,
            failure: .unreadableOrMalformed
        )
    ) {
        _ = try ForgeRuleCoreBundle.makeRuleCore(resourceDirectory: directory, rules: [])
    }
}

@Test func bundle_assembly_reports_malformed_geoip() throws {
    let directory = try makeTemporaryBundleDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try installBundleFixture(
        "geosite-valid",
        extension: "json",
        as: ForgeRuleCoreBundleResource.geosite.rawValue,
        in: directory
    )
    try installBundleFixture(
        "geoip-malformed",
        extension: "mmdb",
        as: ForgeRuleCoreBundleResource.geoIP.rawValue,
        in: directory
    )
    let path = directory.appendingPathComponent(ForgeRuleCoreBundleResource.geoIP.rawValue).path

    do {
        _ = try ForgeRuleCoreBundle.makeRuleCore(resourceDirectory: directory, rules: [])
        Issue.record("Expected invalid geoip resource")
    } catch let error as ForgeRuleCoreBundleError {
        guard case .invalidResource(.geoIP, let actualPath, .mmdbOpenFailed(let status)) = error else {
            Issue.record("Unexpected bundle error: \(error)")
            return
        }
        #expect(actualPath == path)
        #expect(status != 0)
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}
