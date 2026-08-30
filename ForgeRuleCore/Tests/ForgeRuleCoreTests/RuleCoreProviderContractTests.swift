@testable import ForgeRuleCore
import ForgeBase
import Foundation
import Testing

// Contract IDs: C-ATOMIC-SNAPSHOT C-RELOAD-VALIDATION C-ROLLBACK-LKG

private struct ProviderCountryLookup: CountryLookup {
    func lookupCountryCode(ip _: FBIPv4) -> CountryCode? {
        nil
    }
}

private final class ProviderValidationGate: @unchecked Sendable {
    private let entered = DispatchSemaphore(value: 0)
    private let proceed = DispatchSemaphore(value: 0)

    func markEnteredAndWait() {
        entered.signal()
        proceed.wait()
    }

    func waitUntilEntered() -> Bool {
        entered.wait(timeout: .now() + 1) == .success
    }

    func allowValidation() {
        proceed.signal()
    }
}

private func providerInput() -> RuleInput {
    let address = FBIPv4(a: 1, b: 1, c: 1, d: 1)
    return RuleInput(
        originalIP: address,
        resolvedIP: address,
        domain: "provider.example.test",
        port: 443,
        proto: .tcp,
        factsResolved: true
    )
}

private func makeProviderCore(
    revision: RuleRevision?,
    action: RuleAction
) throws -> (RuleCore, URL) {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ForgeRuleCore-provider-\(UUID().uuidString).json")
    try Data(#"{"geosites":[]}"#.utf8).write(to: url)
    let engine = RuleEngine(
        rules: [Rule(condition: .any, action: action)],
        geosite: try GeoSiteDB(jsonURL: url),
        geoip: GeoIPDB(lookup: ProviderCountryLookup())
    )
    return (RuleCore(engine: engine, revision: revision), url)
}

private func makeProviderSnapshot(
    _ rawRevision: String,
    action: RuleAction
) throws -> (RuleCoreSnapshot, URL) {
    let revision = try #require(RuleRevision(rawValue: rawRevision))
    let (core, url) = try makeProviderCore(revision: revision, action: action)
    return (try #require(RuleCoreSnapshot(core: core)), url)
}

private func expectProviderError(
    _ expected: RuleCoreProviderError,
    performing operation: () throws -> Void
) {
    do {
        try operation()
        Issue.record("Expected RuleCoreProviderError")
    } catch let error as RuleCoreProviderError {
        #expect(error == expected)
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test func snapshot_requires_an_explicit_rule_revision() throws {
    let (core, url) = try makeProviderCore(revision: nil, action: .direct)
    defer { try? FileManager.default.removeItem(at: url) }

    switch RuleCoreSnapshot(core: core) {
    case nil:
        break
    case .some:
        Issue.record("A snapshot without a revision must be rejected")
    }
}

@Test func slow_reload_validation_does_not_block_the_active_read_path() async throws {
    let (first, firstURL) = try makeProviderSnapshot("rules-v1", action: .direct)
    let (second, secondURL) = try makeProviderSnapshot("rules-v2", action: .reject)
    defer {
        try? FileManager.default.removeItem(at: firstURL)
        try? FileManager.default.removeItem(at: secondURL)
    }
    let provider = RuleCoreProvider(initial: first)
    let gate = ProviderValidationGate()

    let reload = Task.detached {
        try provider.reload(second) { _ in
            gate.markEnteredAndWait()
            return true
        }
    }

    let validatorStarted = await Task.detached { gate.waitUntilEntered() }.value
    #expect(validatorStarted)
    let result = provider.classify(providerInput())
    #expect(result.decision == .direct)
    #expect(result.revision == first.revision)

    gate.allowValidation()
    let state = try await reload.value
    #expect(state.activeRevision == second.revision)
}

@Test func provider_classifies_with_the_initial_last_known_good_snapshot() throws {
    let (snapshot, url) = try makeProviderSnapshot("rules-v1", action: .direct)
    defer { try? FileManager.default.removeItem(at: url) }
    let provider = RuleCoreProvider(initial: snapshot)

    let result = provider.classify(providerInput())

    #expect(result.decision == .direct)
    #expect(result.revision == snapshot.revision)
    #expect(provider.state == RuleCoreProviderState(
        activeRevision: snapshot.revision,
        previousRevision: nil
    ))
}

@Test func validated_reload_atomically_activates_and_retains_the_previous_snapshot() throws {
    let (first, firstURL) = try makeProviderSnapshot("rules-v1", action: .direct)
    let (second, secondURL) = try makeProviderSnapshot("rules-v2", action: .reject)
    defer {
        try? FileManager.default.removeItem(at: firstURL)
        try? FileManager.default.removeItem(at: secondURL)
    }
    let provider = RuleCoreProvider(initial: first)

    let state = try provider.reload(second) { candidate in
        candidate.classify(providerInput()).decision == .reject
    }

    #expect(state.activeRevision == second.revision)
    #expect(state.previousRevision == first.revision)
    #expect(provider.classify(providerInput()).decision == .reject)
    #expect(provider.classify(providerInput()).revision == second.revision)
}

@Test func rejected_reload_leaves_active_and_previous_state_unchanged() throws {
    let (first, firstURL) = try makeProviderSnapshot("rules-v1", action: .direct)
    let (rejected, rejectedURL) = try makeProviderSnapshot("rules-v2", action: .reject)
    defer {
        try? FileManager.default.removeItem(at: firstURL)
        try? FileManager.default.removeItem(at: rejectedURL)
    }
    let provider = RuleCoreProvider(initial: first)

    expectProviderError(.rejectedRevision(rejected.revision)) {
        try provider.reload(rejected) { _ in false }
    }

    #expect(provider.state.activeRevision == first.revision)
    #expect(provider.state.previousRevision == nil)
    #expect(provider.classify(providerInput()).decision == .direct)
}

@Test func reload_rejects_reusing_the_active_revision() throws {
    let (first, firstURL) = try makeProviderSnapshot("rules-v1", action: .direct)
    let (duplicate, duplicateURL) = try makeProviderSnapshot("rules-v1", action: .reject)
    defer {
        try? FileManager.default.removeItem(at: firstURL)
        try? FileManager.default.removeItem(at: duplicateURL)
    }
    let provider = RuleCoreProvider(initial: first)

    expectProviderError(.duplicateRevision(first.revision)) {
        try provider.reload(duplicate) { _ in true }
    }

    #expect(provider.classify(providerInput()).decision == .direct)
    #expect(provider.state.previousRevision == nil)
}

@Test func validated_rollback_restores_previous_lkg_and_discards_failed_active() throws {
    let (first, firstURL) = try makeProviderSnapshot("rules-v1", action: .direct)
    let (second, secondURL) = try makeProviderSnapshot("rules-v2", action: .reject)
    defer {
        try? FileManager.default.removeItem(at: firstURL)
        try? FileManager.default.removeItem(at: secondURL)
    }
    let provider = RuleCoreProvider(initial: first)
    try provider.reload(second) { _ in true }

    let state = try provider.rollback { candidate in
        candidate.classify(providerInput()).decision == .direct
    }

    #expect(state.activeRevision == first.revision)
    #expect(state.previousRevision == nil)
    #expect(provider.classify(providerInput()).decision == .direct)
    #expect(provider.classify(providerInput()).revision == first.revision)
}

@Test func rejected_rollback_keeps_both_current_and_previous_snapshots() throws {
    let (first, firstURL) = try makeProviderSnapshot("rules-v1", action: .direct)
    let (second, secondURL) = try makeProviderSnapshot("rules-v2", action: .reject)
    defer {
        try? FileManager.default.removeItem(at: firstURL)
        try? FileManager.default.removeItem(at: secondURL)
    }
    let provider = RuleCoreProvider(initial: first)
    try provider.reload(second) { _ in true }

    expectProviderError(.rollbackRejected(first.revision)) {
        try provider.rollback { _ in false }
    }

    #expect(provider.state.activeRevision == second.revision)
    #expect(provider.state.previousRevision == first.revision)
    #expect(provider.classify(providerInput()).decision == .reject)
}

@Test func rollback_without_a_previous_snapshot_is_explicitly_unavailable() throws {
    let (snapshot, url) = try makeProviderSnapshot("rules-v1", action: .direct)
    defer { try? FileManager.default.removeItem(at: url) }
    let provider = RuleCoreProvider(initial: snapshot)

    expectProviderError(.noRollbackCandidate) {
        try provider.rollback { _ in true }
    }

    #expect(provider.state.activeRevision == snapshot.revision)
}

@Test func concurrent_classification_never_mixes_snapshot_revision_and_decision() async throws {
    let (first, firstURL) = try makeProviderSnapshot("rules-v1", action: .direct)
    let (second, secondURL) = try makeProviderSnapshot("rules-v2", action: .reject)
    defer {
        try? FileManager.default.removeItem(at: firstURL)
        try? FileManager.default.removeItem(at: secondURL)
    }
    let provider = RuleCoreProvider(initial: first)
    let input = providerInput()

    let results = await withTaskGroup(of: RuleClassification.self) { group in
        for _ in 0..<200 {
            group.addTask {
                provider.classify(input)
            }
        }
        group.addTask {
            _ = try? provider.reload(second) { _ in true }
            return provider.classify(input)
        }

        var results: [RuleClassification] = []
        for await result in group {
            results.append(result)
        }
        return results
    }

    #expect(results.count == 201)
    for result in results {
        let isFirst = result.revision == first.revision && result.decision == .direct
        let isSecond = result.revision == second.revision && result.decision == .reject
        #expect(isFirst || isSecond)
    }
}
