@preconcurrency import AVFoundation
import Combine
import CoreImage
import CoreMedia
import CoreMotion
import Foundation
import simd
import UIKit
#if canImport(ARKit)
import ARKit

nonisolated private struct ARIntrinsicsSnapshot: Sendable {
  let width: Int
  let height: Int
  let matrix: [[Float]]
}

nonisolated private struct ARFrameSnapshot: @unchecked Sendable {
  let timestamp: TimeInterval
  let pixelBuffer: CVPixelBuffer
  let transform: simd_float4x4
  let trackingState: String
  let rawFeaturePointsCount: Int?
  let worldMappingStatus: String
  let intrinsics: ARIntrinsicsSnapshot?
}
#endif

final class VideoTakeRecorder: NSObject, ObservableObject {
  enum MotionGuideState: String, Codable {
    case stable = "stable"
    case tooFast = "too_fast"
    case tooSlow = "too_slow"
    case tooRocky = "too_rocky"

    var titleText: String {
      switch self {
      case .stable:
        return "Stabil"
      case .tooFast:
        return "Zu schnell"
      case .tooSlow:
        return "Zu langsam"
      case .tooRocky:
        return "Zu unruhig"
      }
    }

    var detailText: String {
      switch self {
      case .stable:
        return "Bewegung ist gleichmäßig."
      case .tooFast:
        return "Langsamer bewegen und kleinere Schwenks nutzen."
      case .tooSlow:
        return "Etwas gleichmäßiger vorwärts bewegen."
      case .tooRocky:
        return "Gerät ruhiger halten, Ellbogen anlegen."
      }
    }
  }

  struct RecordingResult {
    let videoURL: URL
    let motionCSVURL: URL
    let intrinsicsJSONURL: URL
    let trackingJSONURL: URL
  }

  let session = AVCaptureSession()

  @Published var isSessionRunning = false
  @Published var isRecording = false
  @Published var durationSeconds: Double = 0
  @Published var warningMessage: String?
  @Published var zoomPresets: [Double] = [0.5, 1.0, 2.0, 5.0]
  @Published var currentZoomFactor: Double = 1.0
  // Allows the user to lock AE/WB/Focus before recording, so they can re-auto between rooms.
  @Published var previewLocked: Bool = false
  @Published var stabilizationEnabled: Bool = true
  @Published var isStabilizationSupported: Bool = true
  @Published var motionGuideState: MotionGuideState = .stable
  @Published var isARPipelineActive: Bool = false
  @Published var arPreviewImage: CGImage?

  private let sessionQueue = DispatchQueue(label: "pixcapture.video.session")
  private let outputQueue = DispatchQueue(label: "pixcapture.video.output")
  private let motionSamplesQueue = DispatchQueue(label: "pixcapture.video.motion")
  private let trackingSamplesQueue = DispatchQueue(label: "pixcapture.video.tracking")
  private let arFrameProcessingSemaphore = DispatchSemaphore(value: 1)
  private let writerCIContext = CIContext(options: [CIContextOption.cacheIntermediates: false])
  private let previewCIContext = CIContext(options: [CIContextOption.cacheIntermediates: false])
  // Hard guard for dataset capture: keep tracking/video at <=30 fps.
  private let maxTrackingFrameRate: Int = 30
  // Warm-up frames avoid first-frame timing spikes while encoder/camera pipeline settles.
  private let defaultWriterWarmupFrameCount: Int = 10
  private let ultraWideWriterWarmupFrameCount: Int = 25
  // Require stable frame cadence before arming writer frame 0.
  private let writerStartupMaxGapSeconds: Double = 0.20
  private let writerStartupMinGapSeconds: Double = 0.005
  private let writerStartupStableFrameCountRequired: Int = 6
  private let writerPostPrimeStableFrameCountRequired: Int = 2
  // If hardware intrinsics are not delivered, fallback after a short grace period.
  private let intrinsicsFallbackAfterFrameCount: Int = 15
  private let motionManager = CMMotionManager()
  private let motionQueue: OperationQueue = {
    let q = OperationQueue()
    q.name = "pixcapture.video.motion.queue"
    q.qualityOfService = .userInitiated
    return q
  }()
  private var selectedZoomPreset: Double = 1.0

  private let videoOutput = AVCaptureVideoDataOutput()
  private var videoDevice: AVCaptureDevice?
  private var desiredPreviewLocked: Bool = false
  private var desiredStabilizationEnabled: Bool = true
  private var videoOutputDelegate: VideoDataOutputDelegate?
  private var wantsSessionRunning = false
  private var hasInstalledSessionObservers = false
  private var sessionObserverTokens: [NSObjectProtocol] = []

  nonisolated(unsafe) private var writer: AVAssetWriter?
  nonisolated(unsafe) private var writerVideoInput: AVAssetWriterInput?
  nonisolated(unsafe) private var writerPixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
  nonisolated(unsafe) private var recordingURLs: RecordingURLs?
  nonisolated(unsafe) private var firstPTS: CMTime?
  nonisolated(unsafe) private var startUptime: TimeInterval?
  nonisolated(unsafe) private var motionTimebaseStartUptime: TimeInterval?
  nonisolated(unsafe) private var recordStartDate: Date?
  nonisolated(unsafe) private var arStartTimestamp: TimeInterval?
  nonisolated(unsafe) private var firstFrameCaptureTimestamp: Double?
  nonisolated(unsafe) private var firstFrameCallbackUptime: Double?
  nonisolated(unsafe) private var hostTimeAligned = false
  nonisolated(unsafe) private var captureTimestampToUptimeOffset: Double?
  nonisolated(unsafe) private var activeWriterWarmupFrameCount: Int = 10
  nonisolated(unsafe) private var discardedWarmupFrames: Int = 0
  nonisolated(unsafe) private var writerStartupStableFrameCount: Int = 0
  nonisolated(unsafe) private var writerSessionPrimed: Bool = false
  nonisolated(unsafe) private var avWarmupLastPTS: CMTime?
  nonisolated(unsafe) private var arWarmupLastTimestamp: TimeInterval?
  nonisolated(unsafe) private var fallbackHorizontalFOVDegrees: Double?
  nonisolated(unsafe) private var usesARFramePipeline = false
  nonisolated(unsafe) private var recordedFrameIndex: Int = 0
  nonisolated(unsafe) private var lastARPreviewTimestamp: TimeInterval = -.greatestFiniteMagnitude
  nonisolated(unsafe) private var lastAcceptedARFrameTimestamp: TimeInterval = -.greatestFiniteMagnitude
  nonisolated(unsafe) private var motionSamples: [MotionSample] = []
  nonisolated(unsafe) private var pendingMotionSamples: [PendingMotionSample] = []
  nonisolated(unsafe) private var motionGuideCurrentState: MotionGuideState = .stable
  nonisolated(unsafe) private var motionGuideLowMotionStart: Double?
  nonisolated(unsafe) private var motionGuideSmoothedGyro: Double = 0
  nonisolated(unsafe) private var motionGuideSmoothedAcc: Double = 0
  nonisolated(unsafe) private var motionGuideLastAccMagnitude: Double = 0
  nonisolated(unsafe) private var motionGuideLastTimestamp: Double?
  nonisolated(unsafe) private var motionGuideSmoothedJerk: Double = 0
  nonisolated(unsafe) private var trackingSamples: [ARTrackingSample] = []
  nonisolated(unsafe) private var frameTimelineSamples: [FrameTimelineSample] = []
  nonisolated(unsafe) private var motionGuideEvents: [MotionGuideEvent] = []
  nonisolated(unsafe) private var hasWrittenIntrinsics = false
  nonisolated(unsafe) private var intrinsicsMissingFrameCount: Int = 0
  private var finishCallback: ((Result<RecordingResult, Error>) -> Void)?
  nonisolated(unsafe) private var recordingActive = false
  nonisolated(unsafe) private var isIntentionalSessionHandoff = false
#if canImport(ARKit)
  private let arSession = ARSession()
  private var arSessionDelegate: ARTrackingDelegate?
  nonisolated(unsafe) private var arVideoOutputDimensions = CMVideoDimensions(width: 3840, height: 2160)
  nonisolated(unsafe) private var arVideoOutputFPS: Int = 30
#endif

  // Separate delegate object to avoid actor-isolation issues in Swift 6 when using self as an AVCapture delegate.
  private nonisolated final class VideoDataOutputDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    weak var recorder: VideoTakeRecorder?

    init(recorder: VideoTakeRecorder) {
      self.recorder = recorder
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
      recorder?.handleVideoSampleBuffer(sampleBuffer)
    }
  }

#if canImport(ARKit)
  // Keep AR callbacks off the main recorder object to avoid actor-isolation issues.
  private nonisolated final class ARTrackingDelegate: NSObject, ARSessionDelegate {
    weak var recorder: VideoTakeRecorder?

    init(recorder: VideoTakeRecorder) {
      self.recorder = recorder
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
      recorder?.handleARFrame(frame)
    }
  }
#endif

  private struct RecordingURLs {
    let videoURL: URL
    let motionCSVURL: URL
    let intrinsicsJSONURL: URL
    let trackingJSONURL: URL
  }

  private struct MotionSample {
    let t: Double
    let acc: SIMD3<Double>
    let gyro: SIMD3<Double>
    let quat: SIMD4<Double> // x, y, z, w
  }

  private struct PendingMotionSample {
    let timestamp: Double
    let acc: SIMD3<Double>
    let gyro: SIMD3<Double>
    let quat: SIMD4<Double> // x, y, z, w
  }

  private struct ARTrackingSample: Codable {
    let frameIndex: Int
    let videoPTS: Double
    let t: Double
    let position: [Double]
    let rotation: [Double] // qx, qy, qz, qw
    let trackingState: String
    let rawFeaturePointsCount: Int?
    let worldMappingStatus: String?

    enum CodingKeys: String, CodingKey {
      case frameIndex = "frame_index"
      case videoPTS = "video_pts"
      case t
      case position
      case rotation
      case trackingState = "tracking_state"
      case rawFeaturePointsCount = "raw_feature_points_count"
      case worldMappingStatus = "world_mapping_status"
    }
  }

  private struct FrameTimelineSample: Codable {
    let frameIndex: Int
    let videoPTS: Double
    let captureTimestamp: Double
    let source: String

    enum CodingKeys: String, CodingKey {
      case frameIndex = "frame_index"
      case videoPTS = "video_pts"
      case captureTimestamp = "capture_timestamp"
      case source
    }
  }

  private struct TrackingSyncMetadata: Codable {
    let motionTimebaseStartUptime: Double?
    let firstFrameCaptureTimestamp: Double?
    let firstFrameCallbackUptime: Double?
    let hostTimeAligned: Bool

    enum CodingKeys: String, CodingKey {
      case motionTimebaseStartUptime = "motion_timebase_start_uptime"
      case firstFrameCaptureTimestamp = "first_frame_capture_timestamp"
      case firstFrameCallbackUptime = "first_frame_callback_uptime"
      case hostTimeAligned = "host_time_aligned"
    }
  }

  private struct TrackingConsistencyCheck: Codable {
    enum Status: String, Codable {
      case ok
      case warning
    }

    let status: Status
    let issues: [String]
    let frameCount: Int
    let droppedFrameCount: Int
    let nonMonotonicVideoPTSCount: Int
    let nonMonotonicCaptureTimestampCount: Int
    let motionSampleCount: Int
    let videoDurationSeconds: Double
    let motionDurationSeconds: Double

    enum CodingKeys: String, CodingKey {
      case status
      case issues
      case frameCount = "frame_count"
      case droppedFrameCount = "dropped_frame_count"
      case nonMonotonicVideoPTSCount = "non_monotonic_video_pts_count"
      case nonMonotonicCaptureTimestampCount = "non_monotonic_capture_timestamp_count"
      case motionSampleCount = "motion_sample_count"
      case videoDurationSeconds = "video_duration_seconds"
      case motionDurationSeconds = "motion_duration_seconds"
    }
  }

  private struct ARTrackingFile: Codable {
    let videoFile: String
    let recordStart: String
    let arStartTimestamp: Double?
    let samples: [ARTrackingSample]
    let frameTimeline: [FrameTimelineSample]
    let sync: TrackingSyncMetadata
    let consistencyCheck: TrackingConsistencyCheck
    let motionCoachingEvents: [MotionGuideEvent]

    enum CodingKeys: String, CodingKey {
      case videoFile = "video_file"
      case recordStart = "record_start"
      case arStartTimestamp = "ar_start_timestamp"
      case samples
      case frameTimeline = "frame_timeline"
      case sync
      case consistencyCheck = "consistency_check"
      case motionCoachingEvents = "motion_coaching_events"
    }
  }

  private struct MotionGuideEvent: Codable {
    let t: Double
    let state: MotionGuideState
    let message: String

    enum CodingKeys: String, CodingKey {
      case t
      case state
      case message
    }
  }

  enum RecorderError: LocalizedError {
    case noCamera
    case video4k60NotSupported
    case notConfigured
    case writerFailed(String)
    case recordingNotActive

    var errorDescription: String? {
      switch self {
      case .noCamera:
        return "Keine Kamera verfügbar."
      case .video4k60NotSupported:
        return "4K/60fps wird auf diesem Gerät nicht unterstützt."
      case .notConfigured:
        return "Video-Recorder ist nicht konfiguriert."
      case .writerFailed(let message):
        return "Video-Export fehlgeschlagen: \(message)"
      case .recordingNotActive:
        return "Keine aktive Aufnahme."
      }
    }
  }

  func configureIfNeeded() {
    sessionQueue.async { [weak self] in
      guard let self else { return }
      guard self.videoDevice == nil else { return }

      DispatchQueue.main.async { [weak self] in
        self?.installSessionObserversIfNeeded()
      }

      self.session.beginConfiguration()
      self.session.sessionPreset = .inputPriority

      guard let device = self.selectBackCamera() else {
        DispatchQueue.main.async { self.warningMessage = RecorderError.noCamera.localizedDescription }
        self.session.commitConfiguration()
        return
      }
      self.videoDevice = device

      do {
        let input = try AVCaptureDeviceInput(device: device)
        if self.session.canAddInput(input) {
          self.session.addInput(input)
        }

        // Default preview behavior: auto exposure/WB/focus (unless user explicitly locked it).
        self.applyPreviewLockState(device: device)

        // Use a stable 4K/30 profile for dataset capture.
        if try !self.applyPreferred4KFormat(device: device) {
          DispatchQueue.main.async { self.warningMessage = "4K wird auf diesem Objektiv nicht unterstützt." }
        }
        self.fallbackHorizontalFOVDegrees = Double(device.activeFormat.videoFieldOfView)

        // Default to 1x (wide) on virtual devices so the user sees a predictable view.
        try device.lockForConfiguration()
        let desiredZoom: CGFloat = 1.0
        if desiredZoom >= device.minAvailableVideoZoomFactor && desiredZoom <= device.maxAvailableVideoZoomFactor {
          device.videoZoomFactor = desiredZoom
        }
        self.selectedZoomPreset = 1.0
        device.unlockForConfiguration()

        self.videoOutput.alwaysDiscardsLateVideoFrames = true
        self.videoOutput.videoSettings = [
          kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
        ]
        let delegate = VideoDataOutputDelegate(recorder: self)
        self.videoOutputDelegate = delegate
        self.videoOutput.setSampleBufferDelegate(delegate, queue: self.outputQueue)
        if self.session.canAddOutput(self.videoOutput) {
          self.session.addOutput(self.videoOutput)
        }

        if let connection = self.videoOutput.connection(with: .video) {
          self.applyVideoConnectionState(connection: connection)
        }

        self.refreshZoomState(selectedPreset: 1.0)
      } catch {
        DispatchQueue.main.async { self.warningMessage = error.localizedDescription }
      }

      self.session.commitConfiguration()
      self.startSession()
    }
  }

  func startSession() {
    wantsSessionRunning = true
    sessionQueue.async { [weak self] in
      guard let self else { return }
      if self.usesARFramePipeline && self.recordingActive {
        return
      }
      if !self.session.isRunning {
        self.session.startRunning()
      }
      DispatchQueue.main.async { self.isSessionRunning = self.session.isRunning }
    }
  }

  func stopSession() {
    wantsSessionRunning = false
    sessionQueue.async { [weak self] in
      guard let self else { return }
#if canImport(ARKit)
      if self.usesARFramePipeline {
        self.stopARSessionIfNeeded()
      }
#endif
      if self.session.isRunning {
        self.session.stopRunning()
      }
      DispatchQueue.main.async {
        self.isSessionRunning = false
        if !self.isRecording {
          self.isARPipelineActive = false
          self.arPreviewImage = nil
        }
      }
    }
  }

  private func installSessionObserversIfNeeded() {
    guard !hasInstalledSessionObservers else { return }
    hasInstalledSessionObservers = true

    let nc = NotificationCenter.default
    sessionObserverTokens.append(
      nc.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main) { [weak self] note in
        self?.handleSessionRuntimeError(note)
      }
    )
    sessionObserverTokens.append(
      nc.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: .main) { [weak self] note in
        self?.handleSessionInterrupted(note)
      }
    )
    sessionObserverTokens.append(
      nc.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: .main) { [weak self] _ in
        guard let self else { return }
        if self.wantsSessionRunning {
          self.startSession()
        }
      }
    )
    sessionObserverTokens.append(
      nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
        guard let self else { return }
        if self.wantsSessionRunning {
          self.startSession()
        }
      }
    )
  }

  private func handleSessionRuntimeError(_ note: Notification) {
    guard let nsError = note.userInfo?[AVCaptureSessionErrorKey] as? NSError else { return }
    let code = AVError.Code(rawValue: nsError.code)

    if code == .mediaServicesWereReset {
      if wantsSessionRunning {
        startSession()
      }
      return
    }

    warningMessage = "Camera runtime error: \(nsError.localizedDescription)"
  }

  private func handleSessionInterrupted(_ note: Notification) {
    if isIntentionalSessionHandoff { return }

    let reasonValue = (note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber)?.intValue
    let reason = reasonValue.flatMap(AVCaptureSession.InterruptionReason.init(rawValue:))

    switch reason {
    case .audioDeviceInUseByAnotherClient, .videoDeviceInUseByAnotherClient:
      warningMessage = "Kamera wird gerade von einer anderen App verwendet."
    case .videoDeviceNotAvailableWithMultipleForegroundApps:
      warningMessage = "Kamera nicht verfügbar (Mehrfach-Apps)."
    case .videoDeviceNotAvailableDueToSystemPressure:
      warningMessage = "Kamera pausiert (Systemlast)."
    default:
      warningMessage = "Kamera wurde unterbrochen."
    }
  }

  func setZoomFactor(_ requested: Double) {
    sessionQueue.async { [weak self] in
      guard let self, let device = self.videoDevice else { return }

      if self.isRecording {
        DispatchQueue.main.async { self.warningMessage = "Zoom ist während der Aufnahme deaktiviert." }
        return
      }

      let preset = self.normalizedZoomPreset(for: requested)

      var targetDevice = device
      if let preferredDevice = self.selectLensDevice(for: preset),
         preferredDevice.uniqueID != device.uniqueID {
        guard self.switchToDevice(preferredDevice) else { return }
        if let updated = self.videoDevice {
          targetDevice = updated
        }
      }

      let targetZoomOnDevice = self.mapRequestedZoomToDeviceZoom(requested: preset, device: targetDevice)
      let clamped = min(max(targetZoomOnDevice, Double(targetDevice.minAvailableVideoZoomFactor)), Double(targetDevice.maxAvailableVideoZoomFactor))
      do {
        try targetDevice.lockForConfiguration()
        targetDevice.videoZoomFactor = CGFloat(clamped)
        targetDevice.unlockForConfiguration()

        self.selectedZoomPreset = preset
        self.refreshZoomState(selectedPreset: preset)

        if preset < 1.0 && targetDevice.deviceType != .builtInUltraWideCamera {
          DispatchQueue.main.async { self.warningMessage = "Ultraweit (0,5x) ist auf diesem Gerät nicht verfügbar." }
        }
      } catch {
        DispatchQueue.main.async { self.warningMessage = error.localizedDescription }
      }
    }
  }

  func setPreviewLocked(_ locked: Bool) {
    sessionQueue.async { [weak self] in
      guard let self, let device = self.videoDevice else { return }
      self.desiredPreviewLocked = locked
      self.applyPreviewLockState(device: device)
    }
  }

  func setVideoStabilizationEnabled(_ enabled: Bool) {
    sessionQueue.async { [weak self] in
      guard let self else { return }
      if self.isRecording {
        DispatchQueue.main.async {
          self.warningMessage = "Stabilisierung kann während der Aufnahme nicht geändert werden."
        }
        return
      }
      self.desiredStabilizationEnabled = enabled
      if let connection = self.videoOutput.connection(with: .video) {
        self.applyVideoConnectionState(connection: connection)
      } else {
        DispatchQueue.main.async {
          self.stabilizationEnabled = enabled
        }
      }
    }
  }

  private func applyPreviewLockState(device: AVCaptureDevice) {
    do {
      try device.lockForConfiguration()
      if desiredPreviewLocked {
        applyLockedCaptureSettings(device: device)
      } else {
        applyAutoCaptureSettings(device: device)
      }
      device.unlockForConfiguration()
      DispatchQueue.main.async { self.previewLocked = self.desiredPreviewLocked }
    } catch {
      DispatchQueue.main.async { self.warningMessage = error.localizedDescription }
    }
  }

  private func applyAutoCaptureSettings(device: AVCaptureDevice) {
    if device.isFocusModeSupported(.continuousAutoFocus) {
      device.focusMode = .continuousAutoFocus
    } else if device.isFocusModeSupported(.autoFocus) {
      device.focusMode = .autoFocus
    }

    if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
      device.whiteBalanceMode = .continuousAutoWhiteBalance
    } else if device.isWhiteBalanceModeSupported(.autoWhiteBalance) {
      device.whiteBalanceMode = .autoWhiteBalance
    }

    if device.isExposureModeSupported(.continuousAutoExposure) {
      device.exposureMode = .continuousAutoExposure
    } else if device.isExposureModeSupported(.autoExpose) {
      device.exposureMode = .autoExpose
    }
  }

  private func applyLockedCaptureSettings(device: AVCaptureDevice) {
    if device.isFocusModeSupported(.locked) {
      device.focusMode = .locked
    }
    if device.isWhiteBalanceModeSupported(.locked) {
      device.whiteBalanceMode = .locked
    }
    if device.isExposureModeSupported(.custom) {
      device.setExposureModeCustom(duration: device.exposureDuration, iso: device.iso, completionHandler: nil)
    } else if device.isExposureModeSupported(.locked) {
      device.exposureMode = .locked
    }
  }

  func startRecording(
    videoURL: URL,
    motionCSVURL: URL,
    intrinsicsJSONURL: URL,
    trackingJSONURL: URL,
    selectedZoomOverride: Double? = nil
  ) {
    sessionQueue.async { [weak self] in
      guard let self else { return }
      guard let initialDevice = self.videoDevice else {
        DispatchQueue.main.async { self.warningMessage = RecorderError.noCamera.localizedDescription }
        return
      }

      var activeDevice = initialDevice
      if let selectedZoomOverride {
        let requestedPreset = self.normalizedZoomPreset(for: selectedZoomOverride)
        if let preferredDevice = self.selectLensDevice(for: requestedPreset),
           preferredDevice.uniqueID != activeDevice.uniqueID {
          guard self.switchToDevice(preferredDevice) else { return }
          if let updated = self.videoDevice {
            activeDevice = updated
          }
        }

        let targetZoomOnDevice = self.mapRequestedZoomToDeviceZoom(requested: requestedPreset, device: activeDevice)
        let clampedZoom = min(
          max(targetZoomOnDevice, Double(activeDevice.minAvailableVideoZoomFactor)),
          Double(activeDevice.maxAvailableVideoZoomFactor)
        )
        do {
          try activeDevice.lockForConfiguration()
          activeDevice.videoZoomFactor = CGFloat(clampedZoom)
          activeDevice.unlockForConfiguration()
          self.selectedZoomPreset = requestedPreset
          self.refreshZoomState(selectedPreset: requestedPreset)
        } catch {
          DispatchQueue.main.async { self.warningMessage = error.localizedDescription }
        }
      }

      let selectedZoom = self.selectedZoomPreset
#if canImport(ARKit)
      let arSupported = ARWorldTrackingConfiguration.isSupported
      let requiresNonMainLens = abs(selectedZoom - 1.0) > 0.05
      let useARPipeline = arSupported && !requiresNonMainLens
#else
      let arSupported = false
      let requiresNonMainLens = false
      let useARPipeline = false
#endif

      DispatchQueue.main.async { self.warningMessage = nil }
      if arSupported && requiresNonMainLens {
        DispatchQueue.main.async {
          self.warningMessage = "AR-Tracking ist nur mit 1x verfügbar. Aufnahme läuft mit gewähltem Objektiv ohne AR-Tracking."
        }
      }
      self.hasWrittenIntrinsics = false
      self.firstPTS = nil
      self.startUptime = nil
      self.motionTimebaseStartUptime = nil
      self.recordStartDate = Date()
      self.arStartTimestamp = nil
      self.firstFrameCaptureTimestamp = nil
      self.firstFrameCallbackUptime = nil
      self.hostTimeAligned = false
      self.captureTimestampToUptimeOffset = nil
      let useUltraWideWarmup = !useARPipeline && selectedZoom <= 0.75
      self.activeWriterWarmupFrameCount = useUltraWideWarmup ? self.ultraWideWriterWarmupFrameCount : self.defaultWriterWarmupFrameCount
      self.discardedWarmupFrames = 0
      self.writerStartupStableFrameCount = 0
      self.writerSessionPrimed = false
      self.avWarmupLastPTS = nil
      self.arWarmupLastTimestamp = nil
      self.fallbackHorizontalFOVDegrees = Double(activeDevice.activeFormat.videoFieldOfView)
      self.recordedFrameIndex = 0
      self.lastARPreviewTimestamp = -.greatestFiniteMagnitude
      self.lastAcceptedARFrameTimestamp = -.greatestFiniteMagnitude
      self.intrinsicsMissingFrameCount = 0
      self.usesARFramePipeline = useARPipeline
      DispatchQueue.main.async { self.durationSeconds = 0 }
      DispatchQueue.main.async {
        self.isARPipelineActive = useARPipeline
        if !useARPipeline {
          self.arPreviewImage = nil
        }
      }
      self.recordingURLs = RecordingURLs(
        videoURL: videoURL,
        motionCSVURL: motionCSVURL,
        intrinsicsJSONURL: intrinsicsJSONURL,
        trackingJSONURL: trackingJSONURL
      )
      self.motionSamplesQueue.sync {
        self.motionSamples.removeAll(keepingCapacity: true)
        self.pendingMotionSamples.removeAll(keepingCapacity: true)
        self.motionGuideEvents.removeAll(keepingCapacity: true)
        self.motionGuideCurrentState = .stable
        self.motionGuideLowMotionStart = nil
        self.motionGuideSmoothedGyro = 0
        self.motionGuideSmoothedAcc = 0
        self.motionGuideLastAccMagnitude = 0
        self.motionGuideLastTimestamp = nil
        self.motionGuideSmoothedJerk = 0
      }
      self.trackingSamplesQueue.sync {
        self.trackingSamples.removeAll(keepingCapacity: true)
        self.frameTimelineSamples.removeAll(keepingCapacity: true)
      }
      self.outputQueue.sync {
        self.recordingActive = true
      }
      DispatchQueue.main.async {
        self.motionGuideState = .stable
      }

      // Lock exposure/focus/WB so the footage is stable for reconstruction.
      do {
        try activeDevice.lockForConfiguration()
        self.applyLockedCaptureSettings(device: activeDevice)
        activeDevice.unlockForConfiguration()
      } catch {
        DispatchQueue.main.async { self.warningMessage = error.localizedDescription }
      }

      if useARPipeline {
        self.isIntentionalSessionHandoff = true
        if self.session.isRunning {
          self.session.stopRunning()
          DispatchQueue.main.async { self.isSessionRunning = false }
        }
        // Short handoff window to let AVCapture release camera resources.
        Thread.sleep(forTimeInterval: 0.12)
#if canImport(ARKit)
        self.startARSessionIfNeeded()
#endif
        self.isIntentionalSessionHandoff = false
      }

      do {
        if FileManager.default.fileExists(atPath: videoURL.path) {
          try? FileManager.default.removeItem(at: videoURL)
        }
        if FileManager.default.fileExists(atPath: motionCSVURL.path) {
          try? FileManager.default.removeItem(at: motionCSVURL)
        }
        if FileManager.default.fileExists(atPath: intrinsicsJSONURL.path) {
          try? FileManager.default.removeItem(at: intrinsicsJSONURL)
        }
        if FileManager.default.fileExists(atPath: trackingJSONURL.path) {
          try? FileManager.default.removeItem(at: trackingJSONURL)
        }
        let writer = try AVAssetWriter(outputURL: videoURL, fileType: .mov)
        self.writer = writer

        let outputWidth: Int
        let outputHeight: Int
        let outputFPS: Int
        let outputBitrate: Int
        if useARPipeline {
          outputWidth = max(1, Int(self.arVideoOutputDimensions.width))
          outputHeight = max(1, Int(self.arVideoOutputDimensions.height))
          outputFPS = max(1, min(self.arVideoOutputFPS, self.maxTrackingFrameRate))
          outputBitrate = (outputWidth >= 3840 && outputHeight >= 2160) ? 45_000_000 : 28_000_000
        } else {
          outputWidth = 3840
          outputHeight = 2160
          outputFPS = 30
          outputBitrate = 45_000_000
        }

        let videoSettings: [String: Any] = [
          AVVideoCodecKey: AVVideoCodecType.hevc,
          AVVideoWidthKey: outputWidth,
          AVVideoHeightKey: outputHeight,
          AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey: outputBitrate,
            AVVideoExpectedSourceFrameRateKey: outputFPS,
            AVVideoMaxKeyFrameIntervalKey: outputFPS
          ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true
        if writer.canAdd(input) {
          writer.add(input)
          self.writerVideoInput = input
          if useARPipeline {
            self.writerPixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
              assetWriterInput: input,
              sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
                kCVPixelBufferWidthKey as String: outputWidth,
                kCVPixelBufferHeightKey as String: outputHeight,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
              ]
            )
          }
        } else {
          throw RecorderError.writerFailed("AVAssetWriterInput konnte nicht hinzugefügt werden.")
        }

        self.startMotionUpdates()

        DispatchQueue.main.async { self.isRecording = true }
      } catch {
        self.outputQueue.sync {
          self.recordingActive = false
        }
        self.recordStartDate = nil
        self.arStartTimestamp = nil
        self.startUptime = nil
        self.motionTimebaseStartUptime = nil
        self.firstFrameCaptureTimestamp = nil
        self.firstFrameCallbackUptime = nil
        self.hostTimeAligned = false
        self.captureTimestampToUptimeOffset = nil
        self.activeWriterWarmupFrameCount = self.defaultWriterWarmupFrameCount
        self.discardedWarmupFrames = 0
        self.writerStartupStableFrameCount = 0
        self.writerSessionPrimed = false
        self.avWarmupLastPTS = nil
        self.arWarmupLastTimestamp = nil
        self.recordedFrameIndex = 0
        self.usesARFramePipeline = false
        self.lastARPreviewTimestamp = -.greatestFiniteMagnitude
        self.lastAcceptedARFrameTimestamp = -.greatestFiniteMagnitude
        self.intrinsicsMissingFrameCount = 0
#if canImport(ARKit)
        self.stopARSessionIfNeeded()
#endif
        if self.wantsSessionRunning && !self.session.isRunning {
          self.session.startRunning()
          DispatchQueue.main.async { self.isSessionRunning = true }
        }
        self.applyPreviewLockState(device: activeDevice)
        DispatchQueue.main.async {
          self.warningMessage = error.localizedDescription
          self.isRecording = false
          self.isARPipelineActive = false
          self.arPreviewImage = nil
        }
      }
    }
  }

  func stopRecording(onFinished: @escaping (Result<RecordingResult, Error>) -> Void) {
    sessionQueue.async { [weak self] in
      guard let self else { return }
      guard self.isRecording else {
        DispatchQueue.main.async { onFinished(.failure(RecorderError.recordingNotActive)) }
        return
      }
      self.outputQueue.sync {
        self.recordingActive = false
      }
      DispatchQueue.main.async {
        self.motionGuideState = .stable
      }
      self.finishCallback = onFinished
      DispatchQueue.main.async { self.isRecording = false }
      self.stopMotionUpdates()
#if canImport(ARKit)
      if self.usesARFramePipeline {
        self.stopARSessionIfNeeded()
      }
#endif
      if self.wantsSessionRunning && !self.session.isRunning {
        self.isIntentionalSessionHandoff = true
        self.session.startRunning()
        DispatchQueue.main.async { self.isSessionRunning = true }
        self.isIntentionalSessionHandoff = false
      }
      if let device = self.videoDevice {
        self.applyPreviewLockState(device: device)
      }

      self.outputQueue.async { [weak self] in
        guard let self else { return }
        self.finalizeWriter()
      }
    }
  }

  private func finalizeWriter() {
    let writer = self.writer
    let input = self.writerVideoInput
    let urls = self.recordingURLs
    self.writer = nil
    self.writerVideoInput = nil
    self.writerPixelBufferAdaptor = nil
    self.recordingURLs = nil
    self.firstPTS = nil
    self.startUptime = nil
    self.captureTimestampToUptimeOffset = nil
    self.activeWriterWarmupFrameCount = self.defaultWriterWarmupFrameCount
    self.discardedWarmupFrames = 0
    self.writerStartupStableFrameCount = 0
    self.writerSessionPrimed = false
    self.avWarmupLastPTS = nil
    self.arWarmupLastTimestamp = nil
    self.intrinsicsMissingFrameCount = 0

    input?.markAsFinished()

    writer?.finishWriting { [weak self] in
      guard let self else { return }

      if let status = writer?.status, status == .failed {
        let message = writer?.error?.localizedDescription ?? "Unbekannter Fehler"
        DispatchQueue.main.async {
          self.recordStartDate = nil
          self.arStartTimestamp = nil
          self.motionTimebaseStartUptime = nil
          self.firstFrameCaptureTimestamp = nil
          self.firstFrameCallbackUptime = nil
          self.hostTimeAligned = false
          self.captureTimestampToUptimeOffset = nil
          self.activeWriterWarmupFrameCount = self.defaultWriterWarmupFrameCount
          self.discardedWarmupFrames = 0
          self.writerStartupStableFrameCount = 0
          self.writerSessionPrimed = false
          self.avWarmupLastPTS = nil
          self.arWarmupLastTimestamp = nil
          self.recordedFrameIndex = 0
          self.usesARFramePipeline = false
          self.lastARPreviewTimestamp = -.greatestFiniteMagnitude
          self.lastAcceptedARFrameTimestamp = -.greatestFiniteMagnitude
          self.intrinsicsMissingFrameCount = 0
          self.isARPipelineActive = false
          self.arPreviewImage = nil
          self.finishCallback?(.failure(RecorderError.writerFailed(message)))
          self.finishCallback = nil
        }
        return
      }

      guard let urls else {
        DispatchQueue.main.async {
          self.recordStartDate = nil
          self.arStartTimestamp = nil
          self.motionTimebaseStartUptime = nil
          self.firstFrameCaptureTimestamp = nil
          self.firstFrameCallbackUptime = nil
          self.hostTimeAligned = false
          self.captureTimestampToUptimeOffset = nil
          self.activeWriterWarmupFrameCount = self.defaultWriterWarmupFrameCount
          self.discardedWarmupFrames = 0
          self.writerStartupStableFrameCount = 0
          self.writerSessionPrimed = false
          self.avWarmupLastPTS = nil
          self.arWarmupLastTimestamp = nil
          self.recordedFrameIndex = 0
          self.usesARFramePipeline = false
          self.lastARPreviewTimestamp = -.greatestFiniteMagnitude
          self.lastAcceptedARFrameTimestamp = -.greatestFiniteMagnitude
          self.intrinsicsMissingFrameCount = 0
          self.isARPipelineActive = false
          self.arPreviewImage = nil
          self.finishCallback?(.failure(RecorderError.writerFailed("Keine Zielpfade.")))
          self.finishCallback = nil
        }
        return
      }

      do {
        try self.writeMotionCSV(to: urls.motionCSVURL)
        let consistencyCheck = try self.writeTrackingJSON(to: urls.trackingJSONURL, videoURL: urls.videoURL)
        let syncWarningMessage = self.syncCheckWarningMessage(for: consistencyCheck)
        let result = RecordingResult(
          videoURL: urls.videoURL,
          motionCSVURL: urls.motionCSVURL,
          intrinsicsJSONURL: urls.intrinsicsJSONURL,
          trackingJSONURL: urls.trackingJSONURL
        )
        DispatchQueue.main.async {
          self.recordStartDate = nil
          self.arStartTimestamp = nil
          self.motionTimebaseStartUptime = nil
          self.firstFrameCaptureTimestamp = nil
          self.firstFrameCallbackUptime = nil
          self.hostTimeAligned = false
          self.captureTimestampToUptimeOffset = nil
          self.activeWriterWarmupFrameCount = self.defaultWriterWarmupFrameCount
          self.discardedWarmupFrames = 0
          self.writerStartupStableFrameCount = 0
          self.writerSessionPrimed = false
          self.avWarmupLastPTS = nil
          self.arWarmupLastTimestamp = nil
          self.recordedFrameIndex = 0
          self.usesARFramePipeline = false
          self.lastARPreviewTimestamp = -.greatestFiniteMagnitude
          self.lastAcceptedARFrameTimestamp = -.greatestFiniteMagnitude
          self.intrinsicsMissingFrameCount = 0
          self.isARPipelineActive = false
          self.arPreviewImage = nil
          if let syncWarningMessage {
            self.warningMessage = syncWarningMessage
          }
          self.finishCallback?(.success(result))
          self.finishCallback = nil
        }
      } catch {
        DispatchQueue.main.async {
          self.recordStartDate = nil
          self.arStartTimestamp = nil
          self.motionTimebaseStartUptime = nil
          self.firstFrameCaptureTimestamp = nil
          self.firstFrameCallbackUptime = nil
          self.hostTimeAligned = false
          self.captureTimestampToUptimeOffset = nil
          self.activeWriterWarmupFrameCount = self.defaultWriterWarmupFrameCount
          self.discardedWarmupFrames = 0
          self.writerStartupStableFrameCount = 0
          self.writerSessionPrimed = false
          self.avWarmupLastPTS = nil
          self.arWarmupLastTimestamp = nil
          self.recordedFrameIndex = 0
          self.usesARFramePipeline = false
          self.lastARPreviewTimestamp = -.greatestFiniteMagnitude
          self.lastAcceptedARFrameTimestamp = -.greatestFiniteMagnitude
          self.intrinsicsMissingFrameCount = 0
          self.isARPipelineActive = false
          self.arPreviewImage = nil
          self.finishCallback?(.failure(error))
          self.finishCallback = nil
        }
      }
    }
  }

  private func startMotionUpdates() {
    guard motionManager.isDeviceMotionAvailable else { return }
    motionManager.deviceMotionUpdateInterval = 1.0 / 100.0
    motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: motionQueue) { [weak self] motion, _ in
      guard let self, let motion else { return }
      let motionTimestamp = motion.timestamp
      let g = 9.80665
      let acc = SIMD3<Double>(motion.userAcceleration.x * g, motion.userAcceleration.y * g, motion.userAcceleration.z * g)
      let gyro = SIMD3<Double>(motion.rotationRate.x, motion.rotationRate.y, motion.rotationRate.z)
      let q = motion.attitude.quaternion
      let quat = SIMD4<Double>(q.x, q.y, q.z, q.w)

      self.motionSamplesQueue.async {
        if let startUptime = self.startUptime {
          let t = max(0, motionTimestamp - startUptime)
          self.appendMotionSample(t: t, acc: acc, gyro: gyro, quat: quat)
        } else {
          self.pendingMotionSamples.append(
            PendingMotionSample(
              timestamp: motionTimestamp,
              acc: acc,
              gyro: gyro,
              quat: quat
            )
          )
          let maxPendingSamples = 600
          if self.pendingMotionSamples.count > maxPendingSamples {
            self.pendingMotionSamples.removeFirst(self.pendingMotionSamples.count - maxPendingSamples)
          }
        }
      }
    }
  }

  nonisolated private func appendMotionSample(t: Double, acc: SIMD3<Double>, gyro: SIMD3<Double>, quat: SIMD4<Double>) {
    if let last = motionSamples.last?.t, t <= (last + 0.000_001) {
      return
    }
    motionSamples.append(MotionSample(t: t, acc: acc, gyro: gyro, quat: quat))

    let accMagnitude = (acc.x * acc.x + acc.y * acc.y + acc.z * acc.z).squareRoot()
    let gyroMagnitude = (gyro.x * gyro.x + gyro.y * gyro.y + gyro.z * gyro.z).squareRoot()
    let dt: Double
    if let lastTS = motionGuideLastTimestamp {
      dt = max(0.005, t - lastTS)
    } else {
      dt = 0.01
    }
    let jerk = abs(accMagnitude - motionGuideLastAccMagnitude) / dt
    motionGuideLastTimestamp = t
    motionGuideLastAccMagnitude = accMagnitude

    let alpha = 0.18
    motionGuideSmoothedGyro = (1.0 - alpha) * motionGuideSmoothedGyro + alpha * gyroMagnitude
    motionGuideSmoothedAcc = (1.0 - alpha) * motionGuideSmoothedAcc + alpha * accMagnitude
    motionGuideSmoothedJerk = (1.0 - alpha) * motionGuideSmoothedJerk + alpha * jerk

    let candidate = motionGuideCandidateState(at: t)
    guard candidate != motionGuideCurrentState else { return }

    motionGuideCurrentState = candidate
    motionGuideEvents.append(
      MotionGuideEvent(
        t: t,
        state: candidate,
        message: motionGuideMessage(for: candidate)
      )
    )
    DispatchQueue.main.async {
      self.motionGuideState = candidate
    }
  }

  nonisolated private func flushPendingMotionSamples(startUptime: Double) {
    motionSamplesQueue.sync {
      guard !pendingMotionSamples.isEmpty else { return }
      let pending = pendingMotionSamples.sorted { $0.timestamp < $1.timestamp }
      pendingMotionSamples.removeAll(keepingCapacity: true)
      var anchorSample: PendingMotionSample?
      var appendedAny = false
      for sample in pending {
        let t = sample.timestamp - startUptime
        if t < 0 {
          anchorSample = sample
          continue
        }
        if !appendedAny, let anchorSample {
          appendMotionSample(t: 0, acc: anchorSample.acc, gyro: anchorSample.gyro, quat: anchorSample.quat)
          appendedAny = true
        }
        appendMotionSample(t: t, acc: sample.acc, gyro: sample.gyro, quat: sample.quat)
        appendedAny = true
      }
      if !appendedAny, let anchorSample {
        appendMotionSample(t: 0, acc: anchorSample.acc, gyro: anchorSample.gyro, quat: anchorSample.quat)
      }
    }
  }

  private func stopMotionUpdates() {
    motionManager.stopDeviceMotionUpdates()
  }

  nonisolated private func motionGuideCandidateState(at t: Double) -> MotionGuideState {
    if motionGuideSmoothedJerk > 8.0 || motionGuideSmoothedGyro > 1.45 {
      motionGuideLowMotionStart = nil
      return .tooRocky
    }

    if motionGuideSmoothedGyro > 0.78 || motionGuideSmoothedAcc > 1.45 {
      motionGuideLowMotionStart = nil
      return .tooFast
    }

    let lowMotion = motionGuideSmoothedGyro < 0.09 && motionGuideSmoothedAcc < 0.18
    if lowMotion {
      if motionGuideLowMotionStart == nil {
        motionGuideLowMotionStart = t
      }
      if let lowStart = motionGuideLowMotionStart, (t - lowStart) > 1.2 {
        return .tooSlow
      }
    } else {
      motionGuideLowMotionStart = nil
    }

    return .stable
  }

  nonisolated private func motionGuideMessage(for state: MotionGuideState) -> String {
    switch state {
    case .stable:
      return "Bewegung ist gleichmäßig."
    case .tooFast:
      return "Langsamer bewegen und kleinere Schwenks nutzen."
    case .tooSlow:
      return "Etwas gleichmäßiger vorwärts bewegen."
    case .tooRocky:
      return "Gerät ruhiger halten, Ellbogen anlegen."
    }
  }

#if canImport(ARKit)
  private func configureARSessionDelegateIfNeeded() {
    guard arSessionDelegate == nil else { return }
    let delegate = ARTrackingDelegate(recorder: self)
    arSessionDelegate = delegate
    arSession.delegate = delegate
    arSession.delegateQueue = trackingSamplesQueue
  }

  private func selectPreferredARVideoFormat() -> ARConfiguration.VideoFormat? {
    let formats = ARWorldTrackingConfiguration.supportedVideoFormats
    guard !formats.isEmpty else { return nil }
    let cappedFormats = formats.filter { $0.framesPerSecond <= maxTrackingFrameRate }
    let candidateFormats = cappedFormats.isEmpty ? formats : cappedFormats

    if let exact4k30 = candidateFormats.first(where: {
      $0.imageResolution.width == 3840 &&
      $0.imageResolution.height == 2160 &&
      $0.framesPerSecond == 30
    }) {
      return exact4k30
    }

    let fourKFormats = candidateFormats.filter {
      $0.imageResolution.width == 3840 && $0.imageResolution.height == 2160
    }
    if let preferredFourK = fourKFormats.max(by: { $0.framesPerSecond < $1.framesPerSecond }) {
      return preferredFourK
    }

    return candidateFormats.max(by: { lhs, rhs in
      let lhsPixels = Int(lhs.imageResolution.width) * Int(lhs.imageResolution.height)
      let rhsPixels = Int(rhs.imageResolution.width) * Int(rhs.imageResolution.height)
      if lhsPixels != rhsPixels { return lhsPixels < rhsPixels }
      return lhs.framesPerSecond < rhs.framesPerSecond
    })
  }

  private func startARSessionIfNeeded() {
    guard ARWorldTrackingConfiguration.isSupported else { return }
    configureARSessionDelegateIfNeeded()

    let config = ARWorldTrackingConfiguration()
    config.worldAlignment = .gravity
    if let format = selectPreferredARVideoFormat() {
      config.videoFormat = format
      let size = format.imageResolution
      arVideoOutputDimensions = CMVideoDimensions(
        width: Int32(size.width),
        height: Int32(size.height)
      )
      arVideoOutputFPS = max(1, min(format.framesPerSecond, maxTrackingFrameRate))
    } else {
      arVideoOutputDimensions = CMVideoDimensions(width: 3840, height: 2160)
      arVideoOutputFPS = maxTrackingFrameRate
    }
    arSession.run(config, options: [.resetTracking, .removeExistingAnchors])
  }

  private func stopARSessionIfNeeded() {
    arSession.pause()
  }

  nonisolated private func trackingStateString(_ state: ARCamera.TrackingState) -> String {
    switch state {
    case .normal:
      return "normal"
    case .notAvailable:
      return "not_available"
    case .limited(let reason):
      switch reason {
      case .initializing:
        return "limited_initializing"
      case .excessiveMotion:
        return "limited_excessive_motion"
      case .insufficientFeatures:
        return "limited_insufficient_features"
      case .relocalizing:
        return "limited_relocalizing"
      @unknown default:
        return "limited_unknown"
      }
    }
  }

  nonisolated private func worldMappingStatusString(_ status: ARFrame.WorldMappingStatus) -> String {
    switch status {
    case .notAvailable:
      return "not_available"
    case .limited:
      return "limited"
    case .extending:
      return "extending"
    case .mapped:
      return "mapped"
    @unknown default:
      return "unknown"
    }
  }
#endif

  private func select4k60Format(device: AVCaptureDevice) -> AVCaptureDevice.Format? {
    for format in device.formats {
      let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
      guard dims.width == 3840, dims.height == 2160 else { continue }
      if format.videoSupportedFrameRateRanges.contains(where: { $0.maxFrameRate >= 60.0 }) {
        return format
      }
    }
    return nil
  }

  private func select4k30Format(device: AVCaptureDevice) -> AVCaptureDevice.Format? {
    for format in device.formats {
      let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
      guard dims.width == 3840, dims.height == 2160 else { continue }
      if format.videoSupportedFrameRateRanges.contains(where: { $0.maxFrameRate >= 30.0 }) {
        return format
      }
    }
    return nil
  }

  private func writeMotionCSV(to url: URL) throws {
    let locale = Locale(identifier: "en_US_POSIX")
    let samples: [MotionSample] = motionSamplesQueue.sync { motionSamples }
    var lines: [String] = []
    lines.reserveCapacity(samples.count + 1)
    lines.append("timestamp,acc_x,acc_y,acc_z,gyro_x,gyro_y,gyro_z,quat_w,quat_x,quat_y,quat_z")
    for s in samples {
      lines.append(
        [
          String(format: "%.6f", locale: locale, s.t),
          String(format: "%.6f", locale: locale, s.acc.x),
          String(format: "%.6f", locale: locale, s.acc.y),
          String(format: "%.6f", locale: locale, s.acc.z),
          String(format: "%.6f", locale: locale, s.gyro.x),
          String(format: "%.6f", locale: locale, s.gyro.y),
          String(format: "%.6f", locale: locale, s.gyro.z),
          String(format: "%.6f", locale: locale, s.quat.w),
          String(format: "%.6f", locale: locale, s.quat.x),
          String(format: "%.6f", locale: locale, s.quat.y),
          String(format: "%.6f", locale: locale, s.quat.z)
        ].joined(separator: ",")
      )
    }

    let content = lines.joined(separator: "\n") + "\n"
    guard let data = content.data(using: .utf8) else {
      throw RecorderError.writerFailed("CSV Encoding fehlgeschlagen.")
    }
    try data.write(to: url, options: [.atomic])
  }

  private func buildTrackingConsistencyCheck(
    frameTimeline: [FrameTimelineSample],
    motionSamples: [MotionSample]
  ) -> TrackingConsistencyCheck {
    let orderedFrames = frameTimeline.sorted { lhs, rhs in
      if lhs.frameIndex != rhs.frameIndex { return lhs.frameIndex < rhs.frameIndex }
      return lhs.videoPTS < rhs.videoPTS
    }

    var droppedFrameCount = 0
    var nonMonotonicVideoPTSCount = 0
    var nonMonotonicCaptureTimestampCount = 0
    var issues: [String] = []

    if orderedFrames.isEmpty {
      issues.append("no_frames_recorded")
    } else if orderedFrames.first?.frameIndex != 0 {
      issues.append("frame_index_does_not_start_at_0")
    }

    if let firstCaptureTimestamp = orderedFrames.first?.captureTimestamp, firstCaptureTimestamp > 0.05 {
      issues.append("capture_timestamps_not_zero_based")
    }

    if orderedFrames.count > 1 {
      let firstDeltaVideoPTS = orderedFrames[1].videoPTS - orderedFrames[0].videoPTS
      if firstDeltaVideoPTS > 0.20 {
        issues.append("initial_frame_gap_video_pts")
      }
      let firstDeltaCapture = orderedFrames[1].captureTimestamp - orderedFrames[0].captureTimestamp
      if firstDeltaCapture > 0.20 {
        issues.append("initial_frame_gap_capture_timestamp")
      }
    }

    for idx in 1..<orderedFrames.count {
      let prev = orderedFrames[idx - 1]
      let current = orderedFrames[idx]

      let expectedFrameIndex = prev.frameIndex + 1
      if current.frameIndex > expectedFrameIndex {
        droppedFrameCount += (current.frameIndex - expectedFrameIndex)
      } else if current.frameIndex <= prev.frameIndex {
        issues.append("frame_index_not_strictly_increasing")
      }

      if current.videoPTS + 0.000_001 < prev.videoPTS {
        nonMonotonicVideoPTSCount += 1
      }
      if current.captureTimestamp + 0.000_001 < prev.captureTimestamp {
        nonMonotonicCaptureTimestampCount += 1
      }
    }

    if droppedFrameCount > 0 {
      issues.append("frame_index_gap_detected")
    }
    if nonMonotonicVideoPTSCount > 0 {
      issues.append("video_pts_not_monotonic")
    }
    if nonMonotonicCaptureTimestampCount > 0 {
      issues.append("capture_timestamp_not_monotonic")
    }

    let videoDurationSeconds = max(0, orderedFrames.last?.videoPTS ?? 0)
    let motionDurationSeconds: Double
    if let first = motionSamples.first?.t, let last = motionSamples.last?.t {
      motionDurationSeconds = max(0, last - first)
    } else {
      motionDurationSeconds = 0
    }

    if motionSamples.isEmpty {
      issues.append("no_motion_samples")
    } else {
      if let firstMotionTime = motionSamples.first?.t, firstMotionTime > 0.25 {
        issues.append("motion_starts_late")
      }
      if let lastMotionTime = motionSamples.last?.t, (lastMotionTime + 0.25) < videoDurationSeconds {
        issues.append("motion_ends_early")
      }
    }

    let status: TrackingConsistencyCheck.Status = issues.isEmpty ? .ok : .warning
    return TrackingConsistencyCheck(
      status: status,
      issues: issues,
      frameCount: orderedFrames.count,
      droppedFrameCount: droppedFrameCount,
      nonMonotonicVideoPTSCount: nonMonotonicVideoPTSCount,
      nonMonotonicCaptureTimestampCount: nonMonotonicCaptureTimestampCount,
      motionSampleCount: motionSamples.count,
      videoDurationSeconds: videoDurationSeconds,
      motionDurationSeconds: motionDurationSeconds
    )
  }

  private func syncCheckWarningMessage(for check: TrackingConsistencyCheck) -> String? {
    guard check.status == .warning else { return nil }
    let primaryIssue = check.issues.first ?? "unknown_sync_issue"
    return "Sync-Check: \(primaryIssue)."
  }

  private func writeTrackingJSON(to url: URL, videoURL: URL) throws -> TrackingConsistencyCheck {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    let samples: [ARTrackingSample] = trackingSamplesQueue.sync { trackingSamples }
    let frameTimeline: [FrameTimelineSample] = trackingSamplesQueue.sync { frameTimelineSamples }
    let motionEvents: [MotionGuideEvent] = motionSamplesQueue.sync { motionGuideEvents }
    let motionSamplesSnapshot: [MotionSample] = motionSamplesQueue.sync { motionSamples }
    let sync = TrackingSyncMetadata(
      motionTimebaseStartUptime: motionTimebaseStartUptime,
      firstFrameCaptureTimestamp: firstFrameCaptureTimestamp,
      firstFrameCallbackUptime: firstFrameCallbackUptime,
      hostTimeAligned: hostTimeAligned
    )
    let consistencyCheck = buildTrackingConsistencyCheck(
      frameTimeline: frameTimeline,
      motionSamples: motionSamplesSnapshot
    )
    let payload = ARTrackingFile(
      videoFile: videoURL.lastPathComponent,
      recordStart: formatter.string(from: recordStartDate ?? Date()),
      arStartTimestamp: arStartTimestamp,
      samples: samples,
      frameTimeline: frameTimeline,
      sync: sync,
      consistencyCheck: consistencyCheck,
      motionCoachingEvents: motionEvents
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(payload)
    try data.write(to: url, options: [.atomic])
    return consistencyCheck
  }

  nonisolated private func parseIntrinsicMatrixArray(from matrixData: Data) -> [[Float]]? {
    guard matrixData.count == MemoryLayout<matrix_float3x3>.size else { return nil }
    var m = matrix_float3x3()
    matrixData.withUnsafeBytes { raw in
      guard let src = raw.baseAddress else { return }
      memcpy(&m, src, MemoryLayout<matrix_float3x3>.size)
    }
    return [
      [m.columns.0.x, m.columns.1.x, m.columns.2.x],
      [m.columns.0.y, m.columns.1.y, m.columns.2.y],
      [m.columns.0.z, m.columns.1.z, m.columns.2.z]
    ]
  }

  nonisolated private func intrinsicsPayload(width: Int, height: Int, matrixArray: [[Float]], source: String? = nil) -> [String: Any] {
    var payload: [String: Any] = [
      "width": width,
      "height": height,
      "intrinsic_matrix": matrixArray
    ]

    if matrixArray.count == 3,
       matrixArray[0].count == 3,
       matrixArray[1].count == 3 {
      payload["fx"] = matrixArray[0][0]
      payload["fy"] = matrixArray[1][1]
      payload["cx"] = matrixArray[0][2]
      payload["cy"] = matrixArray[1][2]
    }
    if let source {
      payload["intrinsic_source"] = source
    }
    return payload
  }

  nonisolated private func estimatedIntrinsicsMatrix(width: Int, height: Int) -> [[Float]]? {
    guard width > 0, height > 0 else { return nil }
    guard let fovXDegrees = fallbackHorizontalFOVDegrees else { return nil }
    guard fovXDegrees.isFinite, fovXDegrees > 1.0, fovXDegrees < 179.0 else { return nil }

    let fovX = fovXDegrees * Double.pi / 180.0
    let tanHalfFovX = tan(fovX * 0.5)
    guard tanHalfFovX.isFinite, tanHalfFovX > 0 else { return nil }

    let widthF = Double(width)
    let heightF = Double(height)
    let aspect = widthF / heightF
    guard aspect.isFinite, aspect > 0 else { return nil }

    let fx = widthF / (2.0 * tanHalfFovX)
    let fovY = 2.0 * atan(tanHalfFovX / aspect)
    let tanHalfFovY = tan(fovY * 0.5)
    guard tanHalfFovY.isFinite, tanHalfFovY > 0 else { return nil }
    let fy = heightF / (2.0 * tanHalfFovY)
    let cx = (widthF - 1.0) * 0.5
    let cy = (heightF - 1.0) * 0.5

    return [
      [Float(fx), 0, Float(cx)],
      [0, Float(fy), Float(cy)],
      [0, 0, 1]
    ]
  }

  nonisolated private func normalizedCaptureTimestamp(
    cameraTimestamp: Double,
    fallbackVideoPTS: Double,
    callbackUptime: Double
  ) -> Double {
    if hostTimeAligned,
       let startUptime,
       let captureTimestampToUptimeOffset,
       cameraTimestamp.isFinite {
      return max(0, (cameraTimestamp + captureTimestampToUptimeOffset) - startUptime)
    }
    if let startUptime {
      return max(0, callbackUptime - startUptime)
    }
    return max(0, fallbackVideoPTS)
  }

  nonisolated private func armAVSyncAnchor(captureTimestamp: Double, callbackUptime: Double) {
    firstFrameCallbackUptime = callbackUptime
    firstFrameCaptureTimestamp = captureTimestamp.isFinite ? captureTimestamp : nil
    // Use callback uptime as shared master clock with CoreMotion.
    startUptime = callbackUptime
    motionTimebaseStartUptime = callbackUptime
    if captureTimestamp.isFinite {
      // Map capture timestamps onto uptime so capture_timestamp and IMU share t=0.
      hostTimeAligned = true
      captureTimestampToUptimeOffset = callbackUptime - captureTimestamp
    } else {
      hostTimeAligned = false
      captureTimestampToUptimeOffset = nil
    }
    flushPendingMotionSamples(startUptime: callbackUptime)
  }

#if canImport(ARKit)
  nonisolated private func armARSyncAnchor(frameTimestamp: Double, callbackUptime: Double) {
    arStartTimestamp = frameTimestamp
    firstFrameCallbackUptime = callbackUptime
    firstFrameCaptureTimestamp = frameTimestamp.isFinite ? frameTimestamp : nil
    // Keep AR and motion on the same callback-uptime timeline.
    startUptime = callbackUptime
    motionTimebaseStartUptime = callbackUptime
    if frameTimestamp.isFinite {
      hostTimeAligned = true
      captureTimestampToUptimeOffset = callbackUptime - frameTimestamp
    } else {
      hostTimeAligned = false
      captureTimestampToUptimeOffset = nil
    }
    flushPendingMotionSamples(startUptime: callbackUptime)
  }
#endif

  nonisolated private func writeIntrinsicsJSONIfNeeded(sampleBuffer: CMSampleBuffer, url: URL) {
    guard !hasWrittenIntrinsics else { return }
    guard let format = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
    let dims = CMVideoFormatDescriptionGetDimensions(format)

    let matrixArrayFromAttachment: [[Float]]? = {
      guard let matrixData = CMGetAttachment(
        sampleBuffer,
        key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix,
        attachmentModeOut: nil
      ) as? Data else {
        return nil
      }
      return parseIntrinsicMatrixArray(from: matrixData)
    }()

    let matrixArray: [[Float]]
    let source: String
    if let matrixArrayFromAttachment {
      matrixArray = matrixArrayFromAttachment
      source = "hardware_attachment"
      intrinsicsMissingFrameCount = 0
    } else {
      intrinsicsMissingFrameCount += 1
      guard intrinsicsMissingFrameCount >= intrinsicsFallbackAfterFrameCount,
            let estimated = estimatedIntrinsicsMatrix(width: Int(dims.width), height: Int(dims.height)) else {
        // Keep trying on subsequent frames until intrinsics become available or fallback is allowed.
        return
      }
      matrixArray = estimated
      source = "estimated_fov"
    }

    let payload = intrinsicsPayload(
      width: Int(dims.width),
      height: Int(dims.height),
      matrixArray: matrixArray,
      source: source
    )
    guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else { return }
    try? data.write(to: url, options: [.atomic])
    hasWrittenIntrinsics = true
  }

#if canImport(ARKit)
  nonisolated private func writeIntrinsicsJSONIfNeeded(width: Int, height: Int, matrixArray: [[Float]], url: URL) {
    guard !hasWrittenIntrinsics else { return }
    let payload = intrinsicsPayload(width: width, height: height, matrixArray: matrixArray, source: "arkit_camera")
    guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else { return }
    try? data.write(to: url, options: [.atomic])
    hasWrittenIntrinsics = true
    intrinsicsMissingFrameCount = 0
  }

  nonisolated private func writeIntrinsicsJSONIfNeeded(frame: ARFrame, url: URL) {
    let matrix = frame.camera.intrinsics
    let dims = frame.camera.imageResolution
    let matrixArray: [[Float]] = [
      [matrix.columns.0.x, matrix.columns.1.x, matrix.columns.2.x],
      [matrix.columns.0.y, matrix.columns.1.y, matrix.columns.2.y],
      [matrix.columns.0.z, matrix.columns.1.z, matrix.columns.2.z]
    ]
    writeIntrinsicsJSONIfNeeded(
      width: Int(dims.width),
      height: Int(dims.height),
      matrixArray: matrixArray,
      url: url
    )
  }

  nonisolated private func copyPixelBufferForWriter(_ source: CVPixelBuffer, pool: CVPixelBufferPool) -> CVPixelBuffer? {
    var copied: CVPixelBuffer?
    let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &copied)
    guard status == kCVReturnSuccess, let copied else { return nil }
    let ciImage = CIImage(cvPixelBuffer: source)
    writerCIContext.render(ciImage, to: copied)
    return copied
  }

  nonisolated private func publishARPreviewIfNeeded(from pixelBuffer: CVPixelBuffer, relativeTime: TimeInterval) {
    let previewInterval = 1.0 / 12.0
    if (relativeTime - lastARPreviewTimestamp) < previewInterval { return }
    lastARPreviewTimestamp = relativeTime

    let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(forExifOrientation: 6)
    let extent = ciImage.extent
    let longestEdge = max(extent.width, extent.height)
    let previewLongestEdge: CGFloat = 1280
    let scale = longestEdge > previewLongestEdge ? (previewLongestEdge / longestEdge) : 1.0
    let scaledImage = scale < 1.0
      ? ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
      : ciImage
    guard let cgImage = previewCIContext.createCGImage(scaledImage, from: scaledImage.extent) else { return }
    DispatchQueue.main.async {
      self.arPreviewImage = cgImage
    }
  }
#endif

  nonisolated private func retimedSampleBuffer(_ sampleBuffer: CMSampleBuffer, offset: CMTime) -> CMSampleBuffer? {
    var count: CMItemCount = 0
    CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)
    var timing = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .invalid, decodeTimeStamp: .invalid), count: count)
    CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: count, arrayToFill: &timing, entriesNeededOut: &count)
    for i in 0..<count {
      timing[i].presentationTimeStamp = timing[i].presentationTimeStamp - offset
      if timing[i].decodeTimeStamp.isValid {
        timing[i].decodeTimeStamp = timing[i].decodeTimeStamp - offset
      }
    }
    var out: CMSampleBuffer?
    CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: sampleBuffer, sampleTimingEntryCount: count, sampleTimingArray: &timing, sampleBufferOut: &out)
    return out
  }

  private func refreshZoomState(selectedPreset: Double) {
    let presets = buildZoomPresets()
    DispatchQueue.main.async {
      self.zoomPresets = presets
      self.currentZoomFactor = selectedPreset
    }
  }

  private func normalizedZoomPreset(for requested: Double) -> Double {
    let presets = zoomPresets.isEmpty ? [1.0, 2.0] : zoomPresets
    return presets.min(by: { abs($0 - requested) < abs($1 - requested) }) ?? 1.0
  }

  private func buildZoomPresets() -> [Double] {
    var presets: [Double] = [1.0, 2.0]

    if let ultra = findBackCamera(of: .builtInUltraWideCamera),
       supportsPreferredLensFormat(device: ultra) {
      presets.insert(0.5, at: 0)
    }

    if let tele = findBackCamera(of: .builtInTelephotoCamera),
       supportsPreferredLensFormat(device: tele) {
      presets.append(5.0)
    }

    return presets
  }

  private func selectLensDevice(for requestedZoom: Double) -> AVCaptureDevice? {
    if requestedZoom <= 0.75,
       let ultra = findBackCamera(of: .builtInUltraWideCamera),
       supportsPreferredLensFormat(device: ultra) {
      return ultra
    }
    if requestedZoom >= 4.0,
       let tele = findBackCamera(of: .builtInTelephotoCamera),
       supportsPreferredLensFormat(device: tele) {
      return tele
    }
    if let wide = findBackCamera(of: .builtInWideAngleCamera) {
      return wide
    }
    return selectBackCamera()
  }

  private func mapRequestedZoomToDeviceZoom(requested: Double, device: AVCaptureDevice) -> Double {
    switch device.deviceType {
    case .builtInUltraWideCamera:
      // 0.5x should be the native ultra-wide lens.
      return 1.0
    case .builtInTelephotoCamera:
      // 5x should be the native tele lens (device-specific; we map preset to native).
      return requested >= 4.0 ? 1.0 : requested
    default:
      // Wide-angle / virtual devices: use zoom factor directly.
      return requested
    }
  }

  private func findBackCamera(of type: AVCaptureDevice.DeviceType) -> AVCaptureDevice? {
    let discovery = AVCaptureDevice.DiscoverySession(
      deviceTypes: [type],
      mediaType: .video,
      position: .back
    )
    return discovery.devices.first
  }

  private func supportsPreferredLensFormat(device: AVCaptureDevice) -> Bool {
    select4k60Format(device: device) != nil || select4k30Format(device: device) != nil
  }

  private func applyPreferred4KFormat(device: AVCaptureDevice) throws -> Bool {
    let selectedFormat: AVCaptureDevice.Format?
    let targetFPS: Int32 = Int32(maxTrackingFrameRate)

    if let format30 = select4k30Format(device: device) {
      selectedFormat = format30
    } else if let format60 = select4k60Format(device: device) {
      selectedFormat = format60
    } else {
      return false
    }

    guard let format = selectedFormat else { return false }
    let targetFPSDouble = Double(targetFPS)
    let supportsTargetFPS = format.videoSupportedFrameRateRanges.contains {
      $0.minFrameRate <= targetFPSDouble && $0.maxFrameRate >= targetFPSDouble
    }
    guard supportsTargetFPS else { return false }

    try device.lockForConfiguration()
    device.activeFormat = format
    let duration = CMTime(value: 1, timescale: targetFPS)
    device.activeVideoMinFrameDuration = duration
    device.activeVideoMaxFrameDuration = duration
    device.unlockForConfiguration()
    return true
  }

  private func switchToDevice(_ device: AVCaptureDevice) -> Bool {
    session.beginConfiguration()
    defer { session.commitConfiguration() }

    for input in session.inputs {
      session.removeInput(input)
    }

    do {
      let input = try AVCaptureDeviceInput(device: device)
      guard session.canAddInput(input) else {
        DispatchQueue.main.async { self.warningMessage = "Kamera konnte nicht umgeschaltet werden." }
        return false
      }
      session.addInput(input)
      videoDevice = device

      if try !applyPreferred4KFormat(device: device) {
        DispatchQueue.main.async { self.warningMessage = "Gewähltes Objektiv unterstützt kein 4K-Profil." }
      }
      self.fallbackHorizontalFOVDegrees = Double(device.activeFormat.videoFieldOfView)

      if let connection = videoOutput.connection(with: .video) {
        self.applyVideoConnectionState(connection: connection)
      }

      DispatchQueue.main.async {
        self.zoomPresets = self.buildZoomPresets()
      }

      return true
    } catch {
      DispatchQueue.main.async { self.warningMessage = error.localizedDescription }
      return false
    }
  }

  private func selectBackCamera() -> AVCaptureDevice? {
    let discovery = AVCaptureDevice.DiscoverySession(
      deviceTypes: [
        .builtInTripleCamera,
        .builtInDualWideCamera,
        .builtInDualCamera,
        .builtInWideAngleCamera,
        .builtInUltraWideCamera,
        .builtInTelephotoCamera
      ],
      mediaType: .video,
      position: .back
    )

    let devices = discovery.devices
    let preferredOrder: [AVCaptureDevice.DeviceType] = [
      .builtInTripleCamera,
      .builtInDualWideCamera,
      .builtInDualCamera,
      .builtInWideAngleCamera
    ]
    for type in preferredOrder {
      if let device = devices.first(where: { $0.deviceType == type }) {
        return device
      }
    }
    return devices.first
  }

  private func applyVideoConnectionState(connection: AVCaptureConnection) {
    // Keep the raw stream in landscape 4K (3840x2160). The UI can stay portrait.
    if #available(iOS 17.0, *) {
      // 0 degrees = native sensor orientation (typically landscape for back camera). Avoids rotating buffers.
      if connection.isVideoRotationAngleSupported(0) {
        connection.videoRotationAngle = 0
      }
    } else {
      connection.videoOrientation = .landscapeRight
    }

    let supportsStabilization = connection.isVideoStabilizationSupported
    if supportsStabilization {
      connection.preferredVideoStabilizationMode = desiredStabilizationEnabled ? .auto : .off
    }

    if connection.isCameraIntrinsicMatrixDeliverySupported {
      connection.isCameraIntrinsicMatrixDeliveryEnabled = true
    }

    DispatchQueue.main.async {
      self.isStabilizationSupported = supportsStabilization
      self.stabilizationEnabled = supportsStabilization ? self.desiredStabilizationEnabled : false
    }
  }
}

extension VideoTakeRecorder {
  // Called on outputQueue (sampleBufferCallbackQueue).
  nonisolated fileprivate func handleVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
    guard recordingActive else { return }
    guard !usesARFramePipeline else { return }
    guard let urls = recordingURLs, let writer, let input = writerVideoInput else { return }

    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    let callbackUptime = ProcessInfo.processInfo.systemUptime
    if firstPTS == nil {
      if writer.status == .failed {
        let message = writer.error?.localizedDescription ?? "startWriting fehlgeschlagen."
        DispatchQueue.main.async {
          self.warningMessage = RecorderError.writerFailed(message).localizedDescription
        }
        return
      }

      if !writerSessionPrimed {
        discardedWarmupFrames += 1
        if discardedWarmupFrames <= activeWriterWarmupFrameCount {
          avWarmupLastPTS = pts
          return
        }

        if let previousPTS = avWarmupLastPTS {
          let delta = CMTimeGetSeconds(pts - previousPTS)
          avWarmupLastPTS = pts
          guard delta.isFinite,
                delta >= writerStartupMinGapSeconds,
                delta <= writerStartupMaxGapSeconds else {
            writerStartupStableFrameCount = 0
            return
          }
          writerStartupStableFrameCount += 1
          guard writerStartupStableFrameCount >= writerStartupStableFrameCountRequired else {
            return
          }
        } else {
          avWarmupLastPTS = pts
          writerStartupStableFrameCount = 0
          return
        }

        avWarmupLastPTS = nil
        writerStartupStableFrameCount = 0
        if writer.status == .unknown {
          if writer.startWriting() {
            writer.startSession(atSourceTime: .zero)
          } else {
            DispatchQueue.main.async { self.warningMessage = RecorderError.writerFailed("startWriting fehlgeschlagen.").localizedDescription }
            return
          }
        }
        writerSessionPrimed = true
        // Allow encoder pipeline to settle before persisting frame index 0.
        return
      }

      guard input.isReadyForMoreMediaData else { return }
      if let previousPTS = avWarmupLastPTS {
        let delta = CMTimeGetSeconds(pts - previousPTS)
        avWarmupLastPTS = pts
        guard delta.isFinite,
              delta >= writerStartupMinGapSeconds,
              delta <= writerStartupMaxGapSeconds else {
          writerStartupStableFrameCount = 0
          return
        }
        writerStartupStableFrameCount += 1
        guard writerStartupStableFrameCount >= writerPostPrimeStableFrameCountRequired else {
          return
        }
        avWarmupLastPTS = nil
        writerStartupStableFrameCount = 0
      } else {
        avWarmupLastPTS = pts
        writerStartupStableFrameCount = 0
        return
      }
    }

    if !hasWrittenIntrinsics {
      writeIntrinsicsJSONIfNeeded(sampleBuffer: sampleBuffer, url: urls.intrinsicsJSONURL)
    }

    let writerStartPTS = firstPTS ?? pts
    let offset = writerStartPTS
    let adjusted = retimedSampleBuffer(sampleBuffer, offset: offset) ?? sampleBuffer

    guard input.isReadyForMoreMediaData else {
      return
    }
    guard input.append(adjusted) else {
      if let error = writer.error {
        DispatchQueue.main.async {
          self.warningMessage = RecorderError.writerFailed(error.localizedDescription).localizedDescription
        }
      }
      return
    }

    if firstPTS == nil {
      firstPTS = pts
      let captureTimestamp = CMTimeGetSeconds(pts)
      armAVSyncAnchor(captureTimestamp: captureTimestamp, callbackUptime: callbackUptime)
    }

    guard let firstPTS else { return }
    let seconds = max(0, CMTimeGetSeconds(pts - firstPTS))
    let captureTimestamp = CMTimeGetSeconds(pts)
    let normalizedCaptureTS = normalizedCaptureTimestamp(
      cameraTimestamp: captureTimestamp,
      fallbackVideoPTS: seconds,
      callbackUptime: callbackUptime
    )
    let frameIndex = recordedFrameIndex
    recordedFrameIndex += 1
    trackingSamplesQueue.sync {
      frameTimelineSamples.append(
        FrameTimelineSample(
          frameIndex: frameIndex,
          videoPTS: seconds,
          captureTimestamp: normalizedCaptureTS,
          source: "avcapture"
        )
      )
    }

    DispatchQueue.main.async {
      self.durationSeconds = seconds
    }
  }
}

#if canImport(ARKit)
extension VideoTakeRecorder {
  // Called on the ARSession delegate queue. Keep it tiny to avoid ARFrame retention warnings.
  nonisolated fileprivate func handleARFrame(_ frame: ARFrame) {
    guard recordingActive else { return }
    guard usesARFramePipeline else { return }
    guard recordingURLs != nil, writer != nil, writerVideoInput != nil, writerPixelBufferAdaptor != nil else { return }

    let camera = frame.camera
    let intrinsicsSnapshot: ARIntrinsicsSnapshot?
    if hasWrittenIntrinsics {
      intrinsicsSnapshot = nil
    } else {
      let matrix = camera.intrinsics
      let dims = camera.imageResolution
      intrinsicsSnapshot = ARIntrinsicsSnapshot(
        width: Int(dims.width),
        height: Int(dims.height),
        matrix: [
          [matrix.columns.0.x, matrix.columns.1.x, matrix.columns.2.x],
          [matrix.columns.0.y, matrix.columns.1.y, matrix.columns.2.y],
          [matrix.columns.0.z, matrix.columns.1.z, matrix.columns.2.z]
        ]
      )
    }

    let snapshot = ARFrameSnapshot(
      timestamp: frame.timestamp,
      pixelBuffer: frame.capturedImage,
      transform: camera.transform,
      trackingState: trackingStateString(camera.trackingState),
      rawFeaturePointsCount: frame.rawFeaturePoints?.points.count,
      worldMappingStatus: worldMappingStatusString(frame.worldMappingStatus),
      intrinsics: intrinsicsSnapshot
    )

    // Drop frames under load instead of stalling ARKit delegate delivery.
    guard arFrameProcessingSemaphore.wait(timeout: .now()) == .success else { return }
    outputQueue.async { [self] in
      processARFrameSnapshot(snapshot)
    }
  }

  nonisolated private func processARFrameSnapshot(_ snapshot: ARFrameSnapshot) {
    defer { arFrameProcessingSemaphore.signal() }
    guard recordingActive else { return }
    guard usesARFramePipeline else { return }
    guard let urls = recordingURLs, let writer, let input = writerVideoInput, let adaptor = writerPixelBufferAdaptor else { return }

    let callbackUptime = ProcessInfo.processInfo.systemUptime
    let frameTimestamp = snapshot.timestamp
    if arStartTimestamp == nil {
      if writer.status == .failed {
        let message = writer.error?.localizedDescription ?? "startWriting fehlgeschlagen."
        DispatchQueue.main.async {
          self.warningMessage = RecorderError.writerFailed(message).localizedDescription
        }
        return
      }

      guard writer.status == .unknown || writer.status == .writing else { return }
      discardedWarmupFrames += 1
      if discardedWarmupFrames <= activeWriterWarmupFrameCount {
        arWarmupLastTimestamp = frameTimestamp
        return
      }

      if let previousTimestamp = arWarmupLastTimestamp {
        let delta = frameTimestamp - previousTimestamp
        arWarmupLastTimestamp = frameTimestamp
        guard delta.isFinite,
              delta >= writerStartupMinGapSeconds,
              delta <= writerStartupMaxGapSeconds else {
          writerStartupStableFrameCount = 0
          return
        }
        writerStartupStableFrameCount += 1
        guard writerStartupStableFrameCount >= writerStartupStableFrameCountRequired else {
          return
        }
      } else {
        arWarmupLastTimestamp = frameTimestamp
        writerStartupStableFrameCount = 0
        return
      }

      if writer.status == .unknown {
        if writer.startWriting() {
          writer.startSession(atSourceTime: .zero)
        } else {
          let message = writer.error?.localizedDescription ?? "startWriting fehlgeschlagen."
          DispatchQueue.main.async {
            self.warningMessage = RecorderError.writerFailed(message).localizedDescription
          }
          return
        }
      }

      arWarmupLastTimestamp = nil
      writerStartupStableFrameCount = 0
    }

    let activeStartTimestamp = arStartTimestamp ?? frameTimestamp
    let relativeTime = max(0, frameTimestamp - activeStartTimestamp)
    let minFrameInterval = 1.0 / Double(max(1, min(arVideoOutputFPS, maxTrackingFrameRate)))
    if recordedFrameIndex > 0,
       (relativeTime - lastAcceptedARFrameTimestamp) + 0.000_001 < minFrameInterval {
      return
    }
    let pts = CMTime(seconds: relativeTime, preferredTimescale: 600)
    let sourcePixelBuffer = snapshot.pixelBuffer

    publishARPreviewIfNeeded(from: sourcePixelBuffer, relativeTime: relativeTime)

    guard input.isReadyForMoreMediaData else { return }
    guard let pool = adaptor.pixelBufferPool,
          let writerPixelBuffer = copyPixelBufferForWriter(sourcePixelBuffer, pool: pool) else {
      return
    }
    guard adaptor.append(writerPixelBuffer, withPresentationTime: pts) else {
      if let error = writer.error {
        DispatchQueue.main.async {
          self.warningMessage = RecorderError.writerFailed(error.localizedDescription).localizedDescription
        }
      }
      return
    }

    if arStartTimestamp == nil {
      armARSyncAnchor(frameTimestamp: frameTimestamp, callbackUptime: callbackUptime)
    }
    guard let arStartTimestamp else { return }
    let anchoredRelativeTime = max(0, frameTimestamp - arStartTimestamp)
    lastAcceptedARFrameTimestamp = anchoredRelativeTime

    if let intrinsics = snapshot.intrinsics {
      writeIntrinsicsJSONIfNeeded(
        width: intrinsics.width,
        height: intrinsics.height,
        matrixArray: intrinsics.matrix,
        url: urls.intrinsicsJSONURL
      )
    }

    let transform = snapshot.transform
    let position = [
      Double(transform.columns.3.x),
      Double(transform.columns.3.y),
      Double(transform.columns.3.z)
    ]

    let rotationMatrix = simd_float3x3(
      SIMD3<Float>(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
      SIMD3<Float>(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
      SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
    )
    let quat = simd_quatf(rotationMatrix)

    let frameIndex = recordedFrameIndex
    recordedFrameIndex += 1
    let normalizedCaptureTS = normalizedCaptureTimestamp(
      cameraTimestamp: frameTimestamp,
      fallbackVideoPTS: anchoredRelativeTime,
      callbackUptime: callbackUptime
    )
    trackingSamplesQueue.sync {
      frameTimelineSamples.append(
        FrameTimelineSample(
          frameIndex: frameIndex,
          videoPTS: anchoredRelativeTime,
          captureTimestamp: normalizedCaptureTS,
          source: "arkit"
        )
      )
    }

    let sample = ARTrackingSample(
      frameIndex: frameIndex,
      videoPTS: anchoredRelativeTime,
      t: anchoredRelativeTime,
      position: position,
      rotation: [
        Double(quat.vector.x),
        Double(quat.vector.y),
        Double(quat.vector.z),
        Double(quat.vector.w)
      ],
      trackingState: snapshot.trackingState,
      rawFeaturePointsCount: snapshot.rawFeaturePointsCount,
      worldMappingStatus: snapshot.worldMappingStatus
    )
    trackingSamplesQueue.sync {
      trackingSamples.append(sample)
    }

    DispatchQueue.main.async {
      self.durationSeconds = anchoredRelativeTime
    }
  }
}
#endif
