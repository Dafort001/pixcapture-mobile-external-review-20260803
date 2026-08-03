import SwiftUI
import UIKit

#if canImport(RoomPlan)
import RoomPlan
import RealityKit
#if canImport(ARKit)
import ARKit
#endif
#endif

struct RoomPlanCaptureScreen: View {
  let outputPaths: RoomPlanOutputPaths
  let roomId: String
  let floorId: String
  let trackingSessionId: String?
  let referenceOverlayImageURL: URL?
  let referenceOverlaySegmentsURL: URL?
  let onCancel: () -> Void
  let onFinished: (URL) -> Void

  @EnvironmentObject private var cameraModel: CameraManager

  @State private var isRunning = true
  @State private var isExporting = false
  @State private var exportError: String? = nil
  @State private var reviewItem: ReviewItem? = nil
  @State private var captureViewID = UUID()
  @State private var showHelp = true
  @State private var helpHideTask: Task<Void, Never>? = nil
  @State private var pendingTrackSamples: [RoomPlanTrackSample] = []
  @State private var trackingMessage: String? = nil
  @State private var isWaitingForCameraRelease = true
  @State private var reviewDismissAction: ReviewDismissAction = .none
  @State private var sessionRecoveryAttempts = 0
  @State private var sessionRecoveryTask: Task<Void, Never>? = nil
  @State private var referenceOverlayImage: UIImage? = nil
  @State private var referenceOverlaySegments: FloorplanSegmentsFile? = nil
  @State private var showReferenceOverlay = false
  @State private var transitionOverlayAutoDismissed = false
  private let maxSessionRecoveryAttempts = 2

  private enum TransitionGuidanceStyle {
    case neutral
    case warning
    case ready
  }

  private struct TransitionGuidance {
    let text: String
    let style: TransitionGuidanceStyle
    let shouldDismissOverlay: Bool
  }

  private enum ReviewDismissAction {
    case none
    case rescan
    case finish(URL)
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
          } else if reviewItem != nil || isExporting {
            Color.black
              .ignoresSafeArea()
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
            .id(captureViewID)
            .ignoresSafeArea()
          }
        } else {
          VStack(spacing: 10) {
            Image(systemName: "iphone")
              .font(.system(size: 36, weight: .semibold))
              .foregroundStyle(.white.opacity(0.85))
            Text("RoomPlan nicht verfügbar")
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(.white)
            Text("Für den Raum-Scan wird ein iPhone/iPad mit LiDAR benötigt (z.B. Pro-Modelle).")
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
        if showReferenceOverlay,
           let referenceOverlayImage,
           reviewItem == nil {
          referenceOverlayCard(image: referenceOverlayImage, guidance: transitionGuidance)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .transition(.opacity)
        }
        Spacer()
        if showHelp {
          bottomHelp
            .transition(.opacity)
        }
      }
      .padding(.horizontal, 16)
      .padding(.top, 14)
      .padding(.bottom, 24)

      if isExporting {
        exportingOverlay
      }
    }
    .fullScreenCover(item: $reviewItem) { item in
      RoomPlanReviewScreen(
        usdzURL: item.usdzURL,
        onRescan: {
          reviewDismissAction = .rescan
          reviewItem = nil
          exportError = nil
          trackingMessage = nil
          sessionRecoveryAttempts = 0
          sessionRecoveryTask?.cancel()
          sessionRecoveryTask = nil
          transitionOverlayAutoDismissed = false
          showHelp = true
          if referenceOverlayImage != nil {
            showReferenceOverlay = true
          }
          scheduleHelpAutoHide()
        },
        onContinue: {
          reviewDismissAction = .finish(item.usdzURL)
          reviewItem = nil
          exportError = nil
          trackingMessage = nil
          sessionRecoveryAttempts = 0
          sessionRecoveryTask?.cancel()
          sessionRecoveryTask = nil
        }
      )
      .interactiveDismissDisabled(true)
    }
    .onAppear {
      // RoomPlan needs exclusive camera access. Ensure our photo camera session is fully stopped first.
      cameraModel.stopSession()
      isWaitingForCameraRelease = true
      transitionOverlayAutoDismissed = false
      loadReferenceOverlayImage()
      loadReferenceOverlaySegments()
      Task { @MainActor in
        for _ in 0..<40 {
          if !cameraModel.isSessionRunning { break }
          try? await Task.sleep(nanoseconds: 50_000_000)
        }
        isWaitingForCameraRelease = false
      }
      scheduleHelpAutoHide()
    }
    .onDisappear {
      helpHideTask?.cancel()
      helpHideTask = nil
      sessionRecoveryTask?.cancel()
      sessionRecoveryTask = nil
    }
    .onChange(of: isRunning) { _, running in
      if running {
        showHelp = true
        if referenceOverlayImage != nil, !transitionOverlayAutoDismissed {
          showReferenceOverlay = true
        }
        scheduleHelpAutoHide()
      }
    }
    .onChange(of: pendingTrackSamples) { _, _ in
      updateTransitionOverlayVisibility()
    }
    .onChange(of: trackingMessage) { _, _ in
      updateTransitionOverlayVisibility()
    }
    .onChange(of: reviewItem != nil) { _, isPresented in
      guard !isPresented else { return }

      let action = reviewDismissAction
      reviewDismissAction = .none

      switch action {
      case .none:
        return
      case .rescan:
        sessionRecoveryTask?.cancel()
        sessionRecoveryTask = Task { @MainActor in
          try? await Task.sleep(nanoseconds: 350_000_000)
          guard !Task.isCancelled else { return }
          guard reviewItem == nil, !isExporting, !isWaitingForCameraRelease else { return }
          captureViewID = UUID()
          isRunning = true
        }
      case .finish(let usdzURL):
        onFinished(usdzURL)
      }
    }
  }

  private var topBar: some View {
    HStack(spacing: 12) {
      Button(action: onCancel) {
        Image(systemName: "xmark")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: 36, height: 36)
          .background(Color.black.opacity(0.4))
          .clipShape(Circle())
          .frame(width: 44, height: 44)
      }
      .accessibilityLabel("Raumscan schließen")

      VStack(alignment: .leading, spacing: 2) {
        Text("Raum-Scan (RoomPlan)")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(.white)
        Text("\(RoomTaxonomy.room(id: roomId).displayName) · \(FloorTaxonomy.floor(id: floorId).shortDisplayName)")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(.white.opacity(0.7))
          .lineLimit(1)
      }

      Spacer()

      Button(action: {
        if !isRunning {
          sessionRecoveryAttempts = 0
          exportError = nil
        }
        isRunning.toggle()
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
      .disabled(isExporting)

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

      if referenceOverlayImage != nil {
        Button {
          withAnimation(.easeInOut(duration: 0.15)) {
            showReferenceOverlay.toggle()
          }
        } label: {
          Image(systemName: showReferenceOverlay ? "square.on.square.fill" : "square.on.square")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white.opacity(showReferenceOverlay ? 0.95 : 0.75))
            .frame(width: 36, height: 36)
            .background(Color.black.opacity(0.35))
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1))
            .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Uebergangshilfe ein-/ausblenden")
        .disabled(isExporting)
      }
    }
  }

  private func referenceOverlayCard(image: UIImage, guidance: TransitionGuidance?) -> some View {
    let overlayPath = referenceOverlayPathProjection(image: image)
    let accentColor = transitionGuidanceColor(for: guidance?.style ?? .neutral)

    return VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Image(systemName: "square.on.square")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(accentColor.opacity(0.95))
        Text("Uebergang")
          .font(.system(size: 11.5, weight: .semibold))
        Spacer(minLength: 0)
      }
      .foregroundStyle(.white.opacity(0.92))

      Text(guidance?.text ?? "Starte noch im vorherigen Raum und gehe dann langsam in den neuen Raum.")
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(accentColor.opacity(guidance == nil ? 0.78 : 0.94))

      ZStack {
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
          .frame(width: 118, height: 118)

        if let overlayPath {
          Canvas { context, size in
            drawReferenceOverlayPath(
              context: &context,
              canvasSize: size,
              imageSize: image.size,
              projection: overlayPath
            )
          }
          .frame(width: 118, height: 118)
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(Color.white.opacity(0.22), lineWidth: 1)
      )

      Text("Blau = Start vorher · Weiß = deine Spur")
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(.white.opacity(0.72))
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: 164, alignment: .leading)
    .padding(10)
    .background(Color.black.opacity(0.42))
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(Color.white.opacity(0.14), lineWidth: 1)
    )
  }

  private func transitionGuidanceColor(for style: TransitionGuidanceStyle) -> Color {
    switch style {
    case .neutral:
      return trackingMessage != nil ? Color.yellow : Color.white
    case .warning:
      return Color.yellow
    case .ready:
      return Color(red: 0.23, green: 0.80, blue: 0.42)
    }
  }

  private var bottomHelp: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Kurz-Anleitung")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white)

      Text("• Starte moeglichst noch im vorherigen Raum.\n• Gehe ruhig durch den Uebergang in den neuen Raum.\n• Danach langsam Wände und Ecken zeigen.\n• Wenn das Mesh vollständig ist: Stop drücken.")
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

  private func loadReferenceOverlayImage() {
    guard let referenceOverlayImageURL,
          FileManager.default.fileExists(atPath: referenceOverlayImageURL.path),
          let image = UIImage(contentsOfFile: referenceOverlayImageURL.path) else {
      referenceOverlayImage = nil
      showReferenceOverlay = false
      return
    }
    referenceOverlayImage = image
    showReferenceOverlay = true
  }

  private func loadReferenceOverlaySegments() {
    guard let referenceOverlaySegmentsURL,
          FileManager.default.fileExists(atPath: referenceOverlaySegmentsURL.path),
          let data = try? Data(contentsOf: referenceOverlaySegmentsURL),
          let decoded = try? JSONDecoder().decode(FloorplanSegmentsFile.self, from: data) else {
      referenceOverlaySegments = nil
      return
    }
    referenceOverlaySegments = decoded.normalizedForDisplay()
  }

  private struct OverlayProjection {
    let pointsImage: [CGPoint]
    let headingImageRadians: Double?
  }

  private func referenceOverlayPathProjection(image: UIImage) -> OverlayProjection? {
    guard let segments = referenceOverlaySegments, !segments.segments.isEmpty else { return nil }
    let reliable = pendingTrackSamples.filter { $0.isTrackingReliable != false }
    guard let start = reliable.first, reliable.count >= 2 else { return nil }

    let anchorLocal = referenceAnchorLocal(segments: segments)
    let rotationOffset = referenceRotationOffset(segments: segments, startHeading: start.headingRadians, anchorLocal: anchorLocal)
    let bounds = localBounds(segments: segments.segments)
    guard bounds.maxX > bounds.minX, bounds.maxY > bounds.minY else { return nil }

    let canvasW = Double(max(1, image.size.width))
    let canvasH = Double(max(1, image.size.height))
    let padding = min(canvasW, canvasH) * 0.05
    let scale = min(
      (canvasW - padding * 2) / max(bounds.maxX - bounds.minX, 0.001),
      (canvasH - padding * 2) / max(bounds.maxY - bounds.minY, 0.001)
    )

    func toImagePoint(local: OverlayPoint) -> CGPoint {
      let x = padding + (local.x - bounds.minX) * scale
      let y = padding + (bounds.maxY - local.y) * scale
      return CGPoint(x: x, y: y)
    }

    let sx = Double(start.x)
    let sy = Double(start.y)
    let mapped: [CGPoint] = reliable.map { sample in
      let dx = Double(sample.x) - sx
      let dy = Double(sample.y) - sy
      let rx = dx * cos(rotationOffset) - dy * sin(rotationOffset)
      let ry = dx * sin(rotationOffset) + dy * cos(rotationOffset)
      return toImagePoint(local: OverlayPoint(x: anchorLocal.x + rx, y: anchorLocal.y + ry))
    }

    let headingImageRadians: Double? = reliable.last?.headingRadians.map { heading in
      // Image space has y-down, so invert y-up angle.
      -(Double(heading) + rotationOffset)
    }

    return OverlayProjection(pointsImage: mapped, headingImageRadians: headingImageRadians)
  }

  private func drawReferenceOverlayPath(
    context: inout GraphicsContext,
    canvasSize: CGSize,
    imageSize: CGSize,
    projection: OverlayProjection
  ) {
    guard projection.pointsImage.count >= 2 else { return }

    let sx = canvasSize.width / max(1, imageSize.width)
    let sy = canvasSize.height / max(1, imageSize.height)
    func map(_ point: CGPoint) -> CGPoint {
      CGPoint(x: point.x * sx, y: point.y * sy)
    }

    var path = Path()
    path.move(to: map(projection.pointsImage[0]))
    for point in projection.pointsImage.dropFirst() {
      path.addLine(to: map(point))
    }
    context.stroke(
      path,
      with: .color(Color(red: 0.99, green: 0.67, blue: 0.36).opacity(0.94)),
      style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round, dash: [5, 3])
    )

    if let first = projection.pointsImage.first {
      let p = map(first)
      let r: CGFloat = 3.4
      let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
      context.fill(Path(ellipseIn: rect), with: .color(Color(red: 0.21, green: 0.60, blue: 0.97).opacity(0.95)))
      context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.9)), lineWidth: 1)
    }

    if let last = projection.pointsImage.last {
      let p = map(last)
      let r: CGFloat = 3.8
      let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
      context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.94)))
      context.stroke(Path(ellipseIn: rect), with: .color(.black.opacity(0.6)), lineWidth: 1)

      if let angle = projection.headingImageRadians {
        let len: CGFloat = 13
        let tip = CGPoint(x: p.x + cos(angle) * len, y: p.y + sin(angle) * len)
        var arrow = Path()
        arrow.move(to: p)
        arrow.addLine(to: tip)
        context.stroke(arrow, with: .color(.white.opacity(0.96)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))

        let wing: CGFloat = 4.8
        let left = CGPoint(
          x: tip.x + cos(angle + .pi * 0.78) * wing,
          y: tip.y + sin(angle + .pi * 0.78) * wing
        )
        let right = CGPoint(
          x: tip.x + cos(angle - .pi * 0.78) * wing,
          y: tip.y + sin(angle - .pi * 0.78) * wing
        )
        var head = Path()
        head.move(to: tip)
        head.addLine(to: left)
        head.move(to: tip)
        head.addLine(to: right)
        context.stroke(head, with: .color(.white.opacity(0.96)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
      }
    }
  }

  private struct OverlayPoint {
    let x: Double
    let y: Double
  }

  private func localBounds(segments: [FloorplanSegment]) -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
    var minX = Double.greatestFiniteMagnitude
    var minY = Double.greatestFiniteMagnitude
    var maxX = -Double.greatestFiniteMagnitude
    var maxY = -Double.greatestFiniteMagnitude
    for seg in segments {
      minX = min(minX, seg.ax, seg.bx)
      minY = min(minY, seg.ay, seg.by)
      maxX = max(maxX, seg.ax, seg.bx)
      maxY = max(maxY, seg.ay, seg.by)
    }
    if !minX.isFinite || !minY.isFinite || !maxX.isFinite || !maxY.isFinite {
      return (0, 0, 1, 1)
    }
    return (minX, minY, maxX, maxY)
  }

  private func referenceAnchorLocal(segments: FloorplanSegmentsFile) -> OverlayPoint {
    if let hint = segments.entryPassageHint, let seg = segmentForHint(segments: segments, hint: hint) {
      return OverlayPoint(x: (seg.ax + seg.bx) * 0.5, y: (seg.ay + seg.by) * 0.5)
    }
    return centroidLocal(segments: segments.segments)
  }

  private func segmentForHint(segments: FloorplanSegmentsFile, hint: FloorplanEntryPassageHint) -> FloorplanSegment? {
    switch hint.kind {
    case "door":
      guard let doors = segments.doors, doors.indices.contains(hint.index) else { return nil }
      return doors[hint.index]
    case "opening":
      guard let openings = segments.openings, openings.indices.contains(hint.index) else { return nil }
      return openings[hint.index]
    default:
      return nil
    }
  }

  private func centroidLocal(segments: [FloorplanSegment]) -> OverlayPoint {
    guard !segments.isEmpty else { return OverlayPoint(x: 0, y: 0) }
    var sumX = 0.0
    var sumY = 0.0
    var count = 0.0
    for seg in segments {
      sumX += seg.ax + seg.bx
      sumY += seg.ay + seg.by
      count += 2
    }
    guard count > 0 else { return OverlayPoint(x: 0, y: 0) }
    return OverlayPoint(x: sumX / count, y: sumY / count)
  }

  private func referenceRotationOffset(
    segments: FloorplanSegmentsFile,
    startHeading: Float?,
    anchorLocal: OverlayPoint
  ) -> Double {
    guard let startHeading else { return 0 }

    let centroid = centroidLocal(segments: segments.segments)
    var vx = anchorLocal.x - centroid.x
    var vy = anchorLocal.y - centroid.y
    let len = (vx * vx + vy * vy).squareRoot()
    if len <= 1e-6 {
      vx = 1
      vy = 0
    } else {
      vx /= len
      vy /= len
    }

    let outwardAngle = atan2(vy, vx)
    return normalizeAngle(outwardAngle - Double(startHeading))
  }

  private func normalizeAngle(_ value: Double) -> Double {
    var v = value
    while v > Double.pi { v -= 2 * Double.pi }
    while v < -Double.pi { v += 2 * Double.pi }
    return v
  }

  private func detectPreviousRoomExitHint(
    referenceSegments: FloorplanSegmentsFile?,
    samples: [RoomPlanTrackSample]
  ) -> FloorplanEntryPassageHint? {
    guard let referenceSegments else { return nil }
    let reliable = samples.filter { $0.isTrackingReliable != false }
    guard let start = reliable.first else { return nil }

    let early = reliable.filter { sample in
      let elapsed = sample.timestamp - start.timestamp
      let dx = Double(sample.x - start.x)
      let dy = Double(sample.y - start.y)
      let distance = (dx * dx + dy * dy).squareRoot()
      return elapsed <= 1.9 && distance <= 1.85
    }
    guard early.count >= 3 else { return nil }

    let anchorLocal = referenceAnchorLocal(segments: referenceSegments)
    let rotationOffset = referenceRotationOffset(
      segments: referenceSegments,
      startHeading: start.headingRadians,
      anchorLocal: anchorLocal
    )

    let mappedPoints: [CGPoint] = early.map { sample in
      let dx = Double(sample.x - start.x)
      let dy = Double(sample.y - start.y)
      let rx = dx * cos(rotationOffset) - dy * sin(rotationOffset)
      let ry = dx * sin(rotationOffset) + dy * cos(rotationOffset)
      return CGPoint(x: anchorLocal.x + rx, y: anchorLocal.y + ry)
    }
    return RoomPlanAutoDockHintDetector.detectHint(
      points: mappedPoints,
      doors: referenceSegments.doors ?? [],
      openings: referenceSegments.openings ?? []
    )
  }

  private var transitionGuidance: TransitionGuidance? {
    guard referenceOverlayImage != nil else { return nil }

    if !isRunning {
      return TransitionGuidance(
        text: "Starte noch im vorherigen Raum und gehe dann langsam in den neuen Raum.",
        style: .neutral,
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
        text: "Tracking unsicher. Bitte kurz in den vorherigen Raum zurück und den Übergang langsamer erneut gehen.",
        style: .warning,
        shouldDismissOverlay: false
      )
    }

    if recentSpeed > 1.15 {
      return TransitionGuidance(
        text: "Zu schnell gegangen. Bitte kurz zurück und langsamer erneut in den neuen Raum gehen.",
        style: .warning,
        shouldDismissOverlay: false
      )
    }

    if elapsed > 5.0 && distanceMeters < 0.20 {
      return TransitionGuidance(
        text: "Du bist noch kaum durch den Übergang gegangen. Starte weiter hinten im vorherigen Raum.",
        style: .neutral,
        shouldDismissOverlay: false
      )
    }

    if distanceMeters >= 0.95 && elapsed >= 1.4 {
      return TransitionGuidance(
        text: "Übergang erkannt. Jetzt normal im neuen Raum weiter scannen.",
        style: .ready,
        shouldDismissOverlay: distanceMeters >= 1.25 && elapsed >= 2.0 && recentSpeed <= 1.0
      )
    }

    if distanceMeters >= 0.35 {
      return TransitionGuidance(
        text: "Gut. Jetzt ruhig weiter in den neuen Raum gehen.",
        style: .neutral,
        shouldDismissOverlay: false
      )
    }

    return TransitionGuidance(
      text: "Noch im Übergang. Richte dich am vorherigen Raum aus und gehe ruhig auf die Tür zu.",
      style: .neutral,
      shouldDismissOverlay: false
    )
  }

  private func updateTransitionOverlayVisibility() {
    guard !transitionOverlayAutoDismissed,
          showReferenceOverlay,
          transitionGuidance?.shouldDismissOverlay == true else { return }
    withAnimation(.easeInOut(duration: 0.2)) {
      showReferenceOverlay = false
      transitionOverlayAutoDismissed = true
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

#if canImport(RoomPlan)
  private func exportCapturedRoom(_ data: CapturedRoomData) {
    sessionRecoveryTask?.cancel()
    sessionRecoveryTask = nil
    sessionRecoveryAttempts = 0
    isExporting = true
    exportError = nil
    isRunning = false

    Task { @MainActor in
      do {
        if FileManager.default.fileExists(atPath: outputPaths.usdz.path) {
          try? FileManager.default.removeItem(at: outputPaths.usdz)
        }
        if FileManager.default.fileExists(atPath: outputPaths.floorplanPNG.path) {
          try? FileManager.default.removeItem(at: outputPaths.floorplanPNG)
        }
        if FileManager.default.fileExists(atPath: outputPaths.segmentsJSON.path) {
          try? FileManager.default.removeItem(at: outputPaths.segmentsJSON)
        }
        if FileManager.default.fileExists(atPath: outputPaths.capturedRoomDataJSON.path) {
          try? FileManager.default.removeItem(at: outputPaths.capturedRoomDataJSON)
        }
        if FileManager.default.fileExists(atPath: outputPaths.capturedRoomJSON.path) {
          try? FileManager.default.removeItem(at: outputPaths.capturedRoomJSON)
        }

        // RoomPlan processing + export can take a moment.
        // We build a CapturedRoom from the raw session output, then export a USDZ mesh for quick review + backend scaling.
        let builder = RoomBuilder(options: [])
        let capturedRoom = try await builder.capturedRoom(from: data)

        // Use AR tracking path to guess which passage the user entered through.
        // This keeps UI simple while improving auto-docking reliability.
        let hint = RoomPlanAutoDockHintDetector.detectEntryHint(
          capturedRoom: capturedRoom,
          samples: pendingTrackSamples
        )
        let previousRoomExitHint = detectPreviousRoomExitHint(
          referenceSegments: referenceOverlaySegments,
          samples: pendingTrackSamples
        )
        try capturedRoom.export(to: outputPaths.usdz)
        try RoomPlanFloorplanRenderer.renderPNG(capturedRoom: capturedRoom, outputURL: outputPaths.floorplanPNG)
        try RoomPlanFloorplanRenderer.writeSegmentsJSON(
          capturedRoom: capturedRoom,
          outputURL: outputPaths.segmentsJSON,
          entryPassageHint: hint,
          previousRoomExitPassageHint: previousRoomExitHint,
          trackingSessionId: trackingSessionId,
          trackingSource: trackingSessionId == nil ? nil : .roomSequenceSharedWorld
        )
        RoomPlanStructureMergeService.saveCapturedArtifactsBestEffort(
          data: data,
          room: capturedRoom,
          outputPaths: outputPaths
        )
        reviewItem = ReviewItem(usdzURL: outputPaths.usdz)
      } catch {
        exportError = error.localizedDescription
        isRunning = true
      }
      isExporting = false
    }
  }
#endif

  private func handleCaptureSessionError(_ error: Error) {
    let message = friendlyCaptureErrorMessage(error)

    guard shouldAutoRecover(from: error), sessionRecoveryAttempts < maxSessionRecoveryAttempts else {
      exportError = message
      trackingMessage = "Tracking verloren. Bitte Start drücken und langsam neu ausrichten."
      showHelp = true
      scheduleHelpAutoHide()
      return
    }

    sessionRecoveryAttempts += 1
    let attempt = sessionRecoveryAttempts

    exportError = "\(message) (Neustart \(attempt)/\(maxSessionRecoveryAttempts) …)"
    trackingMessage = "Tracking verloren. Scan wird neu gestartet."
    showHelp = true
    scheduleHelpAutoHide()

    isRunning = false
    captureViewID = UUID()

    sessionRecoveryTask?.cancel()
    sessionRecoveryTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 900_000_000)
      guard !Task.isCancelled else { return }
      guard !isExporting, reviewItem == nil else { return }
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
}
