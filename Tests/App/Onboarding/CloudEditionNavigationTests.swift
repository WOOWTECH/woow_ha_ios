@testable import HomeAssistant
@testable import Shared
import Testing

/// Covers the fork's onboarding entry-point split (Hook 1, PRD §1): the cloud edition starts its
/// initial onboarding at the chooser leading to the device-flow screens, the on-premise edition keeps
/// the upstream flow. `rootScreen(for:isCloudEdition:)` takes the edition as a parameter, so both
/// branches are asserted from a single build and neither test depends on the `CLOUD_EDITION` symbol.
struct CloudEditionNavigationTests {
    @Test func cloudEdition_onboardingStartsAtDeviceFlowScreen() async throws {
        #expect(OnboardingNavigation.rootScreen(for: .initial, isCloudEdition: true) == .cloudChooser)
        #expect(OnboardingNavigation.rootScreen(for: .required, isCloudEdition: true) == .cloudChooser)
        // Adding another server from settings keeps the upstream servers list in both editions.
        #expect(OnboardingNavigation.rootScreen(for: .secondary, isCloudEdition: true) == .serversList)
    }

    @Test func onpremEdition_onboardingStartsAtUpstreamFlow() async throws {
        #expect(OnboardingNavigation.rootScreen(for: .initial, isCloudEdition: false) == .welcome)
        #expect(OnboardingNavigation.rootScreen(for: .required, isCloudEdition: false) == .welcome)
        #expect(OnboardingNavigation.rootScreen(for: .secondary, isCloudEdition: false) == .serversList)
    }
}
