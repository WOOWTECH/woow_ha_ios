#if CLOUD_EDITION
import Foundation
@testable import Shared
import Testing

// Ported from the Android `TokenErrorClassifierTest`: same case semantics, minimal synthetic inputs.
// Cases that need a real wire body belong to `WoowPaasFixtureContractTests` and its recorded fixtures.

private func isTransient(_ result: TokenPollResult) -> Bool {
    if case .transientError = result { return true }
    return false
}

private func isFailed(_ result: TokenPollResult) -> Bool {
    if case .failed = result { return true }
    return false
}

@Suite("TokenErrorClassifier")
struct TokenErrorClassifierTests {
    @Test("Given HTTP 5xx, the result is a transient error")
    func serverErrorIsTransient() {
        let result = TokenErrorClassifier.classify(httpCode: 503, error: nil, errorDescription: nil, currentInterval: 5)

        #expect(isTransient(result))
    }

    @Test("Given HTTP 5xx with an error body, 5xx still wins as a transient error")
    func serverErrorWinsOverErrorBody() {
        let result = TokenErrorClassifier.classify(
            httpCode: 500,
            error: "server_error",
            errorDescription: "boom",
            currentInterval: 5
        )

        #expect(isTransient(result))
    }

    @Test("Given authorization_pending, the result is pending")
    func authorizationPendingIsPending() {
        let result = TokenErrorClassifier.classify(
            httpCode: 400,
            error: "authorization_pending",
            errorDescription: nil,
            currentInterval: 5
        )

        #expect(result == .pending)
    }

    @Test("Given slow_down, the interval is increased by 5")
    func slowDownIncreasesIntervalByFive() {
        let result = TokenErrorClassifier.classify(
            httpCode: 400,
            error: "slow_down",
            errorDescription: nil,
            currentInterval: 5
        )

        #expect(result == .slowDown(newInterval: 10))
    }

    @Test("Given access_denied, the result is a terminal failure carrying the description")
    func accessDeniedIsTerminal() {
        let result = TokenErrorClassifier.classify(
            httpCode: 400,
            error: "access_denied",
            errorDescription: "使用者拒絕授權",
            currentInterval: 5
        )

        #expect(result == .failed(error: "使用者拒絕授權"))
    }

    @Test("Given expired_token, the result is a terminal failure")
    func expiredTokenIsTerminal() {
        let result = TokenErrorClassifier.classify(
            httpCode: 400,
            error: "expired_token",
            errorDescription: nil,
            currentInterval: 5
        )

        #expect(result == .failed(error: "expired_token"))
    }

    @Test("Given an unknown OAuth error, the result is a terminal failure")
    func unknownOAuthErrorIsTerminal() {
        let result = TokenErrorClassifier.classify(
            httpCode: 400,
            error: "invalid_grant",
            errorDescription: nil,
            currentInterval: 5
        )

        #expect(result == .failed(error: "invalid_grant"))
    }

    @Test("Given a 4xx without a parseable error, the result is a terminal failure")
    func unparseableClientErrorIsTerminal() {
        let result = TokenErrorClassifier.classify(httpCode: 400, error: nil, errorDescription: nil, currentInterval: 5)

        #expect(isFailed(result))
    }

    @Test(
        "Given a network-layer URLError, the result is a transient error",
        arguments: [URLError.Code.timedOut, .cannotFindHost, .notConnectedToInternet, .networkConnectionLost]
    )
    func networkLayerErrorIsTransient(code: URLError.Code) throws {
        let result = try TokenErrorClassifier.classify(transportError: URLError(code))

        #expect(isTransient(result))
    }

    @Test("Given an unexpected error, the result is a terminal failure")
    func unexpectedErrorIsTerminal() throws {
        struct SomethingOdd: Error {}

        let result = try TokenErrorClassifier.classify(transportError: SomethingOdd())

        #expect(isFailed(result))
    }

    @Test("Given a CancellationError, it is re-thrown, not swallowed")
    func cancellationIsRethrown() {
        #expect(throws: CancellationError.self) {
            try TokenErrorClassifier.classify(transportError: CancellationError())
        }
    }

    @Test("Given a URLError.cancelled, cancellation is surfaced as a thrown CancellationError")
    func urlErrorCancelledIsRethrownAsCancellation() {
        #expect(throws: CancellationError.self) {
            try TokenErrorClassifier.classify(transportError: URLError(.cancelled))
        }
    }
}
#endif
