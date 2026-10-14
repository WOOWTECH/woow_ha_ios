#if CLOUD_EDITION
import Foundation

// MARK: - Errors

/// A failure reported by the WOOW PaaS backend.
///
/// Callers use the code carried by `.api` to tell apart the cases that need a dedicated reaction (403
/// means a missing scope, 503 means the service is not open yet) from the generic ones. The one case
/// that is not told apart by a code has its own case: `.sessionExpired` means the stored session can no
/// longer authenticate — the backend refused the access token and either there was no refresh token left
/// or refreshing it was refused too. Nothing but a new device flow recovers from it, so callers offer a
/// new sign in rather than a retry; the session has already been dropped by the time it is reported.
public enum WoowPaasError: Error, Equatable {
    case api(code: Int, message: String)
    case sessionExpired(message: String)

    /// Placeholder code used when a failure happened before any HTTP status was known.
    public static let unknownHTTPCode = -1
}

// MARK: - Domain models

/// The device and user codes issued when the device flow starts (RFC 8628 §3.2).
public struct DeviceCodeResponse: Equatable, Sendable {
    /// The opaque code the application polls the token endpoint with.
    public let deviceCode: String
    /// The short code the user types on `verificationUri`.
    public let userCode: String
    /// The page where the user enters `userCode`.
    public let verificationUri: String
    /// The same page with `userCode` already filled in, suitable for a QR code.
    public let verificationUriComplete: String
    /// Lifetime of `deviceCode` in seconds; polling must stop once it elapsed.
    public let expiresIn: Int
    /// The delay in seconds the client must wait between two polls.
    public let interval: Int

    public init(
        deviceCode: String,
        userCode: String,
        verificationUri: String,
        verificationUriComplete: String,
        expiresIn: Int,
        interval: Int
    ) {
        self.deviceCode = deviceCode
        self.userCode = userCode
        self.verificationUri = verificationUri
        self.verificationUriComplete = verificationUriComplete
        self.expiresIn = expiresIn
        self.interval = interval
    }
}

/// The answer to a provisioning request.
public struct ProvisionResponse: Equatable, Sendable {
    public let status: ProvisionStatus
    /// The URL of the instance, only present once `status` is `.ready`.
    public let haUrl: String?
    /// A human readable reason, present when the backend refused the request.
    public let error: String?

    public init(status: ProvisionStatus, haUrl: String? = nil, error: String? = nil) {
        self.status = status
        self.haUrl = haUrl
        self.error = error
    }
}

/// The answer to a provisioning status query.
public struct StatusResponse: Equatable, Sendable {
    public let status: ProvisionStatus
    /// The URL of the instance, only present once `status` is `.ready`.
    public let haUrl: String?
    /// A human readable reason, present when `status` is `.error`.
    public let error: String?

    public init(status: ProvisionStatus, haUrl: String? = nil, error: String? = nil) {
        self.status = status
        self.haUrl = haUrl
        self.error = error
    }
}

// MARK: - Wire representations

/// The decoder used for every WOOW PaaS payload.
///
/// It is separate from the decoders used for Home Assistant Core so the two contracts can evolve
/// independently. The snake case strategy lets the DTOs stay idiomatic Swift without a `CodingKeys`
/// on every type; unknown keys are ignored by `JSONDecoder` by default, which keeps older applications
/// working when the backend adds fields.
enum WoowPaasJSONMapper {
    static var decoder: JSONDecoder {
        with(JSONDecoder()) {
            $0.keyDecodingStrategy = .convertFromSnakeCase
        }
    }
}

/// Wire representation of the device authorization response (RFC 8628 §3.2).
///
/// Every field is optional even though the specification makes them mandatory: a backend that answers an
/// incomplete payload must produce a readable error instead of a decoding crash, so the validation
/// happens in the mapping layer where the HTTP status code is still known.
struct DeviceCodeResponseDto: Decodable {
    var deviceCode: String?
    var userCode: String?
    var verificationUri: String?
    var verificationUriComplete: String?
    var expiresIn: Int?
    var interval: Int?
    var error: String?
}

/// Wire representation of the token endpoint response and of its OAuth error payload (RFC 8628 §3.5).
struct TokenResponseDto: Decodable {
    var accessToken: String?
    var tokenType: String?
    var expiresIn: Int?
    var scope: String?
    var refreshToken: String?
    var error: String?
    var errorDescription: String?
}

/// Wire representation of the provisioning request response.
struct ProvisionResponseDto: Decodable {
    var status: String?
    var haUrl: String?
    var error: String?
}

/// Wire representation of the provisioning status response.
struct StatusResponseDto: Decodable {
    var status: String?
    var haUrl: String?
    var error: String?
}
#endif
