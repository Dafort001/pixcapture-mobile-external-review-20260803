import SwiftUI
import Combine
import UIKit

struct CameraView: View {
  private static let shutterDebounceInterval: TimeInterval = 0.35
  var onNavigate: (AppScreen) -> Void
  @EnvironmentObject var settings: AppSettings
  @EnvironmentObject var camera: CameraManager
  @EnvironmentObject var uploadQueue: UploadQueue
  @EnvironmentObject var authService: AuthService
  @AppStorage("pixcapture.supportToolsUnlocked") private var supportToolsUnlocked = false

  @State private var isRoomPickerPresented = false
  @State private var isUploadPresented = false
  @State private var isJobPickerPresented = false
  @State private var isCameraToolsPresented = false
  @State private var focusPosition: CGPoint = CGPoint(x: 0.5, y: 0.5)
  @State private var isFormatPickerPresented = false
  @AppStorage("pixcapture.camera.formatLabel") private var formatLabel: String = "3:2"
  @State private var selectedZoom: Double = 1.0
  @State private var isEvActive = false
  @State private var roomFlash = false
  @State private var showDebugGrid = false
  @State private var lastSeriesPhotoURLs: [URL] = []
  @State private var levelReady: Bool = false
  @State private var lastReadyHapticAt: Date = .distantPast
  @State private var stabilityHapticArmed: Bool = true
  @State private var guidanceHintOverride: String?
  @State private var guidanceAlignmentHapticArmed: Bool = true
  @State private var lastGuidanceAlignmentHapticAt: Date = .distantPast
  @State private var shutterLockoutUntil: Date = .distantPast
  @State private var singleShotFeedback: SingleShotCorrectabilityStatus?
  @State private var allowsUnassignedCapture = true
  @StateObject private var volumeShutter = VolumeShutterListener()
  @StateObject private var systemVolume = SystemVolumeController()
  private let showControls = true
  private let bottomBarHeight: CGFloat = 84
  private let rightRailWidth: CGFloat = 90
  private let debugGridColumns: Int = 6
  private let debugGridRows: Int = 12

  private var showsPhotoLibrarySaveControl: Bool {
    AppFeatureFlags.visiblePhotoLibrarySaveEnabled
      || (AppFeatureFlags.supportToolsUnlockEnabled && supportToolsUnlocked)
  }

  private var pendingCount: Int {
    uploadQueue.records.filter { $0.status == .pending }.count
  }

  var body: some View {
    GeometryReader { proxy in
      cameraScene(for: proxy)
    }
  }

  private func cameraScene(for proxy: GeometryProxy) -> AnyView {
    let isLandscape = proxy.size.width > proxy.size.height
    let safeInsets = proxy.safeAreaInsets
    let ratio = formatRatio(isLandscape: isLandscape, label: formatLabel)
    let basePreviewAspect: CGFloat = isLandscape ? (4.0 / 3.0) : (3.0 / 4.0)
    let fullSize = CGSize(
      width: max(proxy.size.width, 1),
      height: max(proxy.size.height, 1)
    )
    let contentSize = CGSize(
      width: max(fullSize.width, 1),
      height: max(fullSize.height - bottomBarHeight, 1)
    )
    let contentCenter = CGPoint(x: contentSize.width / 2, y: contentSize.height / 2 + 10.0)

    var scene = cameraSceneContent(
      contentSize: contentSize,
      contentCenter: contentCenter,
      ratio: ratio,
      basePreviewAspect: basePreviewAspect,
      fullSize: fullSize,
      isLandscape: isLandscape,
      safeInsets: safeInsets
    )

    scene = AnyView(scene.onChange(of: settings.exposureBiasEV) { _, newValue in
      camera.setExposureBias(newValue)
    })
    scene = AnyView(scene.onReceive(camera.$currentZoomFactor) { zoom in
      guard abs(selectedZoom - zoom) > 0.05 else { return }
      selectedZoom = zoom
    })
    scene = AnyView(scene.onChange(of: camera.isProRAWCaptureAvailable) { _, isAvailable in
      syncPhotoFormatAvailability(isAvailable: isAvailable, showFallbackNotice: true)
    })
    scene = AnyView(scene.onChange(of: camera.hasResolvedProRAWCaptureAvailability) { _, isResolved in
      guard isResolved else { return }
      syncPhotoFormatAvailability(
        isAvailable: camera.isProRAWCaptureAvailable,
        showFallbackNotice: true
      )
    })
    scene = AnyView(scene.onChange(of: settings.whiteBalanceLocked) { _, newValue in
      camera.setWhiteBalanceLocked(newValue)
      if newValue {
        camera.setWhiteBalanceKelvin(Float(settings.whiteBalanceKelvin))
      }
    })
    scene = AnyView(scene.onChange(of: settings.whiteBalanceKelvin) { _, newValue in
      guard settings.whiteBalanceLocked else { return }
      camera.setWhiteBalanceKelvin(Float(newValue))
    })
    scene = AnyView(scene.onChange(of: settings.focusLockEnabled) { _, newValue in
      camera.setFocusPoint(focusPosition, lockEnabled: newValue)
    })
    scene = AnyView(scene.onReceive(camera.$stabilityState.removeDuplicates()) { _ in
      updateLevelReadiness()
    })
    scene = AnyView(scene.onReceive(
      camera.$levelAngle
        .combineLatest(camera.$levelPitch)
        .throttle(for: .milliseconds(250), scheduler: RunLoop.main, latest: true)
    ) { _, _ in
      updateGuidanceAlignmentHaptic()
    })
    scene = AnyView(scene.onChange(of: settings.volumeShutterEnabled) { _, enabled in
      volumeShutter.volumeReset = { value in systemVolume.setVolume(value) }
      volumeShutter.keepVolumeStable = settings.volumeShutterKeepVolumeStable
      enabled ? volumeShutter.start() : volumeShutter.stop()
    })
    scene = AnyView(scene.onChange(of: settings.volumeShutterKeepVolumeStable) { _, enabled in
      volumeShutter.keepVolumeStable = enabled
    })
    scene = AnyView(scene.onReceive(volumeShutter.didTrigger) { _ in
      handleVolumeShutterTrigger()
    })
    scene = AnyView(scene.onReceive(camera.$lastSummary.compactMap { $0 }) { summary in
      let index = settings.nextSeriesIndex(
        jobId: settings.selectedJobId,
        jobLabel: settings.jobLabel,
        roomId: summary.roomId,
        floorId: summary.floorId
      )
      uploadQueue.upsert(
        summary,
        roomId: summary.roomId,
        floorId: summary.floorId,
        jobLabel: settings.jobLabel,
        jobId: settings.selectedJobId,
        seriesIndex: index
      )
      settings.touchCurrentJobActivity(userScope: authService.recentJobScope)
      lastSeriesPhotoURLs = summary.photos.map(\.fileURL)
      if summary.captureMode == .singleShot,
         let assessment = summary.singleShotAssessment {
        showSingleShotFeedback(assessment.status)
      }
      camera.lastSummary = nil
    })
    scene = AnyView(scene.sheet(isPresented: $isRoomPickerPresented) {
      RoomPickerView(
        selectedRoomId: $settings.selectedRoomId,
        selectedFloorId: $settings.selectedFloorId
      )
    })
    scene = AnyView(scene.sheet(isPresented: $isJobPickerPresented) {
      JobSelectionSheet(
        title: l10n("camera.jobPicker.title"),
        subtitle: l10n("camera.jobPicker.subtitle"),
        allowsClear: true,
        clearLabel: l10n("camera.jobPicker.clear"),
        requiresSelection: false,
        onSelect: { job in
          allowsUnassignedCapture = false
          applySelectedJob(job)
          camera.warningMessage = nil
        },
        onClear: {
          settings.clearCurrentJobSelection()
          allowsUnassignedCapture = true
          camera.warningMessage = nil
        }
      )
      .environmentObject(authService)
      .environmentObject(settings)
    })
    scene = AnyView(scene.onChange(of: settings.selectedRoomId) { _, newValue in
      resetExposureBiasForLocationChange()
      camera.setQualityProfile(roomId: newValue)
      if !camera.isCapturing {
        camera.warningMessage = nil
      }
      clearGuidanceOverride()
    })
    scene = AnyView(scene.onChange(of: settings.selectedFloorId) { _, _ in
      resetExposureBiasForLocationChange()
      if !camera.isCapturing {
        camera.warningMessage = nil
      }
    })
    scene = AnyView(scene.sheet(isPresented: $isUploadPresented) {
      UploadQueueView()
    })
    scene = AnyView(scene.sheet(isPresented: $isCameraToolsPresented) {
      cameraToolsSheet()
        .presentationDetents([.height(560), .large])
        .presentationDragIndicator(.visible)
    })
    scene = AnyView(scene.confirmationDialog(
      l10n("camera.aspect.title"),
      isPresented: $isFormatPickerPresented,
      titleVisibility: .visible
    ) {
      Button("3:2") { formatLabel = "3:2" }
      Button("4:3") { formatLabel = "4:3" }
      Button("16:9") { formatLabel = "16:9" }
      Button(l10n("common.cancel"), role: .cancel) {}
    })
    scene = AnyView(scene.onAppear {
      camera.setQualityProfile(roomId: settings.selectedRoomId)
      focusPosition = camera.focusPoint
      restoreCameraZoomForCurrentFormat()
      syncPhotoFormatAvailability(isAvailable: camera.isProRAWCaptureAvailable, showFallbackNotice: false)
      if settings.whiteBalanceLocked {
        camera.setWhiteBalanceKelvin(Float(settings.whiteBalanceKelvin))
      }
      camera.setLevelMonitoringEnabled(settings.levelEnabled)
      updateLevelReadiness(forceReset: true)
      if resolvedCaptureJob() != nil {
        settings.touchCurrentJobActivity(userScope: authService.recentJobScope)
      }
      if settings.volumeShutterEnabled {
        volumeShutter.volumeReset = { value in systemVolume.setVolume(value) }
        volumeShutter.keepVolumeStable = settings.volumeShutterKeepVolumeStable
        volumeShutter.start()
      }
    })
    scene = AnyView(scene.onDisappear {
      volumeShutter.stop()
    })

    return scene
  }

  private func cameraSceneContent(
    contentSize: CGSize,
    contentCenter: CGPoint,
    ratio: CGFloat,
    basePreviewAspect: CGFloat,
    fullSize: CGSize,
    isLandscape: Bool,
    safeInsets: EdgeInsets
  ) -> AnyView {
    return AnyView(
      ZStack {
        cameraBackdrop(
          contentSize: contentSize,
          contentCenter: contentCenter,
          ratio: ratio,
          basePreviewAspect: basePreviewAspect,
          fullSize: fullSize,
          safeInsets: safeInsets
        )
        if showControls {
          cameraControlsLayer(
            fullSize: fullSize,
            isLandscape: isLandscape,
            safeInsets: safeInsets
          )
        }
        if showDebugGrid {
          DebugGridOverlay(columns: debugGridColumns, rows: debugGridRows)
            .frame(width: fullSize.width, height: fullSize.height)
            .position(x: fullSize.width / 2, y: fullSize.height / 2)
            .ignoresSafeArea()
        }
      }
    )
  }

  private func cameraBackdrop(
    contentSize: CGSize,
    contentCenter: CGPoint,
    ratio: CGFloat,
    basePreviewAspect: CGFloat,
    fullSize: CGSize,
    safeInsets: EdgeInsets
  ) -> AnyView {
    return AnyView(
      ZStack {
        Color.black.ignoresSafeArea()
        SystemVolumeView(controller: systemVolume)
          .frame(width: 1, height: 1)
          .opacity(0.01)
          .allowsHitTesting(false)
        cameraLayer(containerSize: contentSize, aspectRatio: ratio)
          .frame(width: contentSize.width, height: contentSize.height)
          .position(contentCenter)
        if settings.gridEnabled {
          AspectGridOverlay(baseAspectRatio: basePreviewAspect, targetAspectRatio: ratio)
            .frame(width: contentSize.width, height: contentSize.height)
            .position(contentCenter)
        }
        AspectMaskOverlay(baseAspectRatio: basePreviewAspect, targetAspectRatio: ratio)
          .frame(width: contentSize.width, height: contentSize.height)
          .position(contentCenter)
        overlaysLayer(
          containerSize: contentSize,
          aspectRatio: ratio,
          fullSize: fullSize,
          safeInsets: safeInsets
        )
          .frame(width: contentSize.width, height: contentSize.height)
          .position(contentCenter)
      }
    )
  }

  private func cameraControlsLayer(
    fullSize: CGSize,
    isLandscape: Bool,
    safeInsets: EdgeInsets
  ) -> AnyView {
    return AnyView(
      ZStack {
        let lowerControlLift: CGFloat = 5.0
        zoomControls(
          totalSize: fullSize,
          isLandscape: isLandscape,
          lowerControlLift: lowerControlLift
        )
        bracketLabel()
          .position(
            x: (CGFloat(4) + 0.5) / CGFloat(debugGridColumns) * fullSize.width,
            y: (CGFloat(10) + 0.5) / CGFloat(debugGridRows) * fullSize.height - lowerControlLift
          )
        captureProgressBadge()
          .position(
            x: (CGFloat(3) + 0.5) / CGFloat(debugGridColumns) * fullSize.width,
            y: (CGFloat(8) + 0.5) / CGFloat(debugGridRows) * fullSize.height
          )
        topBarControls(
          containerWidth: fullSize.width,
          isLandscape: isLandscape,
          safeInsets: safeInsets
        )
        .frame(width: fullSize.width)
        .position(
          x: fullSize.width / 2,
          y: CGFloat(1) / CGFloat(debugGridRows) * fullSize.height
        )
        qualityIndicatorDots(fullSize: fullSize, safeInsets: safeInsets)
        captureControls(totalSize: fullSize)
        exposureSliderView(in: fullSize)
        singleShotFeedbackToast(totalSize: fullSize, isLandscape: isLandscape, safeInsets: safeInsets)
        guidanceHintLine(totalSize: fullSize, isLandscape: isLandscape, safeInsets: safeInsets)
        warningBanner()
        levelIndicator(safeInsets: safeInsets)
        BottomNavBar(selected: .camera) { tab in
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
      }
    )
  }

  private func capture() {
    let now = Date()
    guard !camera.isCapturing else { return }
    guard now >= shutterLockoutUntil else { return }
    guard !isRoomPickerPresented && !isUploadPresented && !isFormatPickerPresented && !isCameraToolsPresented else { return }
    guard let resolvedJob = resolvedCaptureJob() else {
      camera.warningMessage = "Bitte zuerst einen Job waehlen."
      isJobPickerPresented = true
      return
    }
    if !resolvedJob.id.isEmpty, resolvedJob.id != settings.selectedJobId {
      applySelectedJob(resolvedJob)
    }
    settings.touchCurrentJobActivity(userScope: authService.recentJobScope)
    if settings.photoCaptureMode == .standardBracket, settings.bracketCount > 1 {
      showTemporaryGuidanceHint("Halte ruhig: \(settings.bracketCount) Aufnahmen für HDR")
    }
    let singleShotAssessment = makeSingleShotAssessment(triggeredAt: now)
    let captureDelaySeconds = settings.photoCaptureMode == .singleShot && normalizedTimerSeconds == 0
      ? 0
      : settings.captureDelaySeconds
    let config = CaptureSeriesConfig(
      bracketCount: settings.photoCaptureMode == .singleShot ? 1 : settings.bracketCount,
      stepEV: settings.exposureStepEV,
      maxExposureSeconds: settings.maxExposureSeconds,
      exposureBiasEV: settings.exposureBiasEV,
      bracketMeteringMode: settings.bracketMeteringMode,
      captureDelaySeconds: captureDelaySeconds,
      photoFormat: settings.photoFormat,
      isoOverride: Float(settings.manualISOValue),
      baseShutterSeconds: settings.manualShutterSeconds,
      roomId: settings.selectedRoomId,
      floorId: settings.selectedFloorId,
      outputAspectRatio: Double(captureOutputAspectRatio()),
      captureMode: settings.photoCaptureMode,
      singleShotAssessment: singleShotAssessment
    )
    shutterLockoutUntil = now.addingTimeInterval(Self.shutterDebounceInterval)
    roomFlash = true
      
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
      roomFlash = false
    }
    camera.captureSeries(config: config)
  }

  private func makeSingleShotAssessment(triggeredAt: Date) -> SingleShotCaptureAssessment? {
    guard settings.photoCaptureMode == .singleShot else { return nil }
    let transform = KeystoneOrientationMapper.transform(
      rollRadians: camera.levelAngle,
      pitchRadians: camera.levelPitch,
      viewportOrientation: KeystoneViewportOrientation.current()
    )
    return SingleShotCaptureAssessment(
      triggeredAt: triggeredAt,
      rollDegrees: transform.normalizedRollForViewport,
      pitchDegrees: transform.normalizedPitchForViewport,
      stabilityScore: camera.stabilityScore.isFinite ? camera.stabilityScore : nil,
      stabilityState: camera.stabilityState.rawValue
    )
  }

  private func showSingleShotFeedback(_ status: SingleShotCorrectabilityStatus) {
    singleShotFeedback = status
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
      if singleShotFeedback == status {
        singleShotFeedback = nil
      }
    }
  }

  private func resetExposureBiasForLocationChange() {
    guard settings.exposureBiasEV != 0 else { return }
    settings.resetExposureBiasToNeutral()
  }

  private func resolvedCaptureJob() -> JobInfo? {
    if let selectedJobId = settings.selectedJobId?.trimmingCharacters(in: .whitespacesAndNewlines),
       !selectedJobId.isEmpty {
      if let selectedJob = authService.availableJobs.first(where: { $0.id == selectedJobId }) {
        return CaptureJobPolicy.allowsNewCapture(job: selectedJob) ? selectedJob : nil
      }
      let fallbackName = settings.jobLabel.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !CaptureJobPolicy.isMobileInboxLabel(fallbackName) else { return nil }
      let fallbackAddress = settings.jobAddress.trimmingCharacters(in: .whitespacesAndNewlines)
      return JobInfo(
        id: selectedJobId,
        name: fallbackName.isEmpty ? "Job" : fallbackName,
        propertyAddress: fallbackAddress.isEmpty ? nil : fallbackAddress
      )
    }

    let fallbackLabel = settings.jobLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    if allowsUnassignedCapture || fallbackLabel.compare(
      CaptureJobPolicy.unassignedJobLabel,
      options: [.caseInsensitive, .diacriticInsensitive]
    ) == .orderedSame {
      return JobInfo(
        id: "",
        name: CaptureJobPolicy.unassignedJobLabel,
        propertyAddress: nil
      )
    }

    guard !fallbackLabel.isEmpty else { return nil }
    guard !CaptureJobPolicy.isMobileInboxLabel(fallbackLabel) else { return nil }
    return authService.availableJobs.first {
      CaptureJobPolicy.allowsNewCapture(job: $0)
        && $0.name.compare(fallbackLabel, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
  }

  private func applySelectedJob(_ job: JobInfo) {
    settings.setCurrentJob(job, userScope: authService.recentJobScope)
  }

  private func handleVolumeShutterTrigger() {
    guard settings.volumeShutterEnabled else { return }
    capture()
  }

  private func syncPhotoFormatAvailability(isAvailable: Bool, showFallbackNotice: Bool) {
    guard camera.hasResolvedProRAWCaptureAvailability else { return }
    switch settings.syncPhotoFormatAvailability(isProRAWAvailable: isAvailable) {
    case .fellBackToJPEG:
      guard showFallbackNotice else { return }
      camera.warningMessage = proRAWFallbackWarningMessage()
    case .restored:
      if isProRAWFallbackWarning(camera.warningMessage) {
        camera.warningMessage = nil
      }
    case .unchanged:
      break
    }
  }

  private func restoreCameraZoomForCurrentFormat() {
    let savedZoom = settings.lastZoomPreset
    selectedZoom = savedZoom
    setCameraZoom(savedZoom)
  }

  private func proRAWFallbackWarningMessage() -> String {
    return l10n("warning.proRawUnavailable")
  }

  private func isProRAWFallbackWarning(_ message: String?) -> Bool {
    message == l10n("warning.proRawUnavailable")
      || message == l10n("warning.proRawZoomFallback")
  }

  @ViewBuilder
  private func exposureSliderView(in size: CGSize) -> some View {
    let anchorX = (CGFloat(5) + 0.5) / CGFloat(debugGridColumns) * size.width
    let rowHeight = size.height / CGFloat(debugGridRows)
    let anchorY = (CGFloat(8) + 0.5) / CGFloat(debugGridRows) * size.height - (rowHeight * 2)

    ExposureSliderView(value: $settings.exposureBiasEV, range: camera.exposureBiasRange, orientation: .vertical)
      .position(x: anchorX, y: anchorY)
  }

  private func resolveSliderPosition(isLandscape: Bool) -> AppSettings.ExposureSliderPosition {
    if settings.exposureSliderPosition != .auto {
      return settings.exposureSliderPosition
    }
    return isLandscape ? .top : .left
  }

  @ViewBuilder
  private func cameraLayer(containerSize: CGSize, aspectRatio: CGFloat) -> some View {
    let activeRect = centeredRect(in: containerSize, aspectRatio: aspectRatio)
    CameraPreviewView(session: camera.session)
      .gesture(
        DragGesture(minimumDistance: 0)
          .onEnded { value in
            guard settings.focusLockEnabled else { return }
            let x = (value.location.x - activeRect.minX) / activeRect.width
            let y = (value.location.y - activeRect.minY) / activeRect.height
            let normalized = clampPoint(CGPoint(x: x, y: y))
            focusPosition = normalized
            camera.setFocusPoint(normalized, lockEnabled: true)
          }
      )
  }

  @ViewBuilder
  private func overlaysLayer(
    containerSize: CGSize,
    aspectRatio: CGFloat,
    fullSize: CGSize,
    safeInsets: EdgeInsets
  ) -> some View {
    let activeRect = centeredRect(in: containerSize, aspectRatio: aspectRatio)

    if AppFeatureFlags.cameraGuidanceSkeletonsEnabled {
      CameraGuidanceSkeletonOverlay(skeleton: currentGuidanceRule.skeleton)
        .frame(width: activeRect.width, height: activeRect.height)
        .position(x: activeRect.midX, y: activeRect.midY)
        .allowsHitTesting(false)
    }

    if settings.levelEnabled {
      if settings.photoCaptureMode == .singleShot {
        KeystoneAlignmentGuide(
          roll: camera.levelAngle,
          pitch: camera.levelPitch,
          viewportOrientation: KeystoneViewportOrientation.current(viewportSize: activeRect.size)
        )
        .frame(width: activeRect.width, height: activeRect.height, alignment: .center)
        .position(x: activeRect.midX, y: activeRect.midY)
        .allowsHitTesting(false)
        LevelOverlayView(roll: camera.levelAngle, pitch: camera.levelPitch)
          .frame(width: activeRect.width, height: activeRect.height, alignment: .center)
          .position(x: activeRect.midX, y: activeRect.midY)
          .allowsHitTesting(false)
      } else {
        LevelOverlayView(roll: camera.levelAngle, pitch: camera.levelPitch)
          .frame(width: containerSize.width, height: containerSize.height, alignment: .center)
          .position(x: containerSize.width / 2, y: containerSize.height / 2)
      }
    }

    if settings.histogramEnabled, camera.highlightWarningActive {
      HighlightWarningOverlayView(mask: camera.highlightWarningMask)
        .frame(width: activeRect.width, height: activeRect.height)
        .position(x: activeRect.midX, y: activeRect.midY)
    }

    if settings.histogramEnabled {
      DraggableOverlay(
        normalizedPosition: $settings.histogramOverlayPosition,
        overlaySize: CGSize(width: 42, height: 92),
        safeInsets: safeInsets
      ) {
        HistogramOverlayView(
          bins: camera.histogramBins,
          showHighlightWarning: camera.highlightWarningActive
        )
          .frame(width: 92, height: 42)
          .rotationEffect(.degrees(90))
          .frame(width: 42, height: 92)
      }
      .frame(width: containerSize.width, height: containerSize.height)
    }

    let clamped = clampPoint(focusPosition)
    if settings.focusLockEnabled {
      FocusReticleView(color: Color.green.opacity(0.9))
        .position(x: activeRect.minX + clamped.x * activeRect.width,
                  y: activeRect.minY + clamped.y * activeRect.height)
        .gesture(
          DragGesture()
            .onChanged { value in
              let x = (value.location.x - activeRect.minX) / activeRect.width
              let y = (value.location.y - activeRect.minY) / activeRect.height
              let normalized = clampPoint(CGPoint(x: x, y: y))
              focusPosition = normalized
              camera.setFocusPoint(normalized, lockEnabled: settings.focusLockEnabled)
            }
        )
    }

  }

  @ViewBuilder
  private func topBarControls(
    containerWidth: CGFloat,
    isLandscape: Bool,
    safeInsets: EdgeInsets
  ) -> some View {
    let _ = isLandscape
    let topBarWidth = min(containerWidth - max(safeInsets.leading + safeInsets.trailing + 28, 40), 382)
    HStack(spacing: 14) {
      jobPickerButton()
        .frame(maxWidth: .infinity)
      cameraToolsButton()
        .frame(width: 48)
      roomPickerButton()
        .frame(maxWidth: .infinity)
    }
    .frame(width: topBarWidth)
    .frame(width: containerWidth, alignment: .center)
  }

  private func jobPickerButton() -> some View {
    let hasJob = !settings.jobLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let displayLabel = hasJob
      ? l10nFormat("camera.job.active.format", settings.jobLabel)
      : CaptureJobPolicy.unassignedJobLabel
    return Button(action: { isJobPickerPresented = true }) {
      HStack(spacing: 6) {
        Image(systemName: "briefcase.fill")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.white.opacity(0.92))
        Text(displayLabel)
          .font(.system(size: 11, weight: .semibold))
          .lineLimit(1)
          .truncationMode(.tail)
      }
      .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
      .padding(.horizontal, 9)
      .padding(.vertical, 4)
      .background(Color.black.opacity(0.48))
      .overlay(
        RoundedRectangle(cornerRadius: 16)
          .stroke(
            hasJob ? Color.white.opacity(0.28) : Color.white.opacity(0.18),
            lineWidth: 1
          )
      )
      .clipShape(Capsule())
    }
    .foregroundStyle(.white)
    .accessibilityLabel(l10n("camera.job.accessibility"))
  }

  private func roomPickerButton() -> some View {
    let roomLabel = RoomTaxonomy.room(id: settings.selectedRoomId).displayName(language: settings.appLanguage)
    let floorLabel = FloorTaxonomy.floor(id: settings.selectedFloorId).shortDisplayName(language: settings.appLanguage)
    let isDefaultLocation = settings.selectedRoomId == RoomTaxonomy.defaultRoomId
      && settings.selectedFloorId == FloorTaxonomy.defaultFloorId
    let isMissingFloorForRoom = settings.selectedRoomId != RoomTaxonomy.defaultRoomId
      && settings.selectedFloorId == FloorTaxonomy.defaultFloorId
    let locationLabel: String
    if isDefaultLocation {
      locationLabel = l10n("camera.room.none")
    } else if isMissingFloorForRoom {
      locationLabel = l10nFormat("camera.room.floorMissing.format", roomLabel)
    } else {
      locationLabel = "\(roomLabel) · \(floorLabel)"
    }

    return Button(action: { isRoomPickerPresented = true }) {
      HStack(spacing: 6) {
        Image(systemName: isDefaultLocation ? "tag" : "mappin.and.ellipse")
          .font(.system(size: 10, weight: .semibold))
        Text(locationLabel)
          .font(.system(size: 11, weight: .semibold))
          .lineLimit(1)
          .truncationMode(.tail)
      }
      .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
      .padding(.horizontal, 9)
      .padding(.vertical, 4)
      .background(roomFlash ? AppTheme.primary.opacity(0.24) : Color.black.opacity(0.42))
      .overlay(
        RoundedRectangle(cornerRadius: 16)
          .stroke(isDefaultLocation ? Color.white.opacity(0.18) : AppTheme.primary.opacity(0.45), lineWidth: 1)
      )
      .clipShape(Capsule())
    }
    .foregroundStyle(isDefaultLocation ? Color.white.opacity(0.72) : .white)
    .accessibilityLabel(l10n("camera.room.accessibility"))
    .accessibilityValue("\(roomLabel), \(floorLabel)")
  }

  private func cameraToolsButton() -> some View {
    Button(action: { isCameraToolsPresented = true }) {
      ZStack(alignment: .topTrailing) {
        Image(systemName: "slider.horizontal.3")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: 38, height: 30)
          .background(AppTheme.primary.opacity(0.82))
          .overlay(
            RoundedRectangle(cornerRadius: 10)
              .stroke(Color.white.opacity(0.22), lineWidth: 1)
          )
          .clipShape(RoundedRectangle(cornerRadius: 10))
          .frame(width: 44, height: 44)

        if cameraToolsHaveActiveOverrides {
          Circle()
            .fill(Color.yellow)
            .frame(width: 7, height: 7)
            .offset(x: 2, y: -2)
        }
      }
    }
    .accessibilityLabel(l10n("camera.tools.accessibility"))
  }

  private var cameraToolsHaveActiveOverrides: Bool {
    settings.captureDelaySeconds > 0
      || settings.gridEnabled
      || settings.levelEnabled
      || formatLabel != "3:2"
      || settings.bracketCount != 5
      || settings.photoCaptureMode == .singleShot
  }

  private func cameraToolsSheet() -> some View {
    VStack(spacing: 0) {
      HStack(alignment: .center) {
        Text(l10n("camera.tools.title"))
          .font(.system(size: 28, weight: .bold))
          .foregroundStyle(.primary)
        Spacer()
        Button {
          isCameraToolsPresented = false
        } label: {
          PixDonePill(title: l10n("common.done"))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(l10n("common.done"))
      }
      .padding(.horizontal, 20)
      .padding(.top, 20)
      .padding(.bottom, 12)

      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 8) {
          Text(l10n("camera.aspect.title"))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
          HStack(spacing: 8) {
            toolsChoiceButton("3:2", isSelected: formatLabel == "3:2") { formatLabel = "3:2" }
            toolsChoiceButton("4:3", isSelected: formatLabel == "4:3") { formatLabel = "4:3" }
            toolsChoiceButton("16:9", isSelected: formatLabel == "16:9") { formatLabel = "16:9" }
          }
        }

        VStack(alignment: .leading, spacing: 8) {
          Text(l10n("camera.tools.timer"))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
          HStack(spacing: 8) {
            toolsChoiceButton(l10n("camera.tools.timer.off"), isSelected: normalizedTimerSeconds == 0) {
              settings.captureDelaySeconds = 0
            }
            toolsChoiceButton("3s", isSelected: normalizedTimerSeconds == 3) {
              settings.captureDelaySeconds = 3
            }
            toolsChoiceButton("10s", isSelected: normalizedTimerSeconds == 10) {
              settings.captureDelaySeconds = 10
            }
          }
        }

        VStack(alignment: .leading, spacing: 8) {
          Text("Aufnahmemodus")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
          HStack(spacing: 8) {
            toolsChoiceButton("Belichtungsreihe", isSelected: settings.photoCaptureMode == .standardBracket) {
              settings.photoCaptureMode = .standardBracket
            }
            toolsChoiceButton("Einzelbild", isSelected: settings.photoCaptureMode == .singleShot) {
              settings.photoCaptureMode = .singleShot
            }
          }
          Text(settings.photoCaptureMode == .singleShot ? "Schnell. Gut bei hellem Raum und stabiler Haltung." : bracketLabelText)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
        }

        VStack(alignment: .leading, spacing: 8) {
          Text(l10n("camera.tools.series"))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
          HStack(spacing: 8) {
            ForEach([1, 3, 5, 7], id: \.self) { count in
              toolsChoiceButton("\(count)x", isSelected: settings.bracketCount == count) {
                settings.bracketCount = count
                settings.photoCaptureMode = .standardBracket
              }
            }
          }
          Text(bracketLabelText)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
        }

        VStack(spacing: 10) {
          Toggle(isOn: $settings.gridEnabled) {
            Label(l10n("camera.tools.grid"), systemImage: "grid")
          }

          Toggle(isOn: levelBinding) {
            Label(l10n("camera.tools.level"), systemImage: "scope")
          }

          Toggle(isOn: focusLockBinding) {
            Label(settings.focusLockEnabled ? l10n("camera.tools.focus.locked") : l10n("camera.tools.focus.auto"), systemImage: "scope")
          }
        }
        .font(.system(size: 14, weight: .semibold))
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

        HStack(spacing: 12) {
          if showsPhotoLibrarySaveControl {
            saveToPhotosButton()
          }
          Spacer(minLength: 0)
        }

        Spacer(minLength: 0)
        }
      }
      .padding(.horizontal, 20)
      .padding(.bottom, 22)
    }
    .background(Color(.systemBackground))
  }

  private func toolsChoiceButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(isSelected ? AppTheme.primary : Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(isSelected ? AppTheme.primary : Color(.separator).opacity(0.35), lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
  }

  private var levelBinding: Binding<Bool> {
    Binding(
      get: { settings.levelEnabled },
      set: { newValue in
        settings.levelEnabled = newValue
        camera.setLevelMonitoringEnabled(newValue)
        updateLevelReadiness(forceReset: !newValue)
      }
    )
  }

  private var normalizedTimerSeconds: Int {
    let seconds = settings.captureDelaySeconds
    if seconds >= 8 { return 10 }
    if seconds >= 1 { return 3 }
    return 0
  }

  private var focusLockBinding: Binding<Bool> {
    Binding(
      get: { settings.focusLockEnabled },
      set: { newValue in
        if newValue {
          focusPosition = CGPoint(x: 0.5, y: 0.5)
        }
        settings.focusLockEnabled = newValue
      }
    )
  }

  private func toolValueButton(
    icon: String,
    title: String,
    value: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: icon)
          .font(.system(size: 14, weight: .semibold))
          .frame(width: 24)
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
          Text(value)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 11)
      .frame(maxWidth: .infinity)
      .background(Color(.secondarySystemBackground))
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  private func toolToggleButton(
    icon: String,
    title: String,
    isActive: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: icon)
          .font(.system(size: 14, weight: .semibold))
          .frame(width: 24)
        Text(title)
          .font(.system(size: 13, weight: .semibold))
        Spacer(minLength: 0)
        Circle()
          .fill(isActive ? AppTheme.primary : Color.secondary.opacity(0.35))
          .frame(width: 10, height: 10)
      }
      .foregroundStyle(isActive ? AppTheme.primary : Color.primary)
      .padding(.horizontal, 12)
      .padding(.vertical, 13)
      .frame(maxWidth: .infinity)
      .background(Color(.secondarySystemBackground))
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  private func toggleFocusLock() {
    let nextValue = !settings.focusLockEnabled
    if nextValue {
      focusPosition = CGPoint(x: 0.5, y: 0.5)
    }
    settings.focusLockEnabled = nextValue
  }

  private func formatButton() -> some View {
    Button(action: { isFormatPickerPresented = true }) {
      Text("\(activePhotoFormatLabel) · \(formatLabel)")
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.1))
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    .foregroundStyle(.white)
  }

  private var activePhotoFormatLabel: String {
    switch settings.photoFormat {
    case .proRaw:
      return "RAW/DNG"
    case .heif:
      return "JPEG"
    case .jpeg:
      return "JPEG"
    }
  }

  private func delayButton() -> some View {
    Button(action: { cycleCaptureDelay() }) {
      Text(delayLabel())
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 32, height: 32)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .frame(width: 44, height: 44)
    }
    .accessibilityLabel("Timer")
    .accessibilityValue(delayLabel())
  }

  private func gridButton() -> some View {
    Button(action: { settings.gridEnabled.toggle() }) {
      Image(systemName: "grid")
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(settings.gridEnabled ? Color.white : Color.white.opacity(0.6))
        .frame(width: 32, height: 32)
        .background(settings.gridEnabled ? AppTheme.primary.opacity(0.3) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .frame(width: 44, height: 44)
    }
    .accessibilityLabel("Raster")
    .accessibilityValue(settings.gridEnabled ? "Ein" : "Aus")
  }

  private func levelButton() -> some View {
    Button(action: {
      settings.levelEnabled.toggle()
      camera.setLevelMonitoringEnabled(settings.levelEnabled)
      updateLevelReadiness(forceReset: !settings.levelEnabled)
    }) {
      Image(systemName: "scope")
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(settings.levelEnabled ? Color.white : Color.white.opacity(0.6))
        .frame(width: 32, height: 32)
        .background(settings.levelEnabled ? AppTheme.primary.opacity(0.3) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .frame(width: 44, height: 44)
    }
    .accessibilityLabel("Wasserwaage")
    .accessibilityValue(settings.levelEnabled ? "Ein" : "Aus")
  }

  private func saveToPhotosButton() -> some View {
    let enabled = !lastSeriesPhotoURLs.isEmpty && !camera.isCapturing
    return Button(action: saveLastSeriesToPhotos) {
      Image(systemName: "square.and.arrow.down")
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(enabled ? Color.white : Color.white.opacity(0.4))
        .frame(width: 32, height: 32)
        .background(Color.white.opacity(enabled ? 0.12 : 0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .stroke(Color.white.opacity(enabled ? 0.2 : 0.08), lineWidth: 1)
        )
        .frame(width: 44, height: 44)
    }
    .disabled(!enabled)
    .accessibilityLabel(LocalizedStringKey("save.photos.accessibility"))
  }

  private func saveLastSeriesToPhotos() {
    guard !lastSeriesPhotoURLs.isEmpty else { return }
    Task {
      let saved = await camera.saveSeriesToPhotoLibrary(urls: lastSeriesPhotoURLs)
      guard saved else { return }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        camera.warningMessage = NSLocalizedString("save.photos.success", comment: "")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
          if camera.warningMessage == NSLocalizedString("save.photos.success", comment: "") {
            camera.warningMessage = nil
          }
        }
      }
    }
  }

  private func uploadStatusButton(color: Color, label: String) -> some View {
    Button(action: { isUploadPresented = true }) {
      HStack(spacing: 4) {
        Circle()
          .fill(color.opacity(0.9))
          .frame(width: 6, height: 6)
        Text(label)
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(color)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .background(AppTheme.primary.opacity(0.25))
      .clipShape(RoundedRectangle(cornerRadius: 6))
    }
  }

  private func qualityStatusChip(color: Color, label: String) -> some View {
    HStack(spacing: 4) {
      Circle()
        .fill(color.opacity(0.9))
        .frame(width: 6, height: 6)
      Text(label)
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(color)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .background(AppTheme.primary.opacity(0.25))
    .clipShape(RoundedRectangle(cornerRadius: 6))
  }

  private func qualityIndicatorDots(fullSize: CGSize, safeInsets: EdgeInsets) -> some View {
    let topBarY = CGFloat(1) / CGFloat(debugGridRows) * fullSize.height
    let blackAreaY = min(max(safeInsets.top + 42, 54), max(topBarY - 56, 44))

    return HStack(spacing: 48) {
      qualityIndicatorLabel(
        color: color(for: camera.exposureQualityState),
        text: l10n("camera.quality.exposure"),
        accessibilityLabel: "\(l10n("camera.quality.exposure")) \(label(for: camera.exposureQualityState))"
      )
      qualityIndicatorLabel(
        color: color(for: camera.sharpnessQualityState),
        text: l10n("camera.quality.sharpness"),
        accessibilityLabel: "\(l10n("camera.quality.sharpness")) \(label(for: camera.sharpnessQualityState))"
      )
    }
    .position(
      x: fullSize.width / 2,
      y: blackAreaY
    )
    .allowsHitTesting(false)
  }

  private func qualityIndicatorLabel(color: Color, text: String, accessibilityLabel: String) -> some View {
    HStack(spacing: 5) {
      Circle()
        .fill(color.opacity(0.95))
        .frame(width: 7, height: 7)
        .overlay(
          Circle()
            .stroke(Color.black.opacity(0.25), lineWidth: 1)
        )
      Text(text)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(color.opacity(0.95))
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background(Color.black.opacity(0.18))
    .clipShape(Capsule())
      .accessibilityLabel(accessibilityLabel)
  }

  private func label(for state: LiveQualityState) -> String {
    switch state {
    case .good:
      return "OK"
    case .warning:
      return "!"
    case .bad:
      return "X"
    }
  }

  private func color(for state: LiveQualityState) -> Color {
    switch state {
    case .good:
      return .green
    case .warning:
      return .yellow
    case .bad:
      return .red
    }
  }

  private var currentGuidanceRule: CameraGuidanceRule {
    CameraGuidanceCatalog.rule(forRoomId: settings.selectedRoomId)
  }

  private var guidanceHintText: String {
    if let progress = camera.captureProgress,
       progress.total > 1 {
      return "Belichtungsreihe aktiv - nicht bewegen"
    }

    if camera.sharpnessQualityState == .bad, !camera.isCapturing {
      return "Unscharf - erneut aufnehmen?"
    }

    if AppFeatureFlags.cameraGuidanceHintsEnabled,
       !camera.isCapturing,
       maxGuidanceTiltDegrees > CameraGuidanceCatalog.tiltThresholdDegrees {
      return "Vertikalen ausrichten"
    }

    if let guidanceHintOverride {
      return guidanceHintOverride
    }

    return currentGuidanceRule.defaultHint
  }

  private var maxGuidanceTiltDegrees: Double {
    let roll = normalizedGuidanceAngle(camera.levelAngle) * 180 / .pi
    let pitch = normalizedGuidanceAngle(camera.levelPitch) * 180 / .pi
    return max(abs(roll), abs(pitch))
  }

  private func normalizedGuidanceDegrees(_ angle: Double) -> Double {
    normalizedGuidanceAngle(angle) * 180 / .pi
  }

  private func normalizedGuidanceAngle(_ angle: Double) -> Double {
    var normalized = angle
    if normalized > .pi / 2 {
      normalized = .pi - normalized
    } else if normalized < -.pi / 2 {
      normalized = -.pi - normalized
    }
    return normalized
  }

  private func showTemporaryGuidanceHint(_ hint: String) {
    guard AppFeatureFlags.cameraGuidanceHintsEnabled else { return }
    guidanceHintOverride = hint
    DispatchQueue.main.asyncAfter(deadline: .now() + CameraGuidanceCatalog.hintTimeoutSeconds) {
      if guidanceHintOverride == hint {
        guidanceHintOverride = nil
      }
    }
  }

  private func clearGuidanceOverride() {
    guidanceHintOverride = nil
  }

  private func updateGuidanceAlignmentHaptic() {
    guard AppFeatureFlags.cameraGuidanceHapticsEnabled, settings.levelEnabled else { return }
    let tilt = maxGuidanceTiltDegrees
    if tilt > CameraGuidanceCatalog.tiltThresholdDegrees {
      guidanceAlignmentHapticArmed = true
      return
    }

    guard tilt <= CameraGuidanceCatalog.alignedThresholdDegrees,
          guidanceAlignmentHapticArmed else { return }
    let now = Date()
    guard now.timeIntervalSince(lastGuidanceAlignmentHapticAt) > 1.4 else { return }

    let generator = UISelectionFeedbackGenerator()
    generator.prepare()
    generator.selectionChanged()
    lastGuidanceAlignmentHapticAt = now
    guidanceAlignmentHapticArmed = false
  }

  @ViewBuilder
  private func singleShotFeedbackToast(
    totalSize: CGSize,
    isLandscape: Bool,
    safeInsets: EdgeInsets
  ) -> some View {
    if let singleShotFeedback {
      let y = isLandscape
        ? max(safeInsets.top + 118, 126)
        : max((CGFloat(8) / CGFloat(debugGridRows)) * totalSize.height, safeInsets.top + 132)

      HStack(spacing: 8) {
        Circle()
          .fill(color(for: singleShotFeedback))
          .frame(width: 8, height: 8)
        Text(singleShotFeedback.feedbackText)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.white.opacity(0.95))
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(Color.black.opacity(0.48))
      .overlay(
        Capsule()
          .stroke(color(for: singleShotFeedback).opacity(0.42), lineWidth: 1)
      )
      .clipShape(Capsule())
      .position(x: totalSize.width / 2, y: y)
      .allowsHitTesting(false)
      .zIndex(11)
      .transition(.opacity)
    }
  }

  private func color(for status: SingleShotCorrectabilityStatus) -> Color {
    switch status {
    case .good:
      return .green
    case .usable:
      return .yellow
    case .retake:
      return .red
    }
  }

  @ViewBuilder
  private func guidanceHintLine(
    totalSize: CGSize,
    isLandscape: Bool,
    safeInsets: EdgeInsets
  ) -> some View {
    if AppFeatureFlags.cameraGuidanceHintsEnabled {
      let maxWidth = min(max(totalSize.width - safeInsets.leading - safeInsets.trailing - 48, 160), 360)
      let shutterY = (CGFloat(9) + 0.5) / CGFloat(debugGridRows) * totalSize.height
      let y = isLandscape
        ? max(safeInsets.top + 90, 94)
        : max(shutterY - 74, safeInsets.top + 104)

      Text(guidanceHintText)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white.opacity(0.94))
        .lineLimit(1)
        .truncationMode(.tail)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: maxWidth)
        .background(Color.black.opacity(0.38))
        .overlay(
          Capsule()
            .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .clipShape(Capsule())
        .position(x: totalSize.width / 2, y: y)
        .allowsHitTesting(false)
        .zIndex(9)
    }
  }

  private func navItem(icon: String, label: String, selected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      VStack(spacing: 2) {
        Image(systemName: icon)
          .font(.system(size: 14))
        Text(label)
          .font(.system(size: 9))
      }
      .foregroundStyle(selected ? Color.white : Color.white.opacity(0.6))
      .padding(.horizontal, selected ? 8 : 0)
      .padding(.vertical, selected ? 4 : 0)
      .background(selected ? AppTheme.primary.opacity(0.3) : Color.clear)
      .clipShape(RoundedRectangle(cornerRadius: 8))
    }
  }

  private func cycleCaptureDelay() {
    let current = settings.captureDelaySeconds
    let next: Double
    switch Int(current.rounded()) {
    case 0: next = 3
    case 3: next = 10
    default: next = 0
    }
    settings.captureDelaySeconds = next
  }

  private func delayLabel() -> String {
    let seconds = Int(settings.captureDelaySeconds.rounded())
    return "\(seconds)s"
  }

  @ViewBuilder
  private func captureControls(totalSize: CGSize) -> some View {
    let shutterCenterX = CGFloat(3) / CGFloat(debugGridColumns) * totalSize.width
    let shutterCenterY = (CGFloat(9) + 0.5) / CGFloat(debugGridRows) * totalSize.height
    let isSingleShot = settings.photoCaptureMode == .singleShot
    let fillSize: CGFloat = isSingleShot ? 78 : 68
    let ringSize: CGFloat = isSingleShot ? 96 : 82
    let readyRingSize: CGFloat = isSingleShot ? 108 : 92
    let touchSize: CGFloat = isSingleShot ? 128 : 100
    VStack(spacing: 12) {
      Button(action: capture) {
        ZStack {
          Circle()
            .fill(camera.isCapturing ? Color.gray : Color.white)
            .frame(width: fillSize, height: fillSize)
          Circle()
            .stroke(Color.white.opacity(0.6), lineWidth: 4)
            .frame(width: ringSize, height: ringSize)
          if levelReady {
            Circle()
              .stroke(Color.green.opacity(0.95), lineWidth: 3)
              .frame(width: readyRingSize, height: readyRingSize)
          }
        }
        .frame(width: touchSize, height: touchSize)
        .contentShape(Circle())
      }
      .disabled(camera.isCapturing)
      .accessibilityIdentifier("camera.shutter")
      .accessibilityLabel("Ausloeser")
    }
    .frame(maxWidth: .infinity)
    .position(x: shutterCenterX, y: shutterCenterY)
    .zIndex(10)
  }

  @ViewBuilder
  private func bracketLabel() -> some View {
    if settings.photoCaptureMode == .standardBracket {
      Button(action: cyclePrimaryBracketCount) {
        bracketLabelChip()
      }
      .buttonStyle(.plain)
      .disabled(camera.isCapturing)
      .accessibilityLabel("Belichtungsreihe")
      .accessibilityValue("\(settings.bracketCount) Fotos")
    } else {
      bracketLabelChip()
    }
  }

  private var bracketLabelText: String {
    switch settings.photoCaptureMode {
    case .standardBracket:
      let effectiveStepEV = BracketStepPolicy.effectiveStepEV(
        configuredStepEV: settings.exposureStepEV,
        bracketCount: settings.bracketCount,
        photoFormat: settings.photoFormat
      )
      return "\(settings.bracketCount)x  \(String(format: "%.1f", effectiveStepEV)) EV"
    case .darkRoom:
      return "Kellermodus · 1 Bild"
    case .singleShot:
      return "Einzelbild"
    }
  }

  private func bracketLabelChip() -> some View {
    Text(bracketLabelText)
      .font(.caption)
      .foregroundStyle(.white)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(Color.black.opacity(0.5))
      .clipShape(Capsule())
  }

  private func cyclePrimaryBracketCount() {
    settings.cyclePrimaryBracketCount()
  }

  @ViewBuilder
  private func captureProgressBadge() -> some View {
    if let progress = camera.captureProgress,
       progress.total > 1 || settings.photoCaptureMode == .darkRoom {
      VStack(spacing: 5) {
        HStack(spacing: 6) {
          if camera.bracketAELockActive {
            Image(systemName: "lock.fill")
              .font(.system(size: 9, weight: .bold))
              .foregroundStyle(.white.opacity(0.85))
          }
          Text(captureProgressLabel(progress))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
        }

        if progress.total > 1 {
          GeometryReader { proxy in
            ZStack(alignment: .leading) {
              Capsule()
                .fill(Color.white.opacity(0.16))
              Capsule()
                .fill(Color.white.opacity(0.88))
                .frame(width: max(proxy.size.width * captureProgressFraction(progress), 0))
            }
          }
          .frame(width: 62, height: 4)
        }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .background(Color.black.opacity(0.55))
      .clipShape(Capsule())
      .transition(.opacity)
    }
  }

  private func captureProgressLabel(_ progress: CaptureProgress) -> String {
    if settings.photoCaptureMode == .darkRoom {
      return "Kellermodus \(progress.current)/\(progress.total)"
    }
    return "\(progress.current)/\(progress.total)  EV \(String(format: "%.1f", progress.ev))"
  }

  private func captureProgressFraction(_ progress: CaptureProgress) -> CGFloat {
    let total = max(progress.total, 1)
    let current = min(max(progress.current, 0), total)
    return CGFloat(current) / CGFloat(total)
  }

  private func levelIndicator(safeInsets: EdgeInsets) -> some View {
    Group {
      if settings.levelEnabled {
        stabilityIndicatorChip()
          .padding(.top, max(safeInsets.top + 54, 62))
          .padding(.trailing, max(safeInsets.trailing + 12, 16))
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
          .allowsHitTesting(false)
      }
    }
  }

  private func stabilityIndicatorChip() -> some View {
    HStack(spacing: 6) {
      Circle()
        .fill(stabilityIndicatorColor)
        .frame(width: 8, height: 8)
      Text(stabilityIndicatorLabel)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.white.opacity(0.92))
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(Color.black.opacity(0.42))
    .overlay(
      Capsule()
        .stroke(Color.white.opacity(0.16), lineWidth: 1)
    )
    .clipShape(Capsule())
  }

  private var stabilityIndicatorLabel: String {
    if camera.stabilityState == .unstable {
      return "Instabil"
    }

    let tilt = maxGuidanceTiltDegrees
    if tilt > CameraGuidanceCatalog.tiltThresholdDegrees {
      return "Schief"
    }
    if tilt > CameraGuidanceCatalog.alignedThresholdDegrees {
      return "Ausrichten"
    }
    return camera.stabilityState == .stable ? "Gerade" : "Ruhig halten"
  }

  private var stabilityIndicatorColor: Color {
    if camera.stabilityState == .unstable {
      return .red
    }

    let tilt = maxGuidanceTiltDegrees
    if tilt > CameraGuidanceCatalog.tiltThresholdDegrees {
      return .red
    }
    if tilt > CameraGuidanceCatalog.alignedThresholdDegrees || camera.stabilityState == .marginal {
      return .yellow
    }
    return .green
  }

  private func updateLevelReadiness(forceReset: Bool = false) {
    if forceReset || !settings.levelEnabled {
      levelReady = false
      stabilityHapticArmed = true
      return
    }

    let now = Date()
    if camera.stabilityState == .stable
      && maxGuidanceTiltDegrees <= CameraGuidanceCatalog.alignedThresholdDegrees {
      if !levelReady {
        levelReady = true
        emitPreShotStabilityHapticIfNeeded(now: now)
      }
    } else {
      levelReady = false
      if camera.stabilityState == .unstable {
        stabilityHapticArmed = true
      }
    }
  }

  private func emitPreShotStabilityHapticIfNeeded(now: Date) {
    guard stabilityHapticArmed else { return }
    guard now.timeIntervalSince(lastReadyHapticAt) > 1.4 else { return }

    let generator = UISelectionFeedbackGenerator()
    generator.prepare()
    generator.selectionChanged()
    lastReadyHapticAt = now
    stabilityHapticArmed = false
  }

  @ViewBuilder
  private func warningBanner() -> some View {
    if let message = camera.warningMessage {
      Text(message)
        .font(.subheadline)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.7))
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.top, 84)
        .padding(.horizontal, 20)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
  }

  @ViewBuilder
  private func zoomControls(
    totalSize: CGSize,
    isLandscape: Bool,
    lowerControlLift: CGFloat
  ) -> some View {
    if isLandscape {
      zoomSelector(presets: camera.zoomPresets)
        .position(
          x: (CGFloat(1) + 0.5) / CGFloat(debugGridColumns) * totalSize.width,
          y: (CGFloat(10) + 0.5) / CGFloat(debugGridRows) * totalSize.height - lowerControlLift
        )
    } else {
      splitZoomSelector(totalSize: totalSize)
    }
  }

  private func splitZoomSelector(totalSize: CGSize) -> some View {
    let presets = camera.zoomPresets
    let splitIndex = max(1, presets.count / 2)
    let leftPresets = Array(presets.prefix(splitIndex))
    let rightPresets = Array(presets.dropFirst(splitIndex))
    let largestSideCount = max(leftPresets.count, rightPresets.count)
    let buttonSize: CGFloat = 44
    let spacing: CGFloat = 8
    let horizontalPadding: CGFloat = 8
    let selectorWidth = CGFloat(largestSideCount) * buttonSize
      + CGFloat(max(largestSideCount - 1, 0)) * spacing
      + horizontalPadding * 2
    let shutterCenterX = CGFloat(3) / CGFloat(debugGridColumns) * totalSize.width
    let shutterCenterY = (CGFloat(9) + 0.5) / CGFloat(debugGridRows) * totalSize.height
    let shutterRadius: CGFloat = settings.photoCaptureMode == .singleShot ? 64 : 52
    let gap: CGFloat = totalSize.width < 380 ? 4 : 8
    let sideOffset = shutterRadius + gap + selectorWidth / 2
    let edgePadding: CGFloat = 10
    let leftX = max(edgePadding + selectorWidth / 2, shutterCenterX - sideOffset)
    let rightX = min(totalSize.width - edgePadding - selectorWidth / 2, shutterCenterX + sideOffset)

    return ZStack {
      if !leftPresets.isEmpty {
        zoomSelector(presets: leftPresets)
          .position(x: leftX, y: shutterCenterY)
      }
      if !rightPresets.isEmpty {
        zoomSelector(presets: rightPresets)
          .position(x: rightX, y: shutterCenterY)
      }
    }
  }

  private func zoomSelector(presets: [Double]) -> some View {
    HStack(spacing: 8) {
      ForEach(presets, id: \.self) { zoom in
        zoomButton(zoom)
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .background(Color.black.opacity(0.28))
    .clipShape(Capsule())
    .overlay(
      Capsule()
        .stroke(Color.white.opacity(0.14), lineWidth: 1)
    )
  }

  private func zoomButton(_ value: Double) -> some View {
    Button(action: { setCameraZoom(value) }) {
      Text(zoomLabel(value))
        .font(.system(size: 11, weight: .semibold))
        .lineLimit(1)
        .foregroundStyle(abs(selectedZoom - value) < 0.05 ? Color.black : Color.white)
        .frame(width: 32, height: 32)
        .background(abs(selectedZoom - value) < 0.05 ? Color.yellow : Color.black.opacity(0.5))
        .clipShape(Circle())
        .frame(width: 44, height: 44)
    }
    .accessibilityLabel("Zoom \(zoomLabel(value))")
  }

  private func setCameraZoom(_ value: Double) {
    selectedZoom = value
    settings.lastZoomPreset = value
    camera.setZoomFactor(value)
  }

  private func zoomLabel(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.minimumIntegerDigits = 1
    formatter.maximumFractionDigits = value == floor(value) ? 0 : 1
    formatter.minimumFractionDigits = value == floor(value) ? 0 : 1
    let number = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    return "\(number)x"
  }

  private func formatRatio(isLandscape: Bool, label: String) -> CGFloat {
    let ratio = baseFormatRatio(label: label)

    if isLandscape {
      return ratio
    }
    return ratio >= 1 ? 1 / ratio : ratio
  }

  private func baseFormatRatio(label: String) -> CGFloat {
    switch label {
    case "1:1":
      return 1.0
    case "4:3":
      return 4.0 / 3.0
    case "3:2":
      return 3.0 / 2.0
    case "16:9":
      return 16.0 / 9.0
    case "9:16":
      return 9.0 / 16.0
    default:
      return 3.0 / 2.0
    }
  }

  private func captureOutputAspectRatio() -> CGFloat {
    let base = baseFormatRatio(label: formatLabel)
    if isDeviceLandscapeForCapture() {
      return base >= 1 ? base : (1 / base)
    }
    return base >= 1 ? 1 / base : base
  }

  private func isDeviceLandscapeForCapture() -> Bool {
    switch UIDevice.current.orientation {
    case .landscapeLeft, .landscapeRight:
      return true
    case .portrait, .portraitUpsideDown:
      return false
    default:
      return false
    }
  }

  private func centeredRect(in size: CGSize, aspectRatio: CGFloat) -> CGRect {
    let safeSize = CGSize(width: max(size.width, 1), height: max(size.height, 1))
    let safeAspectRatio = aspectRatio.isFinite ? max(aspectRatio, 0.001) : 1
    let viewRatio = safeSize.width / max(safeSize.height, 1)
    var targetSize = size

    if viewRatio > safeAspectRatio {
      let width = safeSize.height * safeAspectRatio
      targetSize = CGSize(width: width, height: safeSize.height)
    } else {
      let height = safeSize.width / safeAspectRatio
      targetSize = CGSize(width: safeSize.width, height: height)
    }

    let origin = CGPoint(
      x: (safeSize.width - targetSize.width) / 2,
      y: (safeSize.height - targetSize.height) / 2
    )
    return CGRect(origin: origin, size: targetSize)
  }

  private func clampPoint(_ point: CGPoint) -> CGPoint {
    CGPoint(x: min(max(0.05, point.x), 0.95), y: min(max(0.05, point.y), 0.95))
  }

  private func l10n(_ key: String) -> String {
    settings.localized(key)
  }

  private func l10nFormat(_ key: String, _ arguments: CVarArg...) -> String {
    AppLocalizer.localizedFormat(key, language: settings.appLanguage, arguments: arguments)
  }
}

private enum CameraGuidanceSkeleton {
  case genericRoom
  case kitchenCountertop
  case bathroomMirrorSink
  case livingWindowSeating
  case bedroomSimpleFrame
  case hallwayPerspective
  case exteriorFacade
  case balconyView
}

private struct CameraGuidanceRule {
  let defaultHint: String
  let skeleton: CameraGuidanceSkeleton
}

private enum CameraGuidanceCatalog {
  static let hintTimeoutSeconds: TimeInterval = 3.5
  static let tiltThresholdDegrees = 2.0
  static let alignedThresholdDegrees = 1.0

  static func rule(forRoomId roomId: String) -> CameraGuidanceRule {
    switch roomId {
    case "kitchen", "living_kitchen", "dining_room", "pantry", "utility_room":
      return CameraGuidanceRule(
        defaultHint: "Kamera ruhig und gerade halten",
        skeleton: .kitchenCountertop
      )
    case "bathroom", "guest_wc":
      return CameraGuidanceRule(
        defaultHint: "Kamera ruhig und gerade halten",
        skeleton: .bathroomMirrorSink
      )
    case "living_room", "studio", "conservatory":
      return CameraGuidanceRule(
        defaultHint: "Kamera ruhig und gerade halten",
        skeleton: .livingWindowSeating
      )
    case "bedroom", "children_room", "guest_room":
      return CameraGuidanceRule(
        defaultHint: "Kamera ruhig und gerade halten",
        skeleton: .bedroomSimpleFrame
      )
    case "hallway", "corridor", "stairs":
      return CameraGuidanceRule(
        defaultHint: "Kamera ruhig und gerade halten",
        skeleton: .hallwayPerspective
      )
    case "exterior", "street", "garage", "carport", "driveway", "outbuilding":
      return CameraGuidanceRule(
        defaultHint: "Kamera ruhig und gerade halten",
        skeleton: .exteriorFacade
      )
    case "balcony", "terrace", "roof_terrace", "garden", "courtyard":
      return CameraGuidanceRule(
        defaultHint: "Kamera ruhig und gerade halten",
        skeleton: .balconyView
      )
    default:
      return CameraGuidanceRule(
        defaultHint: "Kanten gerade halten",
        skeleton: .genericRoom
      )
    }
  }
}

private struct CameraGuidanceSkeletonOverlay: View {
  let skeleton: CameraGuidanceSkeleton

  private let lineColor = Color.white.opacity(0.11)
  private let accentColor = Color.white.opacity(0.16)

  var body: some View {
    Canvas { context, size in
      drawBaseElements(in: &context, size: size)

      switch skeleton {
      case .genericRoom:
        drawVerticalEdgeGuides(in: &context, size: size)
      case .kitchenCountertop:
        drawCountertopGuide(in: &context, size: size)
        drawCabinetGuides(in: &context, size: size)
      case .bathroomMirrorSink:
        drawMirrorAndSink(in: &context, size: size)
      case .livingWindowSeating:
        drawWindowAndSeating(in: &context, size: size)
      case .bedroomSimpleFrame:
        drawBedroomFrame(in: &context, size: size)
      case .hallwayPerspective:
        drawHallwayPerspective(in: &context, size: size)
      case .exteriorFacade:
        drawFacadeGuide(in: &context, size: size)
      case .balconyView:
        drawBalconyGuide(in: &context, size: size)
      }
    }
  }

  private func drawBaseElements(in context: inout GraphicsContext, size: CGSize) {
    let w = size.width
    let h = size.height
    let stroke = StrokeStyle(lineWidth: 1, dash: [8, 10])

    for x in [w / 3, (w / 3) * 2] {
      var path = Path()
      path.move(to: CGPoint(x: x, y: h * 0.08))
      path.addLine(to: CGPoint(x: x, y: h * 0.92))
      context.stroke(path, with: .color(lineColor), style: stroke)
    }

    for y in [h / 3, (h / 3) * 2] {
      var path = Path()
      path.move(to: CGPoint(x: w * 0.08, y: y))
      path.addLine(to: CGPoint(x: w * 0.92, y: y))
      context.stroke(path, with: .color(lineColor), style: stroke)
    }

    var horizon = Path()
    horizon.move(to: CGPoint(x: w * 0.16, y: h * 0.52))
    horizon.addLine(to: CGPoint(x: w * 0.84, y: h * 0.52))
    context.stroke(horizon, with: .color(accentColor), style: StrokeStyle(lineWidth: 1.2, dash: [12, 10]))
  }

  private func drawVerticalEdgeGuides(in context: inout GraphicsContext, size: CGSize) {
    let w = size.width
    let h = size.height
    for x in [w * 0.18, w * 0.82] {
      var path = Path()
      path.move(to: CGPoint(x: x, y: h * 0.16))
      path.addLine(to: CGPoint(x: x, y: h * 0.86))
      context.stroke(path, with: .color(accentColor), style: StrokeStyle(lineWidth: 1.5))
    }
  }

  private func drawCountertopGuide(in context: inout GraphicsContext, size: CGSize) {
    let rect = CGRect(x: size.width * 0.12, y: size.height * 0.62, width: size.width * 0.76, height: size.height * 0.11)
    context.stroke(Path(roundedRect: rect, cornerRadius: 8), with: .color(accentColor), lineWidth: 1.5)
  }

  private func drawCabinetGuides(in context: inout GraphicsContext, size: CGSize) {
    for x in [size.width * 0.28, size.width * 0.5, size.width * 0.72] {
      var path = Path()
      path.move(to: CGPoint(x: x, y: size.height * 0.18))
      path.addLine(to: CGPoint(x: x, y: size.height * 0.58))
      context.stroke(path, with: .color(lineColor), style: StrokeStyle(lineWidth: 1.2))
    }
  }

  private func drawMirrorAndSink(in context: inout GraphicsContext, size: CGSize) {
    let mirror = CGRect(x: size.width * 0.31, y: size.height * 0.17, width: size.width * 0.38, height: size.height * 0.34)
    let sink = CGRect(x: size.width * 0.27, y: size.height * 0.59, width: size.width * 0.46, height: size.height * 0.12)
    context.stroke(Path(roundedRect: mirror, cornerRadius: 10), with: .color(accentColor), lineWidth: 1.5)
    context.stroke(Path(ellipseIn: sink), with: .color(lineColor), lineWidth: 1.3)
    drawVerticalEdgeGuides(in: &context, size: size)
  }

  private func drawWindowAndSeating(in context: inout GraphicsContext, size: CGSize) {
    let window = CGRect(x: size.width * 0.58, y: size.height * 0.16, width: size.width * 0.25, height: size.height * 0.32)
    context.stroke(Path(roundedRect: window, cornerRadius: 6), with: .color(accentColor), lineWidth: 1.4)
    var seating = Path()
    seating.move(to: CGPoint(x: size.width * 0.16, y: size.height * 0.68))
    seating.addLine(to: CGPoint(x: size.width * 0.68, y: size.height * 0.68))
    context.stroke(seating, with: .color(accentColor), style: StrokeStyle(lineWidth: 1.5, dash: [14, 8]))
  }

  private func drawBedroomFrame(in context: inout GraphicsContext, size: CGSize) {
    let bed = CGRect(x: size.width * 0.18, y: size.height * 0.57, width: size.width * 0.52, height: size.height * 0.22)
    let window = CGRect(x: size.width * 0.68, y: size.height * 0.18, width: size.width * 0.18, height: size.height * 0.27)
    context.stroke(Path(roundedRect: bed, cornerRadius: 12), with: .color(accentColor), lineWidth: 1.4)
    context.stroke(Path(roundedRect: window, cornerRadius: 6), with: .color(lineColor), lineWidth: 1.2)
  }

  private func drawHallwayPerspective(in context: inout GraphicsContext, size: CGSize) {
    let center = CGPoint(x: size.width * 0.5, y: size.height * 0.48)
    for point in [
      CGPoint(x: size.width * 0.18, y: size.height * 0.16),
      CGPoint(x: size.width * 0.82, y: size.height * 0.16),
      CGPoint(x: size.width * 0.12, y: size.height * 0.84),
      CGPoint(x: size.width * 0.88, y: size.height * 0.84)
    ] {
      var path = Path()
      path.move(to: point)
      path.addLine(to: center)
      context.stroke(path, with: .color(accentColor), style: StrokeStyle(lineWidth: 1.2, dash: [10, 8]))
    }

    var axis = Path()
    axis.move(to: CGPoint(x: center.x, y: size.height * 0.14))
    axis.addLine(to: CGPoint(x: center.x, y: size.height * 0.88))
    context.stroke(axis, with: .color(lineColor), lineWidth: 1.2)
  }

  private func drawFacadeGuide(in context: inout GraphicsContext, size: CGSize) {
    let frame = CGRect(x: size.width * 0.15, y: size.height * 0.16, width: size.width * 0.7, height: size.height * 0.62)
    context.stroke(Path(roundedRect: frame, cornerRadius: 8), with: .color(accentColor), lineWidth: 1.5)
    drawVerticalEdgeGuides(in: &context, size: size)
  }

  private func drawBalconyGuide(in context: inout GraphicsContext, size: CGSize) {
    var railing = Path()
    railing.move(to: CGPoint(x: size.width * 0.14, y: size.height * 0.56))
    railing.addLine(to: CGPoint(x: size.width * 0.86, y: size.height * 0.56))
    context.stroke(railing, with: .color(accentColor), lineWidth: 1.6)

    let viewFrame = CGRect(x: size.width * 0.18, y: size.height * 0.18, width: size.width * 0.64, height: size.height * 0.42)
    context.stroke(Path(roundedRect: viewFrame, cornerRadius: 8), with: .color(lineColor), lineWidth: 1.2)
  }
}
