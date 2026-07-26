import Foundation

/// Serializes CloudKit mutations and coalesces repeated automatic sync requests.
///
/// CloudSyncService is main-actor isolated, but actor isolation alone does not
/// prevent async methods from interleaving at suspension points. This
/// coordinator provides an explicit, FIFO critical section across those awaits.
@MainActor
final class SyncOperationCoordinator {
    enum CoalescingKey: Hashable {
        case push
        case pull
    }

    private var isLocked = false
    private var lockWaiters: [CheckedContinuation<Void, Never>] = []

    private var activeFlights: [CoalescingKey: Task<Void, Never>] = [:]
    private var trailingOperations: [
        CoalescingKey: @MainActor () async -> Void
    ] = [:]

    /// Runs one operation after every previously submitted operation finishes.
    func runExclusive<T>(
        _ operation: @MainActor () async throws -> T
    ) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await operation()
    }

    /// Joins an active flight for `key` and requests at most one trailing run,
    /// using the most recently submitted closure for that trailing run.
    ///
    /// The trailing run is important for local saves or CloudKit notifications
    /// that arrive after the active operation captured its input snapshot.
    func runCoalesced(
        key: CoalescingKey,
        operation: @escaping @MainActor () async -> Void
    ) async {
        if let activeFlight = activeFlights[key] {
            trailingOperations[key] = operation
            await activeFlight.value
            return
        }

        let flight = Task { @MainActor [weak self] in
            guard let self else { return }
            var nextOperation = operation

            while true {
                await runExclusive {
                    await nextOperation()
                }

                guard let trailingOperation = trailingOperations.removeValue(forKey: key) else {
                    break
                }
                nextOperation = trailingOperation
            }

            activeFlights[key] = nil
        }

        activeFlights[key] = flight
        await flight.value
    }

    private func acquire() async {
        guard isLocked else {
            isLocked = true
            return
        }

        await withCheckedContinuation { continuation in
            lockWaiters.append(continuation)
        }
    }

    private func release() {
        guard !lockWaiters.isEmpty else {
            isLocked = false
            return
        }

        let next = lockWaiters.removeFirst()
        next.resume()
    }
}
