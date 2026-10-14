#if CLOUD_EDITION
import Foundation

/// Raw HTTP transport for the WOOW PaaS endpoints used by the cloud onboarding flow.
///
/// Every call returns the status code together with the body instead of a decoded payload: the
/// onboarding flow reacts to individual status codes (a 409 is a normal answer, a 401 has to be told
/// apart from a 403) and reads the body of unsuccessful responses too (the OAuth `error` field, the
/// state behind a 409), so decoding belongs to the caller.
final class WoowPaasClient: Sendable {
    /// A status code and body pair, everything the repository needs to interpret an answer.
    struct Response {
        let statusCode: Int
        let body: Data
    }

    /// Path segments appended to the configured environment root.
    ///
    /// They are relative on purpose: the production environment is served under a path prefix, so the
    /// final URL is built from the configured base instead of replacing its path.
    private enum Endpoints {
        static let deviceAuthorization = "oauth2/device_authorization"
        static let token = "oauth2/token"
        static let provision = "api/ha-paas/provision"
        static let status = "api/ha-paas/status"
    }

    private enum Header {
        static let authorization = "Authorization"
        static let contentType = "Content-Type"
    }

    private static let formURLEncodedContentType = "application/x-www-form-urlencoded; charset=utf-8"
    private static let bearerPrefix = "Bearer "

    /// Upper bound on a whole request, the counterpart of the Android client's call timeout.
    private static let requestTimeout: TimeInterval = 30

    private let baseURL: URL
    private let clientID: String
    private let scopes: String
    private let session: URLSession

    /// - Parameters:
    ///   - baseURL: the environment root; it may carry a path prefix, every endpoint is appended to it
    ///   - clientID: the OAuth 2.0 client identifier registered for this application
    ///   - scopes: the space separated OAuth 2.0 scopes requested during the device flow
    ///   - session: the transport to use; the default one waits for connectivity instead of failing a
    ///     poll the moment the network blips, and is ephemeral so no response ever touches the disk cache
    init(
        baseURL: URL = WoowtechConfiguration.paasBaseURL,
        clientID: String = WoowtechConfiguration.clientID,
        scopes: String = WoowtechConfiguration.scopes,
        session: URLSession? = nil
    ) {
        self.baseURL = baseURL
        self.clientID = clientID
        self.scopes = scopes
        self.session = session ?? URLSession(configuration: with(URLSessionConfiguration.ephemeral) {
            $0.waitsForConnectivity = true
            $0.timeoutIntervalForRequest = Self.requestTimeout
        })
    }

    /// Starts the OAuth 2.0 device flow (RFC 8628 §3.1).
    func requestDeviceAuthorization() async throws -> Response {
        try await send(formPOST(
            endpoint: Endpoints.deviceAuthorization,
            fields: [
                ("client_id", clientID),
                ("scope", scopes),
            ]
        ))
    }

    /// Polls the token endpoint once with the device code (RFC 8628 §3.4).
    func requestToken(deviceCode: String) async throws -> Response {
        try await send(formPOST(
            endpoint: Endpoints.token,
            fields: [
                ("grant_type", WoowtechConfiguration.deviceCodeGrantType),
                ("device_code", deviceCode),
                ("client_id", clientID),
            ]
        ))
    }

    /// Exchanges a refresh token for a brand new session (RFC 6749 §6).
    ///
    /// The client is a public one: sending a client secret here is answered with a 401, so the body
    /// carries nothing but the grant type, the refresh token and the client identifier.
    func refreshToken(_ refreshToken: String) async throws -> Response {
        try await send(formPOST(
            endpoint: Endpoints.token,
            fields: [
                ("grant_type", WoowtechConfiguration.refreshTokenGrantType),
                ("refresh_token", refreshToken),
                ("client_id", clientID),
            ]
        ))
    }

    /// Asks the backend to provision the Home Assistant instance of the authenticated account.
    func provision(accessToken: String) async throws -> Response {
        var request = formPOST(endpoint: Endpoints.provision, fields: [])
        request.setValue(Self.bearerPrefix + accessToken, forHTTPHeaderField: Header.authorization)
        return try await send(request)
    }

    /// Queries the provisioning status of the authenticated account's Home Assistant instance.
    func provisionStatus(accessToken: String) async throws -> Response {
        var request = URLRequest(url: endpoint(Endpoints.status))
        request.setValue(Self.bearerPrefix + accessToken, forHTTPHeaderField: Header.authorization)
        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> Response {
        let (body, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return Response(statusCode: httpResponse.statusCode, body: body)
    }

    /// Appends `segments` to the configured base URL, keeping any path prefix it already carries.
    private func endpoint(_ segments: String) -> URL {
        baseURL.appendingPathComponent(segments)
    }

    private func formPOST(endpoint segments: String, fields: [(String, String)]) -> URLRequest {
        with(URLRequest(url: endpoint(segments))) {
            $0.httpMethod = "POST"
            $0.setValue(Self.formURLEncodedContentType, forHTTPHeaderField: Header.contentType)
            $0.httpBody = Self.formURLEncode(fields)
        }
    }

    /// Characters that survive `application/x-www-form-urlencoded` encoding unescaped.
    private static let formAllowedCharacters = with(CharacterSet.alphanumerics) {
        $0.insert(charactersIn: "-._*")
    }

    private static func formURLEncode(_ fields: [(String, String)]) -> Data {
        fields
            .map { name, value in
                let encode: (String) -> String = {
                    $0.addingPercentEncoding(withAllowedCharacters: formAllowedCharacters) ?? $0
                }
                return "\(encode(name))=\(encode(value))"
            }
            .joined(separator: "&")
            .data(using: .utf8) ?? Data()
    }
}
#endif
