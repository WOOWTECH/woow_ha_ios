#if CLOUD_EDITION
import Foundation
import SwiftUI

/// Constants the cloud edition needs at runtime to talk to WOOW PaaS.
///
/// Only values the code itself needs live here (PaaS URL, OAuth client, brand color); anything the build
/// system needs (bundle id, product name) lives in the xcconfig files and is never mirrored here. The
/// staging/production split is decided at compile time with `DEBUG`, matching the Android edition plugin
/// where debug variants talk to staging and release variants to production.
public enum WoowtechConfiguration {
    /// The WOOW PaaS environment root. It may carry a path prefix; every endpoint is appended to it.
    public static var paasBaseURL: URL {
        #if DEBUG
        return URL(string: "https://stg.woowtech.io")!
        #else
        return URL(string: "https://paas.woowtech.io")!
        #endif
    }

    /// The OAuth 2.0 client identifier registered for this application.
    public static let clientID = "woow-ha-app"

    /// The space separated OAuth 2.0 scopes requested during the device flow.
    public static let scopes = "ha:provision workspace:read smarthome:read"

    /// The OAuth 2.0 grant type identifier of the device flow (RFC 8628 §3.4).
    public static let deviceCodeGrantType = "urn:ietf:params:oauth:grant-type:device_code"

    /// The OAuth 2.0 grant type identifier used to rotate a session (RFC 6749 §6).
    public static let refreshTokenGrantType = "refresh_token"

    /// The woowtech brand blue, `#6183FC`.
    public static var brandColor: Color {
        Color(red: 0x61 / 255, green: 0x83 / 255, blue: 0xFC / 255)
    }
}
#endif
