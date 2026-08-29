#if CLOUD_EDITION
import Foundation

/// Minimal suspension point abstraction so the polling engine can be tested without real time passing.
///
/// The production implementation is ``TaskSleeper``; tests substitute a fake that records the requested
/// delays and returns immediately. (`swift-clocks` is resolved transitively in this project but its
/// `Clocks` product is not linked to any target, so this protocol stands in for an injected
/// `any Clock<Duration>` without adding a package product dependency.)
public protocol WoowSleeper: Sendable {
    /// Suspends the caller for `duration`.
    ///
    /// - Throws: `CancellationError` when the surrounding task is cancelled, so a cancelled polling loop
    ///   stops right away instead of waiting the delay out
    func sleep(for duration: Duration) async throws
}

/// The production ``WoowSleeper``, backed by `Task.sleep`.
public struct TaskSleeper: WoowSleeper {
    public init() {}

    public func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

/// Ceiling for the exponential backoff applied while the backend is unreachable, in seconds.
private let maxPollBackoffSeconds = 60

/// How a finished polling loop ended. Cancellation is not an outcome: it propagates as a thrown
/// `CancellationError`, because a user leaving the screen is a normal path, not a result to display.
public enum DeviceFlowPollOutcome: Equatable, Sendable {
    /// The user authorized the device; the credentials are already stored in the ``WoowPaasSession``, so
    /// nothing has to be carried over by the caller.
    case authorized
    /// The device code expired while the backend was unreachable, the client-side bound on the loop.
    case deviceCodeExpired(message: String)
    /// The backend answered with a terminal failure (`access_denied`, `expired_token`, …).
    case failed(message: String)
}

/// The polling half of the OAuth 2.0 device flow (RFC 8628 §3.4-3.5).
///
/// Polls the token endpoint until the user authorizes, the device code expires or a terminal error
/// occurs. Transient failures (network hiccups, HTTP 5xx) do not abort the flow: the loop keeps polling
/// with an exponential backoff and surfaces a "reconnecting" hint, bounded by the device code lifetime.
///
/// The engine is a plain structured `async` function: its lifetime is exactly the lifetime of the task
/// that runs it (a SwiftUI `.task(id:)` in the cloud onboarding screens), and cancelling that task
/// cancels the loop between polls.
public struct DeviceFlowPoller {
    private let repository: any WoowPaasRepository
    private let sleeper: any WoowSleeper
    private let dateProvider: @Sendable () -> Date

    /// - Parameters:
    ///   - repository: performs the actual token polls and stores the issued session
    ///   - sleeper: the suspension point between two polls; injectable so tests control time
    ///   - dateProvider: the wall clock the device code deadline is checked against; a wall clock rather
    ///     than a poll counter because a frozen application wakes up with time already elapsed
    public init(
        repository: any WoowPaasRepository,
        sleeper: any WoowSleeper = TaskSleeper(),
        dateProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.repository = repository
        self.sleeper = sleeper
        self.dateProvider = dateProvider
    }

    /// Polls the token endpoint until the flow reaches an outcome.
    ///
    /// - Parameters:
    ///   - deviceCode: the code obtained from ``WoowPaasRepository/requestDeviceCode()``
    ///   - interval: the polling interval in seconds the backend asked for
    ///   - expiresIn: the device code lifetime in seconds, from which the wall clock deadline is computed
    ///   - onReconnectingChanged: reports when the loop starts riding out transient failures (true) and
    ///     when a poll got through again (false), so the caller can show and hide a reconnecting hint
    /// - Throws: `CancellationError` when the surrounding task is cancelled; nothing else escapes, every
    ///   other failure is folded into the returned outcome or retried
    public func poll(
        deviceCode: String,
        interval: Int,
        expiresIn: Int,
        onReconnectingChanged: @Sendable (Bool) -> Void = { _ in }
    ) async throws -> DeviceFlowPollOutcome {
        // Client-side upper bound: once the device code has expired we stop even if the server is
        // unreachable. While the server answers, it stays the authority on expiry (`expired_token`).
        let deadline = dateProvider().addingTimeInterval(TimeInterval(expiresIn))
        var currentInterval = interval
        var backoffInterval = interval
        var isReconnecting = false

        func setReconnecting(_ value: Bool) {
            guard isReconnecting != value else { return }
            isReconnecting = value
            onReconnectingChanged(value)
        }

        while true {
            try await sleeper.sleep(for: .seconds(backoffInterval))

            switch try await repository.pollToken(deviceCode: deviceCode, currentInterval: currentInterval) {
            case .success:
                return .authorized
            case .pending:
                setReconnecting(false)
                backoffInterval = currentInterval
            case let .slowDown(newInterval):
                currentInterval = newInterval
                backoffInterval = newInterval
                setReconnecting(false)
            case .transientError:
                if dateProvider() >= deadline {
                    return .deviceCodeExpired(message: "連線逾時，請重新開始登入")
                }
                setReconnecting(true)
                backoffInterval = min(backoffInterval * 2, maxPollBackoffSeconds)
            case let .failed(error):
                return .failed(message: error)
            }
        }
    }
}
#endif
