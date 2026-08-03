import SwiftUI

struct OnboardingView: View {
  @EnvironmentObject private var settings: AppSettings

  var onDone: () -> Void
  var onLogin: () -> Void

  private enum Palette {
    static let background = Color.black
    static let primary = Color(red: 42.0 / 255.0, green: 63.0 / 255.0, blue: 104.0 / 255.0)
    static let blue = Color(red: 108.0 / 255.0, green: 168.0 / 255.0, blue: 200.0 / 255.0)
    static let orange = Color(red: 209.0 / 255.0, green: 94.0 / 255.0, blue: 64.0 / 255.0)
    static let pink = Color(red: 227.0 / 255.0, green: 163.0 / 255.0, blue: 174.0 / 255.0)
    static let panel = Color.white.opacity(0.07)
    static let border = Color.white.opacity(0.13)
    static let text = AppTheme.textOnDark
    static let strongText = AppTheme.textOnDarkStrong
  }

  private static let registrationURL = URL(string: "https://pixcapture.app/auth/signin?mode=register")!

  var body: some View {
    GeometryReader { geometry in
      let contentWidth = min(max(geometry.size.width - 40, 0), 460)

      ZStack {
        Palette.background
          .ignoresSafeArea()

        ScrollView(showsIndicators: false) {
          VStack(alignment: .leading, spacing: 18) {
            Image("AppLogo")
              .resizable()
              .renderingMode(.original)
              .scaledToFit()
              .frame(width: min(contentWidth * 0.62, 250))
              .frame(maxWidth: .infinity, alignment: .center)
              .padding(.bottom, 6)

            Text(l10n("onboarding.activation.title"))
              .font(.pixInter(size: 23, weight: .semibold))
              .foregroundStyle(Palette.strongText)

            Text(l10n("onboarding.activation.intro"))
              .font(.pixInter(size: 14, weight: .regular))
              .foregroundStyle(Palette.text.opacity(0.88))
              .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
              onboardingRow(
                number: "1",
                title: l10n("onboarding.activation.step1.title"),
                body: l10n("onboarding.activation.step1.body"),
                color: Palette.blue
              )
              onboardingRow(
                number: "2",
                title: l10n("onboarding.activation.step2.title"),
                body: l10n("onboarding.activation.step2.body"),
                color: Palette.orange
              )
              onboardingRow(
                number: "3",
                title: l10n("onboarding.activation.step3.title"),
                body: l10n("onboarding.activation.step3.body"),
                color: Palette.pink
              )
              onboardingRow(
                number: "4",
                title: l10n("onboarding.activation.step4.title"),
                body: l10n("onboarding.activation.step4.body"),
                color: Palette.blue
              )
              onboardingRow(
                number: "5",
                title: l10n("onboarding.activation.step5.title"),
                body: l10n("onboarding.activation.step5.body"),
                color: Palette.orange
              )
            }

            VStack(spacing: 10) {
              Button {
                onDone()
              } label: {
                Text(l10n("onboarding.activation.offlineButton"))
                  .font(.pixInter(size: 16, weight: .semibold))
                  .foregroundStyle(Color.black.opacity(0.82))
                  .frame(maxWidth: .infinity, minHeight: 50)
                  .background(Palette.orange)
                  .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
              }
              .buttonStyle(.plain)

              Link(destination: Self.registrationURL) {
                Text(l10n("onboarding.activation.registerButton"))
                  .font(.pixInter(size: 16, weight: .semibold))
                  .foregroundStyle(Palette.blue)
                  .frame(maxWidth: .infinity, minHeight: 46)
                  .background(Palette.blue.opacity(0.10))
                  .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
              }
              .buttonStyle(.plain)

              Button {
                onLogin()
              } label: {
                Text(l10n("onboarding.activation.loginButton"))
                  .font(.pixInter(size: 14, weight: .semibold))
                  .foregroundStyle(Palette.text.opacity(0.76))
                  .frame(maxWidth: .infinity, minHeight: 44)
              }
              .buttonStyle(.plain)
            }
            .padding(.top, 6)
          }
          .frame(width: contentWidth, alignment: .leading)
          .frame(maxWidth: .infinity)
          .padding(.top, max(geometry.safeAreaInsets.top + 28, 44))
          .padding(.bottom, max(geometry.safeAreaInsets.bottom + 28, 40))
          .padding(.horizontal, 20)
        }
      }
    }
  }

  private func onboardingRow(number: String, title: String, body: String, color: Color) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Text(number)
        .font(.pixInter(size: 13, weight: .semibold))
        .foregroundStyle(Color.black.opacity(0.82))
        .frame(width: 28, height: 28)
        .background(color)
        .clipShape(Circle())

      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.pixInter(size: 14, weight: .semibold))
          .foregroundStyle(Palette.strongText.opacity(0.96))
        Text(body)
          .font(.pixInter(size: 12, weight: .regular))
          .foregroundStyle(Palette.text.opacity(0.82))
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(13)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Palette.panel)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Palette.border, lineWidth: 1)
    )
  }

  private func l10n(_ key: String) -> String {
    settings.localized(key)
  }
}
