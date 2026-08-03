import SwiftUI
import os

#if canImport(RoomPlan)
import RoomPlan
#if canImport(ARKit)
import ARKit
#endif
#endif

// Shared UIKit wrapper so we can reuse the same RoomCaptureView for single-room capture
// and multi-room "floor scan" flows (iOS 17+).
#if canImport(RoomPlan)
@available(iOS 17.0, *)
struct RoomPlanCaptureUIView: UIViewRepresentable {
  @Binding var isRunning: Bool
  @Binding var pendingTrackSamples: [RoomPlanTrackSample]
  @Binding var trackingMessage: String?
  let sharedTrackingSessionId: String?
  let onEnd: (CapturedRoomData?, Error?) -> Void
  private static let log = Logger(subsystem: "app.pixcapture.PIXCAPTURE", category: "RoomPlanSession")

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self, onEnd: onEnd)
  }

  func makeUIView(context: Context) -> RoomCaptureView {
    let view: RoomCaptureView
#if canImport(ARKit)
    if let sharedTrackingSessionId = normalizedTrackingSessionId(sharedTrackingSessionId),
       let sharedSession = SharedRoomPlanARSessionStore.session(for: sharedTrackingSessionId) {
      RoomPlanCaptureUIView.log.info("reusing shared ARSession for trackingSessionId=\(sharedTrackingSessionId, privacy: .public)")
      view = RoomCaptureView(frame: .zero, arSession: sharedSession)
    } else {
      view = RoomCaptureView(frame: .zero)
      if let sharedTrackingSessionId = normalizedTrackingSessionId(sharedTrackingSessionId) {
        SharedRoomPlanARSessionStore.store(view.captureSession.arSession, for: sharedTrackingSessionId)
        RoomPlanCaptureUIView.log.info("stored new shared ARSession for trackingSessionId=\(sharedTrackingSessionId, privacy: .public)")
      }
    }
#else
    view = RoomCaptureView(frame: .zero)
#endif
    view.captureSession.delegate = context.coordinator

#if canImport(ARKit)
    let session = view.captureSession.arSession
    context.coordinator.arSession = session
#endif

    return view
  }

  func updateUIView(_ uiView: RoomCaptureView, context: Context) {
    context.coordinator.parent = self
    context.coordinator.updateDesiredRunning(uiView: uiView, desired: isRunning)
  }

  static func dismantleUIView(_ uiView: RoomCaptureView, coordinator: Coordinator) {
    coordinator.teardown(uiView: uiView)
  }

  static func releaseSharedARSession(for trackingSessionId: String?) {
#if canImport(ARKit)
    SharedRoomPlanARSessionStore.release(for: trackingSessionId)
#endif
  }

  private func normalizedTrackingSessionId(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

#if canImport(ARKit)
  private enum SharedRoomPlanARSessionStore {
    private static var sessions: [String: ARSession] = [:]

    static func session(for trackingSessionId: String) -> ARSession? {
      sessions[trackingSessionId]
    }

    static func store(_ session: ARSession, for trackingSessionId: String) {
      sessions[trackingSessionId] = session
    }

    static func release(for trackingSessionId: String?) {
      guard let trackingSessionId,
            !trackingSessionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
      sessions[trackingSessionId]?.pause()
      sessions.removeValue(forKey: trackingSessionId)
    }
  }

  final class Coordinator: NSObject, RoomCaptureSessionDelegate {
    enum State {
      case idle
      case starting
      case running
      case stopping
    }

    var parent: RoomPlanCaptureUIView
    let onEnd: (CapturedRoomData?, Error?) -> Void
    var isRecording = false
    private var state: State = .idle
    private var startAttempts = 0
    private var desiredRunning = false
    private var lastAppliedDesiredRunning: Bool? = nil
    private var startWorkItem: DispatchWorkItem? = nil
    private var runSequence: Int = 0

    weak var arSession: ARSession? = nil
    private var lastSampleTS: TimeInterval = 0
    private var samples: [RoomPlanTrackSample] = []
    private var sampleTimer: Timer? = nil
    private var relocalizingSince: TimeInterval? = nil
    private var normalTrackingSince: TimeInterval? = nil

    init(parent: RoomPlanCaptureUIView, onEnd: @escaping (CapturedRoomData?, Error?) -> Void) {
      self.parent = parent
      self.onEnd = onEnd
    }

    func updateDesiredRunning(uiView: RoomCaptureView, desired: Bool) {
      isRecording = desired
      guard lastAppliedDesiredRunning != desired else { return }
      lastAppliedDesiredRunning = desired
      if desired {
        DispatchQueue.main.async {
          self.startIfNeeded(uiView: uiView)
        }
      } else {
        DispatchQueue.main.async {
          self.stopIfNeeded(uiView: uiView)
        }
      }
    }

    deinit {
      startWorkItem?.cancel()
      stopSampling()
    }

    func startIfNeeded(uiView: RoomCaptureView) {
      runSequence += 1
      desiredRunning = true
      RoomPlanCaptureUIView.log.info("startIfNeeded seq=\(self.runSequence) state=\(String(describing: self.state)) desired=true")
      guard state == .idle else { return }

#if canImport(ARKit)
      // Avoid hard crashes on devices without LiDAR depth support.
      // RoomPlan effectively requires LiDAR; on non-supported devices we show an error instead of running.
      guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) else {
        DispatchQueue.main.async {
          self.parent.trackingMessage = "Dieses Gerät unterstützt keinen LiDAR-Scan."
          self.parent.pendingTrackSamples = []
        }
        state = .idle
        return
      }
#endif

      state = .starting
      startAttempts = 0
      scheduleStartAttempt(uiView: uiView)
    }

    func stopIfNeeded(uiView: RoomCaptureView) {
      desiredRunning = false
      RoomPlanCaptureUIView.log.info("stopIfNeeded seq=\(self.runSequence) state=\(String(describing: self.state)) desired=false")
      startWorkItem?.cancel()
      startWorkItem = nil
      startAttempts = 0

      switch state {
      case .idle:
        return
      case .starting:
        state = .idle
        return
      case .running:
        state = .stopping
        stopSampling()
        if keepsSharedARSessionAlive {
          uiView.captureSession.stop(pauseARSession: false)
        } else {
          uiView.captureSession.stop()
        }
      case .stopping:
        return
      }
    }

    func teardown(uiView: RoomCaptureView) {
      RoomPlanCaptureUIView.log.info("teardown seq=\(self.runSequence) state=\(String(describing: self.state))")
      desiredRunning = false
      startWorkItem?.cancel()
      startWorkItem = nil
      stopSampling()
      if state == .running || state == .stopping {
        if keepsSharedARSessionAlive {
          uiView.captureSession.stop(pauseARSession: false)
        } else {
          uiView.captureSession.stop()
        }
      }
      state = .idle
      lastAppliedDesiredRunning = nil
      uiView.captureSession.delegate = nil
    }

    private var keepsSharedARSessionAlive: Bool {
      guard let trackingSessionId = parent.sharedTrackingSessionId?.trimmingCharacters(in: .whitespacesAndNewlines) else {
        return false
      }
      return !trackingSessionId.isEmpty
    }

    func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
      if let error {
        RoomPlanCaptureUIView.log.error("didEnd seq=\(self.runSequence) error=\(error.localizedDescription, privacy: .public)")
      } else {
        RoomPlanCaptureUIView.log.info("didEnd seq=\(self.runSequence) ok")
      }
      DispatchQueue.main.async {
#if canImport(ARKit)
        self.parent.pendingTrackSamples = self.samples
#else
        self.parent.pendingTrackSamples = []
#endif
        // Ensure SwiftUI state matches the underlying RoomPlan session lifecycle.
        // If the session ends due to an internal error (e.g. too many bad tracking reports),
        // we must not keep "isRunning" true, otherwise SwiftUI will immediately attempt to start again,
        // which can snowball into GPU/memory pressure and crashes.
        self.parent.isRunning = false
        self.desiredRunning = false
        self.startWorkItem?.cancel()
        self.startWorkItem = nil
        self.stopSampling()
        self.state = .idle
        self.onEnd(data, error)
      }
    }

    private func scheduleStartAttempt(uiView: RoomCaptureView) {
      startWorkItem?.cancel()

      let item = DispatchWorkItem { [weak self, weak uiView] in
        guard let self, let uiView else { return }
        guard self.desiredRunning else { self.state = .idle; return }
        guard self.state == .starting else { return }

        // Wait until the view is actually on-screen and has a drawable size.
        if uiView.window == nil || uiView.bounds.width < 10 || uiView.bounds.height < 10 {
          self.startAttempts += 1
          if self.startAttempts > 80 {
            RoomPlanCaptureUIView.log.error("start timeout seq=\(self.runSequence) attempts=\(self.startAttempts)")
            DispatchQueue.main.async {
              self.parent.trackingMessage = "UI noch nicht bereit. Bitte erneut versuchen."
            }
            self.state = .idle
            return
          }
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.scheduleStartAttempt(uiView: uiView)
          }
          return
        }

        // Let the render pipeline settle a frame before running (reduces Metal validation crashes).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self, weak uiView] in
          guard let self, let uiView else { return }
          guard self.desiredRunning else { self.state = .idle; return }
          guard self.state == .starting else { return }
          if uiView.window == nil || uiView.bounds.width < 10 || uiView.bounds.height < 10 { return }

          self.state = .running
          RoomPlanCaptureUIView.log.info("run started seq=\(self.runSequence) attempts=\(self.startAttempts)")
          DispatchQueue.main.async {
            self.parent.trackingMessage = nil
            self.parent.pendingTrackSamples = []
          }
          self.samples = []
          self.lastSampleTS = 0
          self.relocalizingSince = nil
          self.normalTrackingSince = nil
          var config = RoomCaptureSession.Configuration()
          config.isCoachingEnabled = true
          uiView.captureSession.run(configuration: config)
          self.startSampling()
        }
      }

      startWorkItem = item
      DispatchQueue.main.async(execute: item)
    }

    private func startSampling() {
      // Do not set ourselves as ARSession.delegate; RoomPlan/RealityKit can use this internally.
      // Instead, poll currentFrame at low rate to avoid retaining ARFrames.
      stopSampling()
      let timer = Timer(timeInterval: 0.10, repeats: true) { [weak self] _ in
        self?.sampleCurrentFrame()
      }
      sampleTimer = timer
      RunLoop.main.add(timer, forMode: .common)
    }

    private func stopSampling() {
      sampleTimer?.invalidate()
      sampleTimer = nil
    }

    private func sampleCurrentFrame() {
      guard state == .running else { return }
      guard let frame = arSession?.currentFrame else { return }

      if case .normal = frame.camera.trackingState {
        if normalTrackingSince == nil {
          normalTrackingSince = frame.timestamp
        }
      } else {
        normalTrackingSince = nil
      }

      if let msg = trackingMessage(for: frame.camera.trackingState, timestamp: frame.timestamp) {
        if parent.trackingMessage != msg { parent.trackingMessage = msg }
      } else {
        if let normalTrackingSince,
           frame.timestamp - normalTrackingSince >= 0.8,
           parent.trackingMessage != nil {
          parent.trackingMessage = nil
        }
      }

      // Record camera path at low frequency to keep memory small.
      guard isRecording else { return }
      let ts = frame.timestamp
      if ts - lastSampleTS < 0.20 { return }
      lastSampleTS = ts
      let t = frame.camera.transform
      // Use x/z plane and mirror-x to match our floorplan coordinate fix.
      let x = -t.columns.3.x
      let y = t.columns.3.z
      let headingX = t.columns.2.x
      let headingY = -t.columns.2.z
      let heading = atan2f(headingY, headingX)
      let isReliable: Bool
      switch frame.camera.trackingState {
      case .normal:
        isReliable = true
      default:
        isReliable = false
      }
      samples.append(
        RoomPlanTrackSample(
          timestamp: ts,
          x: x,
          y: y,
          headingRadians: heading,
          isTrackingReliable: isReliable
        )
      )
      if samples.count > 1500 { samples.removeFirst(samples.count - 1500) }
      if samples.count % 3 == 0 {
        parent.pendingTrackSamples = samples
      }
    }

    private func trackingMessage(for state: ARCamera.TrackingState, timestamp: TimeInterval) -> String? {
      switch state {
      case .normal:
        relocalizingSince = nil
        return nil
      case .notAvailable:
        relocalizingSince = nil
        return "Tracking kurz nicht verfügbar."
      case .limited(let reason):
        switch reason {
        case .initializing:
          relocalizingSince = nil
          return "Tracking initialisiert … iPhone ruhig halten."
        case .excessiveMotion:
          relocalizingSince = nil
          return "Tracking instabil. Bitte langsamer bewegen."
        case .insufficientFeatures:
          relocalizingSince = nil
          return "Zu wenig Struktur. Bitte auf Wände/Ecken richten."
        case .relocalizing:
          if relocalizingSince == nil {
            relocalizingSince = timestamp
          }
          let elapsed = timestamp - (relocalizingSince ?? timestamp)
          if elapsed < 3.0 {
            return "Tracking richtet sich neu aus … langsam weiterbewegen."
          }
          if elapsed < 8.0 {
            return "Tracking bleibt instabil. Bitte auf markante Wände/Ecken richten."
          }
          return "Tracking weiterhin instabil. Gehe wenige Schritte zum letzten stabilen Punkt."
        @unknown default:
          relocalizingSince = nil
          return "Tracking eingeschränkt."
        }
      }
    }
  }
#else
  final class Coordinator: NSObject, RoomCaptureSessionDelegate {
    enum State {
      case idle
      case running
      case stopping
    }

    var parent: RoomPlanCaptureUIView
    let onEnd: (CapturedRoomData?, Error?) -> Void
    var isRecording = false
    private var state: State = .idle
    private var lastAppliedDesiredRunning: Bool? = nil
    private var runSequence: Int = 0

    init(parent: RoomPlanCaptureUIView, onEnd: @escaping (CapturedRoomData?, Error?) -> Void) {
      self.parent = parent
      self.onEnd = onEnd
    }

    func updateDesiredRunning(uiView: RoomCaptureView, desired: Bool) {
      isRecording = desired
      guard lastAppliedDesiredRunning != desired else { return }
      lastAppliedDesiredRunning = desired
      if desired {
        DispatchQueue.main.async {
          self.startIfNeeded(uiView: uiView)
        }
      } else {
        DispatchQueue.main.async {
          self.stopIfNeeded(uiView: uiView)
        }
      }
    }

    func startIfNeeded(uiView: RoomCaptureView) {
      runSequence += 1
      RoomPlanCaptureUIView.log.info("startIfNeeded(seq=\(self.runSequence)) legacy state=\(String(describing: self.state))")
      guard state != .running else { return }
      state = .running
      parent.trackingMessage = nil
      parent.pendingTrackSamples = []
      var config = RoomCaptureSession.Configuration()
      config.isCoachingEnabled = true
      uiView.captureSession.run(configuration: config)
    }

    func stopIfNeeded(uiView: RoomCaptureView) {
      RoomPlanCaptureUIView.log.info("stopIfNeeded(seq=\(self.runSequence)) legacy state=\(String(describing: self.state))")
      guard state == .running else { return }
      state = .stopping
      uiView.captureSession.stop()
    }

    func teardown(uiView: RoomCaptureView) {
      RoomPlanCaptureUIView.log.info("teardown(seq=\(self.runSequence)) legacy state=\(String(describing: self.state))")
      if state == .running || state == .stopping {
        uiView.captureSession.stop()
      }
      state = .idle
      lastAppliedDesiredRunning = nil
      uiView.captureSession.delegate = nil
    }

    func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
      if let error {
        RoomPlanCaptureUIView.log.error("didEnd(seq=\(self.runSequence)) legacy error=\(error.localizedDescription, privacy: .public)")
      } else {
        RoomPlanCaptureUIView.log.info("didEnd(seq=\(self.runSequence)) legacy ok")
      }
      DispatchQueue.main.async {
        self.parent.pendingTrackSamples = []
        self.parent.isRunning = false
        self.state = .idle
        self.onEnd(data, error)
      }
    }
  }
#endif
}
#endif

struct RoomPlanTrackSample: Codable, Hashable {
  var timestamp: TimeInterval
  var x: Float
  var y: Float
  var headingRadians: Float?
  var isTrackingReliable: Bool?
}

#if canImport(RoomPlan)
@available(iOS 17.0, *)
enum RoomPlanAutoDockHintDetector {
  static func detectEntryHint(capturedRoom: CapturedRoom, samples: [RoomPlanTrackSample]) -> FloorplanEntryPassageHint? {
    let doors = RoomPlanFloorplanRenderer.doorSegments(capturedRoom: capturedRoom)
    let openings = RoomPlanFloorplanRenderer.openingSegments(capturedRoom: capturedRoom)
    let points = transitionPoints(from: samples)
    return detectHint(points: points, doors: doors, openings: openings)
  }

  static func detectHint(
    points: [CGPoint],
    doors: [FloorplanSegment],
    openings: [FloorplanSegment]
  ) -> FloorplanEntryPassageHint? {
    guard points.count >= 3 else { return nil }

    var candidates: [(hint: FloorplanEntryPassageHint, score: Double, length: Double)] = []

    func consider(kind: String, idx: Int, seg: FloorplanSegment) {
      let score = passageScore(points: points, segment: seg, kind: kind)
      let length = segmentLength(seg)
      candidates.append((FloorplanEntryPassageHint(kind: kind, index: idx), score, length))
    }

    for (idx, seg) in doors.enumerated() {
      consider(kind: "door", idx: idx, seg: seg)
    }
    for (idx, seg) in openings.enumerated() {
      consider(kind: "opening", idx: idx, seg: seg)
    }

    guard !candidates.isEmpty else { return nil }
    candidates.sort { lhs, rhs in
      if abs(lhs.score - rhs.score) > 0.0001 {
        return lhs.score < rhs.score
      }
      return lhs.length > rhs.length
    }

    guard var best = candidates.first else { return nil }
    if best.hint.kind == "door" {
      if let openingAlternative = candidates.first(where: {
        $0.hint.kind == "opening" &&
        $0.score <= best.score + 0.45 &&
        $0.length >= best.length * 1.25
      }) {
        best = openingAlternative
      }
    }

    return best.hint
  }

  private static func transitionPoints(from samples: [RoomPlanTrackSample]) -> [CGPoint] {
    let reliable = samples.filter { $0.isTrackingReliable != false }
    guard let start = reliable.first else { return [] }

    var points: [CGPoint] = []
    var lastAccepted = start
    let maxElapsed: TimeInterval = 1.9
    let maxTravelDistance: Double = 1.85

    for sample in reliable {
      let elapsed = sample.timestamp - start.timestamp
      let dx = Double(sample.x - start.x)
      let dy = Double(sample.y - start.y)
      let travelDistance = (dx * dx + dy * dy).squareRoot()
      if elapsed > maxElapsed || travelDistance > maxTravelDistance {
        break
      }

      let stepX = Double(sample.x - lastAccepted.x)
      let stepY = Double(sample.y - lastAccepted.y)
      let stepDistance = (stepX * stepX + stepY * stepY).squareRoot()
      if stepDistance < 0.03, !points.isEmpty {
        continue
      }

      points.append(CGPoint(x: Double(sample.x), y: Double(sample.y)))
      lastAccepted = sample
    }

    return points
  }

  private static func passageScore(points: [CGPoint], segment: FloorplanSegment, kind: String) -> Double {
    let distances = points.map {
      distancePointToSegment(
        px: Double($0.x),
        py: Double($0.y),
        ax: segment.ax,
        ay: segment.ay,
        bx: segment.bx,
        by: segment.by
      )
    }.sorted()

    let closest = distances.first ?? .greatestFiniteMagnitude
    let headCount = max(1, min(4, distances.count))
    let headMean = distances.prefix(headCount).reduce(0.0, +) / Double(headCount)
    let startDistance = distancePointToSegment(
      px: Double(points.first?.x ?? 0),
      py: Double(points.first?.y ?? 0),
      ax: segment.ax,
      ay: segment.ay,
      bx: segment.bx,
      by: segment.by
    )
    let length = segmentLength(segment)

    var score = 0.0
    score += startDistance * 4.8
    score += closest * 2.8
    score += headMean * 2.0
    score -= min(length, 2.4) * 0.55
    if kind == "opening" {
      score -= min(length, 2.2) * 0.18
    }
    return score
  }

  private static func segmentLength(_ seg: FloorplanSegment) -> Double {
    let dx = seg.bx - seg.ax
    let dy = seg.by - seg.ay
    return (dx * dx + dy * dy).squareRoot()
  }

  // Standard point-to-segment distance in 2D.
  private static func distancePointToSegment(px: Double, py: Double, ax: Double, ay: Double, bx: Double, by: Double) -> Double {
    let vx = bx - ax
    let vy = by - ay
    let wx = px - ax
    let wy = py - ay
    let c1 = vx * wx + vy * wy
    if c1 <= 0 {
      let dx = px - ax
      let dy = py - ay
      return (dx * dx + dy * dy).squareRoot()
    }
    let c2 = vx * vx + vy * vy
    if c2 <= c1 {
      let dx = px - bx
      let dy = py - by
      return (dx * dx + dy * dy).squareRoot()
    }
    let t = c1 / c2
    let projX = ax + t * vx
    let projY = ay + t * vy
    let dx = px - projX
    let dy = py - projY
    return (dx * dx + dy * dy).squareRoot()
  }
}
#endif
