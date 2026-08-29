#if CLOUD_EDITION
import Foundation

/// Outcome of a single poll of the OAuth 2.0 device flow token endpoint (RFC 8628 §3.4).
///
/// The distinction that matters to callers is whether the flow may continue: `.pending`, `.slowDown` and
/// `.transientError` all mean "keep polling", while `.success` and `.failed` end the loop.
public enum TokenPollResult: Equatable, Sendable {
    /// The user authorized the device, and the session that was issued is already stored.
    ///
    /// The credentials themselves are not reported: they live in the ``WoowPaasSession`` so there is a
    /// single place holding them.
    case success

    /// The user has not authorized the device yet.
    case pending

    /// The backend asked the client to poll less often; `newInterval` is the new delay in seconds.
    case slowDown(newInterval: Int)

    /// A retryable failure such as a network hiccup or an HTTP 5xx response.
    /// Per RFC 8628 §3.4 the client should keep polling instead of aborting the flow.
    case transientError(reason: String)

    /// A terminal failure such as `access_denied`, `expired_token` or any other OAuth error.
    /// Polling must stop.
    case failed(error: String)
}
#endif
