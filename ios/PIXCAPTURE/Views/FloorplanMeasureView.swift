import SwiftUI
import simd

#if canImport(ARKit) && canImport(SceneKit)
import ARKit
import SceneKit
#endif

private let floorplanMeasureGreen = Color(red: 0.28, green: 0.9, blue: 0.36)
private let floorplanMeasureOrange = Color(red: 1.0, green: 0.72, blue: 0.20)

enum FloorplanMeasurementKind: String, Codable, CaseIterable, Identifiable {
  case lengthA
  case lengthB
  case lengthC
  case lengthD
  case lengthE
  case lengthF
  case lengthG
  case lengthH

  var id: String { rawValue }

  var title: String {
    switch self {
    case .lengthA: return "Länge A"
    case .lengthB: return "Länge B"
    case .lengthC: return "Länge C"
    case .lengthD: return "Länge D"
    case .lengthE: return "Länge E"
    case .lengthF: return "Länge F"
    case .lengthG: return "Länge G"
    case .lengthH: return "Länge H"
    }
  }

  var iconName: String {
    "ruler"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let rawValue = try container.decode(String.self)
    switch rawValue {
    case "lengthA", "doorWidth":
      self = .lengthA
    case "lengthB", "entranceWidth":
      self = .lengthB
    case "lengthC", "wallHeight":
      self = .lengthC
    case "lengthD", "roomHeight":
      self = .lengthD
    case "lengthE", "custom":
      self = .lengthE
    case "lengthF":
      self = .lengthF
    case "lengthG":
      self = .lengthG
    case "lengthH":
      self = .lengthH
    default:
      self = .lengthA
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

struct FloorplanMeasurementRecord: Codable, Identifiable, Equatable {
  let id: UUID
  let createdAt: Date
  let projectKey: String
  let kind: FloorplanMeasurementKind
  let label: String
  let note: String?
  let distanceMeters: Double
  let pointAWorldMeters: [Double]
  let pointBWorldMeters: [Double]

  enum CodingKeys: String, CodingKey {
    case id
    case createdAt = "created_at"
    case projectKey = "project_key"
    case kind
    case label
    case note
    case distanceMeters = "distance_meters"
    case pointAWorldMeters = "point_a_world_meters"
    case pointBWorldMeters = "point_b_world_meters"
  }
}

private struct FloorplanMeasurePoint: Identifiable, Equatable {
  let id: UUID
  let label: String
  let worldPositionMeters: SIMD3<Float>
  let cameraPositionMeters: SIMD3<Float>?
  let screenPositionNormalized: [Double]
  let trackingQuality: String
  let source: String

  init(
    id: UUID = UUID(),
    label: String,
    worldPositionMeters: SIMD3<Float>,
    cameraPositionMeters: SIMD3<Float>? = nil,
    screenPositionNormalized: [Double] = [0.5, 0.5],
    trackingQuality: String = "unknown",
    source: String
  ) {
    self.id = id
    self.label = label
    self.worldPositionMeters = worldPositionMeters
    self.cameraPositionMeters = cameraPositionMeters
    self.screenPositionNormalized = screenPositionNormalized
    self.trackingQuality = trackingQuality
    self.source = source
  }

  func withLabel(_ nextLabel: String) -> FloorplanMeasurePoint {
    FloorplanMeasurePoint(
      id: id,
      label: nextLabel,
      worldPositionMeters: worldPositionMeters,
      cameraPositionMeters: cameraPositionMeters,
      screenPositionNormalized: screenPositionNormalized,
      trackingQuality: trackingQuality,
      source: source
    )
  }
}

struct FloorplanMeasureView: View {
  let projectKey: String?
  let onDone: () -> Void

  init(projectKey: String? = nil, onDone: @escaping () -> Void) {
    self.projectKey = projectKey
    self.onDone = onDone
  }

  @State private var captureRequestID = 0
  @State private var points: [FloorplanMeasurePoint] = []
  @State private var liveProbePoint: FloorplanMeasurePoint?
  @State private var liveReticlePositionNormalized = [0.5, 0.5]
  @State private var liveReticleAspect = 1.0
  @State private var liveReticleRotationDegrees = 0.0
  @State private var projectedPointsNormalized: [UUID: [Double]] = [:]
  @State private var pointZoom = 1.0
  @State private var selectedKind: FloorplanMeasurementKind = .lengthA
  @State private var measurementNote = ""
  @State private var savedMeasurements: [FloorplanMeasurementRecord] = []
  @State private var statusText = "Zielpunkt auf eine Kante oder Fläche legen und + drücken."

  private var nextPointLabel: String {
    points.isEmpty ? "A" : "B"
  }

  private var distanceMeters: Double? {
    guard points.count >= 2 else { return nil }
    return Double(simd_distance(points[0].worldPositionMeters, points[1].worldPositionMeters))
  }

  private var measurementLabel: String {
    selectedKind.title
  }

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        ZStack {
          #if canImport(ARKit) && canImport(SceneKit)
          FloorplanMeasureARView(
            captureRequestID: $captureRequestID,
            pointLabel: nextPointLabel,
            points: $points,
            liveProbePoint: $liveProbePoint,
            liveReticlePositionNormalized: $liveReticlePositionNormalized,
            liveReticleAspect: $liveReticleAspect,
            liveReticleRotationDegrees: $liveReticleRotationDegrees,
            projectedPointsNormalized: $projectedPointsNormalized,
            statusText: $statusText,
            captureEnabled: points.count < 2
          )
          .ignoresSafeArea()
          #else
          Color.black.ignoresSafeArea()
          Text("AR-Messen ist auf diesem Gerät nicht verfügbar.")
            .foregroundStyle(.white)
            .padding()
          #endif

          Color.black.opacity(0.04)
            .ignoresSafeArea()
            .allowsHitTesting(false)

          measurementOverlay
          liveReticle
        }
        .scaleEffect(CGFloat(pointZoom), anchor: .center)
        .ignoresSafeArea()

        controls(in: proxy)
      }
    }
    .onAppear(perform: loadSavedMeasurements)
  }

  private func controls(in proxy: GeometryProxy) -> some View {
    VStack(spacing: 0) {
      topBar
      Spacer()
      readoutBar
      compactBottomControls
    }
    .padding(.horizontal, 18)
    .padding(.top, max(proxy.safeAreaInsets.top + 10, 58))
    .padding(.bottom, max(proxy.safeAreaInsets.bottom + 8, 16))
  }

  private var topBar: some View {
    HStack(spacing: 10) {
      measureIconButton(symbol: "xmark", action: onDone)
      VStack(alignment: .leading, spacing: 2) {
        Text("Messen")
          .font(.system(size: 20, weight: .heavy, design: .rounded))
        Text(statusText)
          .font(.system(size: 11, weight: .bold, design: .rounded))
          .foregroundStyle(.white.opacity(0.76))
          .lineLimit(1)
          .minimumScaleFactor(0.58)
      }
      .foregroundStyle(.white)
      .shadow(color: .black.opacity(0.7), radius: 5, y: 1)
      Spacer()
      measureIconButton(symbol: "trash") {
        resetMeasurement()
      }
      .disabled(points.isEmpty)
      .opacity(points.isEmpty ? 0.42 : 1)
    }
  }

  private var readoutBar: some View {
    HStack(spacing: 8) {
      Text(resultText)
        .font(.system(size: 17, weight: .heavy, design: .rounded))
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.62)
      Spacer(minLength: 8)
      pointBadge("A", isSet: points.indices.contains(0))
      pointBadge("B", isSet: points.indices.contains(1))
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(Color.black.opacity(0.52))
    .clipShape(Capsule())
    .padding(.bottom, 10)
  }

  private var compactBottomControls: some View {
    VStack(spacing: 8) {
      if distanceMeters != nil {
        saveStrip
      }

      HStack(alignment: .center, spacing: 20) {
        measureIconButton(symbol: "arrow.uturn.backward", size: 54, symbolSize: 22) {
          undoLastPoint()
        }
        .disabled(points.isEmpty)
        .opacity(points.isEmpty ? 0.42 : 1)

        Spacer()

        Button {
          addCurrentPoint()
        } label: {
          Image(systemName: points.count >= 2 ? "plus" : "plus")
            .font(.system(size: 46, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 92, height: 92)
            .background(Color.black.opacity(0.86))
            .clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(liveProbePoint == nil && points.count < 2 ? 0.28 : 0.54), lineWidth: 3))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(points.count >= 2 ? "Neue Messung" : "Punkt \(nextPointLabel) setzen")

        Spacer()

        measureIconButton(symbol: pointZoom > 1 ? "1.magnifyingglass" : "plus.magnifyingglass", size: 54, symbolSize: 21) {
          withAnimation(.easeInOut(duration: 0.16)) {
            pointZoom = pointZoom > 1 ? 1.0 : 2.0
          }
        }
        .foregroundStyle(pointZoom > 1 ? Color.black.opacity(0.82) : .white)
        .background(pointZoom > 1 ? floorplanMeasureGreen.opacity(0.96) : Color.black.opacity(0.54))
        .clipShape(Circle())
      }
    }
  }

  private var saveStrip: some View {
    HStack(spacing: 8) {
      Menu {
        ForEach(FloorplanMeasurementKind.allCases) { kind in
          Button {
            selectedKind = kind
          } label: {
            Label(kind.title, systemImage: kind.iconName)
          }
        }
      } label: {
        Label(measurementLabel, systemImage: selectedKind.iconName)
          .font(.system(size: 13, weight: .heavy, design: .rounded))
          .lineLimit(1)
          .minimumScaleFactor(0.6)
          .frame(maxWidth: .infinity, minHeight: 42)
      }
      .foregroundStyle(.white)
      .padding(.horizontal, 10)
      .background(Color.black.opacity(0.56))
      .clipShape(Capsule())

      TextField("Notiz", text: $measurementNote)
        .textInputAutocapitalization(.sentences)
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .foregroundStyle(.white)
        .tint(floorplanMeasureGreen)
        .frame(maxWidth: .infinity, minHeight: 42)
        .padding(.horizontal, 12)
        .background(Color.black.opacity(0.56))
        .clipShape(Capsule())

      Button {
        saveCurrentMeasurement()
      } label: {
        Image(systemName: "tray.and.arrow.down.fill")
          .font(.system(size: 17, weight: .heavy))
          .frame(width: 50, height: 42)
      }
      .foregroundStyle(.black.opacity(0.82))
      .background(floorplanMeasureGreen.opacity(projectKey == nil ? 0.42 : 0.96))
      .clipShape(Capsule())
      .disabled(projectKey == nil)
    }
  }

  private var measurementOverlay: some View {
    GeometryReader { proxy in
      ZStack {
        if let start = pointScreenPosition(points.first, in: proxy.size),
           let end = activeEndPosition(in: proxy.size) {
          FloorplanMeasureLineShape(start: start, end: end)
            .stroke(.white.opacity(points.count >= 2 ? 0.94 : 0.78), style: StrokeStyle(lineWidth: points.count >= 2 ? 5 : 4, lineCap: .round, dash: points.count >= 2 ? [] : [8, 7]))
          if let previewDistance = activeDistanceMeters {
            midpointLabel(
              text: distanceLabel(previewDistance),
              start: start,
              end: end,
              in: proxy.size,
              live: points.count < 2
            )
          }
        }

        ForEach(points) { point in
          if let position = pointScreenPosition(point, in: proxy.size) {
            FloorplanPointMarker(label: point.label)
              .position(position)
          }
        }
      }
      .ignoresSafeArea()
    }
    .allowsHitTesting(false)
  }

  private var liveReticle: some View {
    GeometryReader { proxy in
      let position = liveReticlePosition(in: proxy.size)
      let hasProbe = liveProbePoint != nil
      let ellipseWidth: CGFloat = 82
      let ellipseHeight = ellipseWidth * max(0.34, min(1.0, liveReticleAspect))
      ZStack {
        Ellipse()
          .trim(from: 0.08, to: 0.43)
          .stroke(.white.opacity(hasProbe ? 0.96 : 0.56), style: StrokeStyle(lineWidth: 4, lineCap: .round))
          .frame(width: ellipseWidth, height: ellipseHeight)
          .rotationEffect(.degrees(liveReticleRotationDegrees))
        Ellipse()
          .trim(from: 0.58, to: 0.93)
          .stroke(.white.opacity(hasProbe ? 0.96 : 0.56), style: StrokeStyle(lineWidth: 4, lineCap: .round))
          .frame(width: ellipseWidth, height: ellipseHeight)
          .rotationEffect(.degrees(liveReticleRotationDegrees))
        Circle()
          .fill(hasProbe ? floorplanMeasureGreen : .white.opacity(0.66))
          .frame(width: hasProbe ? 10 : 8, height: hasProbe ? 10 : 8)
        if !hasProbe && points.count < 2 {
          Text("3D-Punkt suchen")
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .foregroundStyle(.white.opacity(0.84))
            .offset(y: 72)
            .shadow(color: .black.opacity(0.72), radius: 4, y: 1)
        }
      }
      .position(position)
    }
    .allowsHitTesting(false)
  }

  private var resultText: String {
    if let distanceMeters {
      return "\(measurementLabel): \(distanceLabel(distanceMeters))"
    }
    if let liveDistance = activeDistanceMeters, points.count == 1 {
      return "Live \(distanceLabel(liveDistance))"
    }
    return points.isEmpty ? "Punkt A setzen" : "Punkt B setzen"
  }

  private var activeDistanceMeters: Double? {
    if let distanceMeters {
      return distanceMeters
    }
    guard points.count == 1, let liveProbePoint else { return nil }
    return Double(simd_distance(points[0].worldPositionMeters, liveProbePoint.worldPositionMeters))
  }

  private func activeEndPosition(in size: CGSize) -> CGPoint? {
    if points.count >= 2 {
      return pointScreenPosition(points[1], in: size)
    }
    guard points.count == 1, let liveProbePoint else { return nil }
    return pointScreenPosition(liveProbePoint, in: size)
  }

  private func addCurrentPoint() {
    if points.count >= 2 {
      resetMeasurement()
      return
    }
    if let liveProbePoint {
      appendPoint(liveProbePoint)
      return
    }
    statusText = "3D-Punkt wird am Zielpunkt gesucht."
    captureRequestID += 1
  }

  private func appendPoint(_ rawPoint: FloorplanMeasurePoint) {
    guard points.count < 2 else { return }
    let point = rawPoint.withLabel(nextPointLabel)
    points.append(point)
    liveProbePoint = nil
    if points.count == 2, let distanceMeters {
      statusText = "Messung gesetzt: \(distanceLabel(distanceMeters)). Typ wählen und speichern."
    } else {
      statusText = "Punkt A gesetzt. Jetzt Punkt B setzen."
    }
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
  }

  private func undoLastPoint() {
    guard !points.isEmpty else { return }
    points.removeLast()
    statusText = points.isEmpty ? "Punkt A setzen." : "Punkt B setzen."
  }

  private func resetMeasurement() {
    points = []
    liveProbePoint = nil
    projectedPointsNormalized = [:]
    liveReticlePositionNormalized = [0.5, 0.5]
    liveReticleAspect = 1.0
    liveReticleRotationDegrees = 0.0
    statusText = "Neue Messung: Punkt A setzen."
  }

  private func loadSavedMeasurements() {
    guard let projectKey else { return }
    savedMeasurements = (try? FloorplanProjectStore.loadMeasurements(projectKey: projectKey)) ?? []
  }

  private func saveCurrentMeasurement() {
    guard let projectKey, points.count >= 2, let distanceMeters else {
      statusText = "Erst A und B setzen."
      return
    }
    let record = FloorplanMeasurementRecord(
      id: UUID(),
      createdAt: Date(),
      projectKey: projectKey,
      kind: selectedKind,
      label: measurementLabel,
      note: measurementNote.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
      distanceMeters: distanceMeters,
      pointAWorldMeters: points[0].worldArray,
      pointBWorldMeters: points[1].worldArray
    )
    do {
      try FloorplanProjectStore.appendMeasurement(projectKey: projectKey, record: record)
      savedMeasurements = try FloorplanProjectStore.loadMeasurements(projectKey: projectKey)
      statusText = "\(record.label) gespeichert: \(distanceLabel(distanceMeters))."
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
    } catch {
      statusText = "Messung ok, Speichern fehlgeschlagen."
    }
  }

  private func pointScreenPosition(_ point: FloorplanMeasurePoint?, in size: CGSize) -> CGPoint? {
    guard let point else { return nil }
    let normalized = projectedPointsNormalized[point.id] ?? point.screenPositionNormalized
    guard normalized.count >= 2 else { return nil }
    return CGPoint(x: normalized[0] * size.width, y: normalized[1] * size.height)
  }

  private func liveReticlePosition(in size: CGSize) -> CGPoint {
    guard liveReticlePositionNormalized.count >= 2 else {
      return CGPoint(x: size.width * 0.5, y: size.height * 0.5)
    }
    return CGPoint(
      x: liveReticlePositionNormalized[0] * size.width,
      y: liveReticlePositionNormalized[1] * size.height
    )
  }

  private func midpointLabel(text: String, start: CGPoint, end: CGPoint, in size: CGSize, live: Bool) -> some View {
    let center = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
    let x = min(max(center.x, 78), max(78, size.width - 78))
    let y = min(max(center.y - 34, 54), max(54, size.height - 142))
    return Text(text)
      .font(.system(size: live ? 14 : 13, weight: .heavy, design: .rounded))
      .foregroundStyle(.white)
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .background(Color.black.opacity(live ? 0.76 : 0.68))
      .clipShape(Capsule())
      .position(x: x, y: y)
  }

  private func pointBadge(_ text: String, isSet: Bool) -> some View {
    Text(text)
      .font(.system(size: 12, weight: .heavy, design: .rounded))
      .foregroundStyle(isSet ? .black.opacity(0.82) : .white.opacity(0.68))
      .frame(width: 28, height: 28)
      .background(isSet ? floorplanMeasureGreen.opacity(0.96) : Color.white.opacity(0.16))
      .clipShape(Circle())
  }

  private func measureIconButton(symbol: String, size: CGFloat = 48, symbolSize: CGFloat = 19, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: symbolSize, weight: .heavy))
        .frame(width: size, height: size)
        .background(Color.black.opacity(0.54))
        .clipShape(Circle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(.white)
  }

  private func distanceLabel(_ meters: Double) -> String {
    let centimeters = meters * 100
    if centimeters < 100 {
      return "\(String(format: "%.1f", centimeters)) cm"
    }
    return "\(String(format: "%.2f", meters)) m"
  }
}

private extension FloorplanMeasurePoint {
  var worldArray: [Double] {
    [
      Double(worldPositionMeters.x),
      Double(worldPositionMeters.y),
      Double(worldPositionMeters.z)
    ]
  }
}

private extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}

private struct FloorplanMeasureLineShape: Shape {
  let start: CGPoint
  let end: CGPoint

  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: start)
    path.addLine(to: end)
    return path
  }
}

private struct FloorplanPointMarker: View {
  let label: String

  var body: some View {
    ZStack {
      Circle()
        .fill(floorplanMeasureGreen.opacity(0.96))
        .frame(width: 28, height: 28)
      Circle()
        .stroke(.white.opacity(0.92), lineWidth: 2)
        .frame(width: 36, height: 36)
      Text(label)
        .font(.system(size: 13, weight: .heavy, design: .rounded))
        .foregroundStyle(.black.opacity(0.82))
    }
    .shadow(color: .black.opacity(0.46), radius: 5, y: 1)
  }
}

#if canImport(ARKit) && canImport(SceneKit)
private struct FloorplanMeasureARView: UIViewRepresentable {
  @Binding var captureRequestID: Int
  let pointLabel: String
  @Binding var points: [FloorplanMeasurePoint]
  @Binding var liveProbePoint: FloorplanMeasurePoint?
  @Binding var liveReticlePositionNormalized: [Double]
  @Binding var liveReticleAspect: Double
  @Binding var liveReticleRotationDegrees: Double
  @Binding var projectedPointsNormalized: [UUID: [Double]]
  @Binding var statusText: String
  let captureEnabled: Bool

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeUIView(context: Context) -> ARSCNView {
    let view = ARSCNView(frame: .zero)
    view.automaticallyUpdatesLighting = true
    view.session.delegate = context.coordinator
    context.coordinator.sceneView = view

    let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
    view.addGestureRecognizer(tapGesture)

    let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
    panGesture.maximumNumberOfTouches = 1
    view.addGestureRecognizer(panGesture)

    let coachingOverlay = ARCoachingOverlayView()
    coachingOverlay.session = view.session
    coachingOverlay.goal = .anyPlane
    coachingOverlay.activatesAutomatically = true
    coachingOverlay.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(coachingOverlay)
    NSLayoutConstraint.activate([
      coachingOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      coachingOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      coachingOverlay.topAnchor.constraint(equalTo: view.topAnchor),
      coachingOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    ])

    if ARWorldTrackingConfiguration.isSupported {
      let configuration = ARWorldTrackingConfiguration()
      configuration.planeDetection = [.horizontal, .vertical]
      if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
        configuration.frameSemantics.insert(.smoothedSceneDepth)
      } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
        configuration.frameSemantics.insert(.sceneDepth)
      }
      view.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    } else {
      statusText = "AR-Messen ist auf diesem Gerät nicht verfügbar."
    }

    return view
  }

  func updateUIView(_ uiView: ARSCNView, context: Context) {
    context.coordinator.pointLabel = pointLabel
    context.coordinator.points = $points
    context.coordinator.liveProbePoint = $liveProbePoint
    context.coordinator.liveReticlePositionNormalized = $liveReticlePositionNormalized
    context.coordinator.liveReticleAspect = $liveReticleAspect
    context.coordinator.liveReticleRotationDegrees = $liveReticleRotationDegrees
    context.coordinator.projectedPointsNormalized = $projectedPointsNormalized
    context.coordinator.statusText = $statusText
    context.coordinator.captureEnabled = captureEnabled
    context.coordinator.syncPointNodes()
    if context.coordinator.lastCaptureRequestID != captureRequestID {
      context.coordinator.lastCaptureRequestID = captureRequestID
      DispatchQueue.main.async {
        context.coordinator.captureVisiblePoint()
      }
    }
  }

  static func dismantleUIView(_ uiView: ARSCNView, coordinator: Coordinator) {
    uiView.session.pause()
    uiView.session.delegate = nil
  }

  final class Coordinator: NSObject, ARSessionDelegate {
    weak var sceneView: ARSCNView?
    var points: Binding<[FloorplanMeasurePoint]>?
    var liveProbePoint: Binding<FloorplanMeasurePoint?>?
    var liveReticlePositionNormalized: Binding<[Double]>?
    var liveReticleAspect: Binding<Double>?
    var liveReticleRotationDegrees: Binding<Double>?
    var projectedPointsNormalized: Binding<[UUID: [Double]]>?
    var statusText: Binding<String>?
    var pointLabel = "A"
    var captureEnabled = true
    var lastCaptureRequestID = 0

    private var lastGuideUpdate = CACurrentMediaTime()
    private var lastCandidateScreenPoint: CGPoint?
    private var lastUserPointInteraction = CACurrentMediaTime()
    private var smoothedLiveProbePoint: FloorplanMeasurePoint?
    private var pointNodes: [UUID: SCNNode] = [:]
    private var lineNode: SCNNode?

    @objc func handleTap(_ sender: UITapGestureRecognizer) {
      guard captureEnabled, let view = sender.view else { return }
      let screenPoint = sender.location(in: view)
      lastCandidateScreenPoint = screenPoint
      lastUserPointInteraction = CACurrentMediaTime()
      updateReticleScreenPosition(screenPoint, in: view.bounds.size)
      guard let point = capturePoint(at: screenPoint, source: "screen_tap") else {
        statusText?.wrappedValue = "Kein stabiler 3D-Punkt. Telefon leicht bewegen oder klare Kante antippen."
        return
      }
      liveProbePoint?.wrappedValue = smoothedLivePoint(point)
      UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.55)
    }

    @objc func handlePan(_ sender: UIPanGestureRecognizer) {
      guard captureEnabled, let view = sender.view else { return }
      let screenPoint = sender.location(in: view)
      lastCandidateScreenPoint = screenPoint
      lastUserPointInteraction = CACurrentMediaTime()
      updateReticleScreenPosition(screenPoint, in: view.bounds.size)
      guard let point = capturePoint(at: screenPoint, source: sender.state == .changed ? "screen_drag" : "screen_pan") else {
        if sender.state == .ended || sender.state == .cancelled {
          statusText?.wrappedValue = "Punkt konnte hier nicht stabil berechnet werden."
        }
        return
      }
      liveProbePoint?.wrappedValue = smoothedLivePoint(point)
    }

    func captureVisiblePoint() {
      guard captureEnabled, let sceneView else { return }
      let screenPoint = lastCandidateScreenPoint ?? CGPoint(x: sceneView.bounds.midX, y: sceneView.bounds.midY)
      lastCandidateScreenPoint = screenPoint
      updateReticleScreenPosition(screenPoint, in: sceneView.bounds.size)
      let capturedPoint = capturePoint(at: screenPoint, source: "center_plus_button")
      guard let point = capturedPoint else {
        statusText?.wrappedValue = "Kein stabiler 3D-Punkt. Telefon leicht bewegen und Zielpunkt auf eine klare Fläche legen."
        return
      }
      appendFixedPoint(point)
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
      let now = CACurrentMediaTime()
      guard now - lastGuideUpdate > 0.07 else { return }
      lastGuideUpdate = now
      DispatchQueue.main.async { [weak self] in
        self?.updateLiveProbe()
        self?.updateProjectedPoints()
      }
    }

    func syncPointNodes() {
      guard let sceneView else { return }
      let current = points?.wrappedValue ?? []
      let ids = Set(current.map(\.id))
      for (id, node) in pointNodes where !ids.contains(id) {
        node.removeFromParentNode()
        pointNodes.removeValue(forKey: id)
      }
      for point in current where pointNodes[point.id] == nil {
        let node = makePointNode(label: point.label)
        node.simdWorldPosition = point.worldPositionMeters
        sceneView.scene.rootNode.addChildNode(node)
        pointNodes[point.id] = node
      }
      updateLineNode(points: current, sceneView: sceneView)
    }

    private func appendFixedPoint(_ rawPoint: FloorplanMeasurePoint) {
      var next = points?.wrappedValue ?? []
      if next.count >= 2 {
        next.removeAll()
      }
      let fixedPoint = rawPoint.withLabel(next.isEmpty ? "A" : "B")
      next.append(fixedPoint)
      points?.wrappedValue = next
      liveProbePoint?.wrappedValue = nil
      smoothedLiveProbePoint = nil
      if next.count == 2 {
        let distance = simd_distance(next[0].worldPositionMeters, next[1].worldPositionMeters)
        statusText?.wrappedValue = "Messung gesetzt: \(Self.distanceLabel(Double(distance)))."
      } else {
        statusText?.wrappedValue = "Punkt A gesetzt. Jetzt Punkt B setzen."
      }
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func updateLiveProbe() {
      guard captureEnabled, let sceneView else {
        liveProbePoint?.wrappedValue = nil
        smoothedLiveProbePoint = nil
        return
      }
      let candidate = lastCandidateScreenPoint ?? CGPoint(x: sceneView.bounds.midX, y: sceneView.bounds.midY)
      updateReticleScreenPosition(candidate, in: sceneView.bounds.size)
      let rawPoint = capturePoint(at: candidate, source: "live_probe")
      liveProbePoint?.wrappedValue = rawPoint.map(smoothedLivePoint)
    }

    private func updateProjectedPoints() {
      guard let sceneView else {
        projectedPointsNormalized?.wrappedValue = [:]
        return
      }
      let current = points?.wrappedValue ?? []
      let width = max(sceneView.bounds.width, 1)
      let height = max(sceneView.bounds.height, 1)
      var next: [UUID: [Double]] = [:]
      for point in current {
        let projected = sceneView.projectPoint(SCNVector3(
          point.worldPositionMeters.x,
          point.worldPositionMeters.y,
          point.worldPositionMeters.z
        ))
        guard projected.x.isFinite,
              projected.y.isFinite,
              projected.z.isFinite,
              projected.z >= 0
        else { continue }
        next[point.id] = [
          Double(CGFloat(projected.x) / width),
          Double(CGFloat(projected.y) / height)
        ]
      }
      projectedPointsNormalized?.wrappedValue = next
    }

    private func capturePoint(at screenPoint: CGPoint, source: String) -> FloorplanMeasurePoint? {
      guard let sceneView, let frame = sceneView.session.currentFrame else { return nil }
      updateReticleScreenPosition(screenPoint, in: sceneView.bounds.size)

      if let point = raycastMeasuredPoint(
        at: screenPoint,
        frame: frame,
        sceneView: sceneView,
        allowing: .existingPlaneGeometry,
        alignment: .any,
        source: "\(source)_raycast_existing_plane"
      ) {
        return point
      }
      if let point = depthMeasuredPoint(at: screenPoint, frame: frame, sceneView: sceneView, source: source) {
        return point
      }
      if let point = raycastMeasuredPoint(
        at: screenPoint,
        frame: frame,
        sceneView: sceneView,
        allowing: .estimatedPlane,
        alignment: .any,
        source: "\(source)_raycast_estimated_plane"
      ) {
        return point
      }
      if let point = nearestFeatureMeasuredPoint(at: screenPoint, frame: frame, sceneView: sceneView, source: source) {
        return point
      }
      return nil
    }

    private func raycastMeasuredPoint(
      at screenPoint: CGPoint,
      frame: ARFrame,
      sceneView: ARSCNView,
      allowing target: ARRaycastQuery.Target,
      alignment: ARRaycastQuery.TargetAlignment,
      source: String
    ) -> FloorplanMeasurePoint? {
      guard
        let query = sceneView.raycastQuery(from: screenPoint, allowing: target, alignment: alignment),
        let result = sceneView.session.raycast(query).first
      else { return nil }
      updateSurfacePresentation(
        worldTransform: result.worldTransform,
        cameraTransform: frame.camera.transform,
        sceneView: sceneView
      )
      return measuredPoint(
        worldTransform: result.worldTransform,
        cameraTransform: frame.camera.transform,
        trackingState: frame.camera.trackingState,
        screenPoint: screenPoint,
        viewportSize: sceneView.bounds.size,
        sceneView: sceneView,
        source: source
      )
    }

    private func depthMeasuredPoint(
      at screenPoint: CGPoint,
      frame: ARFrame,
      sceneView: ARSCNView,
      source: String
    ) -> FloorplanMeasurePoint? {
      guard let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth else { return nil }
      let depthMap = depthData.depthMap
      CVPixelBufferLockBaseAddress(depthMap, .readOnly)
      defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
      guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return nil }

      let width = CVPixelBufferGetWidth(depthMap)
      let height = CVPixelBufferGetHeight(depthMap)
      let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
      let viewport = sceneView.bounds.size
      guard viewport.width > 0, viewport.height > 0, width > 1, height > 1 else { return nil }

      let orientation = sceneView.window?.windowScene?.interfaceOrientation ?? .portrait
      let displayTransform = frame.displayTransform(for: orientation, viewportSize: viewport)
      let normalizedViewPoint = CGPoint(x: screenPoint.x / viewport.width, y: screenPoint.y / viewport.height)
      let normalizedImagePoint = normalizedViewPoint.applying(displayTransform.inverted())
      guard normalizedImagePoint.x.isFinite, normalizedImagePoint.y.isFinite else { return nil }

      let centerX = Int((normalizedImagePoint.x * CGFloat(width)).rounded())
      let centerY = Int((normalizedImagePoint.y * CGFloat(height)).rounded())
      guard centerX >= 0, centerX < width, centerY >= 0, centerY < height else { return nil }

      struct DepthSample {
        let x: Int
        let y: Int
        let depth: Float
      }
      var samples: [DepthSample] = []
      let radius = 3
      for y in max(0, centerY - radius)...min(height - 1, centerY + radius) {
        let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float32.self)
        for x in max(0, centerX - radius)...min(width - 1, centerX + radius) {
          let depth = row[x]
          if depth.isFinite, depth > 0.08, depth < 8 {
            samples.append(DepthSample(x: x, y: y, depth: depth))
          }
        }
      }
      guard samples.count >= 4 else { return nil }
      let sortedDepths = samples.map(\.depth).sorted()
      let medianDepth = sortedDepths[sortedDepths.count / 2]
      let stableSamples = samples.filter { abs($0.depth - medianDepth) < max(0.015, medianDepth * 0.018) }
      let cluster = stableSamples.count >= 4 ? stableSamples : samples

      var weightedDepth: Float = 0
      var weightedX: Float = 0
      var weightedY: Float = 0
      var weightSum: Float = 0
      for sample in cluster {
        let dx = Float(sample.x - centerX)
        let dy = Float(sample.y - centerY)
        let screenWeight = 1 / max(1, sqrt(dx * dx + dy * dy))
        let depthWeight = 1 / max(0.002, abs(sample.depth - medianDepth) + 0.002)
        let weight = screenWeight * depthWeight
        weightedDepth += sample.depth * weight
        weightedX += Float(sample.x) * weight
        weightedY += Float(sample.y) * weight
        weightSum += weight
      }
      guard weightSum > 0 else { return nil }
      let stableDepth = weightedDepth / weightSum

      let intrinsics = frame.camera.intrinsics
      let imageResolution = frame.camera.imageResolution
      let scaleX = Float(width) / Float(imageResolution.width)
      let scaleY = Float(height) / Float(imageResolution.height)
      let fx = intrinsics.columns.0.x * scaleX
      let fy = intrinsics.columns.1.y * scaleY
      let cx = intrinsics.columns.2.x * scaleX
      let cy = intrinsics.columns.2.y * scaleY
      guard abs(fx) > 0.0001, abs(fy) > 0.0001 else { return nil }

      let u = weightedX / weightSum
      let v = weightedY / weightSum
      let cameraX = (u - cx) * stableDepth / fx
      let cameraY = -(v - cy) * stableDepth / fy
      let cameraZ = -stableDepth
      let world = frame.camera.transform * SIMD4<Float>(cameraX, cameraY, cameraZ, 1)
      var transform = matrix_identity_float4x4
      transform.columns.3 = SIMD4<Float>(world.x, world.y, world.z, 1)
      liveReticleAspect?.wrappedValue = 1.0
      liveReticleRotationDegrees?.wrappedValue = 0
      return measuredPoint(
        worldTransform: transform,
        cameraTransform: frame.camera.transform,
        trackingState: frame.camera.trackingState,
        screenPoint: screenPoint,
        viewportSize: viewport,
        sceneView: sceneView,
        source: "\(source)_scene_depth"
      )
    }

    private func nearestFeatureMeasuredPoint(
      at screenPoint: CGPoint,
      frame: ARFrame,
      sceneView: ARSCNView,
      source: String
    ) -> FloorplanMeasurePoint? {
      guard let rawPoints = frame.rawFeaturePoints?.points else { return nil }
      var best: (distance: CGFloat, point: SIMD3<Float>)?
      for point in rawPoints {
        let projected = sceneView.projectPoint(SCNVector3(point.x, point.y, point.z))
        guard projected.z >= 0, projected.x.isFinite, projected.y.isFinite else { continue }
        let dx = CGFloat(projected.x) - screenPoint.x
        let dy = CGFloat(projected.y) - screenPoint.y
        let distance = hypot(dx, dy)
        guard distance <= 32 else { continue }
        if best == nil || distance < best!.distance {
          best = (distance, point)
        }
      }
      guard let best else { return nil }
      var transform = matrix_identity_float4x4
      transform.columns.3 = SIMD4<Float>(best.point.x, best.point.y, best.point.z, 1)
      liveReticleAspect?.wrappedValue = 1.0
      liveReticleRotationDegrees?.wrappedValue = 0
      return measuredPoint(
        worldTransform: transform,
        cameraTransform: frame.camera.transform,
        trackingState: frame.camera.trackingState,
        screenPoint: screenPoint,
        viewportSize: sceneView.bounds.size,
        sceneView: sceneView,
        source: "\(source)_raw_feature_point"
      )
    }

    private func measuredPoint(
      worldTransform: simd_float4x4,
      cameraTransform: simd_float4x4,
      trackingState: ARCamera.TrackingState,
      screenPoint: CGPoint,
      viewportSize: CGSize,
      sceneView: ARSCNView,
      source: String
    ) -> FloorplanMeasurePoint {
      let world = SIMD3<Float>(
        worldTransform.columns.3.x,
        worldTransform.columns.3.y,
        worldTransform.columns.3.z
      )
      let projected = sceneView.projectPoint(SCNVector3(world.x, world.y, world.z))
      let normalized: [Double]
      if projected.x.isFinite, projected.y.isFinite, projected.z.isFinite, projected.z >= 0 {
        normalized = [
          Double(CGFloat(projected.x) / max(viewportSize.width, 1)),
          Double(CGFloat(projected.y) / max(viewportSize.height, 1))
        ]
      } else {
        normalized = [
          Double(screenPoint.x / max(viewportSize.width, 1)),
          Double(screenPoint.y / max(viewportSize.height, 1))
        ]
      }
      liveReticlePositionNormalized?.wrappedValue = normalized
      return FloorplanMeasurePoint(
        label: pointLabel,
        worldPositionMeters: world,
        cameraPositionMeters: SIMD3<Float>(
          cameraTransform.columns.3.x,
          cameraTransform.columns.3.y,
          cameraTransform.columns.3.z
        ),
        screenPositionNormalized: normalized,
        trackingQuality: trackingQualityText(trackingState),
        source: source
      )
    }

    private func smoothedLivePoint(_ point: FloorplanMeasurePoint) -> FloorplanMeasurePoint {
      guard let previous = smoothedLiveProbePoint else {
        smoothedLiveProbePoint = point
        return point
      }
      let distance = simd_distance(previous.worldPositionMeters, point.worldPositionMeters)
      if distance > 0.16 {
        smoothedLiveProbePoint = point
        return point
      }
      let isUserActivelyAiming = CACurrentMediaTime() - lastUserPointInteraction < 0.35
      let alpha: Float = isUserActivelyAiming ? 0.42 : 0.20
      let world = previous.worldPositionMeters * (1 - alpha) + point.worldPositionMeters * alpha
      let projected = projectedScreenPosition(for: world) ?? point.screenPositionNormalized
      let smoothed = FloorplanMeasurePoint(
        id: point.id,
        label: point.label,
        worldPositionMeters: world,
        cameraPositionMeters: point.cameraPositionMeters,
        screenPositionNormalized: projected,
        trackingQuality: point.trackingQuality,
        source: "\(point.source)_stable"
      )
      smoothedLiveProbePoint = smoothed
      liveReticlePositionNormalized?.wrappedValue = projected
      return smoothed
    }

    private func projectedScreenPosition(for worldPositionMeters: SIMD3<Float>) -> [Double]? {
      guard let sceneView else { return nil }
      let projected = sceneView.projectPoint(SCNVector3(
        worldPositionMeters.x,
        worldPositionMeters.y,
        worldPositionMeters.z
      ))
      guard projected.x.isFinite, projected.y.isFinite, projected.z.isFinite, projected.z >= 0 else {
        return nil
      }
      return [
        Double(CGFloat(projected.x) / max(sceneView.bounds.width, 1)),
        Double(CGFloat(projected.y) / max(sceneView.bounds.height, 1))
      ]
    }

    private func updateReticleScreenPosition(_ screenPoint: CGPoint, in viewportSize: CGSize) {
      guard viewportSize.width > 0, viewportSize.height > 0 else { return }
      liveReticlePositionNormalized?.wrappedValue = [
        Double(screenPoint.x / viewportSize.width),
        Double(screenPoint.y / viewportSize.height)
      ]
    }

    private func updateSurfacePresentation(
      worldTransform: simd_float4x4,
      cameraTransform: simd_float4x4,
      sceneView: ARSCNView
    ) {
      let center = worldTransform.columns.3
      let localX = center + worldTransform.columns.0 * 0.06
      let localZ = center + worldTransform.columns.2 * 0.06
      let projectedCenter = sceneView.projectPoint(SCNVector3(center.x, center.y, center.z))
      let projectedX = sceneView.projectPoint(SCNVector3(localX.x, localX.y, localX.z))
      let projectedZ = sceneView.projectPoint(SCNVector3(localZ.x, localZ.y, localZ.z))
      guard projectedCenter.x.isFinite, projectedCenter.y.isFinite,
            projectedX.x.isFinite, projectedX.y.isFinite,
            projectedZ.x.isFinite, projectedZ.y.isFinite
      else { return }

      let xVector = CGVector(dx: CGFloat(projectedX.x - projectedCenter.x), dy: CGFloat(projectedX.y - projectedCenter.y))
      let zVector = CGVector(dx: CGFloat(projectedZ.x - projectedCenter.x), dy: CGFloat(projectedZ.y - projectedCenter.y))
      let xLength = max(1, hypot(xVector.dx, xVector.dy))
      let zLength = max(1, hypot(zVector.dx, zVector.dy))
      let planeNormal = simd_normalize(SIMD3<Float>(
        worldTransform.columns.1.x,
        worldTransform.columns.1.y,
        worldTransform.columns.1.z
      ))
      let cameraForward = simd_normalize(SIMD3<Float>(
        -cameraTransform.columns.2.x,
        -cameraTransform.columns.2.y,
        -cameraTransform.columns.2.z
      ))
      let incidence = abs(simd_dot(planeNormal, cameraForward))
      let perspectiveAspect = max(0.34, min(1.0, CGFloat(incidence)))
      let projectedAspect = max(0.34, min(1.0, min(xLength, zLength) / max(xLength, zLength)))
      liveReticleAspect?.wrappedValue = Double(min(perspectiveAspect, projectedAspect))
      let vector = xLength >= zLength ? xVector : zVector
      liveReticleRotationDegrees?.wrappedValue = Double(atan2(vector.dy, vector.dx) * 180 / .pi)
    }

    private func makePointNode(label: String) -> SCNNode {
      let sphere = SCNSphere(radius: 0.018)
      sphere.firstMaterial?.diffuse.contents = UIColor.systemGreen
      sphere.firstMaterial?.emission.contents = UIColor.systemGreen.withAlphaComponent(0.45)
      let sphereNode = SCNNode(geometry: sphere)

      let text = SCNText(string: label, extrusionDepth: 0.001)
      text.font = UIFont.systemFont(ofSize: 0.12, weight: .bold)
      text.firstMaterial?.diffuse.contents = UIColor.white
      let textNode = SCNNode(geometry: text)
      textNode.scale = SCNVector3(0.18, 0.18, 0.18)
      textNode.position = SCNVector3(0.026, 0.022, 0)

      let node = SCNNode()
      node.addChildNode(sphereNode)
      node.addChildNode(textNode)
      return node
    }

    private func updateLineNode(points: [FloorplanMeasurePoint], sceneView: ARSCNView) {
      lineNode?.removeFromParentNode()
      lineNode = nil
      guard points.count >= 2 else { return }
      let start = points[0].worldPositionMeters
      let end = points[1].worldPositionMeters
      let source = SCNVector3(start.x, start.y, start.z)
      let target = SCNVector3(end.x, end.y, end.z)
      let node = SCNNode.lineNode(from: source, to: target, color: UIColor.systemGreen)
      sceneView.scene.rootNode.addChildNode(node)
      lineNode = node
    }

    private func trackingQualityText(_ state: ARCamera.TrackingState) -> String {
      switch state {
      case .normal:
        return "normal"
      case .notAvailable:
        return "not_available"
      case .limited(let reason):
        return "limited_\(String(describing: reason))"
      }
    }

    private static func distanceLabel(_ meters: Double) -> String {
      let centimeters = meters * 100
      if centimeters < 100 {
        return "\(String(format: "%.1f", centimeters)) cm"
      }
      return "\(String(format: "%.2f", meters)) m"
    }
  }
}

private extension SCNNode {
  static func lineNode(from start: SCNVector3, to end: SCNVector3, color: UIColor) -> SCNNode {
    let vector = SCNVector3(end.x - start.x, end.y - start.y, end.z - start.z)
    let distance = CGFloat(sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z))
    let cylinder = SCNCylinder(radius: 0.006, height: distance)
    cylinder.firstMaterial?.diffuse.contents = color
    cylinder.firstMaterial?.emission.contents = color.withAlphaComponent(0.35)
    let node = SCNNode(geometry: cylinder)
    node.position = SCNVector3((start.x + end.x) / 2, (start.y + end.y) / 2, (start.z + end.z) / 2)
    node.eulerAngles = lineEulerAngles(from: start, to: end)
    return node
  }

  private static func lineEulerAngles(from start: SCNVector3, to end: SCNVector3) -> SCNVector3 {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let dz = end.z - start.z
    let length = sqrt(dx * dx + dy * dy + dz * dz)
    guard length > 0 else { return SCNVector3Zero }
    let yaw = atan2(dx, dz)
    let pitch = acos(dy / length)
    return SCNVector3(Float.pi / 2 - pitch, yaw, 0)
  }
}
#endif
