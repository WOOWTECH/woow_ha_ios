#if CLOUD_EDITION
import Foundation
@testable import Shared
import Testing

// These tests live under `Tests/Shared/Models/` because it is the closest directory that is a
// file-system synchronized group of the Tests-Shared target; new directories at the `Tests/Shared` root
// would need project file edits to be compiled.

private struct UnexpectedCallError: Error {}

/// A typed fake repository that replays a scripted sequence of ``TokenPollResult`` values, the way the
/// real repository would after classifying backend answers. No JSON is involved on purpose: wire-level
/// decoding is covered by the fixture contract tests, not here.
private actor ScriptedPollRepository: WoowPaasRepository {
    private var script: [TokenPollResult]
    private(set) var pollCount = 0
    private(set) var receivedIntervals: [Int] = []
    /// Mirrors the session write the real repository performs on a successful poll.
    private(set) var tokenStored = false

    init(script: [TokenPollResult]) {
        self.script = script
    }

    func requestDeviceCode() async throws -> DeviceCodeResponse { throw UnexpectedCallError() }

    func pollToken(deviceCode: String, currentInterval: Int) async throws -> TokenPollResult {
        pollCount += 1
        receivedIntervals.append(currentInterval)
        guard !script.isEmpty else { return .pending }
        let next = script.removeFirst()
        if next == .success {
            tokenStored = true
        }
        return next
    }

    func provision() async throws -> ProvisionResponse { throw UnexpectedCallError() }

    func getStatus() async throws -> StatusResponse { throw UnexpectedCallError() }
}

/// A hand-rolled wall clock the fakes can advance, standing in for swift-clocks' `TestClock` (whose
/// `Clocks` product is not linked to this project's targets).
private final class FakeWallClock: @unchecked Sendable {
    private let lock = NSLock()
    private var now = Date(timeIntervalSinceReferenceDate: 0)

    func current() -> Date {
        lock.withLock { now }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock { now += interval }
    }
}

/// Records every requested delay and returns immediately, advancing the fake wall clock instead of
/// letting real time pass.
private actor RecordingSleeper: WoowSleeper {
    private(set) var sleeps: [Duration] = []
    private let clock: FakeWallClock?

    init(advancing clock: FakeWallClock? = nil) {
        self.clock = clock
    }

    func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
        sleeps.append(duration)
        clock?.advance(by: TimeInterval(duration.components.seconds))
    }
}

/// Sleeps long enough to never wake up on its own, so a test can cancel the loop mid-sleep.
private struct HangingSleeper: WoowSleeper {
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: .seconds(60 * 60))
    }
}

private let fixedDate: @Sendable () -> Date = { Date(timeIntervalSinceReferenceDate: 0) }

@Suite("DeviceFlowPoller")
struct DeviceFlowPollerTests {
    @Test("Given pending twice then success, polls at the recorded interval and reports authorized")
    func pendingThenSuccessPollsAtRecordedIntervalThenAuthorizes() async throws {
        let repository = ScriptedPollRepository(script: [.pending, .pending, .success])
        let sleeper = RecordingSleeper()
        let poller = DeviceFlowPoller(repository: repository, sleeper: sleeper, dateProvider: fixedDate)

        let outcome = try await poller.poll(deviceCode: "device-code", interval: 5, expiresIn: 600)

        #expect(outcome == .authorized)
        let sleeps = await sleeper.sleeps
        #expect(sleeps == [.seconds(5), .seconds(5), .seconds(5)])
        let pollCount = await repository.pollCount
        #expect(pollCount == 3)
        let tokenStored = await repository.tokenStored
        #expect(tokenStored)
    }

    @Test("Given slow_down, the poll interval grows and the new interval is reported back to the repository")
    func slowDownIncreasesPollInterval() async throws {
        let repository = ScriptedPollRepository(script: [.slowDown(newInterval: 10), .pending, .success])
        let sleeper = RecordingSleeper()
        let poller = DeviceFlowPoller(repository: repository, sleeper: sleeper, dateProvider: fixedDate)

        let outcome = try await poller.poll(deviceCode: "device-code", interval: 5, expiresIn: 600)

        #expect(outcome == .authorized)
        let sleeps = await sleeper.sleeps
        #expect(sleeps == [.seconds(5), .seconds(10), .seconds(10)])
        let receivedIntervals = await repository.receivedIntervals
        #expect(receivedIntervals == [5, 10, 10])
    }

    @Test("Given access_denied, polling stops and the denied message surfaces")
    func accessDeniedStopsPollingSurfacesDeniedState() async throws {
        let repository = ScriptedPollRepository(script: [.failed(error: "使用者拒絕授權")])
        let poller = DeviceFlowPoller(repository: repository, sleeper: RecordingSleeper(), dateProvider: fixedDate)

        let outcome = try await poller.poll(deviceCode: "device-code", interval: 5, expiresIn: 600)

        #expect(outcome == .failed(message: "使用者拒絕授權"))
        let pollCount = await repository.pollCount
        #expect(pollCount == 1)
    }

    @Test("Given expired_token from the backend, polling stops and the expired message surfaces")
    func expiredTokenStopsPollingSurfacesExpiredState() async throws {
        let repository = ScriptedPollRepository(script: [.failed(error: "expired_token")])
        let poller = DeviceFlowPoller(repository: repository, sleeper: RecordingSleeper(), dateProvider: fixedDate)

        let outcome = try await poller.poll(deviceCode: "device-code", interval: 5, expiresIn: 600)

        #expect(outcome == .failed(message: "expired_token"))
        let pollCount = await repository.pollCount
        #expect(pollCount == 1)
    }

    @Test("Given transient errors, backoff doubles until the wall clock deadline expires the device code")
    func transientErrorsBackOffThenDeviceCodeExpiresAtWallClockDeadline() async throws {
        let clock = FakeWallClock()
        let repository = ScriptedPollRepository(script: [
            .transientError(reason: "HTTP 503"),
            .transientError(reason: "HTTP 503"),
        ])
        let sleeper = RecordingSleeper(advancing: clock)
        let poller = DeviceFlowPoller(repository: repository, sleeper: sleeper, dateProvider: { clock.current() })

        // Deadline at t=8s: the first transient poll happens at t=5 (still alive), the backoff doubles
        // to 10s, and the second poll at t=15 is past the deadline.
        let outcome = try await poller.poll(deviceCode: "device-code", interval: 5, expiresIn: 8)

        #expect(outcome == .deviceCodeExpired(message: "連線逾時，請重新開始登入"))
        let sleeps = await sleeper.sleeps
        #expect(sleeps == [.seconds(5), .seconds(10)])
    }

    @Test("Given cancellation mid poll, the loop stops without a token write")
    func cancellationMidPollStopsWithoutTokenWrite() async throws {
        let repository = ScriptedPollRepository(script: [.success])
        let poller = DeviceFlowPoller(repository: repository, sleeper: HangingSleeper(), dateProvider: fixedDate)

        let task = Task {
            try await poller.poll(deviceCode: "device-code", interval: 5, expiresIn: 600)
        }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        let pollCount = await repository.pollCount
        #expect(pollCount == 0)
        let tokenStored = await repository.tokenStored
        #expect(!tokenStored)
    }
}
#endif
