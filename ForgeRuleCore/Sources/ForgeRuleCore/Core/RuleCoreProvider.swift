import Foundation

/// A complete immutable rule kernel with the identity required for activation and rollback.
public struct RuleCoreSnapshot: Sendable {
    public let core: RuleCore
    public let revision: RuleRevision

    public init?(core: RuleCore) {
        guard let revision = core.revision else { return nil }
        self.core = core
        self.revision = revision
    }

    public func classify(_ input: RuleInput) -> RuleClassification {
        core.classify(input)
    }
}

public struct RuleCoreProviderState: Sendable, Equatable {
    public let activeRevision: RuleRevision
    public let previousRevision: RuleRevision?

    public init(activeRevision: RuleRevision, previousRevision: RuleRevision?) {
        self.activeRevision = activeRevision
        self.previousRevision = previousRevision
    }
}

public enum RuleCoreProviderError: Error, Sendable, Equatable {
    case duplicateRevision(RuleRevision)
    case rejectedRevision(RuleRevision)
    case noRollbackCandidate
    case rollbackRejected(RuleRevision)
}

public typealias RuleCoreSnapshotValidator = @Sendable (RuleCoreSnapshot) -> Bool

/// Owns one active immutable snapshot and at most one previously accepted rollback snapshot.
///
/// Validation runs without the read-state lock. Update operations are serialized, while
/// classifications capture the active snapshot under a short lock and evaluate outside it.
/// Validators must not call `reload` or `rollback` on this provider because update operations
/// are intentionally non-reentrant.
public final class RuleCoreProvider: @unchecked Sendable {
    private let stateLock = NSLock()
    private let updateLock = NSLock()
    private var active: RuleCoreSnapshot
    private var previous: RuleCoreSnapshot?

    public init(initial: RuleCoreSnapshot) {
        active = initial
    }

    public var state: RuleCoreProviderState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return RuleCoreProviderState(
            activeRevision: active.revision,
            previousRevision: previous?.revision
        )
    }

    public func classify(_ input: RuleInput) -> RuleClassification {
        stateLock.lock()
        let snapshot = active
        stateLock.unlock()
        return snapshot.classify(input)
    }

    @discardableResult
    public func reload(
        _ candidate: RuleCoreSnapshot,
        validating validator: RuleCoreSnapshotValidator
    ) throws -> RuleCoreProviderState {
        updateLock.lock()
        defer { updateLock.unlock() }

        let currentRevision = state.activeRevision
        guard candidate.revision != currentRevision else {
            throw RuleCoreProviderError.duplicateRevision(candidate.revision)
        }
        guard validator(candidate) else {
            throw RuleCoreProviderError.rejectedRevision(candidate.revision)
        }

        stateLock.lock()
        previous = active
        active = candidate
        let result = RuleCoreProviderState(
            activeRevision: active.revision,
            previousRevision: previous?.revision
        )
        stateLock.unlock()
        return result
    }

    @discardableResult
    public func rollback(
        validating validator: RuleCoreSnapshotValidator
    ) throws -> RuleCoreProviderState {
        updateLock.lock()
        defer { updateLock.unlock() }

        stateLock.lock()
        let candidate = previous
        stateLock.unlock()
        guard let candidate else {
            throw RuleCoreProviderError.noRollbackCandidate
        }
        guard validator(candidate) else {
            throw RuleCoreProviderError.rollbackRejected(candidate.revision)
        }

        stateLock.lock()
        active = candidate
        previous = nil
        let result = RuleCoreProviderState(
            activeRevision: active.revision,
            previousRevision: nil
        )
        stateLock.unlock()
        return result
    }
}
