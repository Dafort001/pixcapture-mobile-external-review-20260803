import AVFoundation
import SwiftUI
import UIKit

struct MainVideoCaptureScreen: View {
  let projectId: UUID
  let takeId: UUID
  let captureKind: VideoCaptureKind
  let roomId: String
  let floorId: String
  let onCancel: () -> Void
  let onFinished: (VideoCaptureTake) -> Void

  @StateObject private var recorder = VideoTakeRecorder()
  @EnvironmentObject private var settings: AppSettings
  @EnvironmentObject private var cameraModel: CameraManager
  @State private var isPreparing = true
  @State private var capturePaths: VideoCapturePaths? = nil
  @State private var selectedZoom: Double = 1.0
  @State private var framingGuide: FramingGuide = .portrait9x16
  @State private var reviewItem: ReviewItem? = nil
  @State private var showHelp = true
  @State private var helpHideTask: Task<Void, Never>? = nil
  @State private var prepareTask: Task<Void, Never>? = nil
  @State private var countdownValue: Int? = nil
  @State private var countdownTask: Task<Void, Never>? = nil
  @State private var didSignalLiveRecording = false
  @State private var showRecordingStartedBanner = false
  @State private var recordingStartedBannerTask: Task<Void, Never>? = nil

  private var isPad: Bool {
    UIDevice.current.userInterfaceIdiom == .pad
  }

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      if recorder.isARPipelineActive {
        if let arPreviewImage = recorder.arPreviewImage {
          Image(decorative: arPreviewImage, scale: 1.0)
            .resizable()
            .scaledToFill()
            .ignoresSafeArea()
        } else {
          Color.black.ignoresSafeArea()
        }
      } else {
        CameraPreviewView(session: recorder.session)
          .ignoresSafeArea()
      }

      if let target = framingGuide.targetAspectRatio {
        AspectMaskOverlay(
          baseAspectRatio: FramingGuide.baseAspectRatio,
          targetAspectRatio: target
        )
        .ignoresSafeArea()
      }

      VStack(spacing: isPad ? 14 : 10) {
        topBar
          .frame(maxWidth: isPad ? 920 : .infinity, alignment: .leading)
        Spacer()
        bottomPanel
          .frame(maxWidth: isPad ? 920 : .infinity, alignment: .leading)
      }
      .frame(maxWidth: .infinity)
      .padding(.horizontal, isPad ? 28 : 16)
      .padding(.top, isPad ? 20 : 14)
      .padding(.bottom, isPad ? 32 : 24)

      if isPreparing {
        ProgressView()
          .tint(.white)
      }

      if let countdownValue {
        countdownOverlay(value: countdownValue)
      } else if recorder.isRecording && recorder.durationSeconds <= 0 {
        syncOverlay
      } else if showRecordingStartedBanner {
        recordingStartedOverlay
      }
    }
    .onAppear {
      recorder.setVideoStabilizationEnabled(settings.videoStabilizationEnabled)
      prepare()
      scheduleHelpAutoHide()
    }
    .onDisappear {
      prepareTask?.cancel()
      prepareTask = nil
      helpHideTask?.cancel()
      helpHideTask = nil
      countdownTask?.cancel()
      countdownTask = nil
      recordingStartedBannerTask?.cancel()
      recordingStartedBannerTask = nil
      recorder.stopSession()
    }
    .onChange(of: selectedZoom) { _, newValue in
      guard abs(newValue - recorder.currentZoomFactor) > 0.05 else { return }
      recorder.setZoomFactor(newValue)
    }
    .onReceive(recorder.$currentZoomFactor) { zoom in
      guard abs(selectedZoom - zoom) > 0.05 else { return }
      selectedZoom = zoom
    }
    .onChange(of: settings.videoStabilizationEnabled) { _, enabled in
      recorder.setVideoStabilizationEnabled(enabled)
    }
    .onReceive(recorder.$isRecording) { isRecording in
      if !isRecording {
        didSignalLiveRecording = false
        showRecordingStartedBanner = false
        recordingStartedBannerTask?.cancel()
        recordingStartedBannerTask = nil
      }
    }
    .onReceive(recorder.$durationSeconds) { duration in
      guard recorder.isRecording else { return }
      guard !didSignalLiveRecording else { return }
      guard duration > 0.0001 else { return }
      didSignalLiveRecording = true
      UINotificationFeedbackGenerator().notificationOccurred(.success)
      showRecordingStartedBanner = true
      recordingStartedBannerTask?.cancel()
      recordingStartedBannerTask = Task { @MainActor in
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        showRecordingStartedBanner = false
        recordingStartedBannerTask = nil
      }
    }
    .fullScreenCover(item: $reviewItem) { item in
      MainVideoReviewScreen(
        videoURL: item.videoURL,
        onDiscard: {
          discardRecording(item)
          reviewItem = nil
        },
        onContinue: {
          Task {
            let duration = await videoDurationSeconds(url: item.videoURL)
            await MainActor.run {
              onFinished(
                VideoCaptureTake(
                  id: takeId,
                  createdAt: Date(),
                  kind: captureKind,
                  roomId: RoomTaxonomy.normalizedRoomId(roomId),
                  floorId: FloorTaxonomy.normalizedFloorId(floorId),
                  videoRelativePath: item.videoRelativePath,
                  motionRelativePath: item.motionRelativePath,
                  intrinsicsRelativePath: item.intrinsicsRelativePath,
                  trackingRelativePath: item.trackingRelativePath,
                  durationSeconds: duration
                )
              )
            }
          }
        }
      )
      .interactiveDismissDisabled(false)
    }
  }

  private var topBar: some View {
    HStack(spacing: isPad ? 14 : 12) {
      Button(action: handleCancelTapped) {
        Image(systemName: "xmark")
          .font(.system(size: isPad ? 18 : 14, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: isPad ? 44 : 36, height: isPad ? 44 : 36)
          .background(Color.black.opacity(0.4))
          .clipShape(Circle())
      }

      VStack(alignment: .leading, spacing: isPad ? 3 : 2) {
        Text(String(format: l10n("video.capture.header.title.format"), captureKind.displayName))
          .font(.system(size: isPad ? 18 : 15, weight: .semibold))
          .foregroundStyle(.white)
        Text(String(format: l10n("video.capture.header.meta.format"),
                    RoomTaxonomy.room(id: roomId).displayName,
                    FloorTaxonomy.floor(id: floorId).shortDisplayName,
                    lockStatusText))
          .font(.system(size: isPad ? 14 : 12, weight: .medium))
          .foregroundStyle(.white.opacity(0.7))
          .lineLimit(1)
      }

      Spacer()

      Button {
        recorder.setPreviewLocked(!recorder.previewLocked)
      } label: {
        HStack(spacing: isPad ? 8 : 6) {
          Image(systemName: (recorder.previewLocked || recorder.isRecording) ? "lock.fill" : "lock.open")
          Text((recorder.previewLocked || recorder.isRecording)
               ? l10n("video.capture.lock.mode.fixed")
               : l10n("video.capture.lock.mode.auto"))
        }
        .font(.system(size: isPad ? 14 : 12, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, isPad ? 13 : 10)
        .padding(.vertical, isPad ? 9 : 7)
        .background(Color.black.opacity(0.35))
        .clipShape(Capsule())
        .overlay(
          Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
      }
      .disabled(recorder.isRecording || countdownValue != nil)

      Button {
        let next = !recorder.stabilizationEnabled
        settings.videoStabilizationEnabled = next
        recorder.setVideoStabilizationEnabled(next)
      } label: {
        HStack(spacing: isPad ? 8 : 6) {
          Image(systemName: recorder.stabilizationEnabled ? "camera.fill" : "gyroscope")
          VStack(alignment: .leading, spacing: isPad ? 2 : 1) {
            Text(recorder.stabilizationEnabled
                 ? l10n("video.capture.mode.handheld")
                 : l10n("video.capture.mode.gimbal"))
            Text(recorder.stabilizationEnabled
                 ? l10n("video.capture.stabilization.on")
                 : l10n("video.capture.stabilization.off"))
              .font(.system(size: isPad ? 11 : 10, weight: .medium))
              .foregroundStyle(.white.opacity(0.78))
          }
        }
        .font(.system(size: isPad ? 14 : 12, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, isPad ? 13 : 10)
        .padding(.vertical, isPad ? 9 : 7)
        .background(Color.black.opacity(0.35))
        .clipShape(Capsule())
        .overlay(
          Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
      }
      .disabled(recorder.isRecording || countdownValue != nil || !recorder.isStabilizationSupported)
      .opacity((recorder.isRecording || countdownValue != nil || !recorder.isStabilizationSupported) ? 0.45 : 1.0)

      if recorder.isRecording {
        Text(String(format: "%.1fs", recorder.durationSeconds))
          .font(.system(size: isPad ? 14 : 12, weight: .semibold, design: .monospaced))
          .foregroundStyle(.white)
          .padding(.horizontal, isPad ? 12 : 10)
          .padding(.vertical, isPad ? 8 : 6)
          .background(Color.red.opacity(0.7))
          .clipShape(Capsule())
      }

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
          .font(.system(size: isPad ? 20 : 16, weight: .semibold))
          .foregroundStyle(.white.opacity(showHelp ? 0.95 : 0.75))
          .frame(width: isPad ? 42 : 34, height: isPad ? 42 : 34)
          .background(Color.black.opacity(0.35))
          .clipShape(Circle())
          .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
      }
      .accessibilityLabel(l10n("video.capture.help.toggle.accessibility"))
    }
  }

  private var bottomPanel: some View {
    VStack(alignment: .leading, spacing: isPad ? 12 : 10) {
      if showHelp {
        Text(l10n("video.capture.help.title"))
          .font(.system(size: isPad ? 16 : 13, weight: .semibold))
          .foregroundStyle(.white)
          .transition(.opacity)

        Text(l10n("video.capture.help.body"))
          .font(.system(size: isPad ? 14 : 12))
          .foregroundStyle(.white.opacity(0.8))
          .fixedSize(horizontal: false, vertical: true)
          .transition(.opacity)
      }

      if let warning = recorder.warningMessage {
        Text(warning)
          .font(.system(size: isPad ? 14 : 12, weight: .semibold))
          .foregroundStyle(Color.orange.opacity(0.95))
          .fixedSize(horizontal: false, vertical: true)
      }

      if !recorder.isStabilizationSupported {
        Text(l10n("video.capture.warning.stabilization.unsupported"))
          .font(.system(size: isPad ? 13 : 11, weight: .semibold))
          .foregroundStyle(Color.yellow.opacity(0.92))
          .fixedSize(horizontal: false, vertical: true)
      } else {
        Text(recorder.stabilizationEnabled
             ? l10n("video.capture.gimbal.status.off")
             : l10n("video.capture.gimbal.status.on"))
          .font(.system(size: isPad ? 13 : 11, weight: .semibold))
          .foregroundStyle(Color.white.opacity(0.82))
          .fixedSize(horizontal: false, vertical: true)
      }

      if recorder.isRecording {
        motionGuidePanel
      }

      Text(String(format: l10n("video.capture.kind.format"), captureKind.displayName))
        .font(.system(size: isPad ? 13 : 11, weight: .semibold))
        .foregroundStyle(Color.white.opacity(0.8))

      zoomSelector
        .frame(maxWidth: .infinity, alignment: .center)

      framingSelector
        .frame(maxWidth: .infinity, alignment: .center)

      HStack(spacing: 12) {
        Spacer()
        Button(action: toggleRecording) {
          ZStack {
            Circle()
              .fill(recorder.isRecording ? Color.red : Color.white)
              .frame(width: isPad ? 84 : 64, height: isPad ? 84 : 64)
            Circle()
              .stroke(Color.white.opacity(0.6), lineWidth: isPad ? 5 : 4)
              .frame(width: isPad ? 102 : 78, height: isPad ? 102 : 78)
          }
        }
        .disabled(capturePaths == nil || countdownValue != nil)
        Spacer()
      }
    }
    .padding(isPad ? 16 : 12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.black.opacity(0.45))
    .clipShape(RoundedRectangle(cornerRadius: isPad ? 18 : 14, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: isPad ? 18 : 14, style: .continuous)
        .stroke(Color.white.opacity(0.14), lineWidth: 1)
    )
  }

  private var motionGuidePanel: some View {
    let state = recorder.motionGuideState
    let iconSize: CGFloat = isPad ? 18 : 13
    let topInset: CGFloat = isPad ? 2 : 1
    let titleSize: CGFloat = isPad ? 16 : 12
    let detailSize: CGFloat = isPad ? 14 : 11
    let panelPadding: CGFloat = isPad ? 14 : 10
    let cornerRadius: CGFloat = isPad ? 14 : 10
    let spacing: CGFloat = isPad ? 12 : 8

    return HStack(alignment: .top, spacing: spacing) {
      Image(systemName: motionGuideIcon(for: state))
        .font(.system(size: iconSize, weight: .semibold))
        .foregroundStyle(motionGuideColor(for: state))
        .padding(.top, topInset)

      VStack(alignment: .leading, spacing: isPad ? 4 : 2) {
        Text("Bewegungs-Coach: \(state.titleText)")
          .font(.system(size: titleSize, weight: .semibold))
          .foregroundStyle(.white)
        Text(state.detailText)
          .font(.system(size: detailSize, weight: .medium))
          .foregroundStyle(Color.white.opacity(0.84))
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .padding(panelPadding)
    .frame(maxWidth: isPad ? 640 : .infinity, alignment: .leading)
    .background(motionGuideColor(for: state).opacity(0.22))
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .stroke(motionGuideColor(for: state).opacity(0.65), lineWidth: isPad ? 1.3 : 1)
    )
  }

  private func motionGuideIcon(for state: VideoTakeRecorder.MotionGuideState) -> String {
    switch state {
    case .stable:
      return "checkmark.shield"
    case .tooFast:
      return "hare.fill"
    case .tooSlow:
      return "tortoise.fill"
    case .tooRocky:
      return "waveform.path.ecg"
    }
  }

  private func motionGuideColor(for state: VideoTakeRecorder.MotionGuideState) -> Color {
    switch state {
    case .stable:
      return .green
    case .tooFast:
      return .orange
    case .tooSlow:
      return .yellow
    case .tooRocky:
      return .red
    }
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

  private var zoomSelector: some View {
    HStack(spacing: isPad ? 12 : 10) {
      ForEach(recorder.zoomPresets, id: \.self) { zoom in
        zoomButton(zoom)
      }
    }
    .padding(.horizontal, isPad ? 16 : 12)
    .padding(.vertical, isPad ? 8 : 6)
    .background(Color.black.opacity(0.15))
    .clipShape(Capsule())
  }

  private var framingSelector: some View {
    HStack(spacing: isPad ? 12 : 10) {
      ForEach(FramingGuide.allCases, id: \.self) { guide in
        Button {
          framingGuide = guide
        } label: {
          Text(guide.label)
            .font(.system(size: isPad ? 13 : 11, weight: .semibold))
            .foregroundStyle(framingGuide == guide ? Color.black : Color.white)
            .padding(.horizontal, isPad ? 14 : 10)
            .padding(.vertical, isPad ? 10 : 8)
            .background(framingGuide == guide ? Color.white : Color.black.opacity(0.35))
            .clipShape(Capsule())
            .overlay(
              Capsule().stroke(Color.white.opacity(framingGuide == guide ? 0 : 0.2), lineWidth: 1)
            )
        }
        .disabled(recorder.isRecording || countdownValue != nil)
      }
    }
    .padding(.horizontal, isPad ? 16 : 12)
    .padding(.vertical, isPad ? 8 : 6)
    .background(Color.black.opacity(0.15))
    .clipShape(Capsule())
  }

  private var lockStatusText: String {
    let locked = recorder.isRecording || recorder.previewLocked
    return locked
      ? l10n("video.capture.lockstatus.locked")
      : l10n("video.capture.lockstatus.auto")
  }

  private func zoomButton(_ value: Double) -> some View {
    return Button(action: { selectedZoom = value }) {
      Text(zoomLabel(value))
        .font(.system(size: isPad ? 13 : 11, weight: .semibold))
        .lineLimit(1)
        .foregroundStyle(abs(selectedZoom - value) < 0.05 ? Color.black : Color.white)
        .frame(width: isPad ? 44 : 32, height: isPad ? 44 : 32)
        .background(abs(selectedZoom - value) < 0.05 ? Color.yellow : Color.black.opacity(0.5))
        .clipShape(Circle())
    }
    .disabled(recorder.isRecording || countdownValue != nil)
  }

  private func zoomLabel(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.minimumIntegerDigits = 1
    formatter.maximumFractionDigits = value == floor(value) ? 0 : 1
    formatter.minimumFractionDigits = value == floor(value) ? 0 : 1
    let number = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    return "\(number)x"
  }

  private func prepare() {
    isPreparing = true
    do {
      capturePaths = try VideoProjectStore.createCapturePaths(projectId: projectId, takeId: takeId)
    } catch {
      recorder.warningMessage = error.localizedDescription
    }
    cameraModel.stopSession()
    prepareTask?.cancel()
    prepareTask = Task { @MainActor in
      // Wait for shared photo session to stop before starting video capture.
      for _ in 0..<40 {
        if !cameraModel.isSessionRunning { break }
        try? await Task.sleep(nanoseconds: 50_000_000)
      }
      recorder.configureIfNeeded()
      try? await Task.sleep(nanoseconds: 200_000_000)
      isPreparing = false
      prepareTask = nil
    }
  }

  private func toggleRecording() {
    guard let capturePaths else { return }
    if recorder.isRecording {
      countdownTask?.cancel()
      countdownTask = nil
      recorder.stopRecording { result in
        switch result {
        case .success(let res):
          reviewItem = ReviewItem(
            videoURL: res.videoURL,
            motionCSVURL: res.motionCSVURL,
            intrinsicsJSONURL: res.intrinsicsJSONURL,
            trackingJSONURL: res.trackingJSONURL,
            videoRelativePath: capturePaths.videoRelativePath,
            motionRelativePath: capturePaths.motionRelativePath,
            intrinsicsRelativePath: capturePaths.intrinsicsRelativePath,
            trackingRelativePath: capturePaths.trackingRelativePath
          )
        case .failure(let error):
          recorder.warningMessage = error.localizedDescription
        }
      }
      return
    }

    guard countdownTask == nil else { return }
    startRecordingAfterCountdown(capturePaths)
  }

  private func handleCancelTapped() {
    countdownTask?.cancel()
    countdownTask = nil
    recordingStartedBannerTask?.cancel()
    recordingStartedBannerTask = nil
    onCancel()
  }

  private func startRecordingAfterCountdown(_ capturePaths: VideoCapturePaths) {
    didSignalLiveRecording = false
    countdownTask?.cancel()
    countdownTask = Task { @MainActor in
      let feedback = UIImpactFeedbackGenerator(style: .medium)
      for step in stride(from: 3, through: 1, by: -1) {
        if Task.isCancelled {
          countdownValue = nil
          countdownTask = nil
          return
        }
        countdownValue = step
        feedback.impactOccurred()
        try? await Task.sleep(nanoseconds: 700_000_000)
      }
      countdownValue = nil
      recorder.startRecording(
        videoURL: capturePaths.videoURL,
        motionCSVURL: capturePaths.motionCSVURL,
        intrinsicsJSONURL: capturePaths.intrinsicsJSONURL,
        trackingJSONURL: capturePaths.trackingJSONURL,
        selectedZoomOverride: selectedZoom
      )
      countdownTask = nil
    }
  }

  private func countdownOverlay(value: Int) -> some View {
    VStack(spacing: 12) {
      Text(l10n("video.capture.countdown.title"))
        .font(.system(size: isPad ? 18 : 15, weight: .semibold))
        .foregroundStyle(.white.opacity(0.95))
      Text("\(value)")
        .font(.system(size: isPad ? 92 : 72, weight: .heavy, design: .rounded))
        .foregroundStyle(.white)
    }
    .padding(.horizontal, 28)
    .padding(.vertical, 20)
    .background(Color.black.opacity(0.62))
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(Color.white.opacity(0.2), lineWidth: 1)
    )
  }

  private var syncOverlay: some View {
    VStack(spacing: 10) {
      ProgressView()
        .tint(.white)
      Text(l10n("video.capture.syncing.title"))
        .font(.system(size: isPad ? 17 : 14, weight: .semibold))
        .foregroundStyle(.white.opacity(0.95))
    }
    .padding(.horizontal, 22)
    .padding(.vertical, 16)
    .background(Color.black.opacity(0.62))
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(Color.white.opacity(0.18), lineWidth: 1)
    )
  }

  private var recordingStartedOverlay: some View {
    Text(l10n("video.capture.started.banner"))
      .font(.system(size: isPad ? 16 : 13, weight: .semibold))
      .foregroundStyle(.white)
      .padding(.horizontal, 18)
      .padding(.vertical, 10)
      .background(Color.green.opacity(0.7))
      .clipShape(Capsule())
      .overlay(
        Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1)
      )
  }

  private func discardRecording(_ item: ReviewItem) {
    try? FileManager.default.removeItem(at: item.videoURL)
    try? FileManager.default.removeItem(at: item.motionCSVURL)
    try? FileManager.default.removeItem(at: item.intrinsicsJSONURL)
    try? FileManager.default.removeItem(at: item.trackingJSONURL)
    tryRemoveEmptyTakeFolder(forVideoURL: item.videoURL)
  }

  private func tryRemoveEmptyTakeFolder(forVideoURL videoURL: URL) {
    let folderURL = videoURL.deletingLastPathComponent()
    guard VideoProjectStore.isTakeFolderName(folderURL.lastPathComponent) else { return }
    try? FileManager.default.removeItem(at: folderURL)
  }

  private enum FramingGuide: CaseIterable, Hashable {
    case off
    case portrait9x16
    case landscape16x9

    static let baseAspectRatio: CGFloat = 16.0 / 9.0

    var targetAspectRatio: CGFloat? {
      switch self {
      case .off:
        return nil
      case .portrait9x16:
        return 9.0 / 16.0
      case .landscape16x9:
        return 16.0 / 9.0
      }
    }

    var label: String {
      switch self {
      case .off:
        return NSLocalizedString("video.capture.framing.off", comment: "Framing guide off")
      case .portrait9x16:
        return "9:16"
      case .landscape16x9:
        return "16:9"
      }
    }
  }

  private struct ReviewItem: Identifiable {
    let id = UUID()
    let videoURL: URL
    let motionCSVURL: URL
    let intrinsicsJSONURL: URL
    let trackingJSONURL: URL
    let videoRelativePath: String
    let motionRelativePath: String
    let intrinsicsRelativePath: String
    let trackingRelativePath: String
  }

  private func videoDurationSeconds(url: URL) async -> Double? {
    let asset = AVURLAsset(url: url)
    let duration: CMTime
    do {
      duration = try await asset.load(.duration)
    } catch {
      return nil
    }
    let seconds = duration.seconds
    guard seconds.isFinite, seconds > 0 else { return nil }
    return seconds
  }

  private func l10n(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
  }
}
