#if CLOUD_EDITION
import Foundation

/// Classification helpers turning token endpoint answers and transport failures into ``TokenPollResult``.
///
/// Follows RFC 8628 §3.5: `authorization_pending` and `slow_down` keep the flow alive, an HTTP 5xx is a
/// transient server-side failure worth retrying, and every other OAuth error (`access_denied`,
/// `expired_token`, …) is terminal.
enum TokenErrorClassifier {
    /// The status codes that say something went wrong on the backend side rather than with the request.
    static let serverErrorRange = 500 ... 599

    /// How much the polling interval grows on a `slow_down` answer, in seconds (RFC 8628 §3.5).
    private static let slowDownIntervalIncrementSeconds = 5

    /// The OAuth 2.0 device flow error codes that keep the polling loop alive (RFC 8628 §3.5).
    private enum OAuthDeviceFlowError {
        static let authorizationPending = "authorization_pending"
        static let slowDown = "slow_down"
    }

    /// Classifies a non-successful token endpoint response into a ``TokenPollResult``.
    ///
    /// - Parameters:
    ///   - httpCode: the HTTP status code of the response
    ///   - error: the parsed OAuth `error` field, or nil when it is absent or unparseable
    ///   - errorDescription: the parsed OAuth `error_description` field, if any
    ///   - currentInterval: the current polling interval in seconds, used to compute the slow-down backoff
    static func classify(
        httpCode: Int,
        error: String?,
        errorDescription: String?,
        currentInterval: Int
    ) -> TokenPollResult {
        if serverErrorRange.contains(httpCode) {
            return .transientError(reason: "伺服器暫時無法回應 (HTTP \(httpCode))")
        }
        switch error {
        case OAuthDeviceFlowError.authorizationPending:
            return .pending
        case OAuthDeviceFlowError.slowDown:
            return .slowDown(newInterval: currentInterval + slowDownIntervalIncrementSeconds)
        default:
            return .failed(error: errorDescription ?? error ?? "授權失敗")
        }
    }

    /// Classifies an error raised while polling the token endpoint.
    ///
    /// Network-layer failures (`URLError`, the counterpart of Android's `IOException` family such as
    /// timeouts and DNS failures) are transient and worth retrying; anything else is terminal. A
    /// `CancellationError` is re-thrown, and a `URLError.cancelled` is rewritten into one, so structured
    /// cancellation is never swallowed into a poll result.
    static func classify(transportError: Error) throws -> TokenPollResult {
        if transportError is CancellationError {
            throw transportError
        }
        if let urlError = transportError as? URLError {
            if urlError.code == .cancelled {
                throw CancellationError()
            }
            return .transientError(reason: urlError.localizedDescription)
        }
        return .failed(error: transportError.localizedDescription)
    }
}
#endif
