import SwiftUI

struct PanoramaTourView: View {
  var onNavigate: (AppScreen) -> Void

  @EnvironmentObject private var settings: AppSettings
  @StateObject private var recorder = PanoramaTourRecorder()
  @State private var countdownValue: Int?
  @State private var countdownTask: Task<Void, Never>?
  @State private var latestExportBundle: PanoramaTourRecorder.ExportBundle?
  @State private var shareItems: [Any] = []
  @State private var showShareSheet = false

  private var hasProjectContext: Bool {
    let key = settings.selectedJobId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return !key.isEmpty
  }

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        Color.black.ignoresSafeArea()

        if let previewImage = recorder.previewImage {
          Image(decorative: previewImage, scale: 1.0)
            .resizable()
            .scaledToFill()
            .ignoresSafeArea()
        } else {
          Color.black.ignoresSafeArea()
        }

        markerOverlay(in: proxy.size)

        VStack(spacing: 14) {
          topBar
          Spacer()
          bottomPanel
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 24)

        if let countdownValue {
          countdownOverlay(countdownValue)
        }
      }
      .onAppear {
        recorder.setFloorplanProjectKey(settings.selectedJobId)
        recorder.updateViewportSize(proxy.size)
        recorder.startSession()
      }
      .onDisappear {
        countdownTask?.cancel()
        countdownTask = nil
        recorder.stopSession()
      }
      .onChange(of: proxy.size) { _, newSize in
        recorder.updateViewportSize(newSize)
      }
      .onChange(of: settings.selectedJobId) { _, newValue in
        recorder.setFloorplanProjectKey(newValue)
      }
      .sheet(isPresented: $showShareSheet) {
        ShareSheet(activityItems: shareItems)
      }
    }
  }

  private var topBar: some View {
    HStack(spacing: 12) {
      Button(action: {
        countdownTask?.cancel()
        countdownTask = nil
        onNavigate(.start)
      }) {
        Image(systemName: "chevron.left")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: 36, height: 36)
          .background(Color.black.opacity(0.45))
          .clipShape(Circle())
          .frame(width: 44, height: 44)
      }
      .accessibilityLabel("Zur Startseite")

      VStack(alignment: .leading, spacing: 2) {
        Text("360° Panorama Tour")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(.white)
        Text(recorder.isRecording ? "AR + Video laufen" : "Bereit")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(.white.opacity(0.72))
      }

      Spacer()

      if recorder.isRecording {
        Text(String(format: "%.1fs", recorder.durationSeconds))
          .font(.system(size: 12, weight: .semibold, design: .monospaced))
          .foregroundStyle(.white)
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(Color.red.opacity(0.72))
          .clipShape(Capsule())
      }
    }
  }

  private var bottomPanel: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        Text("Codec: \(recorder.writerProfileLabel)")
        Text("Grundriss: \(currentFloorplanProjectKey)")
        if let markerId = recorder.lastTriggerMarkerId,
           let timestamp = recorder.lastTriggerTimestamp {
          Text("Spot \(markerId) @ \(String(format: "%.2f", timestamp))s")
        }
      }
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(Color.white.opacity(0.82))

      if let warning = recorder.warningMessage, !warning.isEmpty {
        Text(warning)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Color.orange.opacity(0.95))
          .fixedSize(horizontal: false, vertical: true)
      }

      if !hasProjectContext {
        Text("Bitte zuerst einen Job waehlen, bevor du eine Panorama-Tour aufnimmst.")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Color.orange.opacity(0.95))
          .fixedSize(horizontal: false, vertical: true)
      }

      HStack(spacing: 12) {
        Button {
          recorder.markHighResSpot()
        } label: {
          Label("High-Res Spot", systemImage: "flag.checkered")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.blue.opacity(0.82))
            .clipShape(Capsule())
        }
        .disabled(!recorder.isRecording)
        .opacity(recorder.isRecording ? 1 : 0.45)

        Spacer()

        Button(action: toggleRecording) {
          ZStack {
            Circle()
              .fill(recorder.isRecording ? Color.red : Color.white)
              .frame(width: 64, height: 64)
            Circle()
              .stroke(Color.white.opacity(0.6), lineWidth: 4)
              .frame(width: 78, height: 78)
          }
        }
        .disabled(countdownValue != nil || !hasProjectContext)
        .opacity(hasProjectContext ? 1 : 0.45)

        Spacer()

        Button {
          guard let latestExportBundle else { return }
          shareItems = [latestExportBundle.bundleURL]
          showShareSheet = true
        } label: {
          Label("Export", systemImage: "square.and.arrow.up")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.6))
            .clipShape(Capsule())
            .overlay(
              Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
        }
        .disabled(latestExportBundle == nil)
        .opacity(latestExportBundle == nil ? 0.45 : 1)
      }

      BottomNavBar(selected: .panorama) { tab in
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
      .padding(.top, 2)
    }
    .padding(12)
    .background(Color.black.opacity(0.46))
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(Color.white.opacity(0.14), lineWidth: 1)
    )
  }

  @ViewBuilder
  private func markerOverlay(in size: CGSize) -> some View {
    ZStack {
      ForEach(recorder.markerOverlays) { marker in
        let rect = markerRect(marker.boundingBox, in: size)
        RoundedRectangle(cornerRadius: 8)
          .stroke(marker.isAnchored ? Color.green : Color.yellow, lineWidth: 2)
          .frame(width: rect.width, height: rect.height)
          .position(x: rect.midX, y: rect.midY)

        Text(marker.markerId)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background((marker.isAnchored ? Color.green : Color.orange).opacity(0.8))
          .clipShape(Capsule())
          .position(x: rect.midX, y: max(14, rect.minY - 10))
      }
    }
    .allowsHitTesting(false)
  }

  private func markerRect(_ normalized: CGRect, in size: CGSize) -> CGRect {
    let width = normalized.width * size.width
    let height = normalized.height * size.height
    let x = normalized.minX * size.width
    let y = (1 - normalized.maxY) * size.height
    return CGRect(x: x, y: y, width: width, height: height)
  }

  private var currentFloorplanProjectKey: String {
    let key = settings.selectedJobId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return key.isEmpty ? "Kein Job" : key
  }

  private func toggleRecording() {
    if recorder.isRecording {
      countdownTask?.cancel()
      countdownTask = nil
      recorder.stopRecording { result in
        switch result {
        case .success(let bundle):
          latestExportBundle = bundle
        case .failure(let error):
          recorder.warningMessage = error.localizedDescription
        }
      }
      return
    }

    guard hasProjectContext else { return }
    guard countdownTask == nil else { return }
    countdownTask = Task { @MainActor in
      for value in stride(from: 3, through: 1, by: -1) {
        if Task.isCancelled {
          countdownValue = nil
          countdownTask = nil
          return
        }
        countdownValue = value
        try? await Task.sleep(nanoseconds: 700_000_000)
      }
      countdownValue = nil
      recorder.startRecording()
      countdownTask = nil
    }
  }

  private func countdownOverlay(_ value: Int) -> some View {
    VStack(spacing: 10) {
      Text("Aufnahme startet in")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.white.opacity(0.9))
      Text("\(value)")
        .font(.system(size: 72, weight: .heavy, design: .rounded))
        .foregroundStyle(.white)
    }
    .padding(.horizontal, 26)
    .padding(.vertical, 18)
    .background(Color.black.opacity(0.62))
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(Color.white.opacity(0.22), lineWidth: 1)
    )
  }
}
