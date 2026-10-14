#if CLOUD_EDITION
import SFSafeSymbols
import Shared
import SwiftUI

/// Root of the cloud-edition onboarding stack: the user picks between connecting to an on-premise
/// device (the unchanged upstream flow, pushed as ``OnboardingDestination/welcome``) and provisioning
/// a hosted instance (the WOOW device-flow sign-in). Counterpart of Android's `CloudChooserScreen`.
struct CloudChooserView: View {
    private enum Constants {
        static let logoWidth: CGFloat = 120
        static let logoHeight: CGFloat = 120
    }

    /// Owned by `OnboardingNavigationView`; both choices are real pushes onto its navigation path.
    let presenter: OnboardingAuthPresenter

    var body: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spaces.three) {
                Spacer()
                logoBlock
                textBlock
                choices
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .frame(maxWidth: Sizes.maxWidthForLargerScreens)
            .padding(.horizontal, DesignSystem.Spaces.two)
            .padding(.top, DesignSystem.Spaces.six)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var logoBlock: some View {
        VStack(spacing: DesignSystem.Spaces.three) {
            Image(.logo)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(
                    width: Constants.logoWidth,
                    height: Constants.logoHeight,
                    alignment: .center
                )
                .launchSplashLogoAnchor()
            Text(verbatim: WoowtechL10n.Chooser.title)
                .font(DesignSystem.Font.largeTitle.bold())
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var textBlock: some View {
        Text(verbatim: WoowtechL10n.Chooser.subtitle)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, DesignSystem.Spaces.two)
    }

    private var choices: some View {
        VStack(spacing: DesignSystem.Spaces.two) {
            ChooserCard(
                symbol: .houseFill,
                title: WoowtechL10n.Chooser.localTitle,
                subtitle: WoowtechL10n.Chooser.localSubtitle,
                action: { presenter.push(.welcome) }
            )
            ChooserCard(
                symbol: .icloudFill,
                title: WoowtechL10n.Chooser.cloudTitle,
                subtitle: WoowtechL10n.Chooser.cloudSubtitle,
                action: { presenter.push(.cloudSignIn(DeviceFlowViewModel())) }
            )
        }
        .padding(.top, DesignSystem.Spaces.two)
    }
}

private struct ChooserCard: View {
    private enum Constants {
        static let iconSize: CGFloat = 40
        static let cornerRadius: CGFloat = 16
    }

    let symbol: SFSymbol
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spaces.two) {
                Image(systemSymbol: symbol)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: Constants.iconSize, height: Constants.iconSize)
                    .foregroundStyle(Color.haPrimary)
                VStack(alignment: .leading, spacing: DesignSystem.Spaces.half) {
                    Text(verbatim: title)
                        .font(DesignSystem.Font.body.bold())
                        .foregroundStyle(Color(uiColor: .label))
                    Text(verbatim: subtitle)
                        .font(DesignSystem.Font.subheadline)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.leading)
                Spacer()
            }
            .padding(DesignSystem.Spaces.two)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: Constants.cornerRadius))
            // To make the button tappable in any part of it
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        CloudChooserView(presenter: OnboardingAuthPresenter())
    }
}
#endif
