import XCTest
@testable import PumpTally

@MainActor
final class SyncOperationCoordinatorTests: XCTestCase {
    private enum ExpectedError: Error {
        case failure
    }

    func testExclusiveOperationsNeverOverlapAcrossSuspensionPoints() async {
        let coordinator = SyncOperationCoordinator()
        var activeCount = 0
        var maximumActiveCount = 0

        let tasks = (0..<10).map { _ in
            Task { @MainActor in
                await coordinator.runExclusive {
                    activeCount += 1
                    maximumActiveCount = max(maximumActiveCount, activeCount)
                    try? await Task.sleep(for: .milliseconds(2))
                    activeCount -= 1
                }
            }
        }

        for task in tasks {
            await task.value
        }

        XCTAssertEqual(maximumActiveCount, 1)
        XCTAssertEqual(activeCount, 0)
    }

    func testRepeatedRequestsJoinActiveFlightAndProduceOneTrailingRun() async {
        let coordinator = SyncOperationCoordinator()
        let firstRunStarted = expectation(description: "First run started")
        var releaseFirstRun: CheckedContinuation<Void, Never>?
        var runCount = 0
        let operation: @MainActor () async -> Void = {
            runCount += 1
            if runCount == 1 {
                firstRunStarted.fulfill()
                await withCheckedContinuation { continuation in
                    releaseFirstRun = continuation
                }
            }
        }

        let firstRequest = Task { @MainActor in
            await coordinator.runCoalesced(key: .push, operation: operation)
        }

        await fulfillment(of: [firstRunStarted], timeout: 1)

        let duplicateRequests = (0..<5).map { _ in
            Task { @MainActor in
                await coordinator.runCoalesced(key: .push, operation: operation)
            }
        }

        try? await Task.sleep(for: .milliseconds(20))
        releaseFirstRun?.resume()

        await firstRequest.value
        for task in duplicateRequests {
            await task.value
        }

        XCTAssertEqual(runCount, 2)
    }

    func testTrailingRunUsesMostRecentlySubmittedOperation() async {
        let coordinator = SyncOperationCoordinator()
        let firstRunStarted = expectation(description: "First run started")
        var releaseFirstRun: CheckedContinuation<Void, Never>?
        var trailingValue = 0

        let firstRequest = Task { @MainActor in
            await coordinator.runCoalesced(key: .pull) {
                firstRunStarted.fulfill()
                await withCheckedContinuation { continuation in
                    releaseFirstRun = continuation
                }
            }
        }
        await fulfillment(of: [firstRunStarted], timeout: 1)

        let staleRequest = Task { @MainActor in
            await coordinator.runCoalesced(key: .pull) {
                trailingValue = 1
            }
        }
        try? await Task.sleep(for: .milliseconds(10))
        let latestRequest = Task { @MainActor in
            await coordinator.runCoalesced(key: .pull) {
                trailingValue = 2
            }
        }

        try? await Task.sleep(for: .milliseconds(20))
        releaseFirstRun?.resume()

        await firstRequest.value
        await staleRequest.value
        await latestRequest.value

        XCTAssertEqual(trailingValue, 2)
    }

    func testPushAndPullFlightsShareTheExclusivePipeline() async {
        let coordinator = SyncOperationCoordinator()
        var activeCount = 0
        var maximumActiveCount = 0

        let push = Task { @MainActor in
            await coordinator.runCoalesced(key: .push) {
                activeCount += 1
                maximumActiveCount = max(maximumActiveCount, activeCount)
                try? await Task.sleep(for: .milliseconds(10))
                activeCount -= 1
            }
        }
        let pull = Task { @MainActor in
            await coordinator.runCoalesced(key: .pull) {
                activeCount += 1
                maximumActiveCount = max(maximumActiveCount, activeCount)
                try? await Task.sleep(for: .milliseconds(10))
                activeCount -= 1
            }
        }

        await push.value
        await pull.value

        XCTAssertEqual(maximumActiveCount, 1)
    }

    func testExclusiveOperationBlocksCoalescedFlightUntilItFinishes() async {
        let coordinator = SyncOperationCoordinator()
        let exclusiveStarted = expectation(description: "Exclusive operation started")
        var releaseExclusive: CheckedContinuation<Void, Never>?
        var coalescedOperationRan = false

        let exclusive = Task { @MainActor in
            await coordinator.runExclusive {
                exclusiveStarted.fulfill()
                await withCheckedContinuation { continuation in
                    releaseExclusive = continuation
                }
            }
        }
        await fulfillment(of: [exclusiveStarted], timeout: 1)

        let push = Task { @MainActor in
            await coordinator.runCoalesced(key: .push) {
                coalescedOperationRan = true
            }
        }
        try? await Task.sleep(for: .milliseconds(20))

        XCTAssertFalse(coalescedOperationRan)
        releaseExclusive?.resume()

        await exclusive.value
        await push.value
        XCTAssertTrue(coalescedOperationRan)
    }

    func testThrowingOperationReleasesPipelineForNextRequest() async {
        let coordinator = SyncOperationCoordinator()

        do {
            try await coordinator.runExclusive {
                throw ExpectedError.failure
            }
            XCTFail("Expected operation to throw")
        } catch ExpectedError.failure {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let value = await coordinator.runExclusive { 42 }
        XCTAssertEqual(value, 42)
    }
}
