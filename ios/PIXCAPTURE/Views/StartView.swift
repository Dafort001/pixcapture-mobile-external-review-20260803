import SwiftUI

struct StartView: View {
  private enum Palette {
    static let background = Color.black
    static let darkBlue = Color(red: 42.0 / 255.0, green: 63.0 / 255.0, blue: 104.0 / 255.0)
    static let lightBlue = Color(red: 108.0 / 255.0, green: 168.0 / 255.0, blue: 200.0 / 255.0)
    static let orange = Color(red: 209.0 / 255.0, green: 94.0 / 255.0, blue: 64.0 / 255.0)
    static let pink = Color(red: 227.0 / 255.0, green: 163.0 / 255.0, blue: 174.0 / 255.0)
    static let indigo = Color(red: 58.0 / 255.0, green: 70.0 / 255.0, blue: 124.0 / 255.0)
    static let slate = Color(red: 95.0 / 255.0, green: 100.0 / 255.0, blue: 106.0 / 255.0)
    static let darkText = Color.black.opacity(0.78)
    static let utilityText = Color.white.opacity(0.56)
    static let uploadIndicator = Color(red: 1.0, green: 184.0 / 255.0, blue: 76.0 / 255.0)
  }

  var onNavigate: (AppScreen) -> Void
  var onLogout: () -> Void
  var onOpenLogin: () -> Void

  @EnvironmentObject var uploadQueue: UploadQueue
  @EnvironmentObject private var settings: AppSettings
  @EnvironmentObject private var authService: AuthService

  @State private var isJobSheetPresented = false
  @State private var isStartMenuPresented = false
  @State private var showAccountSwitchConfirmation = false

  private var hasOpenUploads: Bool {
    uploadQueue.records.contains(where: { $0.status == .pending || $0.status == .failed })
  }

  private var selectedJobId: String? {
    let trimmed = settings.selectedJobId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
  }

  private var quickJobs: [JobInfo] {
    let jobs = authService.availableJobs
    guard let selectedJobId,
          let selected = jobs.first(where: { $0.id == selectedJobId }) else {
      return jobs
    }
    return [selected] + jobs.filter { $0.id != selectedJobId }
  }

  private var shouldShowJobStrip: Bool {
    authService.isAuthenticated && !quickJobs.isEmpty
  }

  var body: some View {
    GeometryReader { geometry in
      let horizontalPadding = min(max(geometry.size.width * 0.05, 16.0), 24.0)
      let contentWidth = max(geometry.size.width - horizontalPadding * 2.0, 0.0)
      let columnSpacing = geometry.size.width < 390.0 ? 14.0 : 18.0
      let logoWidth = min(max(contentWidth * 0.42, 148.0), 224.0)
      let availableButtonWidth = contentWidth - logoWidth - columnSpacing
      let buttonWidth = min(max(availableButtonWidth, 140.0), 240.0)
      let buttonHeight = min(max(geometry.size.height * 0.084, 70.0), 88.0)

      ZStack {
        Palette.background
          .ignoresSafeArea()

        VStack(alignment: .leading, spacing: 0) {
          Spacer(minLength: max(geometry.safeAreaInsets.top + 118.0, geometry.size.height * 0.17))

          HStack(alignment: .top, spacing: columnSpacing) {
            Image("AppLogo")
              .resizable()
              .renderingMode(.original)
              .scaledToFit()
              .frame(width: logoWidth)
              .padding(.top, buttonHeight * 0.54)
              .accessibilityLabel(l10n("start.logo.accessibility"))

            Spacer(minLength: 0)

            VStack(spacing: 16) {
              menuButton(
                title: l10n("start.button.start"),
                fill: Palette.indigo,
                textColor: Palette.pink,
                width: buttonWidth,
                height: buttonHeight,
                action: { isStartMenuPresented = true }
              )

              menuButton(
                title: l10n("start.button.camera"),
                fill: Palette.lightBlue,
                textColor: Palette.darkBlue,
                width: buttonWidth,
                height: buttonHeight,
                action: { onNavigate(.camera) }
              )

              menuButton(
                title: l10n("start.button.gallery"),
                fill: Palette.pink,
                textColor: Palette.darkBlue,
                width: buttonWidth,
                height: buttonHeight,
                showsUploadIndicator: hasOpenUploads,
                action: { onNavigate(.gallery) }
              )

              menuButton(
                title: l10n("start.button.floorplan"),
                fill: Palette.orange,
                textColor: Palette.darkText,
                width: buttonWidth,
                height: buttonHeight,
                action: { onNavigate(.floorplan) }
              )

              menuButton(
                title: l10n("start.button.sunPlan"),
                fill: Palette.slate,
                textColor: Palette.pink,
                width: buttonWidth,
                height: buttonHeight,
                action: { onNavigate(.sunPlan) }
              )
            }
          }
          .frame(maxWidth: .infinity, alignment: .top)

          Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, horizontalPadding)
      }
    }
    .safeAreaInset(edge: .bottom) {
      BottomNavBar(selected: .start) { tab in
        switch tab {
        case .start: onNavigate(.start)
        case .help: onNavigate(.help)
        case .sunPlan: onNavigate(.sunPlan)
        case .camera: onNavigate(.camera)
        case .panorama: onNavigate(AppFeatureFlags.secondaryCaptureScreen)
        case .gallery: onNavigate(.gallery)
        case .manual: onNavigate(.settings)
        }
      }
    }
    .sheet(isPresented: $isStartMenuPresented) {
      startMenuSheet
    }
    .sheet(isPresented: $isJobSheetPresented) {
      JobSelectionSheet(
        title: l10n("start.jobs.sheet.title"),
        subtitle: l10n("start.jobs.sheet.subtitle"),
        allowsClear: true,
        clearLabel: l10n("start.jobs.sheet.clear"),
        requiresSelection: false,
        onSelect: { job in applySelectedJob(job) },
        onClear: clearSelectedJob
      )
      .environmentObject(authService)
      .environmentObject(settings)
    }
    .confirmationDialog(
      l10n("start.account.switch.title"),
      isPresented: $showAccountSwitchConfirmation,
      titleVisibility: .visible
    ) {
      Button(l10n("start.account.switch.confirm")) {
        onLogout()
      }
      Button(l10n("common.cancel"), role: .cancel) {}
    } message: {
      Text(l10n("start.account.switch.message"))
    }
    .task {
      if authService.isAuthenticated && authService.availableJobs.isEmpty {
        await authService.refreshJobs()
      }
    }
  }

  private var topUtilityBar: some View {
    HStack(spacing: 18) {
      Spacer()

      Button(l10n("start.utility.jobs")) {
        isJobSheetPresented = true
      }
      .buttonStyle(.plain)
      .font(inter(size: 10, weight: .regular))
      .tracking(1.3)
      .foregroundStyle(Palette.utilityText)

      if authService.isAuthenticated {
        Button(l10n("start.utility.account")) {
          showAccountSwitchConfirmation = true
        }
        .buttonStyle(.plain)
        .font(inter(size: 10, weight: .regular))
        .tracking(1.3)
        .foregroundStyle(Palette.utilityText)
      }

      if authService.isAuthenticated && AppFeatureFlags.quickLogoutEnabled {
        Button(l10n("start.utility.logout")) {
          onLogout()
        }
        .buttonStyle(.plain)
        .font(inter(size: 10, weight: .regular))
        .tracking(1.3)
        .foregroundStyle(Palette.utilityText)
      }
    }
  }

  private var startMenuSheet: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 18) {
        VStack(alignment: .leading, spacing: 6) {
          Text(l10n("start.menu.title"))
            .font(inter(size: 11, weight: .regular))
            .tracking(1.4)
            .foregroundStyle(Palette.utilityText)

          if let selectedJob = quickJobs.first(where: { $0.id == selectedJobId }) {
            Text(l10nFormat("start.menu.activeJob.format", selectedJob.name))
              .font(inter(size: 16, weight: .regular))
              .foregroundStyle(Color.white.opacity(0.88))
              .lineLimit(1)

            if let address = selectedJob.propertyAddress?.trimmingCharacters(in: .whitespacesAndNewlines),
               !address.isEmpty {
              Text(address)
                .font(inter(size: 12, weight: .light))
                .foregroundStyle(Color.white.opacity(0.58))
                .lineLimit(1)
            }
          } else {
            Text(l10n("start.menu.noActiveJob"))
              .font(inter(size: 16, weight: .regular))
              .foregroundStyle(Color.white.opacity(0.88))
          }
        }
        .padding(.bottom, 4)

        startMenuRow(
          icon: "briefcase.fill",
          title: l10n("start.menu.jobs.title"),
          subtitle: l10n("start.menu.jobs.subtitle")
        ) {
          isStartMenuPresented = false
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            isJobSheetPresented = true
          }
        }

        if selectedJobId != nil {
          startMenuRow(
            icon: "xmark.circle",
            title: l10n("start.menu.clearJob.title"),
            subtitle: l10n("start.menu.clearJob.subtitle")
          ) {
            clearSelectedJob()
            isStartMenuPresented = false
          }
        }

        startMenuLanguagePicker

        startMenuRow(
          icon: "list.bullet.rectangle",
          title: "Erste Schritte",
          subtitle: "Kurze Anleitung fuer Auftrag, Aufnahme, Galerie, Upload und Grundriss."
        ) {
          isStartMenuPresented = false
          onNavigate(.onboarding)
        }

        if authService.isAuthenticated {
          startMenuRow(
            icon: "person.crop.circle",
            title: l10n("start.menu.account.title"),
            subtitle: l10n("start.menu.account.subtitle")
          ) {
            isStartMenuPresented = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
              showAccountSwitchConfirmation = true
            }
          }
        } else {
          startMenuRow(
            icon: "person.crop.circle.badge.plus",
            title: l10n("start.menu.login.title"),
            subtitle: l10n("start.menu.login.subtitle")
          ) {
            isStartMenuPresented = false
            onOpenLogin()
          }
        }

        startMenuRow(
          icon: "questionmark.circle",
          title: l10n("start.menu.help.title"),
          subtitle: l10n("start.menu.help.subtitle")
        ) {
          isStartMenuPresented = false
          onNavigate(.help)
        }

        Spacer(minLength: 0)
      }
      .padding(22)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(Palette.background)
      .navigationTitle(l10n("bottom.start"))
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(l10n("common.done")) { isStartMenuPresented = false }
        }
      }
    }
    .presentationDetents([.height(620), .large])
    .presentationDragIndicator(.visible)
  }

  private func startMenuRow(
    icon: String,
    title: String,
    subtitle: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 14) {
        Image(systemName: icon)
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(Palette.lightBlue)
          .frame(width: 28, height: 28)

        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(inter(size: 15, weight: .regular))
            .foregroundStyle(Color.white.opacity(0.9))
          Text(subtitle)
            .font(inter(size: 11, weight: .light))
            .foregroundStyle(Color.white.opacity(0.58))
            .lineLimit(2)
        }

        Spacer(minLength: 0)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 13)
      .background(Color.white.opacity(0.07))
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  private var startMenuLanguagePicker: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 14) {
        Image(systemName: "globe")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(Palette.lightBlue)
          .frame(width: 28, height: 28)

        Text(l10n("start.menu.language.title"))
          .font(inter(size: 15, weight: .regular))
          .foregroundStyle(Color.white.opacity(0.9))

        Spacer(minLength: 0)
      }

      Picker(l10n("start.menu.language.title"), selection: $settings.appLanguage) {
        Text(l10n("language.system")).tag(AppLanguage.system)
        Text(l10n("language.de")).tag(AppLanguage.de)
        Text(l10n("language.en")).tag(AppLanguage.en)
      }
      .pickerStyle(.segmented)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 13)
    .background(Color.white.opacity(0.07))
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private var jobQuickStrip: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        Text(l10n("start.utility.jobs"))
          .font(inter(size: 10, weight: .regular))
          .tracking(1.3)
          .foregroundStyle(Palette.utilityText)

        if let selectedJob = quickJobs.first(where: { $0.id == selectedJobId }) {
          Text(l10nFormat("start.quick.active.format", selectedJob.name))
            .font(inter(size: 11, weight: .light))
            .foregroundStyle(Color.white.opacity(0.72))
            .lineLimit(1)
        }

        Spacer()

        if selectedJobId != nil {
          Button(l10n("start.quick.clear")) {
            clearSelectedJob()
          }
          .buttonStyle(.plain)
          .font(inter(size: 10, weight: .regular))
          .tracking(1.0)
          .foregroundStyle(Palette.utilityText)
        }
      }

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 10) {
          Button {
            isJobSheetPresented = true
          } label: {
            HStack(spacing: 8) {
              Image(systemName: "square.grid.2x2")
                .font(.system(size: 12, weight: .semibold))
              Text(l10n("start.quick.allJobs"))
                .font(inter(size: 11, weight: .regular))
                .tracking(0.7)
            }
            .foregroundStyle(Color.white.opacity(0.82))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
          }
          .buttonStyle(.plain)

          ForEach(quickJobs) { job in
            quickJobChip(job)
          }
        }
        .padding(.vertical, 2)
      }
    }
  }

  private func quickJobChip(_ job: JobInfo) -> some View {
    let isSelected = selectedJobId == job.id

    return HStack(spacing: 10) {
      Button {
        applySelectedJob(job)
      } label: {
        VStack(alignment: .leading, spacing: 3) {
          Text(job.name)
            .font(inter(size: 13, weight: .regular))
            .lineLimit(1)
          if let address = job.propertyAddress?.trimmingCharacters(in: .whitespacesAndNewlines),
             !address.isEmpty {
            Text(address)
              .font(inter(size: 10, weight: .light))
              .foregroundStyle((isSelected ? Palette.darkBlue : Color.white).opacity(isSelected ? 0.72 : 0.64))
              .lineLimit(1)
          }
        }
        .foregroundStyle(isSelected ? Palette.darkBlue : Color.white.opacity(0.88))
        .frame(width: 170, alignment: .leading)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .background(isSelected ? Color.white : Color.white.opacity(0.08))
    .clipShape(Capsule())
  }

  private func menuButton(
    title: String,
    fill: Color,
    textColor: Color,
    width: CGFloat,
    height: CGFloat,
    showsUploadIndicator: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      ZStack(alignment: .topTrailing) {
        Rectangle()
          .fill(fill)
          .frame(width: width, height: height)

        if showsUploadIndicator {
          Circle()
            .fill(Palette.uploadIndicator)
            .frame(width: 11, height: 11)
            .padding(.top, 10)
            .padding(.trailing, 10)
        }

        Text(title)
          .font(inter(size: 20, weight: .light))
          .tracking(0.9)
          .foregroundStyle(textColor)
          .lineLimit(1)
          .minimumScaleFactor(0.72)
          .allowsTightening(true)
          .frame(width: max(width - 16.0, 1.0), height: height, alignment: .center)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func applySelectedJob(_ job: JobInfo) {
    settings.setCurrentJob(job, userScope: authService.recentJobScope)
  }

  private func clearSelectedJob() {
    settings.clearCurrentJobSelection()
  }

  private func inter(size: CGFloat, weight: Font.Weight = .regular) -> Font {
    .pixInter(size: size, weight: weight)
  }

  private func l10n(_ key: String) -> String {
    settings.localized(key)
  }

  private func l10nFormat(_ key: String, _ arguments: CVarArg...) -> String {
    AppLocalizer.localizedFormat(key, language: settings.appLanguage, arguments: arguments)
  }
}
