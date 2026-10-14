#if CLOUD_EDITION
import Foundation

/// The credentials issued by WOOW PaaS for the account that authorized this device.
///
/// The backend rotates the credentials on every refresh: a refresh returns a brand new access **and**
/// refresh token, and invalidates the ones that were used. A set of credentials is therefore replaced as
/// a whole and never updated field by field.
public struct WoowPaasCredentials: Equatable, Sendable {
    /// How long before its nominal expiry an access token is already considered unusable.
    ///
    /// A request started at the very end of the lifetime of a token would be refused by the time it
    /// reaches the backend, so the token is retired early and refreshed instead.
    private static let accessTokenExpiryLeeway: TimeInterval = 60

    /// The bearer token sent to the API endpoints.
    public let accessToken: String
    /// The token that buys a new session, absent when the backend did not hand one out.
    ///
    /// Its own expiry is deliberately not modelled: the backend does not report it, so whether it is
    /// still accepted is only known once a refresh is attempted.
    public let refreshToken: String?
    /// The instant `accessToken` stops being accepted, computed from the lifetime the backend reported
    /// when it issued it.
    public let accessTokenExpiresAt: Date

    public init(accessToken: String, refreshToken: String?, accessTokenExpiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
    }

    /// Whether `accessToken` can still be used for a request started at `now`.
    ///
    /// Tokens about to expire are reported as unusable so the caller refreshes ahead of time rather than
    /// paying for a request that is going to be refused.
    public func isAccessTokenUsable(at now: Date) -> Bool {
        now < accessTokenExpiresAt.addingTimeInterval(-Self.accessTokenExpiryLeeway)
    }

    /// Whether these credentials are worth trying to authenticate a request started at `now` with.
    ///
    /// This is a local, optimistic check, and the only one that can be made without calling the backend:
    /// a present refresh token is assumed to still be accepted, because nothing here knows when it
    /// expires. A false answer is therefore certain (nothing left to authenticate or refresh with, only a
    /// new device flow recovers) while a true answer only means it is worth trying: a refresh token that
    /// expired or was revoked is discovered when the backend refuses to exchange it.
    public func canAuthenticate(at now: Date) -> Bool {
        isAccessTokenUsable(at: now) || refreshToken != nil
    }
}

extension WoowPaasCredentials: CustomStringConvertible, CustomDebugStringConvertible {
    /// Stands in for a credential in the printed representation so it never reaches a log.
    private static let redacted = "***"

    /// Describes the credentials without ever spelling out a token.
    ///
    /// The default reflection is what ends up in a log or a crash report the moment anything interpolates
    /// a credential, so the tokens are replaced by a placeholder here rather than trusted to never be
    /// printed.
    public var description: String {
        "WoowPaasCredentials(" +
            "accessToken=\(Self.redacted), " +
            "refreshToken=\(refreshToken == nil ? "nil" : Self.redacted), " +
            "accessTokenExpiresAt=\(accessTokenExpiresAt)" +
            ")"
    }

    public var debugDescription: String { description }
}

/// In-memory home of the WOOW PaaS credentials used by the cloud onboarding flow.
///
/// The session is deliberately never persisted (PRD decision D8): the device flow credentials live at
/// most as long as their `expires_in`, so a killed application simply walks the flow again, and no token
/// can ever be left behind in a Keychain or in `UserDefaults`. The credentials are stored as a whole —
/// the backend rotates the access and the refresh token together, and a half written session would leave
/// the application with an access token whose refresh token is already invalid. The actor guarantees a
/// replacement is observed either not at all or in full.
public actor WoowPaasSession {
    /// The credentials of the account that authorized this device, or nil when there are none.
    public private(set) var credentials: WoowPaasCredentials?

    public init() {}

    /// Replaces the stored credentials with `credentials`.
    public func replace(with credentials: WoowPaasCredentials) {
        self.credentials = credentials
    }

    /// Drops the stored credentials, for instance once the Home Assistant server they produced is
    /// registered in the application, or when the backend refused to refresh them.
    ///
    /// Idempotent: clearing an already empty session does nothing.
    public func clear() {
        credentials = nil
    }
}
#endif
