#if CLOUD_EDITION
import Foundation

/// Strings for the cloud onboarding screens, backed by the fork-owned `Woowtech.strings` table.
///
/// The fork's strings deliberately do not go through swiftgen's `L10n`: that enum is generated from
/// `Localizable.strings`, which upstream's Lokalise sync rewrites wholesale, so fork keys placed there
/// would be washed away on the next sync. A dedicated table plus this small accessor keeps the swiftgen
/// configuration untouched.
enum WoowtechL10n {
    enum Chooser {
        static var title: String { string("woowtech.chooser.title") }
        static var subtitle: String { string("woowtech.chooser.subtitle") }
        static var localTitle: String { string("woowtech.chooser.local.title") }
        static var localSubtitle: String { string("woowtech.chooser.local.subtitle") }
        static var cloudTitle: String { string("woowtech.chooser.cloud.title") }
        static var cloudSubtitle: String { string("woowtech.chooser.cloud.subtitle") }
    }

    enum SignIn {
        static var title: String { string("woowtech.signin.title") }
        static var preparing: String { string("woowtech.signin.preparing") }
        static var instructions: String { string("woowtech.signin.instructions") }
        static var copyCode: String { string("woowtech.signin.copy_code") }
        static var waiting: String { string("woowtech.signin.waiting") }
        static var reconnecting: String { string("woowtech.signin.reconnecting") }
        static var openBrowser: String { string("woowtech.signin.open_browser") }
        static var authorized: String { string("woowtech.signin.authorized") }
        static var retry: String { string("woowtech.signin.retry") }
        static var errorRequestFailed: String { string("woowtech.signin.error.request_failed") }
        static func errorConnection(_ reason: String) -> String {
            string("woowtech.signin.error.connection", reason)
        }
    }

    enum Provision {
        static var idleTitle: String { string("woowtech.provision.idle.title") }
        static var idleBody: String { string("woowtech.provision.idle.body") }
        static var start: String { string("woowtech.provision.start") }
        static var provisioning: String { string("woowtech.provision.provisioning") }
        static var ready: String { string("woowtech.provision.ready") }
        static var reconnect: String { string("woowtech.provision.reconnect") }
        static var retry: String { string("woowtech.provision.retry") }
        static var back: String { string("woowtech.provision.back") }
        static var suspendedTitle: String { string("woowtech.provision.suspended.title") }
        static var suspendedBody: String { string("woowtech.provision.suspended.body") }
        static var deletingTitle: String { string("woowtech.provision.deleting.title") }
        static var deletingBody: String { string("woowtech.provision.deleting.body") }
        static var errorFailed: String { string("woowtech.provision.error.failed") }
        static var errorStatusQueryFailed: String { string("woowtech.provision.error.status_query_failed") }
        static var errorTimeout: String { string("woowtech.provision.error.timeout") }
        static var errorMissingURL: String { string("woowtech.provision.error.missing_url") }
        static func errorUnexpectedStatus(_ rawValue: String) -> String {
            string("woowtech.provision.error.unexpected_status", rawValue)
        }

        static func errorAbnormalStatus(_ rawValue: String) -> String {
            string("woowtech.provision.error.abnormal_status", rawValue)
        }
    }
}

private func string(_ key: String) -> String {
    NSLocalizedString(key, tableName: "Woowtech", comment: "")
}

private func string(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: string(key), arguments: arguments)
}
#endif
