@testable import ForgeRuleCore
import ForgeBase
import Foundation
import Testing

// Contract IDs: C-MMDB-BYTE-ORDER C-MMDB-OWNERSHIP C-MMDB-TEARDOWN

private enum MMDBFixtureError: Error {
    case missing(String)
}

private func mmdbFixtureURL(_ name: String) throws -> URL {
    guard let url = Bundle.module.url(
        forResource: name,
        withExtension: "mmdb",
        subdirectory: "Fixtures"
    ) else {
        throw MMDBFixtureError.missing(name)
    }
    return url
}

private let fixtureUSIPv4 = FBIPv4(a: 214, b: 78, c: 120, d: 1)

@Test func mmdb_reader_reads_official_country_fixture() throws {
    let reader = try MMDBReader(url: mmdbFixtureURL("GeoIP2-Country-Test"))
    #expect(reader.countryCode(of: fixtureUSIPv4) == .us)
}

@Test func mmdb_readers_own_independent_database_handles() throws {
    let countryReader = try MMDBReader(url: mmdbFixtureURL("GeoIP2-Country-Test"))
    let stringReader = try MMDBReader(url: mmdbFixtureURL("MaxMind-DB-string-value-entries"))

    #expect(countryReader.countryCode(of: fixtureUSIPv4) == .us)
    #expect(stringReader.countryCode(of: fixtureUSIPv4) == nil)
}

@Test func mmdb_reader_rejects_missing_path_while_another_reader_is_open() throws {
    let countryReader = try MMDBReader(url: mmdbFixtureURL("GeoIP2-Country-Test"))
    let missingURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("ForgeRuleCore-missing-\(UUID().uuidString).mmdb")

    #expect(throws: MMDBOpenError.self) {
        try MMDBReader(url: missingURL)
    }
    #expect(countryReader.countryCode(of: fixtureUSIPv4) == .us)
}

@Test func mmdb_reader_teardown_does_not_invalidate_another_reader() throws {
    var firstReader: MMDBReader? = try MMDBReader(url: mmdbFixtureURL("GeoIP2-Country-Test"))
    let secondReader = try MMDBReader(url: mmdbFixtureURL("GeoIP2-Country-Test"))

    #expect(firstReader?.countryCode(of: fixtureUSIPv4) == .us)
    firstReader = nil
    #expect(secondReader.countryCode(of: fixtureUSIPv4) == .us)
}
