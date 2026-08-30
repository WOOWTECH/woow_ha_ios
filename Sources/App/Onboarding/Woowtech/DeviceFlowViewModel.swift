#if CLOUD_EDITION
import Foundation
import Shared

/// The cloud-edition service instances shared by the onboarding screens and the launch hook.
///
/// The sign-in screen stores the credentials it obtains in `session`, the provisioning screen reads
/// them back through `repository`, and the `Current.onServerRegistered` hook assigned at launch clears
/// `session` once the provisioned server is registered — all three must therefore see the same
/// instances. The session is in-memory only (PRD decision D8), so nothing here ever touches disk.
enum WoowtechCloud {
    static let session = WoowPaasSession()
    static let repository: any WoowPaasRepository = WoowPaasRepositoryImpl(session: session)
}

/// How long the provisioning screen waits for the instance to become ready before giving up.
private let provisionPollTimeout: TimeInterval = 10 * 60
/// The first delay between two provisioning status polls; doubles on every wait, capped below.
private let initialProvisionPollInterval: Duration = .seconds(5)
/// Ceiling for the provisioning status poll backoff.
private let maxProvisionPollInterval: Duration = .seconds(30)
/// Shown when the local check already knows no stored session can authenticate; the same wording the
/// repository uses when the backend reaches that conclusion (`WoowPaasRepositoryImpl`).
private let sessionExpiredMessage = "登入已過期，請返回重新登入"

/// Drives the two cloud onboarding screens: the OAuth device-flow sign-in and the instance
/// provisioning that follows it (PRD §3.1); the iOS counterpart of Android's `CloudSignInViewModel`
/// and `CloudProvisionViewModel`, folded into one object because the two screens share one session.
///
/// Both long-running halves are structured `async` functions bound to SwiftUI `.task(id:)` modifiers
/// (`runSignIn` to ``sessionID``, `runProvision` to ``provisionAttemptID``), so their lifetime is
/// exactly the lifetime of the screen that shows them and nothing here ever stores an unstructured
/// `Task`. A `CancellationError` is the normal way such a task ends when the user leaves the screen;
/// it is never surfaced as an error state.
@MainActor
final class DeviceFlowViewModel: ObservableObject {
    enum SignInState: Equatable {
        case idle
        case requestingCode
        case waitingForAuth(userCode: String, verificationURL: URL?, isReconnecting: Bool)
        case authorized
        case error(message: String, canRetry: Bool)
    }

    enum ProvisionState: Equatable {
        case idle
        case provisioning
        case ready(serverURL: URL)
        case suspended
        case deleting
        case error(message: String, canRetry: Bool)
    }

    @Published private(set) var signInState: SignInState = .idle
    @Published private(set) var provisionState: ProvisionState = .idle

    /// Identity of one sign-in attempt. The sign-in screen runs `runSignIn()` in `.task(id: sessionID)`,
    /// so replacing the value (``restartSignIn()``) cancels the previous attempt and starts a new one.
    @Published private(set) var sessionID = UUID()

    /// Identity of one provisioning attempt, nil until the user asked for one. The provisioning screen
    /// runs `runProvision()` in `.task(id: provisionAttemptID)`, same replacement semantics as above.
    @Published private(set) var provisionAttemptID: UUID?

    private let repository: any WoowPaasRepository
    private let session: WoowPaasSession
    private let sleeper: any WoowSleeper
    private let dateProvider: @Sendable () -> Date

    /// The codes of the sign-in attempt currently waiting for authorization, kept for the
    /// foreground catch-up poll.
    private var deviceCodeResponse: DeviceCodeResponse?

    init(
        repository: any WoowPaasRepository = WoowtechCloud.repository,
        session: WoowPaasSession = WoowtechCloud.session,
        sleeper: any WoowSleeper = TaskSleeper(),
        dateProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.repository = repository
        self.session = session
        self.sleeper = sleeper
        self.dateProvider = dateProvider
    }

    // MARK: - Sign in

    /// Runs one whole device-flow sign-in: requests the codes, then polls until the user authorized,
    /// the device code expired or a terminal error occurred. Cancellation (the user left the screen or
    /// restarted) ends the function silently — it is a normal path, not an error state.
    func runSignIn() async {
        signInState = .requestingCode
        do {
            let response = try await repository.requestDeviceCode()
            deviceCodeResponse = response
            signInState = .waitingForAuth(
                userCode: response.userCode,
                verificationURL: URL(string: response.verificationUriComplete),
                isReconnecting: false
            )

            let poller = DeviceFlowPoller(repository: repository, sleeper: sleeper, dateProvider: dateProvider)
            let outcome = try await poller.poll(
                deviceCode: response.deviceCode,
                interval: response.interval,
                expiresIn: response.expiresIn,
                onReconnectingChanged: { isReconnecting in
                    Task { @MainActor [weak self] in self?.setReconnecting(isReconnecting) }
                }
            )
            apply(outcome)
        } catch is CancellationError {
            // Normal path (lifecycle rule 1): the screen went away or the user restarted the flow.
        } catch let error as WoowPaasError {
            transitionSignIn(to: .error(message: message(for: error), canRetry: true))
        } catch {
            transitionSignIn(to: .error(
                message: WoowtechL10n.SignIn.errorConnection(error.localizedDescription),
                canRetry: true
            ))
        }
    }

    /// Discards the current sign-in attempt and starts a fresh one ("start over" after an error).
    func restartSignIn() {
        deviceCodeResponse = nil
        signInState = .idle
        sessionID = UUID()
    }

    /// One immediate, out-of-band token poll, run when the scene returns to `.active` (lifecycle
    /// rule 3): the user may have authorized in an external browser while the app could not observe
    /// it, and this removes the up-to-`interval` wait before the running loop notices.
    ///
    /// Anything but a success is left for the polling loop to handle on its next round; a success
    /// is safe to apply here because ``transitionSignIn(to:)`` makes `authorized` terminal, so the
    /// loop's later, stale outcome cannot overwrite it.
    func pollOnceAfterForeground() async {
        guard case .waitingForAuth = signInState, let deviceCodeResponse else { return }
        do {
            let result = try await repository.pollToken(
                deviceCode: deviceCodeResponse.deviceCode,
                currentInterval: deviceCodeResponse.interval
            )
            if result == .success {
                transitionSignIn(to: .authorized)
            }
        } catch {
            // Only CancellationError escapes pollToken — the screen is going away, nothing to update.
        }
    }

    private func apply(_ outcome: DeviceFlowPollOutcome) {
        switch outcome {
        case .authorized:
            transitionSignIn(to: .authorized)
        case let .deviceCodeExpired(message), let .failed(message):
            transitionSignIn(to: .error(message: message, canRetry: true))
        }
    }

    private func setReconnecting(_ isReconnecting: Bool) {
        guard case let .waitingForAuth(userCode, verificationURL, _) = signInState else { return }
        signInState = .waitingForAuth(
            userCode: userCode,
            verificationURL: verificationURL,
            isReconnecting: isReconnecting
        )
    }

    /// `authorized` is terminal: the catch-up poll and the polling loop can both reach it, and once
    /// either did (navigation to provisioning is under way) a stale outcome from the other side must
    /// not drag the screen back into an error.
    private func transitionSignIn(to newState: SignInState) {
        guard signInState != .authorized else { return }
        signInState = newState
    }

    private func message(for error: WoowPaasError) -> String {
        switch error {
        case let .api(_, message), let .sessionExpired(message):
            return message
        }
    }

    // MARK: - Provision

    /// Reports when the sign-in performed earlier left nothing worth trying (no stored session, or an
    /// expired access token with no refresh token). The check is local and optimistic in the other
    /// direction — a revoked refresh token is only discovered when provisioning tries to use it.
    func verifyStoredSession() async {
        let credentials = await session.credentials
        if credentials?.canAuthenticate(at: dateProvider()) != true {
            provisionState = .error(message: sessionExpiredMessage, canRetry: false)
        }
    }

    /// Starts (or retries) one provisioning attempt; the screen's `.task(id:)` picks it up.
    func requestProvision() {
        guard provisionState != .provisioning else { return }
        provisionAttemptID = UUID()
    }

    /// Runs one whole provisioning attempt: asks the backend for an instance, then — when the answer
    /// is "provisioning" — polls the status until ready, a terminal failure or the timeout. As with
    /// sign-in, cancellation ends the function silently.
    func runProvision() async {
        provisionState = .provisioning
        do {
            let response = try await repository.provision()
            switch response.status {
            case .ready:
                provisionState = readyState(haUrl: response.haUrl)
            case .provisioning:
                try await pollProvisionStatus()
            case .suspended:
                provisionState = .suspended
            case .deleting:
                provisionState = .deleting
            case .none, .error, .unknown:
                // A provisioning request never answers "none" or "error"; surface the raw value.
                provisionState = .error(
                    message: WoowtechL10n.Provision.errorUnexpectedStatus(response.status.rawValue),
                    canRetry: true
                )
            }
        } catch is CancellationError {
            // Normal path: the user left the screen.
        } catch {
            provisionState = provisionErrorState(for: error, fallbackMessage: WoowtechL10n.Provision.errorFailed)
        }
    }

    /// Polls the provisioning status until it becomes ready, fails terminally or the timeout elapses.
    ///
    /// Transient transport failures do not abort the wait: the loop keeps polling with an exponential
    /// backoff, bounded by a wall-clock deadline (lifecycle rule 2 — a frozen app wakes up with time
    /// already elapsed, so iterations are never counted). The repository refreshes the credentials on
    /// its own, so an access token expiring mid-wait is not a terminal failure either.
    ///
    /// - Throws: `CancellationError` when the surrounding task is cancelled; every other failure is
    ///   folded into ``provisionState``
    private func pollProvisionStatus() async throws {
        var interval = initialProvisionPollInterval
        let deadline = dateProvider().addingTimeInterval(provisionPollTimeout)

        while true {
            try await sleeper.sleep(for: interval)

            if dateProvider() >= deadline {
                provisionState = .error(message: WoowtechL10n.Provision.errorTimeout, canRetry: true)
                return
            }

            let response: StatusResponse
            do {
                response = try await repository.getStatus()
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as WoowPaasError {
                // The backend answered and refused: terminal, stop the wait.
                provisionState = provisionErrorState(
                    for: error,
                    fallbackMessage: WoowtechL10n.Provision.errorStatusQueryFailed
                )
                return
            } catch {
                // Transport failure (socket timeout, DNS hiccup): keep polling within the deadline.
                interval = min(interval * 2, maxProvisionPollInterval)
                continue
            }

            switch response.status {
            case .ready:
                provisionState = readyState(haUrl: response.haUrl)
                return
            case .provisioning:
                interval = min(interval * 2, maxProvisionPollInterval)
            case .error:
                provisionState = .error(
                    message: response.error ?? WoowtechL10n.Provision.errorFailed,
                    canRetry: true
                )
                return
            case .suspended:
                provisionState = .suspended
                return
            case .deleting:
                provisionState = .deleting
                return
            case .none, .unknown:
                // "none" means the instance vanished mid-flow, which is as abnormal here as a status
                // this version does not know about.
                provisionState = .error(
                    message: WoowtechL10n.Provision.errorAbnormalStatus(response.status.rawValue),
                    canRetry: true
                )
                return
            }
        }
    }

    private func readyState(haUrl: String?) -> ProvisionState {
        guard let haUrl, let serverURL = URL(string: haUrl) else {
            return .error(message: WoowtechL10n.Provision.errorMissingURL, canRetry: true)
        }
        return .ready(serverURL: serverURL)
    }

    /// Turns a failure into the screen state describing it. A `sessionExpired` is the only case that
    /// cannot be retried: the repository already tried to refresh the credentials and the backend
    /// refused, so the user has to sign in again.
    private func provisionErrorState(for error: Error, fallbackMessage: String) -> ProvisionState {
        switch error {
        case let WoowPaasError.sessionExpired(message):
            return .error(message: message, canRetry: false)
        case let WoowPaasError.api(_, message):
            return .error(message: message, canRetry: true)
        default:
            return .error(message: fallbackMessage, canRetry: true)
        }
    }
}
#endif
