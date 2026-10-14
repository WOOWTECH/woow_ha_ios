#if CLOUD_EDITION
import Foundation

/// Lifecycle state of the Home Assistant instance attached to a WOOW PaaS account.
///
/// Modelled as an enum so callers exhaust every case at compile time instead of comparing bare strings.
/// `rawValue` keeps the wire representation around: it is what gets shown when a state is reported in a
/// place where it is not expected, and it is the only thing `.unknown` carries.
///
/// The backend contract defines six values: `none`, `provisioning`, `ready`, `error`, `suspended` and
/// `deleting`. `.unknown` covers anything added later so an older application keeps working.
public enum ProvisionStatus: Equatable, Sendable {
    /// No instance has been requested for this account yet.
    case none
    /// The instance is up and its URL is available.
    case ready
    /// The instance is being created; the caller is expected to keep polling.
    case provisioning
    /// Provisioning failed on the backend side.
    case error
    /// The instance exists but has been suspended, for instance because of a billing issue.
    case suspended
    /// The instance is being torn down.
    case deleting
    /// A state this version of the application does not know about.
    ///
    /// Keeping unknown values as data instead of failing lets the backend introduce new states without
    /// breaking older clients: the caller decides how to react, and nothing crashes.
    case unknown(String)

    /// The value received from the backend, kept verbatim for diagnostics and user facing messages.
    public var rawValue: String {
        switch self {
        case .none: return "none"
        case .ready: return "ready"
        case .provisioning: return "provisioning"
        case .error: return "error"
        case .suspended: return "suspended"
        case .deleting: return "deleting"
        case let .unknown(rawValue): return rawValue
        }
    }

    /// Maps a raw backend status to its `ProvisionStatus`, falling back to `.unknown` for anything this
    /// version does not recognise.
    public init(rawValue: String) {
        switch rawValue {
        case Self.none.rawValue: self = .none
        case Self.provisioning.rawValue: self = .provisioning
        case Self.ready.rawValue: self = .ready
        case Self.error.rawValue: self = .error
        case Self.suspended.rawValue: self = .suspended
        case Self.deleting.rawValue: self = .deleting
        default: self = .unknown(rawValue)
        }
    }
}
#endif
