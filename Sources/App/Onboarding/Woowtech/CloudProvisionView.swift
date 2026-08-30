#if CLOUD_EDITION
import SFSafeSymbols
import Shared
import SwiftUI

/// The provisioning screen: asks WOOW PaaS for a hosted Home Assistant instance, waits for it to
/// become ready and then hands its URL over to the unchanged upstream registration flow — the same
/// `OnboardingServersListViewModel.selectInstance` path manual URL entry uses, so login, device
/// naming and permissions are all the standard pushes. Counterpart of Android's `CloudProvisionScreen`.
struct CloudProvisionView: View {
    private enum Constants {
        static let statusIconSize: CGFloat = 80
        static let progressScale: CGFloat = 2
    }

    @ObservedObject var viewModel: DeviceFlowViewModel
    /// Owned by `OnboardingNavigationView`; the upstream auth flow pushes its pages through it.
    let presenter: OnboardingAuthPresenter

    /// The upstream servers-list view model, reused purely for its `selectInstance` hand-off (it runs
    /// `OnboardingAuth` and pushes `.permissions` on success); its discovery side is never started.
    @StateObject private var handoffViewModel = OnboardingServersListViewModel(shouldDismissOnSuccess: false)
    @State private var hasStartedHandoff = false

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
        .safeAreaInset(edge: .bottom) {
            bottomButtons
        }
        // Provisioning survives leaving-and-returning decisions the user cannot influence, but not an
        // explicit back: hide the back button while a provisioning attempt or the hand-off is running.
        .navigationBarBackButtonHidden(!isBackAllowed)
        .task {
            await viewModel.verifyStoredSession()
        }
        // The whole provisioning attempt is one structured task (lifecycle rule 1); retrying replaces
        // the id, which cancels the previous attempt before starting the new one.
        .task(id: viewModel.provisionAttemptID) {
            guard viewModel.provisionAttemptID != nil else { return }
            await viewModel.runProvision()
        }
        .onChange(of: viewModel.provisionState) { newState in
            if case let .ready(serverURL) = newState, !hasStartedHandoff {
                startHandoff(serverURL: serverURL)
            }
        }
        // Same error presentation as the servers list: the upstream flow reports connection problems
        // through the view model's error sheet.
        .sheet(isPresented: $handoffViewModel.showError, onDismiss: {
            // Allow another attempt at the same, already-provisioned instance.
            hasStartedHandoff = false
            handoffViewModel.resetFlow()
        }) {
            handoffErrorSheet
        }
        // Lifecycle rule 4: auto-lock would freeze the polling loops mid-provision; restored on the
        // way out no matter how the screen is left.
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.provisionState {
        case .idle:
            statusBlock(
                symbol: .icloudFill,
                tint: Color.haPrimary,
                title: WoowtechL10n.Provision.idleTitle,
                body: WoowtechL10n.Provision.idleBody
            )
        case .provisioning:
            VStack(spacing: DesignSystem.Spaces.three) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(Constants.progressScale)
                    .padding(.bottom, DesignSystem.Spaces.two)
                Text(verbatim: WoowtechL10n.Provision.provisioning)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, DesignSystem.Spaces.six)
        case .ready:
            statusBlock(
                symbol: .checkmarkCircleFill,
                tint: Color.haPrimary,
                title: WoowtechL10n.Provision.ready,
                body: nil
            )
        case let .error(message, _):
            statusBlock(
                symbol: .exclamationmarkCircle,
                tint: .red,
                title: nil,
                body: message
            )
        case .suspended:
            statusBlock(
                symbol: .pauseCircle,
                tint: .orange,
                title: WoowtechL10n.Provision.suspendedTitle,
                body: WoowtechL10n.Provision.suspendedBody
            )
        case .deleting:
            statusBlock(
                symbol: .trashCircle,
                tint: .orange,
                title: WoowtechL10n.Provision.deletingTitle,
                body: WoowtechL10n.Provision.deletingBody
            )
        }
    }

    private func statusBlock(symbol: SFSymbol, tint: Color, title: String?, body: String?) -> some View {
        VStack(spacing: DesignSystem.Spaces.three) {
            Image(systemSymbol: symbol)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: Constants.statusIconSize, height: Constants.statusIconSize)
                .foregroundStyle(tint)
            if let title {
                Text(verbatim: title)
                    .font(DesignSystem.Font.largeTitle.bold())
                    .multilineTextAlignment(.center)
            }
            if let body {
                Text(verbatim: body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private var bottomButtons: some View {
        switch viewModel.provisionState {
        case .idle:
            bottomButton(title: WoowtechL10n.Provision.start) {
                viewModel.requestProvision()
            }
        case let .error(_, canRetry) where canRetry:
            bottomButton(title: WoowtechL10n.Provision.retry) {
                viewModel.requestProvision()
            }
        case .deleting:
            bottomButton(title: WoowtechL10n.Provision.retry) {
                viewModel.requestProvision()
            }
        case let .ready(serverURL):
            // Normally the hand-off starts on its own; the button appears once an attempt failed or
            // was cancelled, so the already-provisioned instance can be connected to again.
            if !hasStartedHandoff, handoffViewModel.currentlyInstanceLoading == nil {
                bottomButton(title: WoowtechL10n.Provision.reconnect) {
                    startHandoff(serverURL: serverURL)
                }
            }
        default:
            EmptyView()
        }
    }

    private func bottomButton(title: String, action: @escaping () -> Void) -> some View {
        VStack {
            Button(action: action) {
                Text(verbatim: title)
            }
            .buttonStyle(.primaryButton)
        }
        .padding([.horizontal, .top], DesignSystem.Spaces.two)
        .background(Color(uiColor: .systemBackground))
    }

    private var isBackAllowed: Bool {
        switch viewModel.provisionState {
        case .idle, .suspended, .deleting, .error:
            return true
        case .provisioning:
            return false
        case .ready:
            // Mid hand-off; the auth flow above brings its own chrome once pushed.
            return false
        }
    }

    /// Hands the provisioned instance over to the unchanged upstream registration flow. From here on
    /// everything is upstream code: `selectInstance` runs `OnboardingAuth.authenticate`, whose pages
    /// (login web view, device naming, permissions) are pushed through the shared presenter, and the
    /// `Current.onServerRegistered` hook clears the WOOW PaaS session once the server is persisted.
    private func startHandoff(serverURL: URL) {
        hasStartedHandoff = true
        handoffViewModel.selectInstance(.init(manualURL: serverURL), presenter: presenter)
    }

    @ViewBuilder
    private var handoffErrorSheet: some View {
        if let error = handoffViewModel.error {
            ConnectionErrorDetailsView(
                server: nil,
                error: error,
                showSettingsEntry: false,
                expandMoreDetails: true
            )
        }
    }
}

#Preview {
    NavigationStack {
        CloudProvisionView(viewModel: DeviceFlowViewModel(), presenter: OnboardingAuthPresenter())
    }
}
#endif
