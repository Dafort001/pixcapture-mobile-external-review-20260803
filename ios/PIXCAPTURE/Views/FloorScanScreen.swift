import SwiftUI

#if canImport(RoomPlan)
import RoomPlan
#endif

// iOS 17+ "Etage scannen" flow:
// - keeps one RoomCaptureView alive across rooms
// - minimizes user interaction (only room-type tagging)
// - stores a trackingSessionId in segments.json so backend/video workflows can treat this as a coherent floor session
struct FloorScanScreen: View {
  let projectKey: String
  let initialFloorId: String
  let initialRoomId: String
  let onDone: () -> Void

  @EnvironmentObject private var cameraModel: CameraManager

  private enum ScanDisplayMode: String {
    case threeD = "3D"
    case twoD = "2D"
  }

  @State private var project: FloorplanProject? = nil

  @State private var isRunning = false
  @State private var isExporting = false
  @State private var exportError: String? = nil
  @State private var isWaitingForCameraRelease = true

  @State private var selectedFloorId: String
  @State private var selectedRoomId: String
  @State private var preferredRunningDisplayMode: ScanDisplayMode = .threeD
  @State private var currentScanId: UUID? = nil
  @State private var currentOutputPaths: RoomPlanOutputPaths? = nil

  @State private var showRoomTypePicker = false
  @State private var hasScheduledInitialPicker = false
  @State private var showHelp = true
  @State private var helpHideTask: Task<Void, Never>? = nil

  @State private var pendingTrackSamples: [RoomPlanTrackSample] = []
  @State private var trackingMessage: String? = nil
  @State private var sessionRecoveryAttempts = 0
  @State private var sessionRecoveryTask: Task<Void, Never>? = nil
  private let maxSessionRecoveryAttempts = 4

  @State private var reviewUSDZURL: URL? = nil
  @State private var baseWorldOffset: (x: Double, y: Double)? = nil

  @State private var trackingSessionId: String = UUID().uuidString
  @State private var lastCommittedRoomSnapshot: LastCommittedRoomSnapshot? = nil
  @State private var transitionOverlayDismissedForCurrentScan = false

  private struct PendingScanCommit: Hashable {
    let scanId: UUID
    let roomId: String
    let floorId: String
    let metrics: FloorplanMetrics
    let transform: FloorplanRoomTransform
    let connection: FloorplanRoomConnection?
  }

  private struct LastCommittedRoomSnapshot: Hashable {
    let roomLabel: String
    let floorLabel: String
    let segmentsWorld: [FloorplanSegment]
  }

  private struct TransitionGuidance: Hashable {
    let guidanceText: String
    let guidanceStyle: FloorScanOrientationOverlayView.GuidanceStyle
    let isTrackingLimited: Bool
    let shouldDismissOverlay: Bool
  }

  // We only persist scans after the user confirms in the review screen.
  // This prevents aborted/rescanned attempts from appearing in the overview.
  @State private var pendingCommit: PendingScanCommit? = nil

  init(
    projectKey: String,
    floorId: String,
    initialRoomId: String = RoomTaxonomy.defaultRoomId,
    onDone: @escaping () -> Void
  ) {
    self.projectKey = projectKey
    let normalizedFloor = FloorTaxonomy.normalizedFloorId(floorId)
    self.initialFloorId = normalizedFloor
    let normalizedInitialRoom = RoomTaxonomy.normalizedRoomId(initialRoomId)
    self.initialRoomId = normalizedInitialRoom
    self.onDone = onDone
    _selectedFloorId = State(initialValue: normalizedFloor)
    _selectedRoomId = State(initialValue: normalizedInitialRoom)
  }

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

#if canImport(RoomPlan)
      if #available(iOS 17.0, *) {
        if RoomCaptureSession.isSupported {
          if isWaitingForCameraRelease || cameraModel.isSessionRunning {
            VStack(spacing: 10) {
              ProgressView()
                .tint(.white)
              Text("Kamera wird vorbereitet …")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
              Text("Bitte kurz warten.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.75))
            }
          } else {
            RoomPlanCaptureUIView(
              isRunning: $isRunning,
              pendingTrackSamples: $pendingTrackSamples,
              trackingMessage: $trackingMessage,
              sharedTrackingSessionId: trackingSessionId
            ) { data, error in
              guard !isExporting else { return }
              if let error {
                handleCaptureSessionError(error)
                return
              }
              guard let data else {
                exportError = "Kein RoomPlan-Ergebnis erhalten."
                return
              }
              exportCapturedRoom(data)
            }
            .ignoresSafeArea()

            if effectiveDisplayMode == .twoD {
              Color.black.opacity(0.34)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
          }
        } else {
          VStack(spacing: 10) {
            Image(systemName: "iphone")
              .font(.system(size: 36, weight: .semibold))
              .foregroundStyle(.white.opacity(0.85))
            Text("RoomPlan nicht verfügbar")
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(.white)
            Text("Für den Etagen-Scan wird ein iPhone/iPad mit LiDAR benötigt (z.B. Pro-Modelle).")
              .font(.system(size: 13))
              .foregroundStyle(.white.opacity(0.75))
              .multilineTextAlignment(.center)
              .padding(.horizontal, 28)
          }
        }
      } else {
        Text("RoomPlan ist auf diesem Gerät nicht verfügbar.")
          .foregroundStyle(.white)
      }
#else
      Text("RoomPlan ist auf diesem Gerät nicht verfügbar.")
        .foregroundStyle(.white)
#endif

      VStack(spacing: 10) {
        topBar
        Spacer()
        if showHelp {
          bottomHelp
            .transition(.opacity)
        }
      }
      .padding(.horizontal, 16)
      .padding(.top, 14)
      .padding(.bottom, 24)
      .zIndex(10)

      if showRoomTypePicker {
        roomTypePickerOverlay
          .zIndex(40)
      }

      if let model = orientationOverlayModel {
        VStack(spacing: 0) {
          Spacer(minLength: 0)
          FloorScanOrientationOverlayView(model: model)
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottom)))
        }
        .padding(.horizontal, effectiveDisplayMode == .twoD ? 16 : 12)
        .padding(.bottom, effectiveDisplayMode == .twoD ? (isRunning ? 118 : 132) : 8)
        .allowsHitTesting(false)
        .zIndex(120)
      }

      if shouldShowTransitionPrompt {
        VStack(spacing: 0) {
          Spacer(minLength: 0)
          transitionPrompt
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 26)
        .zIndex(121)
      }

      if isExporting {
        exportingOverlay
          .zIndex(90)
      }
    }
    .onAppear {
      // RoomPlan needs exclusive camera access. Ensure our photo camera session is fully stopped first.
      cameraModel.stopSession()
      isWaitingForCameraRelease = true
      loadProjectIfNeeded()
      scheduleHelpAutoHide()
      // Defer the initial room picker slightly until camera handoff is done.
      if !hasScheduledInitialPicker, currentScanId == nil {
        hasScheduledInitialPicker = true
        Task { @MainActor in
          // Wait for the AVCaptureSession to stop (best-effort).
          for _ in 0..<40 {
            if !cameraModel.isSessionRunning { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
          }
          isWaitingForCameraRelease = false
          try? await Task.sleep(nanoseconds: 250_000_000)
          prepareNextRoomScan(autoStart: true)
        }
      } else {
        // Still clear the waiting flag if the screen is shown again.
        Task { @MainActor in
          for _ in 0..<40 {
            if !cameraModel.isSessionRunning { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
          }
          isWaitingForCameraRelease = false
        }
      }
    }
    .onDisappear {
      helpHideTask?.cancel()
      helpHideTask = nil
      sessionRecoveryTask?.cancel()
      sessionRecoveryTask = nil
      if #available(iOS 17.0, *) {
        RoomPlanCaptureUIView.releaseSharedARSession(for: trackingSessionId)
      }
    }
    .onChange(of: pendingTrackSamples) { _, _ in
      updateTransitionOverlayVisibility()
    }
    .onChange(of: trackingMessage) { _, _ in
      updateTransitionOverlayVisibility()
    }
    .fullScreenCover(item: reviewItemBinding()) { item in
      RoomPlanReviewScreen(
        usdzURL: item.usdzURL,
        onRescan: {
          reviewUSDZURL = nil
          exportError = nil
          pendingCommit = nil
          trackingMessage = nil
          sessionRecoveryAttempts = 0
          sessionRecoveryTask?.cancel()
          sessionRecoveryTask = nil
          transitionOverlayDismissedForCurrentScan = false
          // overwrite same scan id and keep session alive
          preferredRunningDisplayMode = .threeD
          isRunning = true
          showHelp = true
          scheduleHelpAutoHide()
        },
        onContinue: {
          reviewUSDZURL = nil
          exportError = nil
          sessionRecoveryAttempts = 0
          sessionRecoveryTask?.cancel()
          sessionRecoveryTask = nil
          commitPendingIfNeeded()
          currentScanId = nil
          currentOutputPaths = nil
          // Each room requires an explicit room/floor selection.
          showRoomTypePicker = true
        }
      )
      .interactiveDismissDisabled(true)
    }
  }

	  private var topBar: some View {
		    HStack(spacing: 12) {
		      Button(action: onDone) {
		        Image(systemName: "xmark")
	          .font(.system(size: 14, weight: .semibold))
	          .foregroundStyle(.white)
	          .frame(width: 36, height: 36)
	          .background(Color.black.opacity(0.4))
	          .clipShape(Circle())
	          .frame(width: 44, height: 44)
	      }
	      .accessibilityLabel("Etagen-Scan schließen")

	      VStack(alignment: .leading, spacing: 2) {
	        Text("Etage scannen (Tracking)")
	          .font(.system(size: 15, weight: .semibold))
	          .foregroundStyle(.white)
	        Text("\(FloorTaxonomy.floor(id: selectedFloorId).shortDisplayName) · \(RoomTaxonomy.room(id: selectedRoomId).displayName)")
	          .font(.system(size: 12, weight: .medium))
	          .foregroundStyle(.white.opacity(0.7))
	          .lineLimit(1)
	      }

	      Spacer()

      Button {
        if isExporting { return }
        if isRunning {
          exportError = "Bitte zuerst Stop drücken."
          showHelp = true
          scheduleHelpAutoHide()
          return
        }
        if pendingCommit != nil {
          exportError = "Bitte zuerst den letzten Raum bestätigen oder neu scannen."
          showHelp = true
          scheduleHelpAutoHide()
          return
        }
        onDone()
      } label: {
	        HStack(spacing: 7) {
	          Image(systemName: "checkmark.circle.fill")
	            .font(.system(size: 14, weight: .semibold))
	          Text("Etage fertig")
	            .font(.system(size: 13, weight: .semibold))
	        }
	        .foregroundStyle(Color.white)
	        .padding(.horizontal, 12)
	        .padding(.vertical, 8)
	        .background(Color(red: 0.23, green: 0.33, blue: 0.26).opacity(0.95))
	        .clipShape(Capsule())
	        .overlay(
	          Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1)
	        )
	      }
	      .disabled(isExporting || (project?.roomScans.isEmpty ?? true))
	      .opacity((isExporting || (project?.roomScans.isEmpty ?? true)) ? 0.5 : 1.0)
	      .accessibilityLabel("Etage fertig")

	      Button {
	        showRoomTypePicker = true
	      } label: {
	        Image(systemName: "tag")
	          .font(.system(size: 14, weight: .semibold))
	          .foregroundStyle(.white.opacity(0.95))
	          .frame(width: 36, height: 36)
	          .background(Color.black.opacity(0.35))
	          .clipShape(Circle())
	          .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1))
	          .frame(width: 44, height: 44)
	      }
	      .accessibilityLabel("Raum/Etage wählen")
	      .disabled(isRunning || isExporting)
	      .opacity((isRunning || isExporting) ? 0.5 : 1.0)

      Button(action: toggleDisplayMode) {
        Text(effectiveDisplayMode.rawValue)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 10)
          .padding(.vertical, 8)
          .background(Color.black.opacity(0.35))
          .clipShape(Capsule())
          .overlay(
            Capsule().stroke(Color.white.opacity(0.20), lineWidth: 1)
          )
      }
      .disabled(!isRunning || isExporting)
      .opacity((!isRunning || isExporting) ? 0.5 : 1.0)

	      Button(action: {
	        if isRunning {
	          isRunning = false
	        } else {
	          startPreparedScan()
	        }
	      }) {
        Text(isRunning ? "Stop" : "Start")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(isRunning ? Color.black : Color.white)
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(isRunning ? Color.white : Color.black.opacity(0.35))
          .clipShape(Capsule())
          .overlay(
            Capsule().stroke(Color.white.opacity(0.25), lineWidth: isRunning ? 0 : 1)
          )
      }
      .disabled(isExporting || currentScanId == nil)

      Button {
        withAnimation(.easeInOut(duration: 0.15)) {
          showHelp.toggle()
        }
        if showHelp {
          scheduleHelpAutoHide()
        } else {
          helpHideTask?.cancel()
          helpHideTask = nil
        }
      } label: {
        Image(systemName: showHelp ? "info.circle.fill" : "info.circle")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(.white.opacity(showHelp ? 0.95 : 0.75))
          .frame(width: 36, height: 36)
          .background(Color.black.opacity(0.35))
          .clipShape(Circle())
          .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1))
          .frame(width: 44, height: 44)
      }
      .accessibilityLabel("Kurz-Anleitung ein-/ausblenden")
      .disabled(isExporting)
	    }
	  }

  private var effectiveDisplayMode: ScanDisplayMode {
    isRunning ? preferredRunningDisplayMode : .twoD
  }

  private var shouldShowTransitionPrompt: Bool {
    !isRunning &&
    !isExporting &&
    currentScanId != nil &&
    pendingCommit == nil &&
    !showRoomTypePicker &&
    reviewUSDZURL == nil &&
    !isWaitingForCameraRelease
  }

  private var transitionPrompt: some View {
    VStack(spacing: 10) {
      Text("Nächsten Raum übernehmen")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(.white)

      Text("Starte noch im vorherigen Raum und gehe dann langsam in den nächsten Raum.")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white.opacity(0.78))
        .multilineTextAlignment(.center)
        .frame(maxWidth: 260)

      Button(action: startPreparedScan) {
        Circle()
          .fill(Color.red)
          .frame(width: 68, height: 68)
          .overlay(
            Circle().stroke(Color.white, lineWidth: 5)
          )
          .shadow(color: Color.black.opacity(0.30), radius: 8, x: 0, y: 4)
      }
      .accessibilityLabel("Weiteren Raum scannen starten")
    }
  }

  private func toggleDisplayMode() {
    guard isRunning else { return }
    preferredRunningDisplayMode = preferredRunningDisplayMode == .threeD ? .twoD : .threeD
  }

  private func startPreparedScan() {
    guard !isRunning else { return }
    guard currentScanId != nil else { return }
    sessionRecoveryAttempts = 0
    exportError = nil
    preferredRunningDisplayMode = .threeD
    isRunning = true
  }

	  private var bottomHelp: some View {
	    VStack(alignment: .leading, spacing: 8) {
	      Text("Kurz-Anleitung")
	        .font(.system(size: 13, weight: .semibold))
	        .foregroundStyle(.white)

	      Text("• Langsam bewegen, Wände und Ecken zeigen.\n• Wenn der Raum vollständig ist: Stop drücken.\n• Danach: Raum/Etage wählen und Start drücken.")
	        .font(.system(size: 12))
	        .foregroundStyle(.white.opacity(0.8))
	        .fixedSize(horizontal: false, vertical: true)

      if let exportError {
        Text(exportError)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Color.red.opacity(0.95))
          .fixedSize(horizontal: false, vertical: true)
      }

      if let trackingMessage {
        Text("• \(trackingMessage)")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Color.yellow.opacity(0.95))
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(12)
    .background(Color.black.opacity(0.45))
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(Color.white.opacity(0.14), lineWidth: 1)
    )
  }

  private var exportingOverlay: some View {
    VStack(spacing: 10) {
      ProgressView()
        .tint(.white)
      Text("Exportiere scan.usdz & Grundriss …")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white)
    }
    .padding(18)
    .background(Color.black.opacity(0.65))
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
  }

  private func scheduleHelpAutoHide() {
    helpHideTask?.cancel()
    helpHideTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 5_000_000_000)
      withAnimation(.easeInOut(duration: 0.2)) {
        showHelp = false
      }
    }
  }

  private var roomTypePickerOverlay: some View {
    FloorScanRoomTypePickerOverlayView(
      selectedRoomId: $selectedRoomId,
      selectedFloorId: $selectedFloorId,
      topInset: 86,
      bottomReserved: orientationOverlayModel == nil ? 20 : 350,
      onCancel: cancelRoomPicker,
      onDone: confirmRoomPickerAndStart
    )
  }

  private func cancelRoomPicker() {
    if (project?.roomScans.isEmpty ?? true), currentScanId == nil {
      onDone()
      return
    }
    showRoomTypePicker = false
  }

  private func confirmRoomPickerAndStart() {
    selectedRoomId = RoomTaxonomy.normalizedRoomId(selectedRoomId)
    selectedFloorId = FloorTaxonomy.normalizedFloorId(selectedFloorId)
    showRoomTypePicker = false
    DispatchQueue.main.async {
      prepareNextRoomScan(autoStart: false)
    }
  }

  private func loadProjectIfNeeded() {
    if project == nil {
      project = try? FloorplanProjectStore.loadOrCreate(projectKey: projectKey)
      refreshLastCommittedRoomSnapshot()
    }
  }

  private func prepareNextRoomScan(autoStart: Bool) {
    loadProjectIfNeeded()
    refreshLastCommittedRoomSnapshot()
    sessionRecoveryTask?.cancel()
    sessionRecoveryTask = nil
    sessionRecoveryAttempts = 0
    trackingMessage = nil
    transitionOverlayDismissedForCurrentScan = false
    let scanId = UUID()
    currentScanId = scanId
    currentOutputPaths = try? FloorplanProjectStore.roomScanOutputPaths(projectKey: projectKey, scanId: scanId)
    exportError = nil
    if autoStart {
      preferredRunningDisplayMode = .threeD
      isRunning = true
    } else {
      isRunning = false
      preferredRunningDisplayMode = .twoD
    }
    showHelp = true
    scheduleHelpAutoHide()
  }

  private func exportCapturedRoom(_ data: CapturedRoomData) {
    guard let scanId = currentScanId, let outputPaths = currentOutputPaths else {
      exportError = "Interner Fehler: Scan-Pfade fehlen."
      return
    }

    sessionRecoveryTask?.cancel()
    sessionRecoveryTask = nil
    sessionRecoveryAttempts = 0
    isExporting = true
    exportError = nil
    isRunning = false

    Task { @MainActor in
      do {
        // Best-effort overwrite.
        if FileManager.default.fileExists(atPath: outputPaths.usdz.path) { try? FileManager.default.removeItem(at: outputPaths.usdz) }
        if FileManager.default.fileExists(atPath: outputPaths.floorplanPNG.path) { try? FileManager.default.removeItem(at: outputPaths.floorplanPNG) }
        if FileManager.default.fileExists(atPath: outputPaths.segmentsJSON.path) { try? FileManager.default.removeItem(at: outputPaths.segmentsJSON) }
        if FileManager.default.fileExists(atPath: outputPaths.capturedRoomDataJSON.path) { try? FileManager.default.removeItem(at: outputPaths.capturedRoomDataJSON) }
        if FileManager.default.fileExists(atPath: outputPaths.capturedRoomJSON.path) { try? FileManager.default.removeItem(at: outputPaths.capturedRoomJSON) }

        let builder = RoomBuilder(options: [])
        let capturedRoom = try await builder.capturedRoom(from: data)

        let hint = RoomPlanAutoDockHintDetector.detectEntryHint(
          capturedRoom: capturedRoom,
          samples: pendingTrackSamples
        )

        try capturedRoom.export(to: outputPaths.usdz)
        try RoomPlanFloorplanRenderer.renderPNG(capturedRoom: capturedRoom, outputURL: outputPaths.floorplanPNG)
        try RoomPlanFloorplanRenderer.writeSegmentsJSON(
          capturedRoom: capturedRoom,
          outputURL: outputPaths.segmentsJSON,
          entryPassageHint: hint,
          trackingSessionId: trackingSessionId,
          trackingSource: .floorScanSharedWorld
        )
        RoomPlanStructureMergeService.saveCapturedArtifactsBestEffort(
          data: data,
          room: capturedRoom,
          outputPaths: outputPaths
        )

        pendingCommit = computePendingCommit(scanId: scanId, roomId: selectedRoomId, floorId: selectedFloorId)
        reviewUSDZURL = outputPaths.usdz
      } catch {
        exportError = error.localizedDescription
        isRunning = true
      }
      isExporting = false
    }
  }

  private func handleCaptureSessionError(_ error: Error) {
    let message = friendlyCaptureErrorMessage(error)

    guard shouldAutoRecover(from: error),
          sessionRecoveryAttempts < maxSessionRecoveryAttempts,
          currentScanId != nil else {
      exportError = message
      if lastCommittedRoomSnapshot != nil {
        trackingMessage = "Tracking weiter instabil. Bitte kurz zum letzten stabilen Punkt orientieren und dann Start drücken."
      } else {
        trackingMessage = "Tracking instabil. Bitte Start drücken und langsam neu ausrichten."
      }
      showHelp = true
      scheduleHelpAutoHide()
      return
    }

    sessionRecoveryAttempts += 1
    let attempt = sessionRecoveryAttempts
    exportError = "\(message) (Neustart \(attempt)/\(maxSessionRecoveryAttempts) …)"
    trackingMessage = "Tracking instabil. Scan wird automatisch neu ausgerichtet."
    showHelp = true
    scheduleHelpAutoHide()

    preferredRunningDisplayMode = .twoD
    isRunning = false
    sessionRecoveryTask?.cancel()
    sessionRecoveryTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 900_000_000)
      guard !Task.isCancelled else { return }
      guard !isExporting, currentScanId != nil, reviewUSDZURL == nil, !showRoomTypePicker else { return }
      isRunning = true
    }
  }

  private func shouldAutoRecover(from error: Error) -> Bool {
    let ns = error as NSError
    if ns.domain == NSCocoaErrorDomain, ns.code == NSUserCancelledError {
      return false
    }
    let text = "\(ns.domain) \(ns.localizedDescription)".lowercased()
    let blockers = [
      "not supported", "nicht verfügbar", "nicht unterstützt", "permission",
      "zugriffsrechte", "denied", "berechtigung", "lidar"
    ]
    return !blockers.contains(where: { text.contains($0) })
  }

  private func friendlyCaptureErrorMessage(_ error: Error) -> String {
    if shouldAutoRecover(from: error) {
      return "Scan unterbrochen (Tracking/Kamera)."
    }
    return "Scanfehler: \(error.localizedDescription)"
  }

  private struct ReviewItem: Identifiable {
    let id: String
    let usdzURL: URL
    init(usdzURL: URL) {
      self.usdzURL = usdzURL
      self.id = usdzURL.path
    }
  }

  private func reviewItemBinding() -> Binding<ReviewItem?> {
    Binding(
      get: {
        guard let url = reviewUSDZURL else { return nil }
        return ReviewItem(usdzURL: url)
      },
      set: { newValue in
        reviewUSDZURL = newValue?.usdzURL
      }
    )
  }

  private func computePendingCommit(scanId: UUID, roomId: String, floorId: String) -> PendingScanCommit? {
    guard let project else { return nil }

    let segmentsRel = "rooms/\(scanId.uuidString)/segments.json"

    var metrics = FloorplanMetrics(perimeterMeters: 0, widthMeters: 0, depthMeters: 0, areaSqmApprox: 0)
    var newGeo: FloorplanSegmentsFile? = nil

    // Default placement: append to the right (predictable fallback when tracking/auto-dock fails).
    let gap = 1.0
    let offsetX = project.roomScans.reduce(0.0) { partial, scan in
      partial + scan.metrics.widthMeters + gap
    }
    var transform = FloorplanRoomTransform(translationX: offsetX, translationY: 0, rotationRadians: 0)
    var trackedTransform: FloorplanRoomTransform? = nil
    var dockResult: FloorplanAutoDockService.Result? = nil
    var trackedSnapResult: FloorplanAutoDockService.Result? = nil

    if let url = try? FloorplanProjectStore.resolve(projectKey: projectKey, relativePath: segmentsRel),
       let data = try? Data(contentsOf: url),
       let decoded = try? JSONDecoder().decode(FloorplanSegmentsFile.self, from: data) {
      let normalized = decoded.normalizedForDisplay()
      metrics = normalized.metrics
      newGeo = normalized

      // If the scan belongs to this floor-scan session, we *try* to use the stored offset.
      // However, RoomPlan may reset world coordinates between runs; when offsets look implausible,
      // we fall back to door-docking.
      if decoded.trackingSessionId == trackingSessionId,
         let wx = decoded.worldOffsetX,
         let wy = decoded.worldOffsetY {
        if baseWorldOffset == nil {
          baseWorldOffset = (wx, wy)
        }
        if let baseWorldOffset {
          trackedTransform = FloorplanRoomTransform(
            translationX: wx - baseWorldOffset.x,
            translationY: wy - baseWorldOffset.y,
            rotationRadians: 0
          )
        }
      }
    }

    // Try to auto-dock to the previous room (same floor) for a better "MagicPlan-like" zero-edit workflow.
    let normalizedFloorId = FloorTaxonomy.normalizedFloorId(floorId)
    if let newGeo,
       let result = FloorplanAutoDockService.bestAutoDock(
        project: project,
        newScanId: scanId,
        newGeo: newGeo,
        floorId: normalizedFloorId,
        loadGeo: { scanId in
          let rel = "rooms/\(scanId.uuidString)/segments.json"
          guard let url = try? FloorplanProjectStore.resolve(projectKey: projectKey, relativePath: rel),
                let data = try? Data(contentsOf: url),
                let decoded = try? JSONDecoder().decode(FloorplanSegmentsFile.self, from: data) else { return nil }
          return decoded
        },
        preferredTransform: trackedTransform
       ) {
      dockResult = result
    }

    if dockResult == nil,
       let newGeo,
       let trackedTransform,
       newGeo.trackingSource == .roomSequenceSharedWorld {
      trackedSnapResult = FloorplanAutoDockService.refinedTrackedPlacement(
        project: project,
        newScanId: scanId,
        newGeo: newGeo,
        trackedTransform: trackedTransform,
        floorId: normalizedFloorId,
        loadGeo: { scanId in
          let rel = "rooms/\(scanId.uuidString)/segments.json"
          guard let url = try? FloorplanProjectStore.resolve(projectKey: projectKey, relativePath: rel),
                let data = try? Data(contentsOf: url),
                let decoded = try? JSONDecoder().decode(FloorplanSegmentsFile.self, from: data) else { return nil }
          return decoded
        }
      )
    }

    // Decide which transform to keep:
    // 1) Prefer AR tracking when from same continuous session — it is geometric ground truth.
    // 2) Fall back to door-docking when tracking is unavailable or implausible.
    // 3) Otherwise fall back to predictable append-to-right.
    // Note: the door connection from dockResult is always preserved for adjacency/routing.
    if let dockResult {
      transform = dockResult.transform
    } else if let trackedSnapResult {
      transform = trackedSnapResult.transform
    } else if let trackedTransform {
      let prev = project.roomScans
        .filter { $0.floorId == normalizedFloorId }
        .sorted(by: { $0.createdAt < $1.createdAt })
        .last
      let plausible: Bool
      if let prev {
        let dist = FloorplanAutoDockService.transformDistanceMeters(a: prev.transform, b: trackedTransform)
        plausible = dist <= 18.0
      } else {
        plausible = true
      }
      let collides = newGeo.map {
        FloorplanAutoDockService.placementHasSevereOverlap(
          project: project,
          newGeo: $0,
          newTransform: trackedTransform,
          floorId: normalizedFloorId,
          loadGeo: { scanId in
            let rel = "rooms/\(scanId.uuidString)/segments.json"
            guard let url = try? FloorplanProjectStore.resolve(projectKey: projectKey, relativePath: rel),
                  let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode(FloorplanSegmentsFile.self, from: data) else { return nil }
            return decoded
          }
        )
      } ?? false
      if plausible && !collides {
        transform = trackedTransform
      }
    }
    return PendingScanCommit(
      scanId: scanId,
      roomId: RoomTaxonomy.normalizedRoomId(roomId),
      floorId: normalizedFloorId,
      metrics: metrics,
      transform: transform,
      connection: dockResult?.connection ?? trackedSnapResult?.connection
    )
  }

  private func commitPendingIfNeeded() {
    guard let pending = pendingCommit else { return }
    guard var project else { return }

    let scanId = pending.scanId
    let segmentsRel = "rooms/\(scanId.uuidString)/segments.json"
    let usdzRel = "rooms/\(scanId.uuidString)/scan.usdz"
    let pngRel = "rooms/\(scanId.uuidString)/floorplan.png"
    let capturedRoomDataRel = persistedCapturedRoomRelativePathIfExists("rooms/\(scanId.uuidString)/captured_room_data.json")
    let capturedRoomRel = persistedCapturedRoomRelativePathIfExists("rooms/\(scanId.uuidString)/captured_room.json")
    let capturedRoomIdentifier = capturedRoomRel.flatMap { loadCapturedRoomIdentifier(relativePath: $0) }

    let scan = FloorplanRoomScan(
      id: scanId,
      roomId: pending.roomId,
      floorId: pending.floorId,
      createdAt: Date(),
      usdzPath: usdzRel,
      floorplanPNGPath: pngRel,
      segmentsJSONPath: segmentsRel,
      capturedRoomDataPath: capturedRoomDataRel,
      capturedRoomJSONPath: capturedRoomRel,
      capturedRoomIdentifier: capturedRoomIdentifier,
      metrics: pending.metrics,
      transform: pending.transform
    )

    // Upsert (rescan overwrites the same scanId).
    if let idx = project.roomScans.firstIndex(where: { $0.id == scanId }) {
      project.roomScans[idx] = scan
    } else {
      project.roomScans.append(scan)
    }

    if let connection = pending.connection {
      if !project.connections.contains(where: { $0.id == connection.id }) {
        project.connections.append(connection)
      }
    }

    project = FloorplanProjectStore.normalizedLayout(project: project)
    self.project = project
    try? FloorplanProjectStore.save(project: project)
    Task { @MainActor in
      await reconcileRoomPlanStructureMerge()
    }
    refreshLastCommittedRoomSnapshot()
    pendingCommit = nil
    currentScanId = nil
    currentOutputPaths = nil
  }

  private func reconcileRoomPlanStructureMerge() async {
    guard let project else { return }
    do {
      let mergedProject = try await RoomPlanStructureMergeService.reconcileProject(
        projectKey: projectKey,
        project: project
      )
      guard mergedProject != project else { return }
      self.project = mergedProject
      try FloorplanProjectStore.save(project: mergedProject)
      refreshLastCommittedRoomSnapshot()
    } catch {
      exportError = "RoomPlan-Mehrraum-Merge fehlgeschlagen: \(error.localizedDescription)"
    }
  }

  private func loadCapturedRoomIdentifier(relativePath: String) -> String? {
    guard let url = try? FloorplanProjectStore.resolve(projectKey: projectKey, relativePath: relativePath),
          let capturedRoom = try? RoomPlanStructureMergeService.loadCapturedRoom(from: url) else {
      return nil
    }
    return capturedRoom.identifier.uuidString
  }

  private func persistedCapturedRoomRelativePathIfExists(_ relativePath: String) -> String? {
    guard let url = try? FloorplanProjectStore.resolve(projectKey: projectKey, relativePath: relativePath),
          FileManager.default.fileExists(atPath: url.path) else {
      return nil
    }
    return relativePath
  }

  private var orientationOverlayModel: FloorScanOrientationOverlayView.Model? {
    guard !transitionOverlayDismissedForCurrentScan,
          let snapshot = lastCommittedRoomSnapshot,
          let base = baseWorldOffset,
          let guidance = transitionGuidance else { return nil }
    let recent = Array(pendingTrackSamples.suffix(70))
    let pathPoints = recent.map { sample in
      CGPoint(
        x: Double(sample.x) - base.x,
        y: Double(sample.y) - base.y
      )
    }
    let currentSample = recent.last
    let verifiedSample = recent.last(where: { $0.isTrackingReliable != false })

    let currentPoint = currentSample.map {
      CGPoint(x: Double($0.x) - base.x, y: Double($0.y) - base.y)
    }
    let verifiedPoint = verifiedSample.map {
      CGPoint(x: Double($0.x) - base.x, y: Double($0.y) - base.y)
    }

    guard currentPoint != nil || verifiedPoint != nil || !pathPoints.isEmpty else { return nil }

    let heading: Double? = {
      if let sampleHeading = currentSample?.headingRadians {
        return Double(sampleHeading)
      }
      guard recent.count >= 2 else { return nil }
      let a = recent[recent.count - 2]
      let b = recent[recent.count - 1]
      let dx = Double(b.x - a.x)
      let dy = Double(b.y - a.y)
      guard (dx * dx + dy * dy).squareRoot() >= 0.02 else { return nil }
      return atan2(dy, dx)
    }()

    let limited = trackingMessage != nil || (currentSample?.isTrackingReliable == false)

    return FloorScanOrientationOverlayView.Model(
      roomLabel: snapshot.roomLabel,
      floorLabel: snapshot.floorLabel,
      roomSegments: snapshot.segmentsWorld,
      pathPoints: pathPoints,
      verifiedPoint: verifiedPoint,
      currentPoint: currentPoint,
      currentHeadingRadians: heading,
      isTrackingLimited: limited,
      guidanceText: guidance.guidanceText,
      guidanceStyle: guidance.guidanceStyle
    )
  }

  private var transitionGuidance: TransitionGuidance? {
    guard lastCommittedRoomSnapshot != nil,
          currentScanId != nil else { return nil }

    if !isRunning {
      return TransitionGuidance(
        guidanceText: "Im alten Raum starten. Danach langsam und ruhig in den nächsten Raum gehen.",
        guidanceStyle: .neutral,
        isTrackingLimited: false,
        shouldDismissOverlay: false
      )
    }

    let recent = Array(pendingTrackSamples.suffix(90))
    let reliable = recent.filter { $0.isTrackingReliable != false }
    let current = recent.last
    let start = reliable.first ?? recent.first
    let latestReliable = reliable.last

    let elapsed = max(0, (current?.timestamp ?? 0) - (start?.timestamp ?? 0))
    let distanceMeters: Double = {
      guard let start, let latestReliable else { return 0 }
      let dx = Double(latestReliable.x - start.x)
      let dy = Double(latestReliable.y - start.y)
      return (dx * dx + dy * dy).squareRoot()
    }()

    let recentSpeed = transitionSpeedMetersPerSecond(samples: reliable)
    let trackingLimited = trackingMessage != nil || (current?.isTrackingReliable == false)

    if trackingLimited {
      return TransitionGuidance(
        guidanceText: "Tracking unsicher. Bitte kurz in den vorherigen Raum zurück und den Übergang langsamer erneut gehen.",
        guidanceStyle: .warning,
        isTrackingLimited: true,
        shouldDismissOverlay: false
      )
    }

    if recentSpeed > 1.15 {
      return TransitionGuidance(
        guidanceText: "Zu schnell gegangen. Bitte in den vorherigen Raum zurück und langsamer erneut in den nächsten Raum gehen.",
        guidanceStyle: .warning,
        isTrackingLimited: false,
        shouldDismissOverlay: false
      )
    }

    if elapsed > 5.0 && distanceMeters < 0.20 {
      return TransitionGuidance(
        guidanceText: "Du bewegst dich noch kaum. Starte im alten Raum und gehe dann ruhig durch den Übergang.",
        guidanceStyle: .neutral,
        isTrackingLimited: false,
        shouldDismissOverlay: false
      )
    }

    if distanceMeters >= 0.95 && elapsed >= 1.4 {
      return TransitionGuidance(
        guidanceText: "Übergang erfasst. Du kannst den neuen Raum jetzt normal weiter scannen.",
        guidanceStyle: .ready,
        isTrackingLimited: false,
        shouldDismissOverlay: distanceMeters >= 1.25 && elapsed >= 2.0 && recentSpeed <= 1.0
      )
    }

    if distanceMeters >= 0.35 {
      return TransitionGuidance(
        guidanceText: "Gut. Jetzt langsam weiter in den neuen Raum gehen.",
        guidanceStyle: .neutral,
        isTrackingLimited: false,
        shouldDismissOverlay: false
      )
    }

    return TransitionGuidance(
      guidanceText: "Noch im Übergang. Richte dich am vorherigen Raum aus und bewege dich ruhig auf die Tür zu.",
      guidanceStyle: .neutral,
      isTrackingLimited: false,
      shouldDismissOverlay: false
    )
  }

  private func updateTransitionOverlayVisibility() {
    guard !transitionOverlayDismissedForCurrentScan else { return }
    guard transitionGuidance?.shouldDismissOverlay == true else { return }
    withAnimation(.easeInOut(duration: 0.2)) {
      transitionOverlayDismissedForCurrentScan = true
    }
  }

  private func transitionSpeedMetersPerSecond(samples: [RoomPlanTrackSample]) -> Double {
    guard samples.count >= 2 else { return 0 }
    let window = Array(samples.suffix(8))
    guard let first = window.first, let last = window.last else { return 0 }
    let dt = max(0.001, last.timestamp - first.timestamp)
    let dx = Double(last.x - first.x)
    let dy = Double(last.y - first.y)
    return ((dx * dx + dy * dy).squareRoot()) / dt
  }

  private func refreshLastCommittedRoomSnapshot() {
    guard let project else {
      lastCommittedRoomSnapshot = nil
      return
    }

    let normalizedFloor = FloorTaxonomy.normalizedFloorId(selectedFloorId)
    guard let last = project.roomScans
      .filter({ FloorTaxonomy.normalizedFloorId($0.floorId) == normalizedFloor })
      .sorted(by: { $0.createdAt < $1.createdAt })
      .last else {
      lastCommittedRoomSnapshot = nil
      return
    }

    guard let url = try? FloorplanProjectStore.resolve(projectKey: projectKey, relativePath: last.segmentsJSONPath),
          let data = try? Data(contentsOf: url),
          let decoded = try? JSONDecoder().decode(FloorplanSegmentsFile.self, from: data) else {
      lastCommittedRoomSnapshot = nil
      return
    }

    let normalized = decoded.normalizedForDisplay()
    let segmentsWorld = transform(segments: normalized.segments, t: last.transform)
    lastCommittedRoomSnapshot = LastCommittedRoomSnapshot(
      roomLabel: RoomTaxonomy.room(id: last.roomId).displayName,
      floorLabel: FloorTaxonomy.floor(id: last.floorId).shortDisplayName,
      segmentsWorld: segmentsWorld
    )
  }

  private func transform(segments: [FloorplanSegment], t: FloorplanRoomTransform) -> [FloorplanSegment] {
    if segments.isEmpty { return [] }
    let cosR = cos(t.rotationRadians)
    let sinR = sin(t.rotationRadians)

    return segments.map { seg in
      func rotate(_ x: Double, _ y: Double) -> (Double, Double) {
        (x * cosR - y * sinR, x * sinR + y * cosR)
      }

      let (ax, ay) = rotate(seg.ax, seg.ay)
      let (bx, by) = rotate(seg.bx, seg.by)
      return FloorplanSegment(
        ax: ax + t.translationX,
        ay: ay + t.translationY,
        bx: bx + t.translationX,
        by: by + t.translationY
      )
    }
  }
}
