import Foundation
@testable import HomeAssistant
import PromiseKit
@testable import Shared
import XCTest

/// Covers the fork's `Current.onServerRegistered` hook in `OnboardingAuth.authenticate` (PRD §3.2):
/// the observer runs after `servers.add` and before the `.complete` step, and a throwing observer
/// rolls the whole registration back through the existing failure path.
///
/// The hook is plain shared code (the closure is simply nil upstream and in the on-premise edition),
/// so these tests run in both edition configurations without touching `CLOUD_EDITION`.
class HookRollbackTests: XCTestCase {
    private var auth: OnboardingAuth!
    private var instance: DiscoveredHomeAssistant!

    override func setUp() {
        super.setUp()

        auth = OnboardingAuth()

        Current.servers = FakeServerManager()
        Current.onServerRegistered = nil

        instance = DiscoveredHomeAssistant(manualURL: URL(string: "https://external.homeassistant:8123")!)
    }

    override func tearDown() {
        Current.onServerRegistered = nil
        super.tearDown()
    }

    func testObserverThrow_serverAbsentFromCurrentServers() throws {
        Current.onServerRegistered = { _ in throw HookError.cleanupFailed }

        let result = authenticate(postSteps: [])

        XCTAssertThrowsError(try hang(result)) { error in
            XCTAssertEqual(error as? HookError, .cleanupFailed)
        }
        // The recover path ran undoConfigure: the server added by `servers.add` is gone again.
        XCTAssertTrue(Current.servers.all.isEmpty)
    }

    func testObserverSuccess_completeStepReached() throws {
        FakeOnboardingAuthPostStepComplete1.result = .value(())
        FakeOnboardingAuthPostStepComplete1.wasInvoked = false

        var observedServers: [Identifier<Server>] = []
        var hookRanBeforeComplete = false
        Current.onServerRegistered = { server in
            hookRanBeforeComplete = !FakeOnboardingAuthPostStepComplete1.wasInvoked
            observedServers.append(server.identifier)
        }

        let result = authenticate(postSteps: [FakeOnboardingAuthPostStepComplete1.self])
        let server = try hang(result)

        XCTAssertEqual(observedServers, [server.identifier])
        XCTAssertTrue(hookRanBeforeComplete, "the hook must run before the .complete step declares success")
        XCTAssertTrue(FakeOnboardingAuthPostStepComplete1.wasInvoked)
        XCTAssertEqual(Current.servers.all.map(\.identifier), [server.identifier])
    }

    /// Runs `authenticate` with no pre steps and only the given post steps, so the flow reduces to
    /// login → token exchange → `servers.add` → hook → steps — exactly the stretch under test.
    private func authenticate(postSteps: [OnboardingAuthPostStep.Type]) -> Promise<Server> {
        auth.preSteps = []
        auth.postSteps = postSteps

        auth.login = FakeOnboardingAuthLogin(
            expectedDetails: [try! .init(baseURL: instance.externalURL!)],
            results: [.value(.init(code: "code1", resolvedURL: nil))]
        )
        auth.tokenExchange = FakeOnboardingAuthTokenExchange(
            result: .value(TokenInfo(
                accessToken: "access_token1",
                refreshToken: "refresh_token1",
                expiration: Date(timeIntervalSinceNow: 1000)
            )),
            expectedCode: "code1"
        )

        return auth.authenticate(to: instance, presenter: OnboardingAuthPresenter())
    }
}

private enum HookError: Error, Equatable {
    case cleanupFailed
}
