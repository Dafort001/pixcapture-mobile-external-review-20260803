import SwiftUI
import UIKit

enum AppFeatureFlags {
  static let publicBetaProfile = true
  // App Store MVP profile:
  // - Photo + Floorplan in scope
  // - Video + Panorama hidden, but code remains available.
  static let appStoreMVP = true
  static let floorplanEnabled = true
  static let videoEnabled = !appStoreMVP
  static let panoramaEnabled = !appStoreMVP
  static let quickLogoutEnabled = !publicBetaProfile
  static let visiblePhotoLibrarySaveEnabled = !publicBetaProfile
  static let visibleInternalExportEnabled = !publicBetaProfile
  static let emergencyRecoveryBuild = true
  static let supportToolsUnlockEnabled = publicBetaProfile && emergencyRecoveryBuild
  static let cameraGuidanceHintsEnabled = false
  static let cameraGuidanceSkeletonsEnabled = false
  static let cameraGuidanceHapticsEnabled = true

  static var secondaryCaptureScreen: AppScreen {
    if panoramaEnabled {
      return .panoramaTour
    }
    if floorplanEnabled {
      return .floorplan
    }
    return .camera
  }
}

struct RootView: View {
  private static let demoReviewJob = JobInfo(
    id: "demo-review-job",
    name: "Apple Review Demo",
    propertyAddress: "Demo Objekt, Musterstrasse 1, 20354 Hamburg"
  )
  private static let demoReviewFloorId = "eg"
  private static let recentJobResumeWindow: TimeInterval = 60 * 60

  @StateObject private var settings = AppSettings()
  @StateObject private var cameraModel = CameraManager()
  @StateObject private var uploadQueue = UploadQueue()
  @StateObject private var authService = AuthService()
  @StateObject private var companionTransfer = CompanionTransferService()
  @Environment(\.scenePhase) private var scenePhase
  @AppStorage("pixcapture.hasSeenFirstRunOnboarding") private var hasSeenFirstRunOnboarding = false
  @State private var currentScreen: AppScreen = .splash
  @State private var helpReturnScreen: AppScreen = .splash
  @State private var isDemoMode = false
  @State private var hasPreparedAuthenticatedLaunch = false
  @State private var recentLaunchJob: RecentJobSnapshot?
  @State private var isLaunchRecentJobSheetPresented = false
  @State private var isLaunchJobSheetPresented = false
  @State private var pendingLaunchTarget: AppScreen?
  @State private var pendingExternalWebConnectURL: String?

  var body: some View {
    ZStack {
      Group {
        switch currentScreen {
        case .onboarding:
          OnboardingView(
            onDone: {
              hasSeenFirstRunOnboarding = true
              currentScreen = .start
            },
            onLogin: {
              hasSeenFirstRunOnboarding = true
              currentScreen = .splash
            }
          )
        case .splash:
          SplashView(
            onStartDemo: {
              startDemoReviewMode()
            },
            onLogin: {
              isDemoMode = false
              currentScreen = .start
            },
            onOpenHelp: { openHelp(from: .splash) },
            onBackToStart: canUseLocalFeatures ? {
              currentScreen = .start
            } : nil
          )
        case .start:
          StartView(
            onNavigate: { handleNavigation($0) },
            onLogout: handleLogout,
            onOpenLogin: {
              currentScreen = .splash
            }
          )
        case .camera:
          CameraView(onNavigate: { handleNavigation($0) })
        case .gallery:
          GalleryView(
            pendingExternalConnectURL: $pendingExternalWebConnectURL,
            onNavigate: { handleNavigation($0) }
          )
        case .settings:
          ExpertModeView(
            onDone: { handleNavigation(.camera) },
            onOpenHelp: { openHelp(from: .settings) }
          )
        case .video:
          if AppFeatureFlags.videoEnabled {
            VideoWorkflowView(onNavigate: { handleNavigation($0) })
          } else {
            CameraView(onNavigate: { handleNavigation($0) })
          }
        case .panoramaTour:
          if AppFeatureFlags.panoramaEnabled {
            PanoramaTourView(onNavigate: { handleNavigation($0) })
          } else if AppFeatureFlags.floorplanEnabled {
            FloorplanWorkflowView(onNavigate: { handleNavigation($0) })
          } else {
            CameraView(onNavigate: { handleNavigation($0) })
          }
        case .floorplan:
          if AppFeatureFlags.floorplanEnabled {
            FloorplanWorkflowView(onNavigate: { handleNavigation($0) })
          } else {
            CameraView(onNavigate: { handleNavigation($0) })
          }
        case .help:
          HelpView(
            onBack: handleHelpBack,
            backButtonTitle: canUseLocalFeatures ? settings.localized("common.back") : settings.localized("help.backToLogin")
          )
        case .sunPlan:
          SunPlanView(onNavigate: { handleNavigation($0) })
        }
      }
    }
    .environmentObject(settings)
    .environmentObject(cameraModel)
    .environmentObject(uploadQueue)
    .environmentObject(authService)
    .environmentObject(companionTransfer)
    .environment(\.locale, Locale(identifier: settings.appLanguage.localeIdentifier))
    .onOpenURL { url in
      handleIncomingURL(url)
    }
    .onAppear {
      if !hasSeenFirstRunOnboarding {
        currentScreen = .onboarding
        return
      }
      if authService.isAuthenticated && !isDemoMode {
        currentScreen = pendingExternalWebConnectURL == nil ? .start : .gallery
        prepareAuthenticatedLaunchIfNeeded()
      } else {
        currentScreen = .start
      }
    }
    .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
      if isAuthenticated {
        isDemoMode = false
        currentScreen = pendingExternalWebConnectURL == nil ? .start : .gallery
        prepareAuthenticatedLaunchIfNeeded()
      } else {
        clearSelectedJobSelection()
        resetLaunchSetupState()
        currentScreen = hasSeenFirstRunOnboarding ? .start : .onboarding
      }
    }
    .onChange(of: currentScreen) { _, screen in
      let normalized = resolvedScreen(for: screen)
      if normalized != screen {
        currentScreen = normalized
        return
      }
      if screen == .camera {
        cameraModel.configureIfNeeded()
        cameraModel.startSession()
      } else {
        cameraModel.stopSession()
      }
    }
    .onChange(of: uploadQueue.isUploading) { _, isUploading in
      updateIdleTimerForUpload(isUploading: isUploading, scenePhase: scenePhase)
    }
    .onChange(of: scenePhase) { _, phase in
      updateIdleTimerForUpload(isUploading: uploadQueue.isUploading, scenePhase: phase)
      if phase != .active, uploadQueue.isUploading {
        uploadQueue.cancelActiveUpload(
          message: settings.localized("upload.foreground.paused")
        )
      }
    }
    .onDisappear {
      UIApplication.shared.isIdleTimerDisabled = false
    }
    .onChange(of: authService.availableJobs) { _, jobs in
      guard authService.isAuthenticated else { return }
      if let selectedId = settings.selectedJobId,
         let selectedJob = jobs.first(where: { $0.id == selectedId }) {
        settings.jobLabel = selectedJob.name
        settings.jobAddress = selectedJob.propertyAddress ?? ""
        return
      }
      if settings.selectedJobId != nil {
        let staleSelectedJobId = settings.selectedJobId
        clearSelectedJobSelection()
        settings.invalidateRecentJob(id: staleSelectedJobId)
        if currentScreen != .start, screenRequiresJobSelection(currentScreen) {
          pendingLaunchTarget = currentScreen
          beginLaunchMetadataFlow(resetJobSelection: false, forceFreshSelection: true)
        }
      }
      if let pendingLaunchTarget,
         screenRequiresJobSelection(pendingLaunchTarget),
         !hasActiveJobSelection,
         let singleJob = singleCustomerJobCandidate() {
        applySelectedJob(singleJob)
        isLaunchJobSheetPresented = false
        isLaunchRecentJobSheetPresented = false
        completePendingLaunchNavigation()
      }
    }
    .sheet(isPresented: $isLaunchRecentJobSheetPresented) {
      if let recentLaunchJob {
        JobResumeSheet(
          snapshot: recentLaunchJob,
          onContinue: continueWithRecentLaunchJob,
          onChooseDifferent: chooseDifferentLaunchJob
        )
      }
    }
    .sheet(isPresented: $isLaunchJobSheetPresented) {
      JobSelectionSheet(
        title: settings.localized("start.jobs.sheet.title"),
        subtitle: settings.localized("root.jobs.sheet.subtitle"),
        allowsClear: pendingLaunchTarget.map(screenRequiresJobSelection) != true,
        clearLabel: settings.localized("root.jobs.sheet.clear"),
        requiresSelection: pendingLaunchTarget.map(screenRequiresJobSelection) == true,
        onSelect: { job in
          applySelectedJob(job)
          completePendingLaunchNavigation()
        },
        onClear: {
          clearSelectedJobSelection()
          completePendingLaunchNavigation()
        }
      )
      .environmentObject(authService)
      .environmentObject(settings)
    }
  }

  private func updateIdleTimerForUpload(isUploading: Bool, scenePhase: ScenePhase) {
    UIApplication.shared.isIdleTimerDisabled = isUploading && scenePhase == .active
  }

  private func handleNavigation(_ target: AppScreen) {
    guard canUseLocalFeatures else { return }
    if target == .help {
      openHelp(from: currentScreen)
      return
    }
    let resolvedTarget = resolvedScreen(for: target)
    if authService.isAuthenticated,
       screenRequiresJobSelection(resolvedTarget),
       !hasActiveJobSelection {
      if let singleJob = singleCustomerJobCandidate() {
        applySelectedJob(singleJob)
        currentScreen = resolvedTarget
        return
      }
      pendingLaunchTarget = resolvedTarget
      beginLaunchMetadataFlow(resetJobSelection: false)
      return
    }
    currentScreen = resolvedTarget
  }

  private func openHelp(from source: AppScreen) {
    helpReturnScreen = source
    currentScreen = .help
  }

  private func handleHelpBack() {
    if canUseLocalFeatures {
      let fallback: AppScreen = .start
      let target = helpReturnScreen == .help ? fallback : helpReturnScreen
      currentScreen = resolvedScreen(for: target)
    } else {
      currentScreen = .splash
    }
  }

  private func handleIncomingURL(_ url: URL) {
    if looksLikeWebConnectURL(url) {
      pendingExternalWebConnectURL = url.absoluteString
      if canUseLocalFeatures {
        currentScreen = .gallery
      } else {
        currentScreen = .splash
      }
      return
    }
    guard let token = AuthService.parseMobileConnectToken(from: url.absoluteString) else {
      return
    }
    authService.setMobileConnectToken(token)
    isDemoMode = false
    currentScreen = .start
  }

  private func handleLogout() {
    isDemoMode = false
    clearSelectedJobSelection()
    resetLaunchSetupState()
    authService.logout()
    currentScreen = .splash
  }

  private func looksLikeWebConnectURL(_ url: URL) -> Bool {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return false
    }

    let sessionNames: Set<String> = ["session", "sessionid", "web_session_id", "websessionid", "id"]
    if let queryItems = components.queryItems {
      for item in queryItems {
        let name = item.name.lowercased()
        let value = item.value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if sessionNames.contains(name), !value.isEmpty {
          return true
        }
        if name == "token", value.hasPrefix("sess") {
          return true
        }
      }
    }

    let pathParts = components.path
      .split(separator: "/")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
      .filter { !$0.isEmpty }
    if pathParts.count >= 2,
       ["connect", "web-connect", "up"].contains(pathParts[0]),
       pathParts[1].hasPrefix("sess") {
      return true
    }
    if pathParts.count == 1, pathParts[0].hasPrefix("sess") {
      return true
    }

    return false
  }

  private func prepareAuthenticatedLaunchIfNeeded() {
    guard authService.isAuthenticated, !isDemoMode, !hasPreparedAuthenticatedLaunch else { return }
    hasPreparedAuthenticatedLaunch = true
    clearSelectedJobSelection()
    settings.selectedRoomId = RoomTaxonomy.defaultRoomId
    settings.selectedFloorId = FloorTaxonomy.defaultFloorId
    recentLaunchJob = nil
    pendingLaunchTarget = nil
    isLaunchRecentJobSheetPresented = false
    isLaunchJobSheetPresented = false
  }

  private func startDemoReviewMode() {
    isDemoMode = true
    authService.lastError = nil
    resetLaunchSetupState()
    applySelectedJob(Self.demoReviewJob)
    settings.selectedRoomId = RoomTaxonomy.defaultRoomId
    settings.selectedFloorId = Self.demoReviewFloorId
    currentScreen = .camera
    cameraModel.configureIfNeeded()
  }

  private func beginLaunchMetadataFlow(resetJobSelection: Bool, forceFreshSelection: Bool = false) {
    guard authService.isAuthenticated else { return }
    if resetJobSelection {
      clearSelectedJobSelection()
    }
    settings.selectedRoomId = RoomTaxonomy.defaultRoomId
    settings.selectedFloorId = FloorTaxonomy.defaultFloorId
    recentLaunchJob = nil

    if let singleJob = singleCustomerJobCandidate() {
      applySelectedJob(singleJob)
      completePendingLaunchNavigation()
      return
    }

    if !forceFreshSelection,
       let recentJob = settings.recentJobSnapshot(
         for: authService.recentJobScope,
         within: Self.recentJobResumeWindow
       ) {
      recentLaunchJob = recentJob
      DispatchQueue.main.async {
        isLaunchJobSheetPresented = false
        if !isLaunchRecentJobSheetPresented {
          isLaunchRecentJobSheetPresented = true
        }
      }
      return
    }

    DispatchQueue.main.async {
      isLaunchRecentJobSheetPresented = false
      if !isLaunchJobSheetPresented {
        isLaunchJobSheetPresented = true
      }
    }
  }

  private func applySelectedJob(_ job: JobInfo) {
    settings.setCurrentJob(job, userScope: authService.recentJobScope)
  }

  private func clearSelectedJobSelection() {
    settings.clearCurrentJobSelection()
  }

  private func resetLaunchSetupState() {
    hasPreparedAuthenticatedLaunch = false
    recentLaunchJob = nil
    pendingLaunchTarget = nil
    isLaunchRecentJobSheetPresented = false
    isLaunchJobSheetPresented = false
  }

  private func continueWithRecentLaunchJob() {
    guard let recentLaunchJob else { return }
    applySelectedJob(recentLaunchJob.job)
    isLaunchRecentJobSheetPresented = false
    completePendingLaunchNavigation()
  }

  private func chooseDifferentLaunchJob() {
    recentLaunchJob = nil
    isLaunchRecentJobSheetPresented = false
    DispatchQueue.main.async {
      if !isLaunchJobSheetPresented {
        isLaunchJobSheetPresented = true
      }
    }
  }

  private var hasActiveJobSelection: Bool {
    if let selectedJobId = settings.selectedJobId?.trimmingCharacters(in: .whitespacesAndNewlines),
       !selectedJobId.isEmpty {
      return true
    }
    return !settings.jobLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var canUseLocalFeatures: Bool {
    hasSeenFirstRunOnboarding || authService.isAuthenticated || isDemoMode
  }

  private func singleCustomerJobCandidate() -> JobInfo? {
    CaptureJobPolicy.singleRegularCaptureJob(from: authService.availableJobs)
  }

  private func completePendingLaunchNavigation() {
    guard let pendingLaunchTarget else { return }
    self.pendingLaunchTarget = nil
    currentScreen = resolvedScreen(for: pendingLaunchTarget)
  }

  private func screenRequiresJobSelection(_ screen: AppScreen) -> Bool {
    switch screen {
    case .video, .panoramaTour, .floorplan, .sunPlan:
      return true
    case .camera, .gallery, .splash, .onboarding, .start, .settings, .help:
      return false
    }
  }

  private func resolvedScreen(for target: AppScreen) -> AppScreen {
    switch target {
    case .video:
      return AppFeatureFlags.videoEnabled ? .video : .camera
    case .panoramaTour:
      return AppFeatureFlags.secondaryCaptureScreen
    case .floorplan:
      return AppFeatureFlags.floorplanEnabled ? .floorplan : .camera
    default:
      return target
    }
  }
}

enum AppScreen: Equatable {
  case onboarding
  case splash
  case start
  case camera
  case gallery
  case settings
  case video
  case panoramaTour
  case floorplan
  case help
  case sunPlan
}
