#if CLOUD_EDITION
import Shared
import SwiftUI

/// The OAuth device-flow sign-in screen (RFC 8628): shows the user code, opens the verification page
/// in an in-app `SFSafariViewController` (lifecycle rule 3 — the app stays foregrounded so the polling
/// never freezes) and waits for the browser authorization. Counterpart of Android's `CloudSignInScreen`.
struct CloudSignInView: View {
    private enum Constants {
        static let progressScale: CGFloat = 1.6
        static let userCodeKerning: CGFloat = 4
        static let errorIconSize: CGFloat = 64
    }

    @Environment(\.scenePhase) private var scenePhase

    @ObservedObject var viewModel: DeviceFlowViewModel
    /// Owned by `OnboardingNavigationView`; authorization replaces this page with the provisioning one.
    let presenter: OnboardingAuthPresenter

    @State private var showVerificationPage = false
    @State private var hasNavigated = false

    var body: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spaces.three) {
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .frame(maxWidth: Sizes.maxWidthForLargerScreens)
            .padding(.horizontal, DesignSystem.Spaces.two)
            .padding(.top, DesignSystem.Spaces.six)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The whole sign-in lives in this structured task: replacing `sessionID` (start over) cancels
        // the previous attempt, and leaving the screen cancels the polling loop (lifecycle rule 1).
        .task(id: viewModel.sessionID) {
            await viewModel.runSignIn()
        }
        // Lifecycle rule 3: if the user authorized in an external browser, poll immediately on return
        // instead of waiting out the current interval.
        .task(id: scenePhase) {
            if scenePhase == .active {
                await viewModel.pollOnceAfterForeground()
            }
        }
        .onChange(of: viewModel.signInState) { newState in
            if case .authorized = newState, !hasNavigated {
                hasNavigated = true
                advanceToProvision()
            }
        }
        .sheet(isPresented: $showVerificationPage) {
            if let verificationURL {
                SafariWebView(url: verificationURL)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.signInState {
        case .idle, .requestingCode:
            loader(text: WoowtechL10n.SignIn.preparing)
        case let .waitingForAuth(userCode, _, isReconnecting):
            waitingContent(userCode: userCode, isReconnecting: isReconnecting)
        case .authorized:
            loader(text: WoowtechL10n.SignIn.authorized)
        case let .error(message, canRetry):
            errorContent(message: message, canRetry: canRetry)
        }
    }

    private func loader(text: String) -> some View {
        VStack(spacing: DesignSystem.Spaces.three) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(Constants.progressScale)
            Text(verbatim: text)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, DesignSystem.Spaces.six)
    }

    private func waitingContent(userCode: String, isReconnecting: Bool) -> some View {
        VStack(spacing: DesignSystem.Spaces.three) {
            Text(verbatim: WoowtechL10n.SignIn.title)
                .font(DesignSystem.Font.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text(verbatim: WoowtechL10n.SignIn.instructions)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(verbatim: userCode)
                .font(DesignSystem.Font.largeTitle.bold().monospaced())
                .kerning(Constants.userCodeKerning)
                .multilineTextAlignment(.center)
                .padding(.vertical, DesignSystem.Spaces.two)
                .screenCaptureProtected()
            Button {
                UIPasteboard.general.string = userCode
            } label: {
                Label(WoowtechL10n.SignIn.copyCode, systemSymbol: .docOnDoc)
                    .font(DesignSystem.Font.subheadline)
            }
            .tint(Color.haPrimary)
            ProgressView()
                .progressViewStyle(.circular)
            Text(verbatim: isReconnecting ? WoowtechL10n.SignIn.reconnecting : WoowtechL10n.SignIn.waiting)
                .font(DesignSystem.Font.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showVerificationPage = true
            } label: {
                Text(verbatim: WoowtechL10n.SignIn.openBrowser)
            }
            .buttonStyle(.primaryButton)
            .disabled(verificationURL == nil)
        }
    }

    private func errorContent(message: String, canRetry: Bool) -> some View {
        VStack(spacing: DesignSystem.Spaces.three) {
            Image(systemSymbol: .exclamationmarkCircle)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: Constants.errorIconSize, height: Constants.errorIconSize)
                .foregroundStyle(.red)
            Text(verbatim: message)
                .multilineTextAlignment(.center)
            if canRetry {
                Button {
                    viewModel.restartSignIn()
                } label: {
                    Text(verbatim: WoowtechL10n.SignIn.retry)
                }
                .buttonStyle(.secondaryButton)
                .tint(Color.haPrimary)
            }
        }
        .padding(.top, DesignSystem.Spaces.six)
    }

    private var verificationURL: URL? {
        guard case let .waitingForAuth(_, verificationURL, _) = viewModel.signInState else { return nil }
        return verificationURL
    }

    /// Replaces this page with the provisioning one in a single path update, mirroring Android's
    /// `navigateToCloudProvisionAfterSignIn`: back from provisioning must not land on a sign-in
    /// screen whose device code is already spent.
    private func advanceToProvision() {
        var path = presenter.path
        path.removeAll { destination in
            if case .cloudSignIn = destination { return true }
            return false
        }
        path.append(.cloudProvision(viewModel))
        presenter.path = path
    }
}

#Preview {
    NavigationStack {
        CloudSignInView(viewModel: DeviceFlowViewModel(), presenter: OnboardingAuthPresenter())
    }
}
#endif
