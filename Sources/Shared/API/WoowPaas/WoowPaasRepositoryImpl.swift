#if CLOUD_EDITION
import Foundation

private let malformedBodyMessage = "伺服器回應格式錯誤"
private let missingFieldsMessage = "伺服器回應缺少必要欄位"
private let unknownOAuthError = "unknown_error"
private let sessionExpiredMessage = "登入已過期，請返回重新登入"
private let refreshUnavailableMessage = "無法更新登入狀態，請稍後再試"

/// The literal the backend sometimes sends instead of a JSON null for an absent string.
private let nullLiteral = "null"

private let successfulStatusRange = 200 ... 299

/// URLSession backed ``WoowPaasRepository``.
///
/// The authenticated calls read their credentials from the ``WoowPaasSession`` and refresh them when
/// needed. Refreshing is serialized: the backend invalidates a refresh token the moment it is used, so
/// two calls spending the same one would leave the account without a session at all.
public final class WoowPaasRepositoryImpl: WoowPaasRepository {
    private let client: WoowPaasClient
    private let session: WoowPaasSession
    private let dateProvider: @Sendable () -> Date

    private let refreshLock = AsyncLock()

    /// - Parameters:
    ///   - session: where the credentials issued by the device flow are kept
    ///   - dateProvider: used to tell whether an access token is still worth sending; injectable so tests
    ///     control the wall clock
    public convenience init(session: WoowPaasSession, dateProvider: @escaping @Sendable () -> Date = Date.init) {
        self.init(client: WoowPaasClient(), session: session, dateProvider: dateProvider)
    }

    init(client: WoowPaasClient, session: WoowPaasSession, dateProvider: @escaping @Sendable () -> Date) {
        self.client = client
        self.session = session
        self.dateProvider = dateProvider
    }

    public func requestDeviceCode() async throws -> DeviceCodeResponse {
        let response = try await client.requestDeviceAuthorization()
        let dto: DeviceCodeResponseDto = try decodeBody(response)

        guard successfulStatusRange.contains(response.statusCode) else {
            throw WoowPaasError.api(code: response.statusCode, message: apiValue(dto.error) ?? unknownOAuthError)
        }
        return try deviceCodeResponse(from: dto, httpCode: response.statusCode)
    }

    public func pollToken(deviceCode: String, currentInterval: Int) async throws -> TokenPollResult {
        let response: WoowPaasClient.Response
        do {
            response = try await client.requestToken(deviceCode: deviceCode)
        } catch {
            // Rethrows cancellation so the polling loop is cancelled instead of seeing a spurious result
            return try TokenErrorClassifier.classify(transportError: error)
        }

        if successfulStatusRange.contains(response.statusCode) {
            guard let dto: TokenResponseDto = decodeOrNil(response.body) else {
                return .transientError(reason: malformedBodyMessage)
            }
            return await storeIssuedSession(dto)
        }

        let dto: TokenResponseDto? = decodeOrNil(response.body)
        return TokenErrorClassifier.classify(
            httpCode: response.statusCode,
            error: apiValue(dto?.error),
            errorDescription: apiValue(dto?.errorDescription),
            currentInterval: currentInterval
        )
    }

    public func provision() async throws -> ProvisionResponse {
        let response = try await authenticated { accessToken in
            try await self.client.provision(accessToken: accessToken)
        }
        let code = response.statusCode
        // Decided before the body is looked at: whatever a refused answer carries, the credentials were
        // already refreshed and replayed by then, so nothing but a new sign in helps.
        if code == httpUnauthorized { throw await dropExpiredSession() }
        let dto: ProvisionResponseDto = try decodeBody(response)

        switch code {
        case 200, 202:
            return try ProvisionResponse(
                status: provisionStatus(from: dto.status, httpCode: code),
                haUrl: apiValue(dto.haUrl)
            )
        case 409:
            // A 409 is data, not a failure: it reports an instance that is suspended or being deleted.
            return try ProvisionResponse(
                status: provisionStatus(from: dto.status, httpCode: code),
                error: apiValue(dto.error)
            )
        case 403:
            throw WoowPaasError.api(code: code, message: "權限不足（缺少 ha:provision scope）")
        case 503:
            throw WoowPaasError.api(code: code, message: "服務尚未開放，請稍後再試")
        default:
            throw WoowPaasError.api(code: code, message: apiValue(dto.error) ?? "未知錯誤 (HTTP \(code))")
        }
    }

    public func getStatus() async throws -> StatusResponse {
        let response = try await authenticated { accessToken in
            try await self.client.provisionStatus(accessToken: accessToken)
        }
        let code = response.statusCode
        if code == httpUnauthorized { throw await dropExpiredSession() }
        let dto: StatusResponseDto = try decodeBody(response)

        guard successfulStatusRange.contains(code) else {
            throw WoowPaasError.api(code: code, message: apiValue(dto.error) ?? "查詢狀態失敗 (HTTP \(code))")
        }
        return try StatusResponse(
            status: provisionStatus(from: dto.status, httpCode: code),
            haUrl: apiValue(dto.haUrl),
            error: apiValue(dto.error)
        )
    }

    /// Stores the session carried by a successful token response.
    ///
    /// - Returns: `.success` once the session is stored, or a terminal failure when the payload carried
    ///   no usable session
    private func storeIssuedSession(_ dto: TokenResponseDto) async -> TokenPollResult {
        guard let credentials = makeCredentials(from: dto, issuedAt: dateProvider()) else {
            return .failed(error: missingFieldsMessage)
        }
        await session.replace(with: credentials)
        return .success
    }

    /// Runs `call` with the access token of the stored session, refreshing that session when needed.
    ///
    /// The session is rotated before the call when its access token is about to expire, and once more
    /// when the backend refuses a token this client believed valid. The call is replayed a single time: a
    /// second refusal means the account lost its session for good.
    ///
    /// - Throws: ``WoowPaasError/sessionExpired(message:)`` when no stored session can authenticate any more
    private func authenticated(
        _ call: (_ accessToken: String) async throws -> WoowPaasClient.Response
    ) async throws -> WoowPaasClient.Response {
        guard let stored = await session.credentials else {
            throw WoowPaasError.sessionExpired(message: sessionExpiredMessage)
        }
        let credentials: WoowPaasCredentials
        if stored.isAccessTokenUsable(at: dateProvider()) {
            credentials = stored
        } else {
            credentials = try await rotateSession(spent: stored)
        }

        let response = try await call(credentials.accessToken)
        guard response.statusCode == httpUnauthorized else { return response }

        return try await call(rotateSession(spent: credentials).accessToken)
    }

    /// Exchanges the refresh token of the stored session for a brand new one and stores it.
    ///
    /// Runs under a lock because the backend invalidates a refresh token as soon as it is used: a second
    /// caller arriving here while a rotation is in flight waits, then reuses its result instead of
    /// spending a token that is already gone. Such a caller recognises the situation by finding stored
    /// credentials that are no longer the `spent` ones it came in with.
    ///
    /// - Parameter spent: the credentials that turned out to be unusable, compared as a whole rather than
    ///   by their access token alone so a value reappearing could never be mistaken for the session never
    ///   having moved
    /// - Throws: ``WoowPaasError/sessionExpired(message:)`` when the session cannot be rotated, in which
    ///   case it is dropped, or ``WoowPaasError/api(code:message:)`` when the backend could not answer, in
    ///   which case the session is kept so the caller can try again later
    private func rotateSession(spent: WoowPaasCredentials) async throws -> WoowPaasCredentials {
        try await refreshLock.withLock {
            guard let current = await session.credentials else {
                throw WoowPaasError.sessionExpired(message: sessionExpiredMessage)
            }
            if current != spent { return current }

            guard let refreshToken = current.refreshToken else { throw await dropExpiredSession() }
            // The exchange runs in its own task so cancelling the caller cannot interrupt it between the
            // moment the refresh token is handed over and the moment the replacement is stored. The
            // backend invalidates the old pair as soon as it answers, so giving up in between would leave
            // the account holding credentials that are already dead, and the user would have to sign in
            // again for no reason. The window is bounded by the request timeout of the HTTP client.
            let exchange = Task { () async throws -> WoowPaasCredentials in
                let response = try await self.client.refreshToken(refreshToken)
                guard successfulStatusRange.contains(response.statusCode) else {
                    throw await self.refreshRefusal(httpCode: response.statusCode)
                }
                let dto: TokenResponseDto? = decodeOrNil(response.body)
                guard let dto, let credentials = makeCredentials(from: dto, issuedAt: self.dateProvider()) else {
                    throw WoowPaasError.api(
                        code: response.statusCode,
                        message: "\(missingFieldsMessage) (HTTP \(response.statusCode))"
                    )
                }
                await self.session.replace(with: credentials)
                return credentials
            }
            return try await exchange.value
        }
    }

    /// Tells apart a refresh the backend could not serve from one it refused.
    ///
    /// A server side failure says nothing about the credentials, so the session is kept and the caller is
    /// free to try again; anything else means the refresh token is spent or revoked (`invalid_grant`) and
    /// only a new device flow recovers.
    private func refreshRefusal(httpCode: Int) async -> WoowPaasError {
        if TokenErrorClassifier.serverErrorRange.contains(httpCode) {
            return .api(code: httpCode, message: refreshUnavailableMessage)
        }
        return await dropExpiredSession()
    }

    /// Drops the session that cannot authenticate any more and reports that a new device flow is needed.
    private func dropExpiredSession() async -> WoowPaasError {
        await session.clear()
        return .sessionExpired(message: sessionExpiredMessage)
    }
}

private let httpUnauthorized = 401

/// Returns the decoded payload of `response`, whether the call was successful or not.
///
/// This API answers with a meaningful JSON body on failures too (the OAuth `error` field, the state
/// behind a 409), so the payload type is decoded regardless of the status code.
///
/// - Throws: ``WoowPaasError/api(code:message:)`` when the body is empty or is not readable JSON
private func decodeBody<T: Decodable>(_ response: WoowPaasClient.Response) throws -> T {
    guard let dto: T = decodeOrNil(response.body) else {
        throw WoowPaasError.api(
            code: response.statusCode,
            message: "\(malformedBodyMessage) (HTTP \(response.statusCode))"
        )
    }
    return dto
}

/// Turns a payload that is not readable JSON into a nil instead of an error.
private func decodeOrNil<T: Decodable>(_ body: Data) -> T? {
    try? WoowPaasJSONMapper.decoder.decode(T.self, from: body)
}

/// Mirrors the leniency the Android client has: an empty string and the literal `"null"` both mean "the
/// backend did not provide this value".
private func apiValue(_ value: String?) -> String? {
    guard let value, !value.isEmpty, value != nullLiteral else { return nil }
    return value
}

/// - Throws: ``WoowPaasError/api(code:message:)`` when the backend omitted the status, which every
///   documented answer carries
private func provisionStatus(from rawValue: String?, httpCode: Int) throws -> ProvisionStatus {
    guard let rawValue else {
        throw WoowPaasError.api(code: httpCode, message: "\(missingFieldsMessage) (HTTP \(httpCode))")
    }
    return ProvisionStatus(rawValue: rawValue)
}

/// - Throws: ``WoowPaasError/api(code:message:)`` when a field required by RFC 8628 §3.2 is missing
private func deviceCodeResponse(from dto: DeviceCodeResponseDto, httpCode: Int) throws -> DeviceCodeResponse {
    func required<T>(_ value: T?) throws -> T {
        guard let value else {
            throw WoowPaasError.api(code: httpCode, message: "\(missingFieldsMessage) (HTTP \(httpCode))")
        }
        return value
    }

    return try DeviceCodeResponse(
        deviceCode: required(dto.deviceCode),
        userCode: required(dto.userCode),
        verificationUri: required(dto.verificationUri),
        verificationUriComplete: required(dto.verificationUriComplete),
        expiresIn: required(dto.expiresIn),
        interval: required(dto.interval)
    )
}

/// Turns a token payload into the credentials to store, or nil when the backend answered a 2xx that does
/// not actually carry usable credentials.
///
/// Only the two fields the application depends on are required: the token to send and how long it lasts.
/// `token_type` and `scope` are echoed back by the backend but nothing branches on them, so a payload
/// missing them still produces working credentials.
///
/// - Parameter issuedAt: when the answer was received, from which the expiry of the access token is computed
private func makeCredentials(from dto: TokenResponseDto, issuedAt: Date) -> WoowPaasCredentials? {
    guard let accessToken = apiValue(dto.accessToken), let expiresIn = dto.expiresIn else { return nil }
    return WoowPaasCredentials(
        accessToken: accessToken,
        refreshToken: apiValue(dto.refreshToken),
        accessTokenExpiresAt: issuedAt.addingTimeInterval(TimeInterval(expiresIn))
    )
}

/// A suspending mutual exclusion primitive: unlike an actor, the lock stays held across the `await`s of
/// the protected body, which is what serializing a whole token rotation needs.
///
/// Waiting is first-in first-out. The wait is not a cancellation point: a rotation is short and bounded
/// by the HTTP timeout, and a waiter that must not miss the rotated result is exactly the caller that
/// should not give up while waiting.
private actor AsyncLock {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private func acquire() async {
        if isLocked {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            isLocked = true
        }
    }

    private func release() {
        if waiters.isEmpty {
            isLocked = false
        } else {
            // The lock stays held; ownership moves to the resumed waiter.
            waiters.removeFirst().resume()
        }
    }

    /// Runs `body` while holding the lock, releasing it whether `body` returns or throws.
    func withLock<T>(_ body: @Sendable () async throws -> T) async throws -> T {
        await acquire()
        do {
            let value = try await body()
            release()
            return value
        } catch {
            release()
            throw error
        }
    }
}
#endif
