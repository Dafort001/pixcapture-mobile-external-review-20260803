import SwiftUI

struct SplashView: View {
  private enum Field: Hashable {
    case email
    case password
  }

  private enum Palette {
    static let background = Color.black
    static let orange = Color(red: 209.0 / 255.0, green: 94.0 / 255.0, blue: 64.0 / 255.0)
    static let lightBlue = Color(red: 108.0 / 255.0, green: 168.0 / 255.0, blue: 200.0 / 255.0)
    static let pink = Color(red: 227.0 / 255.0, green: 163.0 / 255.0, blue: 174.0 / 255.0)
    static let line = orange
    static let fieldText = AppTheme.textOnDark
    static let infoText = AppTheme.textOnDark.opacity(0.84)
    static let errorText = Color(red: 1.0, green: 111.0 / 255.0, blue: 97.0 / 255.0)
    static let panelFill = Color.white.opacity(0.06)
    static let panelBorder = Color.white.opacity(0.14)
    static let panelText = AppTheme.textOnDarkStrong.opacity(0.94)
    static let panelMuted = AppTheme.textOnDark.opacity(0.78)
  }

  private static let registrationURL = URL(string: "https://pixcapture.app/auth/signin?mode=register")!

  @EnvironmentObject private var authService: AuthService
  @EnvironmentObject private var settings: AppSettings
  @AppStorage("pixcapture.lastLoginEmail") private var lastLoginEmail = ""

  var onStartDemo: () -> Void
  var onLogin: () -> Void
  var onOpenHelp: () -> Void
  var onBackToStart: (() -> Void)? = nil

  @State private var email = ""
  @State private var password = ""
  @State private var isLoading = false
  @State private var isQRScannerPresented = false
  @State private var scannerMessage: String?
  @FocusState private var focusedField: Field?

  var body: some View {
    GeometryReader { geometry in
      let logoWidth = min(geometry.size.width * 0.78, 430.0)
      let fieldWidth = min(geometry.size.width - 64.0, 360.0)
      let topInset = max(geometry.safeAreaInsets.top + 32.0, geometry.size.height * 0.08)
      let bottomInset = max(geometry.safeAreaInsets.bottom + 24.0, 32.0)

      ZStack {
        Palette.background
          .ignoresSafeArea()

        if let onBackToStart {
          Button {
            focusedField = nil
            hideSystemKeyboard()
            onBackToStart()
          } label: {
            HStack(spacing: 8) {
              Image(systemName: "chevron.left")
                .font(.system(size: 14, weight: .semibold))
              Text(l10n("splash.backToStart"))
                .font(inter(size: 11, weight: .regular))
                .tracking(0.8)
            }
            .foregroundStyle(Palette.lightBlue)
            .frame(minHeight: 40)
            .padding(.horizontal, 14)
          }
          .buttonStyle(.plain)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
          .padding(.top, geometry.safeAreaInsets.top + 8)
          .padding(.leading, 18)
          .zIndex(2)
        }

        ScrollViewReader { proxy in
          ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
              Image("AppLogo")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: logoWidth)
                .accessibilityLabel(l10n("start.logo.accessibility"))
                .contentShape(Rectangle())
                .onTapGesture {
                  guard let onBackToStart else { return }
                  focusedField = nil
                  hideSystemKeyboard()
                  onBackToStart()
                }

              onboardingCard(width: fieldWidth)

              VStack(spacing: 18) {
                Text(l10n("splash.login.info"))
                  .font(inter(size: 12, weight: .regular))
                  .tracking(0.5)
                  .multilineTextAlignment(.center)
                  .foregroundStyle(Palette.infoText)
                  .frame(maxWidth: fieldWidth)

                VStack(spacing: 36) {
                  underlineField(
                    placeholder: l10n("splash.login.emailPlaceholder"),
                    text: $email,
                    field: .email,
                    isSecure: false,
                    submitLabel: .next
                  ) {
                    focusedField = .password
                  }

                  underlineField(
                    placeholder: l10n("splash.login.passwordPlaceholder"),
                    text: $password,
                    field: .password,
                    isSecure: true,
                    submitLabel: .go
                  ) {
                    loginWithPassword()
                  }
                }
                .frame(width: fieldWidth)

                Button {
                  focusedField = nil
                  loginWithPassword()
                } label: {
                  Group {
                    if isLoading {
                      ProgressView()
                        .tint(Palette.background)
                    } else {
                      Text(l10n("splash.login.passwordButton"))
                        .font(inter(size: 16, weight: .regular))
                        .tracking(1.0)
                        .foregroundStyle(Palette.background)
                    }
                  }
                  .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.plain)
                .frame(width: fieldWidth)
                .background(Palette.orange)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .opacity(canSubmitPasswordLogin ? 1.0 : 0.55)
                .disabled(!canSubmitPasswordLogin)
                .id("password-submit")
              }

              if let statusMessage {
                Text(statusMessage)
                  .font(inter(size: 12, weight: .regular))
                  .tracking(0.6)
                  .multilineTextAlignment(.center)
                  .foregroundStyle(statusColor)
                  .frame(maxWidth: min(geometry.size.width - 72.0, 380.0))
                  .fixedSize(horizontal: false, vertical: true)
              }

              Button {
                onOpenHelp()
              } label: {
                Text(l10n("splash.help.button"))
                  .font(inter(size: 12, weight: .regular))
                  .tracking(0.9)
                  .foregroundStyle(Palette.lightBlue)
                  .frame(minHeight: 34)
              }
              .buttonStyle(.plain)

              Color.clear
                .frame(height: focusedField == .password ? 170 : 24)
                .id("login-bottom-spacer")
            }
            .frame(maxWidth: .infinity)
            .padding(.top, topInset)
            .padding(.bottom, bottomInset)
            .padding(.horizontal, 24)
          }
          .onChange(of: focusedField) { _, field in
            guard let field else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
              withAnimation(.easeOut(duration: 0.22)) {
                proxy.scrollTo(field == .password ? "password-submit" : fieldScrollId(field), anchor: .center)
              }
            }
          }
        }
      }
    }
    .dismissKeyboardOnTap()
    .keyboardDoneToolbar()
    .sheet(isPresented: $isQRScannerPresented) {
      qrScannerSheet
    }
    .onAppear {
      if email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        email = lastLoginEmail
      }
    }
  }

  private func onboardingCard(width: CGFloat) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 6) {
        Text(l10n("splash.onboarding.title"))
          .font(inter(size: 15, weight: .regular))
          .tracking(0.4)
          .foregroundStyle(Palette.panelText)
          .fixedSize(horizontal: false, vertical: true)
      }

      VStack(alignment: .leading, spacing: 10) {
        onboardingStep(number: "1", text: l10n("splash.onboarding.step1"))
        onboardingStep(number: "2", text: l10n("splash.onboarding.step2"))
        onboardingStep(number: "3", text: l10n("splash.onboarding.step3"))
      }

      Text(l10n("splash.onboarding.footer"))
        .font(inter(size: 12, weight: .regular))
        .tracking(0.4)
        .foregroundStyle(Palette.panelMuted)
        .fixedSize(horizontal: false, vertical: true)

      Link(destination: Self.registrationURL) {
        HStack(spacing: 8) {
          Image(systemName: "safari")
            .font(.system(size: 13, weight: .semibold))
          Text(l10n("splash.onboarding.registerButton"))
            .font(inter(size: 12, weight: .semibold))
            .tracking(0.4)
        }
        .foregroundStyle(Palette.lightBlue)
        .frame(maxWidth: .infinity, minHeight: 42)
        .background(Palette.lightBlue.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Palette.lightBlue.opacity(0.28), lineWidth: 1)
        )
      }
      .buttonStyle(.plain)
    }
    .frame(width: width, alignment: .leading)
    .padding(.horizontal, 16)
    .padding(.vertical, 16)
    .background(Palette.panelFill)
    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .stroke(Palette.panelBorder, lineWidth: 1)
    )
  }

  private func onboardingStep(number: String, text: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Text(number)
        .font(inter(size: 11, weight: .regular))
        .tracking(0.6)
        .foregroundStyle(Palette.background)
        .frame(width: 22, height: 22)
        .background(Palette.pink)
        .clipShape(Circle())

      Text(text)
        .font(inter(size: 12, weight: .regular))
        .tracking(0.4)
        .foregroundStyle(Palette.panelText)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func qrConnectButton(width: CGFloat) -> some View {
    Button {
      focusedField = nil
      scannerMessage = nil
      isQRScannerPresented = true
    } label: {
      Group {
        if isLoading {
          ProgressView()
            .tint(Palette.orange)
        } else {
          VStack(spacing: 3) {
            Text(l10n("splash.qr.title"))
              .font(inter(size: 18, weight: .light))
              .tracking(1.1)
            Text(l10n("splash.qr.subtitle"))
              .font(inter(size: 11, weight: .regular))
              .tracking(0.6)
              .foregroundStyle(Palette.panelMuted)
          }
          .foregroundStyle(Palette.orange)
        }
      }
      .frame(maxWidth: .infinity, minHeight: 54)
    }
    .buttonStyle(.plain)
    .frame(width: width)
    .background(Palette.panelFill)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(Palette.panelBorder, lineWidth: 1)
    )
  }

  private func underlineField(
    placeholder: String,
    text: Binding<String>,
    field: Field,
    isSecure: Bool,
    submitLabel: SubmitLabel,
    onSubmit: @escaping () -> Void
  ) -> some View {
    VStack(spacing: 14) {
      Group {
        if isSecure {
          SecureField(
            "",
            text: text,
            prompt: Text(placeholder).foregroundStyle(Palette.fieldText)
          )
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled(true)
          .textContentType(.password)
        } else {
          TextField(
            "",
            text: text,
            prompt: Text(placeholder).foregroundStyle(Palette.fieldText)
          )
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled(true)
          .keyboardType(.emailAddress)
          .textContentType(.username)
        }
      }
      .focused($focusedField, equals: field)
      .submitLabel(submitLabel)
      .onSubmit(onSubmit)
      .multilineTextAlignment(.center)
      .font(inter(size: 18, weight: .light))
      .tracking(0.9)
      .foregroundStyle(Palette.fieldText)

      Rectangle()
        .fill(Palette.line)
        .frame(height: 1.5)
    }
    .id(fieldScrollId(field))
  }

  private func fieldScrollId(_ field: Field) -> String {
    switch field {
    case .email:
      return "login-email"
    case .password:
      return "login-password"
    }
  }

  private var qrScannerSheet: some View {
    ZStack(alignment: .topTrailing) {
      MobileConnectQRScannerView { rawCode in
        applyScannedPairingCode(rawCode)
      } onError: { message in
        scannerMessage = message
        isQRScannerPresented = false
      }

      Button {
        isQRScannerPresented = false
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.title2)
          .foregroundStyle(.white)
          .padding(14)
      }
    }
    .ignoresSafeArea()
  }

  private func applyScannedPairingCode(_ rawCode: String) {
    guard let token = AuthService.parseMobileConnectToken(from: rawCode) else {
      scannerMessage = AuthService.looksLikeWebConnectQR(rawCode)
        ? l10n("splash.qr.uploadConnectScanned")
        : l10n("splash.qr.invalid")
      isQRScannerPresented = false
      return
    }

    authService.setMobileConnectToken(token)
    scannerMessage = nil
    isQRScannerPresented = false
    onLogin()
  }

  private func loginWithPassword() {
    guard !isLoading else { return }
    let targetEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let targetPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !targetEmail.isEmpty, !targetPassword.isEmpty else {
      authService.lastError = l10n("splash.login.missingCredentials")
      return
    }
    isLoading = true
    scannerMessage = nil

    Task {
      let didLogin = await authService.loginWithPassword(email: targetEmail, password: targetPassword)
      isLoading = false

      guard didLogin, authService.isAuthenticated else { return }
      lastLoginEmail = targetEmail
      onLogin()
    }
  }

  private var statusMessage: String? {
    let error = authService.lastError?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !error.isEmpty {
      return error
    }

    if let scannerMessage,
       !scannerMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return scannerMessage
    }

    let info = authService.lastInfoMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return info.isEmpty ? nil : info
  }

  private var statusColor: Color {
    if let error = authService.lastError?.trimmingCharacters(in: .whitespacesAndNewlines),
       !error.isEmpty {
      return Palette.errorText
    }
    if let scannerMessage,
       !scannerMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return Palette.lightBlue
    }
    return Palette.infoText
  }

  private var canSubmitPasswordLogin: Bool {
    let targetEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
    let targetPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
    return !isLoading && !targetEmail.isEmpty && !targetPassword.isEmpty
  }

  private func inter(size: CGFloat, weight: Font.Weight = .regular) -> Font {
    .pixInter(size: size, weight: weight)
  }

  private func l10n(_ key: String) -> String {
    settings.localized(key)
  }
}
