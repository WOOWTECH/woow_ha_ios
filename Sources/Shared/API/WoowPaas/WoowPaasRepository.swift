#if CLOUD_EDITION
import Foundation

/// Single entry point to the WOOW PaaS backend used by the cloud onboarding flow.
///
/// The flow is: ``requestDeviceCode()`` to start the OAuth 2.0 device flow, ``pollToken(deviceCode:currentInterval:)``
/// until the user authorized the application, then ``provision()`` to ask for a Home Assistant instance
/// and ``getStatus()`` until that instance is ready.
///
/// Credentials never travel through the caller: `pollToken` stores the session it obtained in the
/// ``WoowPaasSession``, and the authenticated calls read it back from there and refresh it on their own.
///
/// Where the Android counterpart reports failures through `Result`, implementations here throw: a thrown
/// ``WoowPaasError`` carries the same information, and a `CancellationError` propagates as usual so a
/// cancelled poll is never mistaken for a failure.
public protocol WoowPaasRepository: Sendable {
    /// Starts the OAuth 2.0 device flow and returns the codes the user needs to authorize the application.
    ///
    /// - Throws: ``WoowPaasError/api(code:message:)`` when the backend rejected the request or answered
    ///   something that cannot be read
    func requestDeviceCode() async throws -> DeviceCodeResponse

    /// Polls the token endpoint once, storing the session as soon as one is issued.
    ///
    /// Never throws for network or protocol problems: everything is reported through ``TokenPollResult``
    /// so the caller can decide whether to keep polling. The only error that escapes is a
    /// `CancellationError`, which is not swallowed and propagates as usual.
    ///
    /// - Parameters:
    ///   - deviceCode: the code obtained from ``requestDeviceCode()``
    ///   - currentInterval: the polling interval in seconds currently in use, used to compute
    ///     ``TokenPollResult/slowDown(newInterval:)``
    func pollToken(deviceCode: String, currentInterval: Int) async throws -> TokenPollResult

    /// Asks the backend to provision the Home Assistant instance of the authenticated account.
    ///
    /// The call is idempotent on the backend side: asking again while an instance already exists reports
    /// the state of that instance instead of failing.
    ///
    /// - Throws: ``WoowPaasError/sessionExpired(message:)`` when the stored session is gone and a new
    ///   device flow is needed, or ``WoowPaasError/api(code:message:)`` when the request was refused, for
    ///   instance with a 403 when the `ha:provision` scope is missing
    func provision() async throws -> ProvisionResponse

    /// Queries the provisioning status of the authenticated account's Home Assistant instance.
    ///
    /// This function is called from a polling loop: a cancellation propagates as a `CancellationError`
    /// instead of being captured, so a cancelled poll never surfaces as a spurious failure.
    ///
    /// - Throws: ``WoowPaasError/sessionExpired(message:)`` when the stored session is gone and a new
    ///   device flow is needed
    func getStatus() async throws -> StatusResponse
}
#endif
