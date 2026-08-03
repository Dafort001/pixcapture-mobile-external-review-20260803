@preconcurrency import AVFoundation
import ImageIO
import Photos
import CoreImage
import CoreMedia
import Foundation
import os
import SwiftUI
import Combine
import UniformTypeIdentifiers
import UIKit

enum LiveQualityState {
  case good
  case warning
  case bad

  var manifestToken: String {
    switch self {
    case .good:
      return "good"
    case .warning:
      return "warning"
    case .bad:
      return "bad"
    }
  }
}

enum CaptureMetadataRewriter {
  static func resolvedExposureSeconds(deviceExposureSeconds: Double?, requestedSeconds: Double?) -> Double? {
    let candidates = [deviceExposureSeconds, requestedSeconds]
    for candidate in candidates {
      guard let candidate, candidate.isFinite, candidate > 0 else { continue }
      return candidate
    }
    return nil
  }

  static func rewriteExposureMetadata(
    data: Data,
    outputFormat: PhotoFormat,
    exposureSeconds: Double?,
    iso: Float?
  ) -> Data {
    guard outputFormat != .proRaw else { return data }
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let sourceType = CGImageSourceGetType(source) else {
      return data
    }

    let writableImageDestinationTypes = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
    guard writableImageDestinationTypes.contains(sourceType as String) else {
      return data
    }

    var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
    var exif = (properties[kCGImagePropertyExifDictionary] as? [CFString: Any]) ?? [:]
    var didUpdate = false

    if let exposureSeconds = resolvedExposureSeconds(deviceExposureSeconds: exposureSeconds, requestedSeconds: nil) {
      exif[kCGImagePropertyExifExposureTime] = exposureSeconds
      exif[kCGImagePropertyExifShutterSpeedValue] = -log2(exposureSeconds)
      didUpdate = true
    }

    if let iso, iso.isFinite, iso > 0 {
      exif[kCGImagePropertyExifISOSpeedRatings] = [max(Int(iso.rounded()), 1)]
      didUpdate = true
    }

    guard didUpdate else { return data }

    properties[kCGImagePropertyExifDictionary] = exif

    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, sourceType, 1, nil) else {
      return data
    }

    CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      return data
    }

    return output as Data
  }
}

struct ActivePhotoFormatCandidate {
  let highestPhotoQualitySupported: Bool
  let maxPhotoArea: Int64
  let streamingArea: Int64
  let minExposureSeconds: Double
  let minISO: Float
  let maxExposureSeconds: Double
}

enum ActivePhotoFormatSelector {
  static func preferredCandidateIndex(in candidates: [ActivePhotoFormatCandidate]) -> Int? {
    let photoCandidates = candidates.indices.filter {
      candidates[$0].highestPhotoQualitySupported && candidates[$0].maxPhotoArea > 0
    }
    let dimensionCandidates = candidates.indices.filter { candidates[$0].maxPhotoArea > 0 }
    let pool = !photoCandidates.isEmpty ? photoCandidates : (!dimensionCandidates.isEmpty ? dimensionCandidates : Array(candidates.indices))
    guard !pool.isEmpty else { return nil }

    return pool.min { lhs, rhs in
      let lhsCandidate = candidates[lhs]
      let rhsCandidate = candidates[rhs]

      if abs(lhsCandidate.minExposureSeconds - rhsCandidate.minExposureSeconds) > 0.000_000_1 {
        return lhsCandidate.minExposureSeconds < rhsCandidate.minExposureSeconds
      }
      if lhsCandidate.maxPhotoArea != rhsCandidate.maxPhotoArea {
        return lhsCandidate.maxPhotoArea > rhsCandidate.maxPhotoArea
      }
      if abs(lhsCandidate.minISO - rhsCandidate.minISO) > 0.5 {
        return lhsCandidate.minISO < rhsCandidate.minISO
      }
      if abs(lhsCandidate.maxExposureSeconds - rhsCandidate.maxExposureSeconds) > 0.000_1 {
        return lhsCandidate.maxExposureSeconds > rhsCandidate.maxExposureSeconds
      }
      return lhsCandidate.streamingArea > rhsCandidate.streamingArea
    }
  }
}

enum RawPixelFormatSelector {
  static func preferredSensorRawPixelFormatType(in rawTypes: [OSType]) -> OSType? {
    rawTypes.first
  }
}

enum BracketCompressionWarningEvaluator {
  static func isSeriesCompressed(_ samples: [ExposureSample], stepEV: Double) -> Bool {
    guard samples.count > 1 else { return false }
    let minDuration = samples.map(\.effectiveDuration.seconds).min() ?? 0
    let maxDuration = samples.map(\.effectiveDuration.seconds).max() ?? 0
    let totalRatio = maxDuration / max(minDuration, 0.000_001)
    let expectedRatio = pow(2.0, stepEV * Double(samples.count - 1))
    return totalRatio < expectedRatio * 0.7
  }

  static func shouldWarn(
    samples: [ExposureSample],
    requestedCount: Int,
    stepEV: Double,
    trimmedFromCount: Int
  ) -> Bool {
    guard trimmedFromCount == 0 else { return false }
    guard samples.count == requestedCount else { return false }
    return isSeriesCompressed(samples, stepEV: stepEV)
  }
}

enum ExtremeBacklightShadowRecoveryHeuristics {
  static func shouldPreferBrighterShift(
    brightClipRatio: Double,
    darkClipRatio: Double,
    meanLuma: Double
  ) -> Bool {
    brightClipRatio <= 0.08 && darkClipRatio >= 0.18 && meanLuma <= 0.24
  }
}

enum HighContrastBracketExpansionPolicy {
  static func expandedCount(
    requestedCount: Int,
    needsDarkEdgeRecovery: Bool
  ) -> Int {
    guard needsDarkEdgeRecovery else { return requestedCount }
    guard requestedCount > 1 else { return requestedCount }
    return requestedCount < 7 ? 7 : requestedCount
  }
}

enum SceneAdaptiveBracketPlan {
  case fixedFive
  case highContrastSeven

  var bracketCount: Int {
    switch self {
    case .fixedFive:
      return 5
    case .highContrastSeven:
      return 7
    }
  }

  var warningMessage: String? {
    switch self {
    case .fixedFive:
      return nil
    case .highContrastSeven:
      return "Hochkontrast erkannt. Automatisch 7er-Reihe mit engeren EV-Abstaenden."
    }
  }
}

final class CameraManager: NSObject, ObservableObject {
  private static let log = Logger(subsystem: "app.pixcapture.PIXCAPTURE", category: "CameraSession")
  private static let rawZoomFallbackWarning = NSLocalizedString("warning.proRawZoomFallback", comment: "ProRAW zoom fallback warning")
  private static let rawStackingFallbackWarning = NSLocalizedString("warning.proRawStackingFallback", comment: "ProRAW stacking fallback warning")
  private static let transientCameraInterruptionWarning = "Kamera kurz pausiert. Die Vorschau wird neu gestartet."
  private static let cameraInUseWarning = "Kamera wird gerade von einer anderen App verwendet."
  private static let multipleForegroundAppsWarning = "Kamera nicht verfügbar (Mehrfach-Apps)."
  private static let systemPressureWarning = "Kamera pausiert wegen hoher Systemlast."
  private static let minStartSessionIntervalSeconds: TimeInterval = 0.75
  private static let lensSwitchSettleDelaySeconds: TimeInterval = 0.25
  private static let captureRequestDebounceSeconds: TimeInterval = 0.35
  private static let iso8601DateFormatter = ISO8601DateFormatter()
  let session = AVCaptureSession()

  @Published var isSessionRunning = false
  @Published var isCapturing = false
  @Published var histogramBins: [CGFloat] = Array(repeating: 0, count: 32)
  @Published var highlightWarningMask: HighlightWarningMask = .empty
  @Published var highlightWarningActive = false
  @Published var focusPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)
  @Published var levelAngle: Double = 0
  @Published var levelPitch: Double = 0
  @Published var stabilityScore: Double = 1
  @Published var stabilityState: CameraStabilityState = .unstable
  @Published var exposureBiasRange: ClosedRange<Double> = -2...2
  @Published var isoRange: ClosedRange<Float> = 50...800
  private let isoHardMin: Float = 50
  private let isoHardMax: Float = 800
  @Published var cameraDebugInfo: String = ""
  @Published var lastSummary: CaptureSeriesSummary?
  @Published var warningMessage: String?
  @Published var captureProgress: CaptureProgress?
  @Published var captureDebugInfo: String?
  @Published var bracketAELockActive: Bool = false
  @Published var exposureQualityState: LiveQualityState = .warning
  @Published var sharpnessQualityState: LiveQualityState = .warning
  @Published var zoomPresets: [Double] = [0.5, 1.0, 2.0, 5.0]
  @Published var currentZoomFactor: Double = 1.0
  @Published private(set) var hasResolvedProRAWCaptureAvailability: Bool = false
  @Published private(set) var isProRAWCaptureAvailable: Bool = false

  private let sessionQueue = DispatchQueue(label: "pixcapture.session")
  private let videoOutputQueue = DispatchQueue(label: "pixcapture.video")
  private let depthOutputQueue = DispatchQueue(label: "pixcapture.depth")
  private let depthStateQueue = DispatchQueue(label: "pixcapture.depth-state")

  private let photoOutput = AVCapturePhotoOutput()
  private let videoOutput = AVCaptureVideoDataOutput()
  private let depthOutput = AVCaptureDepthDataOutput()
  private var videoDevice: AVCaptureDevice?

  private var photoContinuations: [Int64: CheckedContinuation<CapturedPhoto, Error>] = [:]
  private var pendingCaptures: [Int64: PendingCapture] = [:]
  private var multiRepresentationCaptures: [Int64: MultiRepresentationCaptureState] = [:]
  private var bracketContinuations: [Int64: BracketCaptureState] = [:]
  private var latestStreamingDepthFrame: StreamingDepthFrame?
  private var streamDepthSupported = false
  private var streamDepthEnabled = false
  private var manualCaptureState: ManualCaptureState?
  private var activeSeriesId: UUID?
  private var activeSeriesLog: [ExifLogEntry] = []
  private var activeSeriesPhotos: [CapturedPhoto] = []
  private let seriesLogQueue = DispatchQueue(label: "pixcapture.serieslog")
  private var activeSeriesPhotoURLs: [URL] = []
  private let photoSaveQueue = DispatchQueue(label: "pixcapture.photosave")
  private var photoSaveAuthorized: PHAuthorizationStatus?

  private let histogramProcessor = HistogramProcessor()
  private let levelMonitor = LevelMonitor()
  private let ciContext = CIContext(options: [CIContextOption.cacheIntermediates: false])
  private var lastCaptureOrientation: CaptureOrientation = .portrait
  private var captureStartedAt: Date?
  private var captureWatchdogTask: Task<Void, Never>?
  private var warningAutoClearTask: Task<Void, Never>?
  private var motifSequenceCounter: Int = 0
  private var qualityProfile: RoomCategory = .interior
  private var latestMeanLuma: Double?
  private var latestDarkClip: Double?
  private var latestBrightClip: Double?
  private var smoothedMeanLuma: Double?
  private var smoothedDarkClip: Double?
  private var smoothedBrightClip: Double?
  private var smoothedSharpness: Double?
  private var smoothedHistogramBins: [CGFloat]?
  private var smoothedHighlightWarningCells: [CGFloat]?
  private var highlightWarningLatched = false
  private var levelMonitoringEnabled = true
  private var hasLevelSample = false
  private var storedFocusPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)
  private var storedFocusLockEnabled = false
  private var lastLensSwitchUptime: TimeInterval = 0
  private var lastCaptureRequestAt: Date = .distantPast

  private var isConfigured = false
  private var hasConfiguredSession = false
  private var wantsSessionRunning = false
  private var isStartInFlight = false
  private var isStopInFlight = false
  private var lastStartSessionAttemptUptime: TimeInterval = 0
  private var pendingStartWorkItem: DispatchWorkItem?
  private var hasInstalledSessionObservers = false
  private var sessionObserverTokens: [NSObjectProtocol] = []
  private lazy var writableImageDestinationTypes: Set<String> = {
    let identifiers = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
    return Set(identifiers)
  }()

  private struct PersistedCaptureFiles {
    let fileURL: URL
    let originalFileURL: URL?
    let fileDataForExifLog: Data
  }

  func configureIfNeeded() {
    guard !isConfigured else { return }
    isConfigured = true
    installSessionObserversIfNeeded()

    levelMonitor.onMotionSample = { [weak self] sample in
      DispatchQueue.main.async {
        self?.levelAngle = sample.roll
        self?.levelPitch = sample.pitch
        self?.stabilityScore = sample.stabilityScore
        self?.stabilityState = sample.stabilityState
        self?.hasLevelSample = true
      }
    }

    Task { [weak self] in
      guard let self else { return }
      let granted = await requestCameraAccessIfNeeded()
      guard granted else {
        DispatchQueue.main.async {
          self.warningMessage = "Kamera-Zugriff verweigert."
        }
        return
      }
      self.sessionQueue.async { [weak self] in
        self?.configureSession()
      }
    }
  }

  func setQualityProfile(roomId: String) {
    qualityProfile = RoomTaxonomy.room(id: roomId).category
  }

  func setLevelMonitoringEnabled(_ enabled: Bool) {
    DispatchQueue.main.async {
      self.levelMonitoringEnabled = enabled
      if !enabled {
        self.levelAngle = 0
        self.levelPitch = 0
        self.stabilityScore = 1
        self.stabilityState = .unstable
        self.hasLevelSample = false
      }
      self.applyLevelMonitoringState()
    }
  }

  private func applyLevelMonitoringState() {
    guard isSessionRunning, levelMonitoringEnabled else {
      levelMonitor.stop()
      return
    }
    levelMonitor.start()
  }

  private func sceneAdaptiveBracketPlan(
    effectiveFormat: PhotoFormat,
    config: CaptureSeriesConfig,
    baseExposureSeconds: Double,
    brightClipRatio: Double,
    darkClipRatio: Double,
    meanLuma: Double
  ) -> SceneAdaptiveBracketPlan? {
    // Keep the standard bracket deterministic. If we reintroduce an adaptive
    // exterior mode later, it should only trigger on a real shortest-shutter
    // boundary instead of scene heuristics.
    let _ = effectiveFormat
    let _ = config
    let _ = baseExposureSeconds
    let _ = brightClipRatio
    let _ = darkClipRatio
    let _ = meanLuma
    return nil
  }

  private func isUserVisibleCaptureWarning(_ message: String) -> Bool {
    let suppressedWarnings = [
      NSLocalizedString("warning.darkRoomMode", comment: "Dark room mode warning"),
      "Stacking aktiv bei langen Belichtungen.",
      Self.rawStackingFallbackWarning
    ]
    if message.hasPrefix("Dunkle Szene: RAW bleibt aktiv") {
      return false
    }
    return !suppressedWarnings.contains(message)
  }

  private func configureSession() {
    hasConfiguredSession = false
    session.beginConfiguration()
    session.sessionPreset = .photo

    guard let device = selectBackCamera() else {
      DispatchQueue.main.async {
        self.warningMessage = "No camera device available."
      }
      session.commitConfiguration()
      return
    }
    videoDevice = device

    do {
      let input = try AVCaptureDeviceInput(device: device)
      if session.canAddInput(input) { session.addInput(input) }
    } catch {
      DispatchQueue.main.async {
        self.warningMessage = "Camera input error: \(error.localizedDescription)"
      }
      session.commitConfiguration()
      return
    }

    if session.canAddOutput(photoOutput) {
      session.addOutput(photoOutput)
      syncPhotoOutputConfiguration(for: device.activeFormat)
    }

    if session.canAddOutput(videoOutput) {
      videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
      videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)
      session.addOutput(videoOutput)
    }

    if session.canAddOutput(depthOutput) {
      depthOutput.isFilteringEnabled = false
      depthOutput.alwaysDiscardsLateDepthData = true
      depthOutput.setDelegate(self, callbackQueue: depthOutputQueue)
      session.addOutput(depthOutput)
      syncDepthOutputConfiguration(for: device)
    } else {
      updateStreamingDepthState(supported: false, enabled: false, latestFrame: nil)
    }

    session.commitConfiguration()
    hasConfiguredSession = true
    if wantsSessionRunning {
      startSession()
    }

    DispatchQueue.main.async {
      self.exposureBiasRange = Double(device.minExposureTargetBias)...Double(device.maxExposureTargetBias)
      let minISO = max(self.isoHardMin, device.activeFormat.minISO)
      let maxISO = min(self.isoHardMax, device.activeFormat.maxISO)
      self.isoRange = minISO...maxISO
      self.zoomPresets = self.buildZoomPresets(device: device)
      self.currentZoomFactor = Double(device.videoZoomFactor)
      self.hasResolvedProRAWCaptureAvailability = true
      self.isProRAWCaptureAvailable = self.canCaptureProRAW(device: device)
      self.refreshCameraDebugInfo(device: device)
    }
  }

  func startSession() {
    wantsSessionRunning = true
    Self.log.debug("startSession requested")
    sessionQueue.async { [weak self] in
      guard let self else { return }
      self.pendingStartWorkItem?.cancel()
      self.pendingStartWorkItem = nil
      self.startSessionOnQueue(applyThrottle: true)
    }
  }

  func stopSession() {
    wantsSessionRunning = false
    DispatchQueue.main.async {
      self.levelMonitor.stop()
    }
    Self.log.debug("stopSession requested")
    sessionQueue.async { [weak self] in
      guard let self else { return }
      self.pendingStartWorkItem?.cancel()
      self.pendingStartWorkItem = nil
      if !self.session.isRunning {
        DispatchQueue.main.async {
          self.isSessionRunning = false
        }
        Self.log.debug("stopSession ignored(already-stopped)")
        return
      }
      if self.isStopInFlight {
        Self.log.debug("stopSession ignored(in-flight)")
        return
      }

      self.isStopInFlight = true
      self.isStartInFlight = false
      self.session.stopRunning()
      self.isStopInFlight = false
      Self.log.debug("stopSession applied")
      DispatchQueue.main.async {
        self.isSessionRunning = false
      }
    }
  }

  private func startSessionOnQueue(applyThrottle: Bool) {
    if !hasConfiguredSession {
      Self.log.debug("startSession deferred(not-configured)")
      return
    }
    if session.isRunning {
      DispatchQueue.main.async {
        self.isSessionRunning = true
        self.applyLevelMonitoringState()
      }
      Self.log.debug("startSession ignored(already-running)")
      return
    }
    if isStartInFlight {
      Self.log.debug("startSession ignored(in-flight)")
      return
    }
    if isStopInFlight {
      Self.log.debug("startSession deferred(stop-in-flight)")
      scheduleStartRetryOnQueue(after: 0.20)
      return
    }
    if applyThrottle {
      let now = ProcessInfo.processInfo.systemUptime
      let elapsed = now - lastStartSessionAttemptUptime
      if elapsed < Self.minStartSessionIntervalSeconds {
        let delay = max(0.05, Self.minStartSessionIntervalSeconds - elapsed)
        Self.log.debug("startSession throttled(\(delay, format: .fixed(precision: 2))s)")
        scheduleStartRetryOnQueue(after: delay)
        return
      }
      lastStartSessionAttemptUptime = now
    }

    isStartInFlight = true
    isStopInFlight = false
    session.startRunning()
    isStartInFlight = false

    if !wantsSessionRunning {
      Self.log.debug("startSession rollback(stop-requested)")
      session.stopRunning()
      DispatchQueue.main.async {
        self.isSessionRunning = false
      }
      return
    }

    Self.log.debug("startSession applied")
    DispatchQueue.main.async {
      self.isSessionRunning = true
      self.applyLevelMonitoringState()
    }
  }

  private func scheduleStartRetryOnQueue(after delaySeconds: TimeInterval) {
    guard wantsSessionRunning else { return }
    pendingStartWorkItem?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.pendingStartWorkItem = nil
      self.startSessionOnQueue(applyThrottle: false)
    }
    pendingStartWorkItem = work
    sessionQueue.asyncAfter(deadline: .now() + delaySeconds, execute: work)
  }

  func setFocusPoint(_ point: CGPoint, lockEnabled: Bool) {
    DispatchQueue.main.async {
      self.focusPoint = point
    }
    sessionQueue.async { [weak self] in
      guard let self, let device = self.videoDevice else { return }
      self.storedFocusPoint = point
      self.storedFocusLockEnabled = lockEnabled
      self.applyFocusConfiguration(to: device, point: point, lockEnabled: lockEnabled, scheduleDeferredLock: lockEnabled)
    }
  }

  private func applyFocusConfiguration(
    to device: AVCaptureDevice,
    point: CGPoint,
    lockEnabled: Bool,
    scheduleDeferredLock: Bool
  ) {
    do {
      try device.lockForConfiguration()
      if device.isFocusPointOfInterestSupported {
        device.focusPointOfInterest = point
      }
      if lockEnabled {
        if device.isFocusModeSupported(.autoFocus) {
          device.focusMode = .autoFocus
        }
      } else if device.isFocusModeSupported(.continuousAutoFocus) {
        device.focusMode = .continuousAutoFocus
      } else if device.isFocusModeSupported(.autoFocus) {
        device.focusMode = .autoFocus
      }

      if device.isExposurePointOfInterestSupported {
        device.exposurePointOfInterest = point
      }
      if lockEnabled {
        if device.isExposureModeSupported(.continuousAutoExposure) {
          device.exposureMode = .continuousAutoExposure
        }
      } else if device.isExposureModeSupported(.continuousAutoExposure) {
        device.exposureMode = .continuousAutoExposure
      }
      device.unlockForConfiguration()
      if lockEnabled && scheduleDeferredLock {
        lockFocusAndExposureAfterAutofocus(device: device)
      }
    } catch {
      DispatchQueue.main.async {
        self.warningMessage = "Focus lock error: \(error.localizedDescription)"
      }
    }
  }

  func setWhiteBalanceLocked(_ locked: Bool) {
    sessionQueue.async { [weak self] in
      guard let self, let device = self.videoDevice else { return }
      do {
        try device.lockForConfiguration()
        if locked {
          let gains = device.deviceWhiteBalanceGains
          if device.isWhiteBalanceModeSupported(.locked) {
            device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
          }
        } else {
          if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            device.whiteBalanceMode = .continuousAutoWhiteBalance
          }
        }
        device.unlockForConfiguration()
      } catch {
        DispatchQueue.main.async {
          self.warningMessage = "White balance error: \(error.localizedDescription)"
        }
      }
    }
  }

  func setWhiteBalanceKelvin(_ kelvin: Float) {
    sessionQueue.async { [weak self] in
      guard let self, let device = self.videoDevice else { return }
      do {
        try device.lockForConfiguration()
        let targetKelvin = min(max(kelvin, 2000), 6000)
        let tempTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
          temperature: targetKelvin,
          tint: 0
        )
        var gains = device.deviceWhiteBalanceGains(for: tempTint)
        gains = self.clampedWhiteBalanceGains(gains, for: device)
        if device.isWhiteBalanceModeSupported(.locked) {
          device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
        }
        device.unlockForConfiguration()
      } catch {
        DispatchQueue.main.async {
          self.warningMessage = "White balance error: \(error.localizedDescription)"
        }
      }
    }
  }

  private func clampedWhiteBalanceGains(
    _ gains: AVCaptureDevice.WhiteBalanceGains,
    for device: AVCaptureDevice
  ) -> AVCaptureDevice.WhiteBalanceGains {
    let maxGain = device.maxWhiteBalanceGain
    var clamped = gains
    clamped.redGain = min(max(1.0, gains.redGain), maxGain)
    clamped.greenGain = min(max(1.0, gains.greenGain), maxGain)
    clamped.blueGain = min(max(1.0, gains.blueGain), maxGain)
    return clamped
  }

  func setExposureBias(_ biasEV: Double) {
    sessionQueue.async { [weak self] in
      guard let self, let device = self.videoDevice else { return }
      do {
        try device.lockForConfiguration()
        if device.isExposureModeSupported(.continuousAutoExposure) {
          device.exposureMode = .continuousAutoExposure
        }
        let bias = Float(biasEV)
        let clamped = min(max(bias, device.minExposureTargetBias), device.maxExposureTargetBias)
        device.setExposureTargetBias(clamped, completionHandler: nil)
        device.unlockForConfiguration()
      } catch {
        DispatchQueue.main.async {
          self.warningMessage = "Exposure bias error: \(error.localizedDescription)"
        }
      }
    }
  }

  func setZoomFactor(_ factor: Double) {
    sessionQueue.async { [weak self] in
      guard let self, let device = self.videoDevice else { return }
      let preset = self.normalizedZoomPreset(for: factor)
      var targetDevice = device
      if let preferredDevice = self.selectLensDevice(for: preset),
         preferredDevice.uniqueID != device.uniqueID {
        self.switchToDevice(preferredDevice)
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
        DispatchQueue.main.async {
          self.currentZoomFactor = preset
          self.hasResolvedProRAWCaptureAvailability = true
          self.isProRAWCaptureAvailable = self.canCaptureProRAW(device: targetDevice)
          self.refreshCameraDebugInfo(device: targetDevice)
          self.clearZoomDependentRawWarningIfNeeded(for: preset)
        }
        if preset < 1.0 && targetDevice.deviceType != .builtInUltraWideCamera {
          DispatchQueue.main.async {
            self.warningMessage = "Ultraweit nicht verfügbar."
          }
        }
      } catch {
        DispatchQueue.main.async {
          self.warningMessage = "Zoom error: \(error.localizedDescription)"
          self.cameraDebugInfo = "Zoom error"
        }
      }
    }
  }

  private func normalizedZoomPreset(for requested: Double) -> Double {
    let presets = zoomPresets.isEmpty ? [1.0, 2.0] : zoomPresets
    return presets.min(by: { abs($0 - requested) < abs($1 - requested) }) ?? 1.0
  }

  private func selectLensDevice(for requestedZoom: Double) -> AVCaptureDevice? {
    if requestedZoom <= 0.75 {
      return findBackCamera(of: .builtInUltraWideCamera)
    }
    if requestedZoom >= 4.0 {
      return findBackCamera(of: .builtInTelephotoCamera)
    }
    if let wide = findBackCamera(of: .builtInWideAngleCamera) {
      return wide
    }
    return findBackCamera(of: .builtInDualCamera) ?? findBackCamera(of: .builtInDualWideCamera) ?? findBackCamera(of: .builtInTripleCamera)
  }

  private func mapRequestedZoomToDeviceZoom(requested: Double, device: AVCaptureDevice) -> Double {
    switch device.deviceType {
    case .builtInUltraWideCamera:
      // 0.5x should be the native ultra-wide lens.
      return 1.0
    case .builtInTelephotoCamera:
      // 5x should be the native tele lens.
      return requested >= 4.0 ? 1.0 : requested
    case .builtInWideAngleCamera:
      // iPhone-style: 1x native, 2x sensor crop on main camera.
      return requested <= 1.25 ? 1.0 : 2.0
    default:
      return requested
    }
  }

  private func buildZoomPresets(device: AVCaptureDevice) -> [Double] {
    _ = device
    var presets: [Double] = [1.0, 2.0]

    if findBackCamera(of: .builtInUltraWideCamera) != nil {
      presets.insert(0.5, at: 0)
    }

    if findBackCamera(of: .builtInTelephotoCamera) != nil {
      presets.append(5.0)
    }

    return presets
  }

  private func findBackCamera(of type: AVCaptureDevice.DeviceType) -> AVCaptureDevice? {
    let discovery = AVCaptureDevice.DiscoverySession(
      deviceTypes: [type],
      mediaType: .video,
      position: .back
    )
    return discovery.devices.first
  }

  private func switchToDevice(_ device: AVCaptureDevice) {
    let didSwitchLens = videoDevice?.uniqueID != device.uniqueID
    session.beginConfiguration()
    defer { session.commitConfiguration() }

    for input in session.inputs {
      session.removeInput(input)
    }
    do {
      let input = try AVCaptureDeviceInput(device: device)
      if session.canAddInput(input) {
        session.addInput(input)
        videoDevice = device
        syncPhotoOutputConfiguration(for: device.activeFormat)
        syncDepthOutputConfiguration(for: device)
        if didSwitchLens {
          lastLensSwitchUptime = ProcessInfo.processInfo.systemUptime
        }
        applyFocusConfiguration(
          to: device,
          point: storedFocusPoint,
          lockEnabled: storedFocusLockEnabled,
          scheduleDeferredLock: storedFocusLockEnabled
        )
        DispatchQueue.main.async {
          self.zoomPresets = self.buildZoomPresets(device: device)
          self.hasResolvedProRAWCaptureAvailability = true
          self.isProRAWCaptureAvailable = self.canCaptureProRAW(device: device)
          self.refreshCameraDebugInfo(device: device)
        }
      }
    } catch {
      DispatchQueue.main.async {
        self.warningMessage = "Camera switch error: \(error.localizedDescription)"
      }
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
    if let first = devices.first {
      return first
    }
    return nil
  }

  private func applyPreferredActiveFormatIfNeeded(to device: AVCaptureDevice) {
    guard let preferredFormat = preferredActiveFormat(for: device) else { return }
    guard device.activeFormat != preferredFormat else { return }

    do {
      try device.lockForConfiguration()
      device.activeFormat = preferredFormat
      device.unlockForConfiguration()
    } catch {
      DispatchQueue.main.async {
        self.warningMessage = "Formatwahl fehlgeschlagen: \(error.localizedDescription)"
      }
    }
  }

  private func syncPhotoOutputConfiguration(for format: AVCaptureDevice.Format) {
    let supportedDimensions = format.supportedMaxPhotoDimensions
    let classicDNGDimensions = supportedDimensions.first {
      $0.width == 4032 && $0.height == 3024
    }
    if let preferredDimensions = classicDNGDimensions ?? Self.preferredMaxPhotoDimensions(from: supportedDimensions) {
      photoOutput.maxPhotoDimensions = preferredDimensions
    }
    // Dark-room captures request higher quality processing, so allow the output
    // to negotiate up to the highest supported prioritization.
    photoOutput.maxPhotoQualityPrioritization = .quality
    photoOutput.isDepthDataDeliveryEnabled = photoOutput.isDepthDataDeliverySupported
    if #available(iOS 14.3, *), photoOutput.isAppleProRAWSupported, !photoOutput.isAppleProRAWEnabled {
      photoOutput.isAppleProRAWEnabled = true
    }
  }

  private func syncDepthOutputConfiguration(for device: AVCaptureDevice) {
    let supportedDepthFormats = device.activeFormat.supportedDepthDataFormats
    guard !supportedDepthFormats.isEmpty else {
      // Some active formats/lenses (for example ultra-wide without stream depth)
      // raise an Objective-C exception when activeDepthDataFormat is set to nil.
      // Simply disable the depth output for those formats and leave the device
      // configuration untouched.
      depthOutput.connection(with: .depthData)?.isEnabled = false
      updateStreamingDepthState(supported: false, enabled: false, latestFrame: nil)
      return
    }

    let preferredDepthFormat = preferredDepthDataFormat(from: supportedDepthFormats)
    var streamDepthSupported = false
    do {
      try device.lockForConfiguration()
      device.activeDepthDataFormat = preferredDepthFormat
      device.unlockForConfiguration()
      streamDepthSupported = preferredDepthFormat != nil
    } catch {
      DispatchQueue.main.async {
        self.warningMessage = "Depth-Konfiguration fehlgeschlagen: \(error.localizedDescription)"
      }
      streamDepthSupported = false
    }

    // Keep the stream disabled during normal preview and enable it only briefly
    // when we actually need a reference depth frame for capture.
    depthOutput.connection(with: .depthData)?.isEnabled = false
    updateStreamingDepthState(supported: streamDepthSupported, enabled: false, latestFrame: nil)
  }

  private func setStreamingDepthCaptureEnabled(_ enabled: Bool) async {
    let supported = depthStateQueue.sync { streamDepthSupported }
    let resolvedEnabled = supported && enabled

    await withCheckedContinuation { continuation in
      sessionQueue.async { [weak self] in
        guard let self else {
          continuation.resume()
          return
        }
        self.depthOutput.connection(with: .depthData)?.isEnabled = resolvedEnabled
        self.updateStreamingDepthState(
          supported: supported,
          enabled: resolvedEnabled,
          latestFrame: nil
        )
        continuation.resume()
      }
    }
  }

  private func preferredActiveFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
    let selections: [(format: AVCaptureDevice.Format, candidate: ActivePhotoFormatCandidate)] = device.formats.map { format in
      let streamingDimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
      let preferredPhotoDimensions = Self.preferredMaxPhotoDimensions(from: format.supportedMaxPhotoDimensions)
      return (
        format: format,
        candidate: ActivePhotoFormatCandidate(
          highestPhotoQualitySupported: format.isHighestPhotoQualitySupported,
          maxPhotoArea: Self.pixelArea(for: preferredPhotoDimensions),
          streamingArea: Self.pixelArea(for: streamingDimensions),
          minExposureSeconds: max(format.minExposureDuration.seconds, 0.000_000_1),
          minISO: format.minISO,
          maxExposureSeconds: format.maxExposureDuration.seconds
        )
      )
    }

    let candidateIndex = ActivePhotoFormatSelector.preferredCandidateIndex(
      in: selections.map(\.candidate)
    )
    return candidateIndex.map { selections[$0].format }
  }

  static func preferredMaxPhotoDimensions(from dimensions: [NSValue]) -> CMVideoDimensions? {
    let resolvedDimensions = dimensions.map(\.videoDimensionsValue)
    return preferredMaxPhotoDimensions(from: resolvedDimensions)
  }

  static func preferredMaxPhotoDimensions(from dimensions: [CMVideoDimensions]) -> CMVideoDimensions? {
    dimensions.max { lhs, rhs in
      let lhsArea = pixelArea(for: lhs)
      let rhsArea = pixelArea(for: rhs)
      if lhsArea != rhsArea {
        return lhsArea < rhsArea
      }
      if lhs.width != rhs.width {
        return lhs.width < rhs.width
      }
      return lhs.height < rhs.height
    }
  }

  static func pixelArea(for dimensions: CMVideoDimensions?) -> Int64 {
    guard let dimensions else { return 0 }
    return pixelArea(for: dimensions)
  }

  static func pixelArea(for dimensions: CMVideoDimensions) -> Int64 {
    Int64(dimensions.width) * Int64(dimensions.height)
  }

  private func preferredDepthDataFormat(from formats: [AVCaptureDevice.Format]) -> AVCaptureDevice.Format? {
    formats.max { lhs, rhs in
      let lhsScore = depthFormatScore(for: lhs)
      let rhsScore = depthFormatScore(for: rhs)
      if lhsScore != rhsScore {
        return lhsScore < rhsScore
      }

      let lhsDimensions = CMVideoFormatDescriptionGetDimensions(lhs.formatDescription)
      let rhsDimensions = CMVideoFormatDescriptionGetDimensions(rhs.formatDescription)
      let lhsArea = Self.pixelArea(for: lhsDimensions)
      let rhsArea = Self.pixelArea(for: rhsDimensions)
      if lhsArea != rhsArea {
        return lhsArea < rhsArea
      }

      if lhsDimensions.width != rhsDimensions.width {
        return lhsDimensions.width < rhsDimensions.width
      }
      return lhsDimensions.height < rhsDimensions.height
    }
  }

  private func depthFormatScore(for format: AVCaptureDevice.Format) -> Int {
    switch CMFormatDescriptionGetMediaSubType(format.formatDescription) {
    case kCVPixelFormatType_DepthFloat16:
      return 4
    case kCVPixelFormatType_DepthFloat32:
      return 3
    case kCVPixelFormatType_DisparityFloat16:
      return 2
    case kCVPixelFormatType_DisparityFloat32:
      return 1
    default:
      return 0
    }
  }

  private func configureDepthDelivery(for settings: AVCapturePhotoSettings) {
    let depthEnabled = photoOutput.isDepthDataDeliverySupported && photoOutput.isDepthDataDeliveryEnabled
    settings.isDepthDataDeliveryEnabled = depthEnabled
    guard depthEnabled else { return }
    settings.embedsDepthDataInPhoto = false
    settings.isDepthDataFiltered = false
  }

  private func preferredRawPixelFormatType(for format: PhotoFormat) -> OSType? {
    let rawTypes = photoOutput.availableRawPhotoPixelFormatTypes
    switch format {
    case .proRaw:
      return RawPixelFormatSelector.preferredSensorRawPixelFormatType(in: rawTypes)
    case .heif, .jpeg:
      return rawTypes.first
    }
  }

  private func applyMaximumPhotoDimensions(to settings: AVCapturePhotoSettings) {
    let dimensions = photoOutput.maxPhotoDimensions
    guard dimensions.width > 0, dimensions.height > 0 else { return }
    settings.maxPhotoDimensions = dimensions
  }

  func captureSeries(config: CaptureSeriesConfig) {
    if isCapturing {
      if let startedAt = captureStartedAt, Date().timeIntervalSince(startedAt) > 12 {
        isCapturing = false
        captureProgress = nil
        warningMessage = "Aufnahme zurückgesetzt."
      } else {
        return
      }
    }

    guard session.isRunning, videoDevice != nil else {
      warningMessage = "Kamera nicht bereit."
      return
    }
    let now = Date()
    guard now.timeIntervalSince(lastCaptureRequestAt) >= Self.captureRequestDebounceSeconds else {
      return
    }
    lastCaptureRequestAt = now
    isCapturing = true
    captureStartedAt = now
    setCameraWarning(nil)
    armCaptureWatchdog(timeoutSeconds: 45)

    Task {
      do {
        let summary = try await captureSeriesAsync(config: config)
        DispatchQueue.main.async {
          self.lastSummary = summary
          self.captureProgress = nil
        }
      } catch {
        DispatchQueue.main.async {
          self.warningMessage = error.localizedDescription
          self.captureProgress = nil
        }
      }
      DispatchQueue.main.async {
        self.clearCaptureWatchdog()
        self.captureStartedAt = nil
        self.isCapturing = false
      }
    }
  }

  private func armCaptureWatchdog(timeoutSeconds: TimeInterval) {
    captureWatchdogTask?.cancel()
    captureWatchdogTask = Task { [weak self] in
      let cappedTimeout = min(max(timeoutSeconds, 15.0), 180.0)
      try? await Task.sleep(nanoseconds: UInt64(cappedTimeout * 1_000_000_000))
      guard !Task.isCancelled else { return }
      await MainActor.run {
        guard let self, self.isCapturing else { return }
        self.isCapturing = false
        self.captureProgress = nil
        self.captureStartedAt = nil
        self.warningMessage = "Aufnahme-Timeout. Bitte erneut auslösen."
      }
    }
  }

  private func clearCaptureWatchdog() {
    captureWatchdogTask?.cancel()
    captureWatchdogTask = nil
  }

  private func setCameraWarning(_ message: String?) {
    DispatchQueue.main.async {
      self.warningAutoClearTask?.cancel()
      self.warningAutoClearTask = nil
      self.warningMessage = message
    }
  }

  private func scheduleCameraWarningAutoClearIfUnchanged(_ message: String?, after delaySeconds: TimeInterval) {
    guard let message, !message.isEmpty else { return }
    DispatchQueue.main.async {
      self.warningAutoClearTask?.cancel()
      self.warningAutoClearTask = Task { [weak self] in
        let delay = UInt64(max(delaySeconds, 0.5) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: delay)
        await MainActor.run {
          guard let self, self.warningMessage == message else { return }
          self.warningMessage = nil
          self.warningAutoClearTask = nil
        }
      }
    }
  }

  private func captureSeriesAsync(config: CaptureSeriesConfig) async throws -> CaptureSeriesSummary {
    guard let initialDevice = videoDevice else {
      throw CameraError.noDevice
    }

    let seriesId = UUID()
    seriesLogQueue.sync {
      activeSeriesId = seriesId
      activeSeriesLog = []
      activeSeriesPhotos = []
      activeSeriesPhotoURLs = []
    }

    if config.captureMode == .singleShot {
      return try await captureFastSingleShot(
        config: config,
        seriesId: seriesId,
        initialDevice: initialDevice
      )
    }

    let device = try await ensureCustomExposureDevice(preferred: initialDevice)
    try await waitForLensSwitchToSettleIfNeeded(device: device)
    // Always re-meter from auto exposure before each capture series.
    var baseMeasurement = try await measureBaselineExposure(
      device: device,
      biasEV: config.exposureBiasEV,
      isoOverride: config.isoOverride
    )
    var captureBaseBiasEV = config.exposureBiasEV
    let effectiveFormat = effectivePhotoFormat(for: config.photoFormat, device: device)
    let isSingleShotMode = config.captureMode == .singleShot
    var plannedBracketCount = isSingleShotMode ? 1 : max(1, config.bracketCount)
    let isDarkRoomMode = config.captureMode == .darkRoom
    let isExterior = qualityProfile == .exterior
    let previewSeriesShape: ExposureSeriesShape = .balanced
    var seriesShape: ExposureSeriesShape = previewSeriesShape
    let minimumRecoveryISO = device.activeFormat.minISO
    var baseISO = config.isoOverride ?? baseMeasurement.iso
    let initialSeriesBaseISO = baseISO
    var usedRecoveryISO = false
    var maxSafeISO: Float
    if let overrideISO = config.isoOverride, overrideISO > 0 {
      maxSafeISO = min(max(overrideISO, device.activeFormat.minISO), device.activeFormat.maxISO)
    } else {
      maxSafeISO = min(max(baseISO, 800), device.activeFormat.maxISO)
    }
    let brightClipRatio = smoothedBrightClip ?? 0
    let darkClipRatio = smoothedDarkClip ?? 0
    let meanLuma = smoothedMeanLuma ?? 0
    let sceneAdaptivePlan = sceneAdaptiveBracketPlan(
      effectiveFormat: effectiveFormat,
      config: config,
      baseExposureSeconds: baseMeasurement.duration.seconds,
      brightClipRatio: brightClipRatio,
      darkClipRatio: darkClipRatio,
      meanLuma: meanLuma
    )
    let usesSceneAdaptiveBracketPlan = sceneAdaptivePlan != nil
    if let sceneAdaptivePlan, !isSingleShotMode {
      plannedBracketCount = sceneAdaptivePlan.bracketCount
    }
    let stepEV = BracketStepPolicy.effectiveStepEV(
      configuredStepEV: config.stepEV,
      bracketCount: plannedBracketCount,
      photoFormat: effectiveFormat
    )
    let usesHighlightAnchorMetering = !isDarkRoomMode &&
      config.bracketMeteringMode == .highlightAnchor &&
      plannedBracketCount > 1
    let shouldPreferInteriorShadowRecovery = false
    func preferredHighlightPriorityShift(for bracketCount: Int) -> Double {
      let _ = bracketCount
      return 0
    }
    let highlightPriorityShiftEV = usesHighlightAnchorMetering
      ? 0
      : (usesSceneAdaptiveBracketPlan ? 0 : preferredHighlightPriorityShift(for: plannedBracketCount))
    let deviceMinDuration = device.activeFormat.minExposureDuration
    let requestedMaxPerFrameSeconds = max(config.maxExposureSeconds, deviceMinDuration.seconds)
    let reliableMaxPerFrameSeconds: Double
    if isDarkRoomMode {
      reliableMaxPerFrameSeconds = min(
        requestedMaxPerFrameSeconds,
        device.activeFormat.maxExposureDuration.seconds
      )
    } else {
      reliableMaxPerFrameSeconds = min(
        requestedMaxPerFrameSeconds,
        device.activeFormat.maxExposureDuration.seconds
      )
    }
    let reliableMaxPerFrameDuration = CMTimeMakeWithSeconds(
      reliableMaxPerFrameSeconds,
      preferredTimescale: max(baseMeasurement.duration.timescale, 600)
    )
    let darkRoomRequestedSeconds = max(baseMeasurement.duration.seconds, deviceMinDuration.seconds)
    if usesHighlightAnchorMetering {
      let probeBiasEV = config.exposureBiasEV + ExposureSeriesBuilder.brightestOffsetEV(
        for: plannedBracketCount,
        stepEV: stepEV,
        seriesShape: previewSeriesShape
      )
      let anchorSample = try await determineHighlightAnchorMeasurement(
        device: device,
        desiredBiasEV: config.exposureBiasEV,
        probeBiasEV: probeBiasEV,
        stepEV: stepEV,
        isoOverride: config.isoOverride
      )
      baseMeasurement = anchorSample.measurement
      captureBaseBiasEV = anchorSample.biasEV
      seriesShape = .highlightAnchor
    }
    let centerShiftEV = usesHighlightAnchorMetering ? 0 : highlightPriorityShiftEV
    let minimumDistinctDarkGapEV = max(0.5, stepEV * 0.5)
    func buildStandardBracketSeries(
      from measurement: ExposureMeasurement,
      iso: Float,
      count: Int = plannedBracketCount,
      centerShiftOverrideEV: Double? = nil,
      shape: ExposureSeriesShape = seriesShape
    ) -> [ExposureSample] {
      ExposureSeriesBuilder.buildHybridDurations(
        baseDuration: measurement.duration,
        baseISO: iso,
        stepEV: stepEV,
        count: count,
        minDuration: deviceMinDuration,
        maxDuration: reliableMaxPerFrameDuration,
        minISO: device.activeFormat.minISO,
        maxSafeISO: maxSafeISO,
        centerShiftEV: centerShiftOverrideEV
          ?? ((usesSceneAdaptiveBracketPlan || usesHighlightAnchorMetering) ? 0 : centerShiftEV),
        seriesShape: shape
      )
    }
    func buildSingleFrameBracketSeries(
      from measurement: ExposureMeasurement,
      iso: Float,
      count: Int = plannedBracketCount,
      centerShiftOverrideEV: Double? = nil,
      shape: ExposureSeriesShape = seriesShape
    ) -> [ExposureSample] {
      ExposureSeriesBuilder.buildCompressedSingleShotDurations(
        baseDuration: measurement.duration,
        baseISO: iso,
        stepEV: stepEV,
        count: count,
        minDuration: deviceMinDuration,
        maxDuration: reliableMaxPerFrameDuration,
        minISO: device.activeFormat.minISO,
        maxSafeISO: maxSafeISO,
        centerShiftEV: centerShiftOverrideEV
          ?? ((usesSceneAdaptiveBracketPlan || usesHighlightAnchorMetering) ? 0 : centerShiftEV),
        seriesShape: shape
      )
    }
    func centerShiftForBrightestFrameAtMaxExposure(
      measurement: ExposureMeasurement,
      count: Int,
      shape: ExposureSeriesShape
    ) -> Double {
      let baseSeconds = max(measurement.duration.seconds, 0.000_001)
      let maxSeconds = max(reliableMaxPerFrameDuration.seconds, baseSeconds)
      let brightestOffset = ExposureSeriesBuilder.brightestOffsetEV(
        for: count,
        stepEV: stepEV,
        seriesShape: shape
      )
      let targetBrightestEV = log2(maxSeconds / baseSeconds)
      return max(0, targetBrightestEV - brightestOffset)
    }
    var exposures: [ExposureSample]
    if isDarkRoomMode {
      let finalSeconds = min(max(darkRoomRequestedSeconds, deviceMinDuration.seconds), reliableMaxPerFrameSeconds)
      let finalDuration = CMTimeMakeWithSeconds(
        finalSeconds,
        preferredTimescale: max(baseMeasurement.duration.timescale, 600)
      )
      exposures = [
        ExposureSample(
          zone: .standard,
          ev: log2(max(finalSeconds, 0.000_001) / max(baseMeasurement.duration.seconds, 0.000_001)),
          requestedEV: 0,
          perFrameDuration: finalDuration,
          effectiveDuration: finalDuration,
          perFrameISO: baseISO,
          frameCount: 1
        )
      ]
    } else {
      exposures = buildStandardBracketSeries(from: baseMeasurement, iso: baseISO)
      let needsDarkEdgeRecovery = ExposureSeriesBuilder.needsDarkEdgeRecovery(
        samples: exposures,
        expectedCount: plannedBracketCount,
        minDuration: deviceMinDuration,
        minimumDistinctDarkGapEV: minimumDistinctDarkGapEV
      )
      if needsDarkEdgeRecovery,
         minimumRecoveryISO + 0.5 < baseISO {
        if usesHighlightAnchorMetering {
          baseMeasurement = try await measureBaselineExposure(
            device: device,
            biasEV: captureBaseBiasEV,
            isoOverride: minimumRecoveryISO
          )
        } else {
          baseMeasurement = try await measureBaselineExposure(
            device: device,
            biasEV: config.exposureBiasEV,
            isoOverride: minimumRecoveryISO
          )
        }
        baseISO = minimumRecoveryISO
        usedRecoveryISO = true
        maxSafeISO = min(max(baseISO, device.activeFormat.minISO), device.activeFormat.maxISO)
        exposures = buildStandardBracketSeries(from: baseMeasurement, iso: baseISO)
      }
      let _ = shouldPreferInteriorShadowRecovery
    }
    if !isDarkRoomMode, plannedBracketCount == 1, let single = exposures.first {
      exposures = [
        ExposureSample(
          zone: single.zone,
          ev: captureBaseBiasEV,
          requestedEV: captureBaseBiasEV,
          perFrameDuration: single.perFrameDuration,
          effectiveDuration: single.effectiveDuration,
          perFrameISO: single.perFrameISO,
          frameCount: single.frameCount
        )
      ]
    }
    var bracketFallbackWarning: String?
    if !isDarkRoomMode,
       plannedBracketCount > 3,
       exposures.contains(where: { $0.frameCount > 1 }) {
      let originalBracketCount = plannedBracketCount
      let fallbackCount = 3
      let fallbackShape: ExposureSeriesShape = .balanced
      let maxFillCenterShiftEV = centerShiftForBrightestFrameAtMaxExposure(
        measurement: baseMeasurement,
        count: fallbackCount,
        shape: fallbackShape
      )
      plannedBracketCount = fallbackCount
      exposures = buildStandardBracketSeries(
        from: baseMeasurement,
        iso: baseISO,
        count: fallbackCount,
        centerShiftOverrideEV: maxFillCenterShiftEV,
        shape: fallbackShape
      )
      bracketFallbackWarning = "Sehr dunkle Szene: Belichtungsreihe wurde von \(originalBracketCount)x auf 3x begrenzt."
    }
    if !isDarkRoomMode,
       exposures.contains(where: { $0.frameCount > 1 }) {
      exposures = buildSingleFrameBracketSeries(from: baseMeasurement, iso: baseISO)
      if bracketFallbackWarning == nil {
        bracketFallbackWarning = "Sehr lange Belichtung: Zusatz-Stacking deaktiviert, damit die Reihe als normale Aufnahmen gespeichert wird."
      }
    }
    let requiresProcessedStackingFallback = effectiveFormat == .proRaw && exposures.contains { $0.frameCount > 1 }
    let seriesCaptureFormat: PhotoFormat = requiresProcessedStackingFallback ? .jpeg : effectiveFormat
    let manualBase = ExposureMeasurement(
      duration: exposures.first?.perFrameDuration ?? baseMeasurement.duration,
      iso: exposures.first?.perFrameISO ?? baseISO
    )
    let usesBracketAELock = exposures.count > 1 && config.captureMode == .standardBracket
    let seriesDiagnostics = SeriesExposureDiagnostics(
      activeFormatMinISO: device.activeFormat.minISO,
      activeFormatMaxISO: device.activeFormat.maxISO,
      activeFormatMinExposureSeconds: device.activeFormat.minExposureDuration.seconds,
      activeFormatMaxExposureSeconds: device.activeFormat.maxExposureDuration.seconds,
      seriesInitialBaseISO: initialSeriesBaseISO,
      seriesFinalBaseISO: baseISO,
      seriesUsedRecoveryISO: usedRecoveryISO
    )
    try await enableManualCapture(device: device, base: manualBase, lockAutoExposure: usesBracketAELock)

    let trimmedFrom = max((isDarkRoomMode ? 1 : plannedBracketCount) - exposures.count, 0)
    var warnings: [String] = []
    if config.photoFormat == .proRaw, effectiveFormat != .proRaw {
      warnings.append(fallbackWarningMessageForProRAW(device: device))
    } else if requiresProcessedStackingFallback {
      warnings.append(Self.rawStackingFallbackWarning)
    }
    if isDarkRoomMode {
      warnings.append(NSLocalizedString("warning.darkRoomMode", comment: "Dark room mode warning"))
      if darkRoomRequestedSeconds > reliableMaxPerFrameSeconds + 0.000_1 {
        let template = NSLocalizedString("warning.darkRoomClamped", comment: "Dark room clamp warning")
        warnings.append(String(format: template, reliableMaxPerFrameSeconds))
      }
    }
    if let adaptiveWarning = sceneAdaptivePlan?.warningMessage {
      warnings.append(adaptiveWarning)
    }
    if let bracketFallbackWarning {
      warnings.append(bracketFallbackWarning)
    }
    if !usesSceneAdaptiveBracketPlan, effectiveFormat != .proRaw, config.stepEV > stepEV + 0.000_1 {
      let activeFormatName = "JPEG"
      warnings.append("Aktives Format: \(activeFormatName). Der EV-Abstand ist deshalb auf \(String(format: "%.1f", stepEV)) EV begrenzt.")
    }
    if usesHighlightAnchorMetering {
      warnings.append(NSLocalizedString("warning.highlightAnchor", comment: "Highlight anchor warning"))
    }
    if isExterior, centerShiftEV > 0.000_1 {
      warnings.append("Außenreihe wurde heller verschoben, damit die dunkelsten Frames echte EV-Abstände behalten.")
    }
    if highlightPriorityShiftEV < 0 {
      warnings.append(NSLocalizedString("warning.highlightPriority", comment: "Highlight priority warning"))
    }
    if trimmedFrom > 0 {
      let template = NSLocalizedString("warning.bracketShortened", comment: "Shortened bracket warning")
      warnings.append(String(format: template, exposures.count))
    }
    if BracketCompressionWarningEvaluator.shouldWarn(
      samples: exposures,
      requestedCount: plannedBracketCount,
      stepEV: stepEV,
      trimmedFromCount: trimmedFrom
    ) {
      warnings.append(NSLocalizedString("warning.bracketCompressed", comment: "Bracket compressed warning"))
    }
    let maxSeconds = exposures.reduce(0.0) { current, sample in
      max(current, sample.effectiveDuration.seconds)
    }
    if maxSeconds > 1.0 {
      warnings.append(NSLocalizedString("warning.longExposure", comment: "Long exposure warning"))
    }
    if exposures.contains(where: { $0.zone == .stacking }) {
      warnings.append("Stacking aktiv bei langen Belichtungen.")
    }
    let userVisibleWarnings = warnings.filter(isUserVisibleCaptureWarning)
    let publishedCaptureWarning = userVisibleWarnings.isEmpty ? nil : userVisibleWarnings.joined(separator: " ")
    setCameraWarning(publishedCaptureWarning)
    armCaptureWatchdog(
      timeoutSeconds: estimatedCaptureTimeoutSeconds(
        for: exposures,
        captureDelaySeconds: config.captureDelaySeconds
      )
    )
    let frameCountsLog = exposures.map { String($0.frameCount) }.joined(separator: ",")
    Self.log.info(
      "captureSeries resolved mode=\(config.captureMode.rawValue, privacy: .public) requested=\(config.bracketCount) planned=\(plannedBracketCount) samples=\(exposures.count) requestedFormat=\(config.photoFormat.rawValue, privacy: .public) captureFormat=\(seriesCaptureFormat.rawValue, privacy: .public) frameCounts=\(frameCountsLog, privacy: .public)"
    )

    var photos: [CapturedPhoto] = []
    DispatchQueue.main.async {
      self.bracketAELockActive = usesBracketAELock
    }
    defer {
      DispatchQueue.main.async {
        self.bracketAELockActive = false
      }
    }
    do {
      if config.captureDelaySeconds > 0 {
        let delay = UInt64(config.captureDelaySeconds * 1_000_000_000)
        try await Task.sleep(nanoseconds: delay)
      }
      DispatchQueue.main.async {
        self.captureProgress = CaptureProgress(total: exposures.count, current: 0, ev: 0)
      }

      let motifSequence = nextMotifSequence()
      let bracketTotal = max(exposures.count, 1)
      let depthReferenceIndex = preferredDepthReferenceIndex(in: exposures)
      for (index, exposure) in exposures.enumerated() {
        DispatchQueue.main.async {
          self.captureProgress = CaptureProgress(total: exposures.count, current: index + 1, ev: exposure.ev)
        }
        let bracketIndex = index + 1
        let shouldWriteDepthSidecar = index == depthReferenceIndex
        let captureOrientation = currentCaptureVideoOrientation()
        let captureOrientationLabel = orientationDebugLabel(for: captureOrientation)
        let captureExifOrientation = exifOrientation(for: captureOrientation)
        let photo: CapturedPhoto
        if exposure.frameCount > 1 {
          photo = try await captureStackedPhoto(
            exposure: exposure,
            baseBiasEV: captureBaseBiasEV,
            format: seriesCaptureFormat,
            outputAspectRatio: config.outputAspectRatio,
            captureMode: config.captureMode,
            roomId: config.roomId,
            floorId: config.floorId,
            motifSequence: motifSequence,
            bracketIndex: bracketIndex,
            bracketTotal: bracketTotal,
            captureOrientationLabel: captureOrientationLabel,
            captureExifOrientation: captureExifOrientation,
            shouldWriteDepthSidecar: shouldWriteDepthSidecar,
            seriesDiagnostics: seriesDiagnostics,
            singleShotAssessment: config.singleShotAssessment
          )
        } else {
          photo = try await capturePhoto(
            duration: exposure.perFrameDuration,
            effectiveDuration: exposure.effectiveDuration,
            iso: exposure.perFrameISO,
            exposureEV: exposure.ev,
            requestedExposureEV: exposure.requestedEV,
            baseBiasEV: captureBaseBiasEV,
            format: seriesCaptureFormat,
            outputAspectRatio: config.outputAspectRatio,
            captureMode: config.captureMode,
            zone: exposure.zone,
            frameCount: exposure.frameCount,
            includeInSeriesLog: true,
            roomId: config.roomId,
            floorId: config.floorId,
            seriesId: seriesId,
            motifSequence: motifSequence,
            bracketIndex: bracketIndex,
            bracketTotal: bracketTotal,
            shouldWriteDepthSidecar: shouldWriteDepthSidecar,
            seriesDiagnostics: seriesDiagnostics,
            singleShotAssessment: config.singleShotAssessment
          )
        }
        photos.append(photo)
        let interShotDelay = interShotDelayNanoseconds(for: exposure)
        if interShotDelay > 0 {
          try await Task.sleep(nanoseconds: interShotDelay)
        }
      }

      await disableManualCapture(device: device)
      await resetExposureToAuto(device: device, biasEV: config.exposureBiasEV)
      let summary = finalizeSeriesSummary(
        seriesId: seriesId,
        roomId: config.roomId,
        floorId: config.floorId,
        fallbackPhotos: photos,
        trimmedFromCount: trimmedFrom,
        captureMode: config.captureMode,
        singleShotAssessment: config.singleShotAssessment
      )
      scheduleCameraWarningAutoClearIfUnchanged(publishedCaptureWarning, after: 3.5)
      clearActiveSeriesState()
      if let summary {
        return summary
      }
      return CaptureSeriesSummary(
        seriesId: seriesId,
        roomId: config.roomId,
        floorId: config.floorId,
        photos: photos,
        trimmedFromCount: trimmedFrom,
        exifLogURL: nil,
        metadataReady: false,
        captureMode: config.captureMode,
        singleShotAssessment: config.singleShotAssessment
      )
    } catch {
      await disableManualCapture(device: device)
      await resetExposureToAuto(device: device, biasEV: config.exposureBiasEV)
      if let partialSummary = finalizeSeriesSummary(
        seriesId: seriesId,
        roomId: config.roomId,
        floorId: config.floorId,
        fallbackPhotos: photos,
        trimmedFromCount: max((isDarkRoomMode ? 1 : plannedBracketCount) - photos.count, 0),
        captureMode: config.captureMode,
        singleShotAssessment: config.singleShotAssessment
      ) {
        await MainActor.run {
          self.lastSummary = partialSummary
        }
      }
      clearActiveSeriesState()
      throw error
    }
  }

  private func publishIncrementalSeriesSummary(
    seriesId: UUID,
    roomId: String,
    floorId: String,
    trimmedFromCount: Int = 0,
    captureMode: PhotoCaptureMode = .standardBracket,
    singleShotAssessment: SingleShotCaptureAssessment? = nil
  ) {
    let summary: CaptureSeriesSummary? = seriesLogQueue.sync {
      guard activeSeriesId == seriesId, !activeSeriesPhotos.isEmpty else {
        return nil
      }
      return CaptureSeriesSummary(
        seriesId: seriesId,
        roomId: roomId,
        floorId: floorId,
        photos: activeSeriesPhotos,
        trimmedFromCount: trimmedFromCount,
        exifLogURL: nil,
        metadataReady: false,
        captureMode: captureMode,
        singleShotAssessment: singleShotAssessment
      )
    }

    guard let summary else { return }
    DispatchQueue.main.async {
      self.lastSummary = summary
    }
  }

  private func captureFastSingleShot(
    config: CaptureSeriesConfig,
    seriesId: UUID,
    initialDevice: AVCaptureDevice
  ) async throws -> CaptureSeriesSummary {
    let device = videoDevice ?? initialDevice
    let effectiveFormat = effectivePhotoFormat(for: config.photoFormat, device: device)
    var warnings: [String] = []
    if config.photoFormat == .proRaw, effectiveFormat != .proRaw {
      warnings.append(fallbackWarningMessageForProRAW(device: device))
    }
    DispatchQueue.main.async {
      self.warningMessage = warnings.isEmpty ? nil : warnings.joined(separator: " ")
    }
    armCaptureWatchdog(timeoutSeconds: max(15.0, config.captureDelaySeconds + 8.0))

    do {
      if config.captureDelaySeconds > 0 {
        let delay = UInt64(config.captureDelaySeconds * 1_000_000_000)
        try await Task.sleep(nanoseconds: delay)
      }
      DispatchQueue.main.async {
        self.captureProgress = CaptureProgress(total: 1, current: 0, ev: 0)
      }

      let motifSequence = nextMotifSequence()
      let photo = try await capturePhotoWithCurrentExposure(
        format: effectiveFormat,
        outputAspectRatio: config.outputAspectRatio,
        captureMode: .singleShot,
        roomId: config.roomId,
        floorId: config.floorId,
        seriesId: seriesId,
        motifSequence: motifSequence,
        singleShotAssessment: config.singleShotAssessment
      )
      let summary = finalizeSeriesSummary(
        seriesId: seriesId,
        roomId: config.roomId,
        floorId: config.floorId,
        fallbackPhotos: [photo],
        trimmedFromCount: 0,
        captureMode: .singleShot,
        singleShotAssessment: config.singleShotAssessment
      )
      clearActiveSeriesState()
      if let summary {
        return summary
      }
      return CaptureSeriesSummary(
        seriesId: seriesId,
        roomId: config.roomId,
        floorId: config.floorId,
        photos: [photo],
        trimmedFromCount: 0,
        exifLogURL: nil,
        metadataReady: false,
        captureMode: .singleShot,
        singleShotAssessment: config.singleShotAssessment
      )
    } catch {
      clearActiveSeriesState()
      throw error
    }
  }

  private func registerCapturedSeriesPhoto(
    _ photo: CapturedPhoto,
    seriesId: UUID?,
    roomId: String?,
    floorId: String?
  ) {
    guard let seriesId,
          let roomId,
          let floorId else {
      return
    }

    seriesLogQueue.async {
      guard self.activeSeriesId == seriesId else { return }
      self.activeSeriesPhotos.append(photo)
      DispatchQueue.main.async {
        self.publishIncrementalSeriesSummary(
          seriesId: seriesId,
        roomId: roomId,
        floorId: floorId,
        captureMode: photo.captureMode,
        singleShotAssessment: photo.singleShotAssessment
      )
      }
    }
  }

  private func finalizeSeriesSummary(
    seriesId: UUID,
    roomId: String,
    floorId: String,
    fallbackPhotos: [CapturedPhoto],
    trimmedFromCount: Int,
    captureMode: PhotoCaptureMode,
    singleShotAssessment: SingleShotCaptureAssessment?
  ) -> CaptureSeriesSummary? {
    let snapshot: (photos: [CapturedPhoto], entries: [ExifLogEntry], isActive: Bool) = seriesLogQueue.sync {
      (
        photos: activeSeriesPhotos,
        entries: activeSeriesLog,
        isActive: activeSeriesId == seriesId
      )
    }

    guard snapshot.isActive else { return nil }
    let finalPhotos = snapshot.photos.isEmpty ? fallbackPhotos : snapshot.photos
    guard !finalPhotos.isEmpty else { return nil }
    let exifURL = FileStore.saveExifLog(seriesId: seriesId, entries: snapshot.entries)
    return CaptureSeriesSummary(
      seriesId: seriesId,
      roomId: roomId,
      floorId: floorId,
      photos: finalPhotos,
      trimmedFromCount: trimmedFromCount,
      exifLogURL: exifURL,
      metadataReady: exifURL != nil,
      captureMode: captureMode,
      singleShotAssessment: singleShotAssessment
    )
  }

  private func clearActiveSeriesState() {
    seriesLogQueue.sync {
      activeSeriesId = nil
      activeSeriesLog = []
      activeSeriesPhotos = []
      activeSeriesPhotoURLs = []
    }
  }

  private func estimatedCaptureTimeoutSeconds(
    for exposures: [ExposureSample],
    captureDelaySeconds: Double
  ) -> TimeInterval {
    let frameCount = max(exposures.reduce(0) { $0 + max($1.frameCount, 1) }, 1)
    let totalExposureSeconds = exposures.reduce(0.0) { partial, sample in
      partial + (sample.perFrameDuration.seconds * Double(max(sample.frameCount, 1)))
    }
    let processingBudget = Double(frameCount) * 1.4
    let settleBudget = Double(exposures.count) * 0.55
    return captureDelaySeconds + totalExposureSeconds + processingBudget + settleBudget + 14.0
  }

  private func preferredDepthReferenceIndex(in exposures: [ExposureSample]) -> Int {
    guard !exposures.isEmpty else { return 0 }
    return exposures.indices.min { lhs, rhs in
      let lhsRequested = abs(exposures[lhs].requestedEV)
      let rhsRequested = abs(exposures[rhs].requestedEV)
      if abs(lhsRequested - rhsRequested) > 0.000_1 {
        return lhsRequested < rhsRequested
      }

      let lhsActual = abs(exposures[lhs].ev)
      let rhsActual = abs(exposures[rhs].ev)
      if abs(lhsActual - rhsActual) > 0.000_1 {
        return lhsActual < rhsActual
      }
      return lhs < rhs
    } ?? 0
  }

  private func preferredHighlightPriorityShiftEV(
    brightClipRatio: Double,
    darkClipRatio: Double,
    stepEV: Double,
    bracketCount: Int,
    baseBiasEV: Double
  ) -> Double {
    guard bracketCount >= 3 else { return 0 }
    guard stepEV > 0 else { return 0 }
    guard baseBiasEV > -1.5 else { return 0 }

    let brightPressure = brightClipRatio - (darkClipRatio * 0.35)
    if bracketCount >= 5, brightPressure >= 0.05 {
      return -stepEV
    }
    if brightClipRatio >= 0.12 {
      return -stepEV
    }
    return 0
  }

  private func currentLiveMetricsSnapshot() -> LiveExposureMetricsSnapshot {
    LiveExposureMetricsSnapshot(
      meanLuma: latestMeanLuma ?? smoothedMeanLuma ?? 0,
      darkClipRatio: latestDarkClip ?? smoothedDarkClip ?? 0,
      brightClipRatio: latestBrightClip ?? smoothedBrightClip ?? 0
    )
  }

  private func highlightAnchorBrightClipThreshold() -> Double {
    switch qualityProfile {
    case .interior:
      return 0.020
    case .exterior:
      return 0.024
    case .other:
      return 0.022
    }
  }

  private func highlightAnchorSearchStepEV(for stepEV: Double) -> Double {
    min(max(stepEV / 4.0, 0.25), 0.5)
  }

  private func measureAutoExposureSample(
    device: AVCaptureDevice,
    biasEV: Double,
    isoOverride: Float?
  ) async throws -> AutoExposureSample {
    try await applyAutoExposureBias(device: device, biasEV: biasEV)
    try await waitForExposureToStabilize(device: device)
    try await Task.sleep(nanoseconds: 140_000_000)

    let reading = await readExposure(device: device)
    let minISO = device.activeFormat.minISO
    let maxISO = min(device.activeFormat.maxISO, isoHardMax)
    let clampedOverride = isoOverride.map { min(max($0, minISO), maxISO) }
    let iso = clampedOverride ?? reading.iso
    let adjustedDuration: CMTime
    if let overrideISO = clampedOverride, overrideISO > 0, reading.iso > 0 {
      let scale = Double(reading.iso / overrideISO)
      adjustedDuration = CMTimeMultiplyByFloat64(reading.duration, multiplier: scale)
    } else {
      adjustedDuration = reading.duration
    }

    return AutoExposureSample(
      biasEV: biasEV,
      measurement: ExposureMeasurement(duration: adjustedDuration, iso: iso),
      metrics: currentLiveMetricsSnapshot()
    )
  }

  private func determineHighlightAnchorMeasurement(
    device: AVCaptureDevice,
    desiredBiasEV _: Double,
    probeBiasEV: Double,
    stepEV: Double,
    isoOverride: Float?
  ) async throws -> AutoExposureSample {
    let minBias = Double(device.minExposureTargetBias)
    let maxBias = Double(device.maxExposureTargetBias)
    let searchStep = highlightAnchorSearchStepEV(for: stepEV)
    let brightClipThreshold = highlightAnchorBrightClipThreshold()

    var candidateBias = min(max(probeBiasEV, minBias), maxBias)
    var sample = try await measureAutoExposureSample(
      device: device,
      biasEV: candidateBias,
      isoOverride: isoOverride
    )

    while sample.metrics.brightClipRatio > brightClipThreshold && candidateBias > (minBias + 0.000_1) {
      candidateBias = max(minBias, candidateBias - searchStep)
      sample = try await measureAutoExposureSample(
        device: device,
        biasEV: candidateBias,
        isoOverride: isoOverride
      )
    }

    if sample.metrics.brightClipRatio <= brightClipThreshold {
      return sample
    }

    // If even the darkest probe still clips, keep the darkest tested anchor
    // instead of bouncing back to a brighter preview-centered measurement.
    return sample
  }

  private func measureBaselineExposure(device: AVCaptureDevice, biasEV: Double, isoOverride: Float?) async throws -> ExposureMeasurement {
    try await applyAutoExposureBias(device: device, biasEV: biasEV)

    try await waitForExposureToStabilize(device: device)

    let duration = device.exposureDuration
    let measuredISO = device.iso
    let minISO = device.activeFormat.minISO
    let maxISO = min(device.activeFormat.maxISO, isoHardMax)
    let clampedOverride = isoOverride.map { min(max($0, minISO), maxISO) }
    let iso = clampedOverride ?? measuredISO
    let adjustedDuration: CMTime
    if let overrideISO = clampedOverride, overrideISO > 0 {
      let scale = Double(measuredISO / overrideISO)
      adjustedDuration = CMTimeMultiplyByFloat64(duration, multiplier: scale)
    } else {
      adjustedDuration = duration
    }

    return ExposureMeasurement(duration: adjustedDuration, iso: iso)
  }

  private func applyAutoExposureBias(device: AVCaptureDevice, biasEV: Double) async throws {
    try await withCheckedThrowingContinuation { continuation in
      sessionQueue.async {
        do {
          try device.lockForConfiguration()
          if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
          }
          let clamped = min(max(Float(biasEV), device.minExposureTargetBias), device.maxExposureTargetBias)
          device.setExposureTargetBias(clamped) { _ in
            device.unlockForConfiguration()
            continuation.resume()
          }
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
    try await Task.sleep(nanoseconds: 120_000_000)
  }

  private func waitForExposureToStabilize(device: AVCaptureDevice) async throws {
    let maxWait: TimeInterval = 1.2
    let start = Date()
    while device.isAdjustingExposure {
      try await Task.sleep(nanoseconds: 40_000_000)
      if Date().timeIntervalSince(start) > maxWait { break }
    }
  }

  private func waitForFocusToStabilize(device: AVCaptureDevice) async throws {
    let maxWait: TimeInterval = 1.2
    let start = Date()
    while device.isAdjustingFocus {
      try await Task.sleep(nanoseconds: 40_000_000)
      if Date().timeIntervalSince(start) > maxWait { break }
    }
  }

  private func waitForLensSwitchToSettleIfNeeded(device: AVCaptureDevice) async throws {
    let elapsed = ProcessInfo.processInfo.systemUptime - lastLensSwitchUptime
    if elapsed >= 0, elapsed < Self.lensSwitchSettleDelaySeconds {
      let remaining = Self.lensSwitchSettleDelaySeconds - elapsed
      try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
    }
    try await waitForFocusToStabilize(device: device)
    try await waitForExposureToStabilize(device: device)
  }

  private func capturePhoto(
    duration: CMTime,
    effectiveDuration: CMTime,
    iso: Float,
    exposureEV: Double,
    requestedExposureEV: Double,
    baseBiasEV: Double,
    format: PhotoFormat,
    outputAspectRatio: Double,
    captureMode: PhotoCaptureMode,
    zone: ExposureZone,
    frameCount: Int,
    includeInSeriesLog: Bool,
    roomId: String,
    floorId: String,
    seriesId: UUID? = nil,
    motifSequence: Int,
    bracketIndex: Int,
    bracketTotal: Int,
    shouldWriteDepthSidecar: Bool,
    seriesDiagnostics: SeriesExposureDiagnostics? = nil,
    singleShotAssessment: SingleShotCaptureAssessment? = nil
  ) async throws -> CapturedPhoto {
    guard let device = videoDevice else { throw CameraError.noDevice }
    let orientationRequest = configurePhotoOutputOrientation()
    let orientation = orientationRequest.orientation
    let captureExifOrientation = exifOrientation(for: orientation)

    let minDuration = device.activeFormat.minExposureDuration
    let maxDuration = device.activeFormat.maxExposureDuration
    var safeDuration = duration
    if safeDuration < minDuration { safeDuration = minDuration }
    if safeDuration > maxDuration { safeDuration = maxDuration }

    let clampedISO = min(max(iso, device.activeFormat.minISO), device.activeFormat.maxISO)

    if device.isExposureModeSupported(.custom) {
      await applyManualExposure(device: device, duration: safeDuration, iso: clampedISO)
      await waitForExposureMatch(device: device, targetDuration: safeDuration, targetISO: clampedISO)
    } else {
      throw CameraError.customExposureNotSupported
    }

    updateCaptureDebug(ev: exposureEV, requested: safeDuration, iso: clampedISO, device: device)

    // Give the sensor a moment to apply the new manual exposure.
    try await Task.sleep(nanoseconds: 80_000_000)
    try await waitForExposureToStabilize(device: device)
    let sharedSeriesDepthPayload = shouldWriteDepthSidecar
      ? await captureSharedStreamingDepthPayload()
      : nil

    let settingsPlan = buildPhotoSettingsPlan(for: format)
    let settings = settingsPlan.settings
    settings.photoQualityPrioritization = requestedPhotoQualityPrioritization(for: captureMode)
    let snapshot = await readCaptureSnapshot(device: device)
    let sensorSnapshot = currentSensorSnapshot()

    return try await withCheckedThrowingContinuation { continuation in
      photoContinuations[settings.uniqueID] = continuation
      if settingsPlan.expectsRawCompanion {
        self.multiRepresentationCaptures[settings.uniqueID] = MultiRepresentationCaptureState()
      }
      pendingCaptures[settings.uniqueID] = PendingCapture(
        seriesId: seriesId,
        sequenceNumber: bracketIndex,
        roomId: roomId,
        floorId: floorId,
        motifSequence: motifSequence,
        bracketIndex: bracketIndex,
        bracketTotal: bracketTotal,
        zone: zone.rawValue,
        frameCount: frameCount,
        exposureEV: exposureEV,
        requestedExposureEV: requestedExposureEV,
        baseBiasEV: baseBiasEV,
        outputAspectRatio: outputAspectRatio,
        duration: duration,
        effectiveDuration: effectiveDuration,
        iso: iso,
        activeFormatMinISO: seriesDiagnostics?.activeFormatMinISO,
        activeFormatMaxISO: seriesDiagnostics?.activeFormatMaxISO,
        activeFormatMinExposureSeconds: seriesDiagnostics?.activeFormatMinExposureSeconds,
        activeFormatMaxExposureSeconds: seriesDiagnostics?.activeFormatMaxExposureSeconds,
        seriesInitialBaseISO: seriesDiagnostics?.seriesInitialBaseISO,
        seriesFinalBaseISO: seriesDiagnostics?.seriesFinalBaseISO,
        seriesUsedRecoveryISO: seriesDiagnostics?.seriesUsedRecoveryISO,
        deviceExposureSeconds: snapshot.exposureSeconds,
        deviceISO: snapshot.iso,
        deviceExposureTargetBias: snapshot.exposureTargetBias,
        deviceExposureTargetOffset: snapshot.exposureTargetOffset,
        deviceLensPosition: snapshot.lensPosition,
        deviceFocusMode: snapshot.focusMode,
        deviceFocusPointX: snapshot.focusPointX,
        deviceFocusPointY: snapshot.focusPointY,
        deviceAdjustingFocus: snapshot.adjustingFocus,
        deviceSubjectAreaMonitoringEnabled: snapshot.subjectAreaMonitoringEnabled,
        deviceZoomFactor: snapshot.zoomFactor,
        deviceWhiteBalanceGainRed: snapshot.whiteBalanceGainRed,
        deviceWhiteBalanceGainGreen: snapshot.whiteBalanceGainGreen,
        deviceWhiteBalanceGainBlue: snapshot.whiteBalanceGainBlue,
        sensorPitchDegrees: sensorSnapshot.pitchDegrees,
        sensorRollDegrees: sensorSnapshot.rollDegrees,
        sensorHeadingDegrees: sensorSnapshot.headingDegrees,
        requestedCaptureOrientation: orientationDebugLabel(for: orientation),
        connectionRotationAngle: orientationRequest.rotationAngle,
        exifOrientation: captureExifOrientation,
        format: format,
        displayFileExtension: settingsPlan.displayFileExtension,
        expectsRawCompanion: settingsPlan.expectsRawCompanion,
        captureMode: captureMode,
        singleShotAssessment: singleShotAssessment,
        includeInSeriesLog: includeInSeriesLog,
        shouldWriteDepthSidecar: shouldWriteDepthSidecar,
        sharedSeriesDepthPayload: sharedSeriesDepthPayload
      )
      photoOutput.capturePhoto(with: settings, delegate: self)
    }
  }

  private func capturePhotoWithCurrentExposure(
    format: PhotoFormat,
    outputAspectRatio: Double,
    captureMode: PhotoCaptureMode,
    roomId: String,
    floorId: String,
    seriesId: UUID,
    motifSequence: Int,
    singleShotAssessment: SingleShotCaptureAssessment?
  ) async throws -> CapturedPhoto {
    guard let device = videoDevice else { throw CameraError.noDevice }
    let orientationRequest = configurePhotoOutputOrientation()
    let orientation = orientationRequest.orientation
    let captureExifOrientation = exifOrientation(for: orientation)
    let settingsPlan = buildPhotoSettingsPlan(for: format)
    let settings = settingsPlan.settings
    settings.photoQualityPrioritization = .speed
    let snapshot = await readCaptureSnapshot(device: device)
    let sensorSnapshot = currentSensorSnapshot()
    let exposureSeconds = max(snapshot.exposureSeconds ?? 0, 0)
    let exposureDuration = exposureSeconds > 0
      ? CMTimeMakeWithSeconds(exposureSeconds, preferredTimescale: 600)
      : .zero
    let iso = snapshot.iso ?? 0

    return try await withCheckedThrowingContinuation { continuation in
      photoContinuations[settings.uniqueID] = continuation
      if settingsPlan.expectsRawCompanion {
        self.multiRepresentationCaptures[settings.uniqueID] = MultiRepresentationCaptureState()
      }
      pendingCaptures[settings.uniqueID] = PendingCapture(
        seriesId: seriesId,
        sequenceNumber: 1,
        roomId: roomId,
        floorId: floorId,
        motifSequence: motifSequence,
        bracketIndex: 1,
        bracketTotal: 1,
        zone: ExposureZone.standard.rawValue,
        frameCount: 1,
        exposureEV: 0,
        requestedExposureEV: 0,
        baseBiasEV: Double(snapshot.exposureTargetBias ?? 0),
        outputAspectRatio: outputAspectRatio,
        duration: exposureDuration,
        effectiveDuration: exposureDuration,
        iso: iso,
        activeFormatMinISO: device.activeFormat.minISO,
        activeFormatMaxISO: device.activeFormat.maxISO,
        activeFormatMinExposureSeconds: device.activeFormat.minExposureDuration.seconds,
        activeFormatMaxExposureSeconds: device.activeFormat.maxExposureDuration.seconds,
        seriesInitialBaseISO: iso > 0 ? iso : nil,
        seriesFinalBaseISO: iso > 0 ? iso : nil,
        seriesUsedRecoveryISO: false,
        deviceExposureSeconds: snapshot.exposureSeconds,
        deviceISO: snapshot.iso,
        deviceExposureTargetBias: snapshot.exposureTargetBias,
        deviceExposureTargetOffset: snapshot.exposureTargetOffset,
        deviceLensPosition: snapshot.lensPosition,
        deviceFocusMode: snapshot.focusMode,
        deviceFocusPointX: snapshot.focusPointX,
        deviceFocusPointY: snapshot.focusPointY,
        deviceAdjustingFocus: snapshot.adjustingFocus,
        deviceSubjectAreaMonitoringEnabled: snapshot.subjectAreaMonitoringEnabled,
        deviceZoomFactor: snapshot.zoomFactor,
        deviceWhiteBalanceGainRed: snapshot.whiteBalanceGainRed,
        deviceWhiteBalanceGainGreen: snapshot.whiteBalanceGainGreen,
        deviceWhiteBalanceGainBlue: snapshot.whiteBalanceGainBlue,
        sensorPitchDegrees: sensorSnapshot.pitchDegrees,
        sensorRollDegrees: sensorSnapshot.rollDegrees,
        sensorHeadingDegrees: sensorSnapshot.headingDegrees,
        requestedCaptureOrientation: orientationDebugLabel(for: orientation),
        connectionRotationAngle: orientationRequest.rotationAngle,
        exifOrientation: captureExifOrientation,
        format: format,
        displayFileExtension: settingsPlan.displayFileExtension,
        expectsRawCompanion: settingsPlan.expectsRawCompanion,
        captureMode: captureMode,
        singleShotAssessment: singleShotAssessment,
        includeInSeriesLog: true,
        shouldWriteDepthSidecar: true,
        sharedSeriesDepthPayload: nil
      )
      photoOutput.capturePhoto(with: settings, delegate: self)
    }
  }

  private func captureStackedPhoto(
    exposure: ExposureSample,
    baseBiasEV: Double,
    format: PhotoFormat,
    outputAspectRatio: Double,
    captureMode: PhotoCaptureMode,
    roomId: String,
    floorId: String,
    motifSequence: Int,
    bracketIndex: Int,
    bracketTotal: Int,
    captureOrientationLabel: String,
    captureExifOrientation: Int,
    shouldWriteDepthSidecar: Bool,
    seriesDiagnostics: SeriesExposureDiagnostics? = nil,
    singleShotAssessment: SingleShotCaptureAssessment? = nil
  ) async throws -> CapturedPhoto {
    let sensorSnapshot = currentSensorSnapshot()
    let captureSnapshot: CaptureSnapshot?
    if let device = videoDevice {
      captureSnapshot = await readCaptureSnapshot(device: device)
    } else {
      captureSnapshot = nil
    }
    var stackedDepthPayload: PhotoDepthSidecarPayload?
    var frameSourceURLs: [URL] = []
    var frameCleanupURLs: [URL] = []
    for frameIndex in 0..<exposure.frameCount {
      let frame = try await capturePhoto(
        duration: exposure.perFrameDuration,
        effectiveDuration: exposure.effectiveDuration,
        iso: exposure.perFrameISO,
        exposureEV: exposure.ev,
        requestedExposureEV: exposure.requestedEV,
        baseBiasEV: baseBiasEV,
        format: format,
        outputAspectRatio: outputAspectRatio,
        captureMode: captureMode,
        zone: exposure.zone,
        frameCount: exposure.frameCount,
        includeInSeriesLog: false,
        roomId: roomId,
        floorId: floorId,
        seriesId: nil,
        motifSequence: motifSequence,
        bracketIndex: bracketIndex,
        bracketTotal: bracketTotal,
        shouldWriteDepthSidecar: shouldWriteDepthSidecar && frameIndex == 0,
        seriesDiagnostics: seriesDiagnostics,
        singleShotAssessment: singleShotAssessment
      )
      if stackedDepthPayload == nil {
        stackedDepthPayload = FileStore.loadCompanionDepthPayload(for: frame.fileURL)
      }
      frameSourceURLs.append(frame.originalFileURL ?? frame.fileURL)
      frameCleanupURLs.append(frame.fileURL)
      if let originalFileURL = frame.originalFileURL,
         originalFileURL.standardizedFileURL.path != frame.fileURL.standardizedFileURL.path {
        frameCleanupURLs.append(originalFileURL)
      }
    }

    let frameData = frameSourceURLs.compactMap { try? Data(contentsOf: $0) }
    guard frameData.count == frameSourceURLs.count,
          let stackedData = meanStack(frameData: frameData) else {
      throw CameraError.captureProcessingFailed
    }

    let orientationFixed = rewriteExifOrientationIfNeeded(
      data: stackedData,
      outputFormat: format,
      exifOrientation: captureExifOrientation
    )
    let displaySafe = normalizeOrientationForDisplay(
      data: orientationFixed,
      outputFormat: format
    )

    let preferredBaseName = taxonomyBaseName(
      roomId: roomId,
      floorId: floorId,
      motifSequence: motifSequence,
      bracketIndex: bracketIndex,
      bracketTotal: bracketTotal
    )
    let persistedFiles = try persistCapturedPhotoData(
      displayData: displaySafe,
      originalData: orientationFixed,
      outputFormat: format,
      displayFileExtension: displayFileExtension(for: format),
      preferredBaseName: preferredBaseName,
      exposureSeconds: exposure.perFrameDuration.seconds,
      iso: exposure.perFrameISO
    )
    let depthSidecarWritten = shouldWriteDepthSidecar
      ? writeCompanionDepthIfAvailable(
        for: persistedFiles.fileURL,
        payload: stackedDepthPayload,
        sourceFrameCount: exposure.frameCount,
        aggregation: exposure.frameCount > 1 ? "first_frame" : nil
      )
      : false
    _ = FileStore.ensurePreviewExists(
      for: persistedFiles.fileURL,
      captureOrientation: captureOrientationLabel,
      sensorRollDegrees: sensorSnapshot.rollDegrees
    )
    frameCleanupURLs.forEach { FileStore.deletePhoto(at: $0) }
    seriesLogQueue.async {
      self.activeSeriesPhotoURLs.append(persistedFiles.fileURL)
    }

    let pending = PendingCapture(
      seriesId: activeSeriesId,
      sequenceNumber: bracketIndex,
      roomId: roomId,
      floorId: floorId,
      motifSequence: motifSequence,
      bracketIndex: bracketIndex,
      bracketTotal: bracketTotal,
      zone: exposure.zone.rawValue,
      frameCount: exposure.frameCount,
      exposureEV: exposure.ev,
      requestedExposureEV: exposure.requestedEV,
      baseBiasEV: baseBiasEV,
      outputAspectRatio: outputAspectRatio,
      duration: exposure.perFrameDuration,
      effectiveDuration: exposure.effectiveDuration,
      iso: exposure.perFrameISO,
      activeFormatMinISO: seriesDiagnostics?.activeFormatMinISO,
      activeFormatMaxISO: seriesDiagnostics?.activeFormatMaxISO,
      activeFormatMinExposureSeconds: seriesDiagnostics?.activeFormatMinExposureSeconds,
      activeFormatMaxExposureSeconds: seriesDiagnostics?.activeFormatMaxExposureSeconds,
      seriesInitialBaseISO: seriesDiagnostics?.seriesInitialBaseISO,
      seriesFinalBaseISO: seriesDiagnostics?.seriesFinalBaseISO,
      seriesUsedRecoveryISO: seriesDiagnostics?.seriesUsedRecoveryISO,
      deviceExposureSeconds: nil,
      deviceISO: nil,
      deviceExposureTargetBias: nil,
      deviceExposureTargetOffset: nil,
      deviceLensPosition: captureSnapshot?.lensPosition,
      deviceFocusMode: captureSnapshot?.focusMode,
      deviceFocusPointX: captureSnapshot?.focusPointX,
      deviceFocusPointY: captureSnapshot?.focusPointY,
      deviceAdjustingFocus: captureSnapshot?.adjustingFocus,
      deviceSubjectAreaMonitoringEnabled: captureSnapshot?.subjectAreaMonitoringEnabled,
      deviceZoomFactor: captureSnapshot?.zoomFactor,
      deviceWhiteBalanceGainRed: captureSnapshot?.whiteBalanceGainRed,
      deviceWhiteBalanceGainGreen: captureSnapshot?.whiteBalanceGainGreen,
      deviceWhiteBalanceGainBlue: captureSnapshot?.whiteBalanceGainBlue,
      sensorPitchDegrees: sensorSnapshot.pitchDegrees,
      sensorRollDegrees: sensorSnapshot.rollDegrees,
      sensorHeadingDegrees: sensorSnapshot.headingDegrees,
      requestedCaptureOrientation: captureOrientationLabel,
      connectionRotationAngle: nil,
      exifOrientation: captureExifOrientation,
      format: format,
      displayFileExtension: displayFileExtension(for: format),
      expectsRawCompanion: false,
      captureMode: captureMode,
      singleShotAssessment: singleShotAssessment,
      includeInSeriesLog: true,
      shouldWriteDepthSidecar: shouldWriteDepthSidecar,
      sharedSeriesDepthPayload: nil
    )
    recordExifLog(
      data: persistedFiles.fileDataForExifLog,
      pending: pending,
      fileURL: persistedFiles.fileURL,
      depthDiagnostics: depthDiagnostics(
        payload: stackedDepthPayload,
        sidecarWritten: depthSidecarWritten,
        referenceFrame: shouldWriteDepthSidecar
      )
    )

    let captured = CapturedPhoto(
      id: UUID(),
      fileURL: persistedFiles.fileURL,
      originalFileURL: persistedFiles.originalFileURL,
      exposureEV: exposure.ev,
      exposureDuration: exposure.effectiveDuration,
      iso: exposure.perFrameISO,
      captureOrientation: captureOrientationLabel,
      sensorPitchDegrees: sensorSnapshot.pitchDegrees,
      sensorRollDegrees: sensorSnapshot.rollDegrees,
      sensorHeadingDegrees: sensorSnapshot.headingDegrees,
      captureMode: captureMode,
      singleShotAssessment: singleShotAssessment
    )
    registerCapturedSeriesPhoto(
      captured,
      seriesId: pending.seriesId,
      roomId: pending.roomId,
      floorId: pending.floorId
    )
    return captured
  }

  private func captureBracketedPhotos(
    exposures: [ExposureSample],
    baseBiasEV: Double,
    format: PhotoFormat,
    outputAspectRatio: Double
  ) async throws -> [CapturedPhoto] {
    let orientationRequest = configurePhotoOutputOrientation()
    let orientation = orientationRequest.orientation
    let captureExifOrientation = exifOrientation(for: orientation)
    let bracketedSettings = exposures.map {
      AVCaptureManualExposureBracketedStillImageSettings.manualExposureSettings(
        exposureDuration: $0.perFrameDuration,
        iso: $0.perFrameISO
      )
    }
    let processedFormat: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.jpeg]
    let settings = AVCapturePhotoBracketSettings(
      rawPixelFormatType: 0,
      processedFormat: processedFormat,
      bracketedSettings: bracketedSettings
    )
    applyMaximumPhotoDimensions(to: settings)
    configureDepthDelivery(for: settings)
    settings.photoQualityPrioritization = .speed
    let sensorSnapshot = currentSensorSnapshot()
    guard let device = videoDevice else { throw CameraError.noDevice }
    let captureSnapshot = await readCaptureSnapshot(device: device)

    return try await withCheckedThrowingContinuation { continuation in
      let state = BracketCaptureState(
        exposures: exposures,
        iso: exposures.first?.perFrameISO ?? 100,
        baseBiasEV: baseBiasEV,
        format: format,
        outputAspectRatio: outputAspectRatio,
        exifOrientation: captureExifOrientation,
        requestedCaptureOrientation: orientationDebugLabel(for: orientation),
        connectionRotationAngle: orientationRequest.rotationAngle,
        sensorPitchDegrees: sensorSnapshot.pitchDegrees,
        sensorRollDegrees: sensorSnapshot.rollDegrees,
        sensorHeadingDegrees: sensorSnapshot.headingDegrees,
        focusMode: captureSnapshot.focusMode,
        focusPointX: captureSnapshot.focusPointX,
        focusPointY: captureSnapshot.focusPointY,
        adjustingFocus: captureSnapshot.adjustingFocus,
        subjectAreaMonitoringEnabled: captureSnapshot.subjectAreaMonitoringEnabled,
        continuation: continuation
      )
      bracketContinuations[settings.uniqueID] = state
      photoOutput.capturePhoto(with: settings, delegate: self)
    }
  }

  private struct CaptureOrientationRequest {
    let orientation: CaptureOrientation
    let rotationAngle: Double?
  }

  private func configurePhotoOutputOrientation() -> CaptureOrientationRequest {
    guard let connection = photoOutput.connection(with: .video) else {
      return CaptureOrientationRequest(orientation: currentCaptureVideoOrientation(), rotationAngle: nil)
    }
    let orientation = currentCaptureVideoOrientation()
    var appliedAngle: Double? = nil
    if #available(iOS 17.0, *) {
      let angle = rotationAngle(for: orientation)
      if connection.isVideoRotationAngleSupported(angle) {
        connection.videoRotationAngle = angle
        appliedAngle = Double(angle)
      }
    }
    return CaptureOrientationRequest(orientation: orientation, rotationAngle: appliedAngle)
  }

  private func currentCaptureVideoOrientation() -> CaptureOrientation {
    switch UIDevice.current.orientation {
    case .portrait:
      lastCaptureOrientation = .portrait
      return .portrait
    case .portraitUpsideDown:
      lastCaptureOrientation = .portrait
      return .portrait
    case .landscapeLeft:
      // Device left is camera/right in capture coordinates.
      lastCaptureOrientation = .landscapeRight
      return .landscapeRight
    case .landscapeRight:
      lastCaptureOrientation = .landscapeLeft
      return .landscapeLeft
    default:
      break
    }

    if let sceneOrientation = preferredForegroundWindowScene()?.effectiveGeometry.interfaceOrientation,
       let mappedOrientation = captureOrientation(from: sceneOrientation) {
      lastCaptureOrientation = normalizedCaptureOrientation(mappedOrientation)
      return lastCaptureOrientation
    }

    // Motion fallback: when UIDevice orientation is unknown/faceUp/faceDown.
    let roll = levelAngle
    if abs(roll) > 45 {
      if roll < 0 {
        lastCaptureOrientation = .landscapeRight
      } else {
        lastCaptureOrientation = .landscapeLeft
      }
      return lastCaptureOrientation
    }
    // Do not infer portrait vs portraitUpsideDown from pitch.
    // On faceUp/faceDown this signal can flip, causing 180° portrait errors.
    if lastCaptureOrientation == .landscapeLeft || lastCaptureOrientation == .landscapeRight {
      lastCaptureOrientation = .portrait
    }

    lastCaptureOrientation = normalizedCaptureOrientation(lastCaptureOrientation)
    return lastCaptureOrientation
  }

  private func captureOrientation(from interfaceOrientation: UIInterfaceOrientation) -> CaptureOrientation? {
    switch interfaceOrientation {
    case .portrait:
      return .portrait
    case .portraitUpsideDown:
      return .portraitUpsideDown
    case .landscapeLeft:
      return .landscapeLeft
    case .landscapeRight:
      return .landscapeRight
    default:
      return nil
    }
  }

  private func normalizedCaptureOrientation(_ orientation: CaptureOrientation) -> CaptureOrientation {
    if orientation == .portraitUpsideDown {
      return .portrait
    }
    return orientation
  }

  private func preferredForegroundWindowScene() -> UIWindowScene? {
    let scenes = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .filter { $0.activationState == .foregroundActive }
    return scenes.first(where: { $0.windows.contains(where: \.isKeyWindow) }) ?? scenes.first
  }

  private func currentSensorSnapshot() -> (pitchDegrees: Double?, rollDegrees: Double?, headingDegrees: Double?) {
    guard hasLevelSample else {
      return (nil, nil, nil)
    }
    return (
      pitchDegrees: normalizedDegrees(fromRadians: levelPitch),
      rollDegrees: normalizedDegrees(fromRadians: levelAngle),
      headingDegrees: Double?.none
    )
  }

  private func normalizedDegrees(fromRadians value: Double) -> Double? {
    guard value.isFinite else { return nil }
    var degrees = value * 180.0 / .pi
    while degrees > 180.0 {
      degrees -= 360.0
    }
    while degrees < -180.0 {
      degrees += 360.0
    }
    return degrees
  }

  private func rotationAngle(for orientation: CaptureOrientation) -> CGFloat {
    // AVCapture's rotation angle is defined in display coordinates.
    // Portrait must be 90°, otherwise portrait/landscape are swapped.
    switch orientation {
    case .portrait:
      return 90
    case .landscapeRight:
      return 0
    case .portraitUpsideDown:
      return 270
    case .landscapeLeft:
      return 180
    @unknown default:
      return 90
    }
  }

  private func exifOrientation(for orientation: CaptureOrientation) -> Int {
    // Standard EXIF orientation mapping.
    switch orientation {
    case .portrait:
      return 6
    case .portraitUpsideDown:
      return 8
    case .landscapeRight:
      return 1
    case .landscapeLeft:
      return 3
    @unknown default:
      return 6
    }
  }

  private func orientationDebugLabel(for orientation: CaptureOrientation) -> String {
    switch orientation {
    case .portrait:
      return "portrait"
    case .portraitUpsideDown:
      return "portraitUpsideDown"
    case .landscapeLeft:
      return "landscapeLeft"
    case .landscapeRight:
      return "landscapeRight"
    @unknown default:
      return "unknown"
    }
  }

  private func resetExposureToAuto(device: AVCaptureDevice, biasEV: Double) async {
    await withCheckedContinuation { continuation in
      sessionQueue.async {
        do {
          try device.lockForConfiguration()
          if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
          }
          let bias = Float(biasEV)
          let clamped = min(max(bias, device.minExposureTargetBias), device.maxExposureTargetBias)
          device.setExposureTargetBias(clamped, completionHandler: nil)
          device.unlockForConfiguration()
        } catch {
          // best-effort reset
        }
        continuation.resume()
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
        if self.isCameraInterruptionWarning(self.warningMessage) {
          self.warningMessage = nil
        }
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
      Self.log.error("runtimeError mediaServicesWereReset")
      if wantsSessionRunning {
        startSession()
      }
      return
    }

    Self.log.error("runtimeError code=\(nsError.code) message=\(nsError.localizedDescription, privacy: .public)")

    DispatchQueue.main.async {
      self.warningMessage = "Camera runtime error: \(nsError.localizedDescription)"
    }
  }

  private func handleSessionInterrupted(_ note: Notification) {
    let reasonValue = (note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber)?.intValue
    let reason = reasonValue.flatMap(AVCaptureSession.InterruptionReason.init(rawValue:))

    let text: String
    switch reason {
    case .audioDeviceInUseByAnotherClient, .videoDeviceInUseByAnotherClient:
      text = Self.cameraInUseWarning
    case .videoDeviceNotAvailableWithMultipleForegroundApps:
      text = Self.multipleForegroundAppsWarning
    case .videoDeviceNotAvailableDueToSystemPressure:
      text = Self.systemPressureWarning
    default:
      text = Self.transientCameraInterruptionWarning
    }
    Self.log.error("sessionInterrupted reason=\(String(describing: reason), privacy: .public)")

    DispatchQueue.main.async {
      self.warningMessage = text
    }
  }

  private func isCameraInterruptionWarning(_ message: String?) -> Bool {
    switch message {
    case Self.transientCameraInterruptionWarning,
         Self.cameraInUseWarning,
         Self.multipleForegroundAppsWarning,
         Self.systemPressureWarning:
      return true
    default:
      return false
    }
  }

  deinit {
    levelMonitor.stop()
    let nc = NotificationCenter.default
    for token in sessionObserverTokens {
      nc.removeObserver(token)
    }
  }
}

private enum CaptureOrientation {
  case portrait
  case portraitUpsideDown
  case landscapeLeft
  case landscapeRight
}

extension CameraManager {
  func saveSeriesToPhotoLibrary(urls: [URL]) async -> Bool {
    let existingURLs = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
    guard !existingURLs.isEmpty else {
      DispatchQueue.main.async {
        self.warningMessage = NSLocalizedString("save.photos.missingFiles", comment: "")
      }
      return false
    }

    let status = await ensurePhotoAuthorization()
    guard status == .authorized || status == .limited else {
      DispatchQueue.main.async {
        self.warningMessage = NSLocalizedString("save.photos.denied", comment: "")
      }
      return false
    }

    return await withCheckedContinuation { continuation in
      photoSaveQueue.async {
        PHPhotoLibrary.shared().performChanges({
          for url in existingURLs {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = url.lastPathComponent
            if let utType = UTType(filenameExtension: url.pathExtension) {
              options.uniformTypeIdentifier = utType.identifier
            }
            request.addResource(with: .photo, fileURL: url, options: options)
          }
        }) { success, error in
          if !success || error != nil {
            Self.log.error("photoLibrarySaveFailed error=\(error?.localizedDescription ?? "unknown", privacy: .public)")
            DispatchQueue.main.async {
              self.warningMessage = error?.localizedDescription ?? NSLocalizedString("save.photos.failed", comment: "")
            }
            continuation.resume(returning: false)
            return
          }
          continuation.resume(returning: true)
        }
      }
    }
  }

  func ensurePhotoAuthorization() async -> PHAuthorizationStatus {
    let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
    if current != .notDetermined {
      photoSaveAuthorized = current
      return current
    }
    let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    photoSaveAuthorized = status
    return status
  }
}

struct CaptureProgress {
  let total: Int
  let current: Int
  let ev: Double
}

private extension CameraManager {
  func bracketOffsets(count: Int, stepEV: Double) -> [Double] {
    let normalizedCount = [1, 3, 5, 7].contains(count) ? count : 3
    switch normalizedCount {
    case 1:
      return [0]
    case 3:
      return [-stepEV, 0, stepEV]
    case 5:
      return [-2 * stepEV, -stepEV, 0, stepEV, 2 * stepEV]
    case 7:
      return [-3 * stepEV, -2 * stepEV, -stepEV, 0, stepEV, 2 * stepEV, 3 * stepEV]
    default:
      return [-stepEV, 0, stepEV]
    }
  }

  func buildExposureSeries(
    device: AVCaptureDevice,
    offsets: [Double],
    baseBiasEV: Double,
    maxSeconds: Double,
    isoOverride: Float?,
    fallbackDuration: CMTime
  ) async throws -> [ExposureSample] {
    var samples: [ExposureSample] = []
    for ev in offsets {
      let measurement = try await measureExposureForBias(
        device: device,
        biasEV: baseBiasEV + ev
      )
      let adjustedDuration = adjustDurationForISO(
        measurement.duration,
        measuredISO: measurement.iso,
        isoOverride: isoOverride
      )
      let clampedSeconds = min(adjustedDuration.seconds, maxSeconds)
      let duration = CMTimeMakeWithSeconds(clampedSeconds, preferredTimescale: adjustedDuration.timescale)
      samples.append(ExposureSample(
        zone: .standard,
        ev: ev,
        requestedEV: ev,
        perFrameDuration: duration,
        effectiveDuration: duration,
        perFrameISO: isoOverride ?? measurement.iso,
        frameCount: 1
      ))
    }
    if samples.isEmpty {
      return [ExposureSample(
        zone: .standard,
        ev: 0,
        requestedEV: 0,
        perFrameDuration: fallbackDuration,
        effectiveDuration: fallbackDuration,
        perFrameISO: isoOverride ?? 100,
        frameCount: 1
      )]
    }
    return samples
  }

  func measureExposureForBias(device: AVCaptureDevice, biasEV: Double) async throws -> ExposureMeasurement {
    try device.lockForConfiguration()
    if device.isExposureModeSupported(.continuousAutoExposure) {
      device.exposureMode = .continuousAutoExposure
    }
    let bias = Float(biasEV)
    let clamped = min(max(bias, device.minExposureTargetBias), device.maxExposureTargetBias)
    device.setExposureTargetBias(clamped, completionHandler: nil)
    device.unlockForConfiguration()

    try await waitForExposureToStabilize(device: device)
    let duration = device.exposureDuration
    let iso = device.iso
    return ExposureMeasurement(duration: duration, iso: iso)
  }

  func adjustDurationForISO(_ duration: CMTime, measuredISO: Float, isoOverride: Float?) -> CMTime {
    guard let isoOverride, isoOverride > 0 else { return duration }
    let scale = Double(measuredISO / isoOverride)
    return CMTimeMultiplyByFloat64(duration, multiplier: scale)
  }

  func normalizeExposureSeries(_ samples: [ExposureSample], maxSeconds: Double) -> [ExposureSample] {
    guard !samples.isEmpty else { return samples }
    let maxTime = CMTimeMakeWithSeconds(maxSeconds, preferredTimescale: samples[0].perFrameDuration.timescale)
    var trimmed = samples
    while trimmed.count > 1 && trimmed.contains(where: { $0.perFrameDuration > maxTime }) {
      trimmed = Array(trimmed.dropFirst().dropLast())
    }
    return trimmed
  }

  func isExposureSeriesCompressed(_ samples: [ExposureSample], stepEV: Double) -> Bool {
    BracketCompressionWarningEvaluator.isSeriesCompressed(samples, stepEV: stepEV)
  }

  func shouldWarnAboutCompressedBracket(
    _ samples: [ExposureSample],
    requestedCount: Int,
    stepEV: Double,
    trimmedFromCount: Int
  ) -> Bool {
    BracketCompressionWarningEvaluator.shouldWarn(
      samples: samples,
      requestedCount: requestedCount,
      stepEV: stepEV,
      trimmedFromCount: trimmedFromCount
    )
  }

  func refreshCameraDebugInfo(device: AVCaptureDevice) {
    let durationRange = "\(device.activeFormat.minExposureDuration.seconds)s-\(device.activeFormat.maxExposureDuration.seconds)s"
    let isoRange = "\(String(format: "%.1f", device.activeFormat.minISO))-\(String(format: "%.1f", device.activeFormat.maxISO))"
    let custom = device.isExposureModeSupported(.custom) ? "custom✓" : "custom✕"
    let virtual = device.isVirtualDevice ? "virtual✓" : "virtual✕"
    let photoDimensions = photoOutput.maxPhotoDimensions
    let photoLabel = (photoDimensions.width > 0 && photoDimensions.height > 0)
      ? "\(photoDimensions.width)x\(photoDimensions.height)"
      : "n/a"
    let rawLabel: String
    if #available(iOS 14.3, *) {
      let rawTypes = photoOutput.availableRawPhotoPixelFormatTypes
      let hasAppleProRAW = rawTypes.contains { rawType in
        AVCapturePhotoOutput.isAppleProRAWPixelFormat(rawType)
      }
      rawLabel = hasAppleProRAW ? "ProRAW✓" : (rawTypes.isEmpty ? "RAW✕" : "RAW✓")
    } else {
      rawLabel = "RAW✕"
    }
    let streamDepthLabel = depthStateQueue.sync {
      streamDepthSupported ? (streamDepthEnabled ? "streamDepth✓" : "streamDepth-disabled") : "streamDepth✕"
    }
    let photoDepthLabel = photoOutput.isDepthDataDeliverySupported ? "photoDepth✓" : "photoDepth✕"
    cameraDebugInfo = "Device=\(device.deviceType.rawValue) \(virtual) \(custom) zoom=\(String(format: "%.2f", device.videoZoomFactor)) dur=\(durationRange) iso=\(isoRange) photo=\(photoLabel) raw=\(rawLabel) \(photoDepthLabel) \(streamDepthLabel)"
  }

  func resolveCustomExposureDevice(from device: AVCaptureDevice) -> AVCaptureDevice? {
    if device.isExposureModeSupported(.custom) {
      return device
    }
    if device.isVirtualDevice {
      let candidates = device.constituentDevices
      let preferred = candidates.sorted {
        if $0.deviceType == .builtInWideAngleCamera { return true }
        if $1.deviceType == .builtInWideAngleCamera { return false }
        return $0.deviceType.rawValue < $1.deviceType.rawValue
      }
      return preferred.first(where: { $0.isExposureModeSupported(.custom) }) ?? preferred.first
    }
    return nil
  }

  func ensureCustomExposureDevice(preferred: AVCaptureDevice) async throws -> AVCaptureDevice {
    if let resolved = resolveCustomExposureDevice(from: preferred), resolved.isExposureModeSupported(.custom) {
      if resolved.uniqueID != preferred.uniqueID {
        await withCheckedContinuation { continuation in
          sessionQueue.async { [weak self] in
            self?.switchToDevice(resolved)
            continuation.resume()
          }
        }
      }
      return resolved
    }

    if preferred.isExposureModeSupported(.custom) {
      return preferred
    }
    // Do not auto-switch lenses during capture. This caused unexpected jumps
    // (e.g. 0.5x -> 1x) when triggering a shot.
    throw CameraError.customExposureNotSupported
  }

  func requestCameraAccessIfNeeded() async -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      return true
    case .notDetermined:
      return await AVCaptureDevice.requestAccess(for: .video)
    default:
      return false
    }
  }
}

private struct ExposureMeasurement {
  let duration: CMTime
  let iso: Float
}

private struct LiveExposureMetricsSnapshot {
  let meanLuma: Double
  let darkClipRatio: Double
  let brightClipRatio: Double
}

private struct AutoExposureSample {
  let biasEV: Double
  let measurement: ExposureMeasurement
  let metrics: LiveExposureMetricsSnapshot
}

private struct SeriesExposureDiagnostics {
  let activeFormatMinISO: Float
  let activeFormatMaxISO: Float
  let activeFormatMinExposureSeconds: Double
  let activeFormatMaxExposureSeconds: Double
  let seriesInitialBaseISO: Float
  let seriesFinalBaseISO: Float
  let seriesUsedRecoveryISO: Bool
}

private struct PendingCapture {
  let seriesId: UUID?
  let sequenceNumber: Int?
  let roomId: String?
  let floorId: String?
  let motifSequence: Int?
  let bracketIndex: Int?
  let bracketTotal: Int?
  let zone: String?
  let frameCount: Int?
  let exposureEV: Double
  let requestedExposureEV: Double
  let baseBiasEV: Double
  let outputAspectRatio: Double
  let duration: CMTime
  let effectiveDuration: CMTime
  let iso: Float
  let activeFormatMinISO: Float?
  let activeFormatMaxISO: Float?
  let activeFormatMinExposureSeconds: Double?
  let activeFormatMaxExposureSeconds: Double?
  let seriesInitialBaseISO: Float?
  let seriesFinalBaseISO: Float?
  let seriesUsedRecoveryISO: Bool?
  let deviceExposureSeconds: Double?
  let deviceISO: Float?
  let deviceExposureTargetBias: Float?
  let deviceExposureTargetOffset: Float?
  let deviceLensPosition: Float?
  let deviceFocusMode: String?
  let deviceFocusPointX: Double?
  let deviceFocusPointY: Double?
  let deviceAdjustingFocus: Bool?
  let deviceSubjectAreaMonitoringEnabled: Bool?
  let deviceZoomFactor: Double?
  let deviceWhiteBalanceGainRed: Float?
  let deviceWhiteBalanceGainGreen: Float?
  let deviceWhiteBalanceGainBlue: Float?
  let sensorPitchDegrees: Double?
  let sensorRollDegrees: Double?
  let sensorHeadingDegrees: Double?
  let requestedCaptureOrientation: String?
  let connectionRotationAngle: Double?
  let exifOrientation: Int?
  let format: PhotoFormat
  let displayFileExtension: String
  let expectsRawCompanion: Bool
  let captureMode: PhotoCaptureMode
  let singleShotAssessment: SingleShotCaptureAssessment?
  let includeInSeriesLog: Bool
  let shouldWriteDepthSidecar: Bool
  let sharedSeriesDepthPayload: PhotoDepthSidecarPayload?
}

private struct CaptureSnapshot {
  let exposureSeconds: Double?
  let iso: Float?
  let exposureTargetBias: Float?
  let exposureTargetOffset: Float?
  let lensPosition: Float?
  let focusMode: String?
  let focusPointX: Double?
  let focusPointY: Double?
  let adjustingFocus: Bool?
  let subjectAreaMonitoringEnabled: Bool?
  let zoomFactor: Double?
  let whiteBalanceGainRed: Float?
  let whiteBalanceGainGreen: Float?
  let whiteBalanceGainBlue: Float?
}

private struct PhotoSettingsPlan {
  let settings: AVCapturePhotoSettings
  let displayFileExtension: String
  let expectsRawCompanion: Bool
}

private struct MultiRepresentationCaptureState {
  var rawData: Data?
  var processedData: Data?
  var depthSidecarPayload: PhotoDepthSidecarPayload?
}

private struct StreamingDepthFrame {
  let depthData: AVDepthData
  let receivedAtUptime: TimeInterval
}

private struct DepthCaptureDiagnostics {
  let deliverySupported: Bool
  let deliveryEnabled: Bool
  let streamSupported: Bool
  let streamEnabled: Bool
  let referenceFrame: Bool
  let dataPresent: Bool
  let sidecarWritten: Bool
  let source: String?
  let aggregation: String?
  let depthDataType: String?
  let depthMapWidth: Int?
  let depthMapHeight: Int?
  let depthDataFiltered: Bool?
  let depthDataAccuracy: String?
  let depthDataQuality: String?
  let depthCalibrationPresent: Bool
}

private enum CameraError: Error {
  case noDevice
  case customExposureNotSupported
  case photoDataUnavailable
  case captureProcessingFailed
}

private struct ManualCaptureState {
  let exposureMode: AVCaptureDevice.ExposureMode
  let whiteBalanceMode: AVCaptureDevice.WhiteBalanceMode
  let focusMode: AVCaptureDevice.FocusMode
  let subjectAreaMonitoring: Bool
}

private final class BracketCaptureState {
  let exposures: [ExposureSample]
  let iso: Float
  let baseBiasEV: Double
  let format: PhotoFormat
  let outputAspectRatio: Double
  let roomId: String
  let floorId: String
  let motifSequence: Int
  let exifOrientation: Int
  let requestedCaptureOrientation: String
  let connectionRotationAngle: Double?
  let sensorPitchDegrees: Double?
  let sensorRollDegrees: Double?
  let sensorHeadingDegrees: Double?
  let focusMode: String?
  let focusPointX: Double?
  let focusPointY: Double?
  let adjustingFocus: Bool?
  let subjectAreaMonitoringEnabled: Bool?
  let continuation: CheckedContinuation<[CapturedPhoto], Error>
  var photos: [CapturedPhoto] = []

  init(
    exposures: [ExposureSample],
    iso: Float,
    baseBiasEV: Double,
    format: PhotoFormat,
    outputAspectRatio: Double,
    roomId: String = RoomTaxonomy.defaultRoomId,
    floorId: String = FloorTaxonomy.defaultFloorId,
    motifSequence: Int = 1,
    exifOrientation: Int,
    requestedCaptureOrientation: String,
    connectionRotationAngle: Double?,
    sensorPitchDegrees: Double? = nil,
    sensorRollDegrees: Double? = nil,
    sensorHeadingDegrees: Double? = nil,
    focusMode: String? = nil,
    focusPointX: Double? = nil,
    focusPointY: Double? = nil,
    adjustingFocus: Bool? = nil,
    subjectAreaMonitoringEnabled: Bool? = nil,
    continuation: CheckedContinuation<[CapturedPhoto], Error>
  ) {
    self.exposures = exposures
    self.iso = iso
    self.baseBiasEV = baseBiasEV
    self.format = format
    self.outputAspectRatio = outputAspectRatio
    self.roomId = roomId
    self.floorId = floorId
    self.motifSequence = motifSequence
    self.exifOrientation = exifOrientation
    self.requestedCaptureOrientation = requestedCaptureOrientation
    self.connectionRotationAngle = connectionRotationAngle
    self.sensorPitchDegrees = sensorPitchDegrees
    self.sensorRollDegrees = sensorRollDegrees
    self.sensorHeadingDegrees = sensorHeadingDegrees
    self.focusMode = focusMode
    self.focusPointX = focusPointX
    self.focusPointY = focusPointY
    self.adjustingFocus = adjustingFocus
    self.subjectAreaMonitoringEnabled = subjectAreaMonitoringEnabled
    self.continuation = continuation
  }
}

private extension CameraManager {
  func enableManualCapture(
    device: AVCaptureDevice,
    base: ExposureMeasurement,
    lockAutoExposure: Bool = false
  ) async throws {
    let clampedISO = min(max(base.iso, device.activeFormat.minISO), device.activeFormat.maxISO)

    if !device.isExposureModeSupported(.custom) {
      throw CameraError.customExposureNotSupported
    }

    manualCaptureState = ManualCaptureState(
      exposureMode: device.exposureMode,
      whiteBalanceMode: device.whiteBalanceMode,
      focusMode: device.focusMode,
      subjectAreaMonitoring: device.isSubjectAreaChangeMonitoringEnabled
    )

    try await waitForFocusToStabilize(device: device)
    await applyManualLocks(device: device, lockExposure: lockAutoExposure)
    await applyManualExposure(device: device, duration: base.duration, iso: clampedISO)

    try await waitForExposureToStabilize(device: device)
  }

  func disableManualCapture(device: AVCaptureDevice) async {
    guard let state = manualCaptureState else { return }
    manualCaptureState = nil
    do {
      try device.lockForConfiguration()
    if device.isWhiteBalanceModeSupported(state.whiteBalanceMode) {
      device.whiteBalanceMode = state.whiteBalanceMode
    } else if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
      device.whiteBalanceMode = .continuousAutoWhiteBalance
    }
    if device.isFocusModeSupported(state.focusMode) {
      device.focusMode = state.focusMode
    } else if device.isFocusModeSupported(.continuousAutoFocus) {
      device.focusMode = .continuousAutoFocus
    }
    device.isSubjectAreaChangeMonitoringEnabled = state.subjectAreaMonitoring
      if device.isExposureModeSupported(state.exposureMode) {
        device.exposureMode = state.exposureMode
      } else if device.isExposureModeSupported(.continuousAutoExposure) {
        device.exposureMode = .continuousAutoExposure
      }
      device.unlockForConfiguration()
    } catch {
      DispatchQueue.main.async {
        self.warningMessage = "Belichtung zurücksetzen fehlgeschlagen."
      }
    }
  }

  func applyManualExposure(device: AVCaptureDevice, duration: CMTime, iso: Float) async {
    await withCheckedContinuation { continuation in
      sessionQueue.async {
        do {
          try device.lockForConfiguration()
          if device.isExposureModeSupported(.custom) {
            device.exposureMode = .custom
          }
          if device.minExposureTargetBias <= 0 && 0 <= device.maxExposureTargetBias {
            device.setExposureTargetBias(0, completionHandler: nil)
          }
          device.setExposureModeCustom(duration: duration, iso: iso) { _ in
            device.unlockForConfiguration()
            continuation.resume()
          }
        } catch {
          continuation.resume()
        }
      }
    }
  }

  func waitForExposureMatch(device: AVCaptureDevice, targetDuration: CMTime, targetISO: Float) async {
    let targetSeconds = targetDuration.seconds
    // At short shutter speeds 200 microseconds can span several complete EV
    // steps. Keep the tolerance relative and genuinely microsecond-safe.
    let durationTolerance = max(0.000_002, targetSeconds * 0.05)
    let isoTolerance: Float = 2.0

    for _ in 0..<8 {
      let reading = await readExposure(device: device)
      if abs(reading.duration.seconds - targetSeconds) <= durationTolerance &&
          abs(reading.iso - targetISO) <= isoTolerance {
        return
      }
      try? await Task.sleep(nanoseconds: 40_000_000)
      await applyManualExposure(device: device, duration: targetDuration, iso: targetISO)
    }
  }

  func readExposure(device: AVCaptureDevice) async -> (duration: CMTime, iso: Float) {
    await withCheckedContinuation { continuation in
      sessionQueue.async {
        do {
          try device.lockForConfiguration()
          let duration = device.exposureDuration
          let iso = device.iso
          device.unlockForConfiguration()
          continuation.resume(returning: (duration, iso))
        } catch {
          continuation.resume(returning: (CMTime.zero, 0))
        }
      }
    }
  }

  func readCaptureSnapshot(device: AVCaptureDevice) async -> CaptureSnapshot {
    await withCheckedContinuation { continuation in
      sessionQueue.async {
        do {
          try device.lockForConfiguration()
          let gains = device.deviceWhiteBalanceGains
          let focusPoint = device.focusPointOfInterest
          let snapshot = CaptureSnapshot(
            exposureSeconds: device.exposureDuration.seconds,
            iso: device.iso,
            exposureTargetBias: device.exposureTargetBias,
            exposureTargetOffset: device.exposureTargetOffset,
            lensPosition: device.lensPosition,
            focusMode: self.focusModeToken(device.focusMode),
            focusPointX: device.isFocusPointOfInterestSupported ? Double(focusPoint.x) : nil,
            focusPointY: device.isFocusPointOfInterestSupported ? Double(focusPoint.y) : nil,
            adjustingFocus: device.isAdjustingFocus,
            subjectAreaMonitoringEnabled: device.isSubjectAreaChangeMonitoringEnabled,
            zoomFactor: Double(device.videoZoomFactor),
            whiteBalanceGainRed: gains.redGain,
            whiteBalanceGainGreen: gains.greenGain,
            whiteBalanceGainBlue: gains.blueGain
          )
          device.unlockForConfiguration()
          continuation.resume(returning: snapshot)
        } catch {
          continuation.resume(returning: CaptureSnapshot(
            exposureSeconds: nil,
            iso: nil,
            exposureTargetBias: nil,
            exposureTargetOffset: nil,
            lensPosition: nil,
            focusMode: nil,
            focusPointX: nil,
            focusPointY: nil,
            adjustingFocus: nil,
            subjectAreaMonitoringEnabled: nil,
            zoomFactor: nil,
            whiteBalanceGainRed: nil,
            whiteBalanceGainGreen: nil,
            whiteBalanceGainBlue: nil
          ))
        }
      }
    }
  }

  private func focusModeToken(_ mode: AVCaptureDevice.FocusMode) -> String {
    switch mode {
    case .locked:
      return "locked"
    case .autoFocus:
      return "autoFocus"
    case .continuousAutoFocus:
      return "continuousAutoFocus"
    @unknown default:
      return "unknown"
    }
  }

  func meanStack(frameData: [Data]) -> Data? {
    guard let firstData = frameData.first,
          let firstImage = CIImage(data: firstData) else {
      return nil
    }

    var accumulator = firstImage
    for data in frameData.dropFirst() {
      guard let image = CIImage(data: data) else { continue }
      guard let filter = CIFilter(name: "CIAdditionCompositing") else { continue }
      filter.setValue(image, forKey: kCIInputImageKey)
      filter.setValue(accumulator, forKey: kCIInputBackgroundImageKey)
      guard let output = filter.outputImage else { continue }
      accumulator = output
    }

    let scale = 1.0 / CGFloat(max(frameData.count, 1))
    guard let matrix = CIFilter(name: "CIColorMatrix") else { return nil }
    matrix.setValue(accumulator, forKey: kCIInputImageKey)
    matrix.setValue(CIVector(x: scale, y: 0, z: 0, w: 0), forKey: "inputRVector")
    matrix.setValue(CIVector(x: 0, y: scale, z: 0, w: 0), forKey: "inputGVector")
    matrix.setValue(CIVector(x: 0, y: 0, z: scale, w: 0), forKey: "inputBVector")
    matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
    guard let averaged = matrix.outputImage,
          let cgImage = ciContext.createCGImage(averaged, from: firstImage.extent) else {
      return nil
    }

    guard let source = CGImageSourceCreateWithData(firstData as CFData, nil),
          let type = CGImageSourceGetType(source) else {
      return nil
    }
    let properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]

    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, type, 1, nil) else {
      return nil
    }
    let flattened = makeOpaqueCGImageIfNeeded(cgImage)
    CGImageDestinationAddImage(destination, flattened, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      return nil
    }
    return output as Data
  }


  func updateCaptureDebug(ev: Double, requested: CMTime, iso: Float, device: AVCaptureDevice) {
    sessionQueue.async { [weak self] in
      guard let self else { return }
      do {
        try device.lockForConfiguration()
        let actualDuration = device.exposureDuration.seconds
        let actualISO = device.iso
        device.unlockForConfiguration()
        DispatchQueue.main.async {
          self.captureDebugInfo = String(
            format: "EV %.1f • req %.4fs • act %.4fs • ISO %.0f",
            ev,
            requested.seconds,
            actualDuration,
            actualISO
          )
        }
      } catch {
        DispatchQueue.main.async {
          self.captureDebugInfo = String(
            format: "EV %.1f • req %.4fs • ISO %.0f",
            ev,
            requested.seconds,
            iso
          )
        }
      }
    }
  }

  func applyManualLocks(device: AVCaptureDevice, lockExposure: Bool = false) async {
    await withCheckedContinuation { continuation in
      sessionQueue.async {
        do {
          try device.lockForConfiguration()
          device.isSubjectAreaChangeMonitoringEnabled = false
          if device.isWhiteBalanceModeSupported(.locked) {
            let gains = device.deviceWhiteBalanceGains
            device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
          }
          if device.isFocusModeSupported(.locked) {
            device.focusMode = .locked
          }
          if lockExposure, device.isExposureModeSupported(.locked) {
            device.exposureMode = .locked
          }
          device.unlockForConfiguration()
        } catch {
          // ignore
        }
        continuation.resume()
      }
    }
  }

  func lockFocusAndExposureAfterAutofocus(device: AVCaptureDevice) {
    let targetDeviceID = device.uniqueID
    Task { [weak self] in
      guard let self else { return }
      try? await self.waitForFocusToStabilize(device: device)
      self.sessionQueue.async { [weak self] in
        guard let self,
              let activeDevice = self.videoDevice,
              activeDevice.uniqueID == targetDeviceID else { return }
        do {
          try activeDevice.lockForConfiguration()
          if activeDevice.isFocusModeSupported(.locked) {
            activeDevice.focusMode = .locked
          }
          if activeDevice.isExposureModeSupported(.locked) {
            activeDevice.exposureMode = .locked
          }
          activeDevice.unlockForConfiguration()
        } catch {
          DispatchQueue.main.async {
            self.warningMessage = "Focus lock error: \(error.localizedDescription)"
          }
        }
      }
    }
  }

  func recordExifLog(
    photo: AVCapturePhoto,
    pending: PendingCapture,
    fileURL: URL,
    depthDiagnostics: DepthCaptureDiagnostics? = nil
  ) {
    // Log metadata from the persisted file so post-processing/rewrite steps are reflected.
    if let data = try? Data(contentsOf: fileURL),
       let source = CGImageSourceCreateWithData(data as CFData, nil),
       let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
      recordExifLog(
        metadata: metadata,
        pending: pending,
        fileURL: fileURL,
        depthDiagnostics: depthDiagnostics
      )
      return
    }
    // Fallback to capture metadata if file read fails.
    recordExifLog(
      metadata: photo.metadata,
      pending: pending,
      fileURL: fileURL,
      depthDiagnostics: depthDiagnostics
    )
  }

  func recordExifLog(
    data: Data,
    pending: PendingCapture,
    fileURL: URL,
    depthDiagnostics: DepthCaptureDiagnostics? = nil
  ) {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
      return
    }
    recordExifLog(
      metadata: metadata,
      pending: pending,
      fileURL: fileURL,
      depthDiagnostics: depthDiagnostics
    )
  }

  func recordExifLog(
    metadata: [String: Any],
    pending: PendingCapture,
    fileURL: URL,
    depthDiagnostics: DepthCaptureDiagnostics? = nil
  ) {
    let exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any]
    let tiff = metadata[kCGImagePropertyTIFFDictionary as String] as? [String: Any]

    let exifISOValue: Double? = {
      if let list = exif?[kCGImagePropertyExifISOSpeedRatings as String] as? [Double] {
        return list.first
      }
      return exif?[kCGImagePropertyExifISOSpeedRatings as String] as? Double
    }()

    if let exifISOValue, isoDeviationExceedsTolerance(actualISO: exifISOValue, requestedISO: Double(pending.iso)) {
      DispatchQueue.main.async {
        self.warningMessage = "ISO weicht ab (\(Int(exifISOValue)) statt \(Int(pending.iso)))."
      }
    }

    let meanLuma = calculateMeanLuma(fileURL: fileURL)
    let qualitySnapshot = currentQualityMetadataSnapshot()

    let entry = ExifLogEntry(
      fileName: fileURL.lastPathComponent,
      sequenceNumber: pending.sequenceNumber,
      zone: pending.zone,
      frameCount: pending.frameCount,
      requestedBiasEV: pending.baseBiasEV,
      requestedAspectRatio: pending.outputAspectRatio,
      requestedExposureEV: pending.requestedExposureEV,
      exposureEV: pending.exposureEV,
      requestedSeconds: pending.duration.seconds,
      perFrameSeconds: pending.duration.seconds,
      effectiveSeconds: pending.effectiveDuration.seconds,
      requestedISO: pending.iso,
      activeFormatMinISO: pending.activeFormatMinISO,
      activeFormatMaxISO: pending.activeFormatMaxISO,
      activeFormatMinExposureSeconds: pending.activeFormatMinExposureSeconds,
      activeFormatMaxExposureSeconds: pending.activeFormatMaxExposureSeconds,
      seriesInitialBaseISO: pending.seriesInitialBaseISO,
      seriesFinalBaseISO: pending.seriesFinalBaseISO,
      seriesUsedRecoveryISO: pending.seriesUsedRecoveryISO,
      deviceExposureSeconds: pending.deviceExposureSeconds,
      deviceISO: pending.deviceISO,
      deviceExposureTargetBias: pending.deviceExposureTargetBias,
      deviceExposureTargetOffset: pending.deviceExposureTargetOffset,
      deviceLensPosition: pending.deviceLensPosition,
      deviceFocusMode: pending.deviceFocusMode,
      deviceFocusPointX: pending.deviceFocusPointX,
      deviceFocusPointY: pending.deviceFocusPointY,
      deviceAdjustingFocus: pending.deviceAdjustingFocus,
      deviceSubjectAreaMonitoringEnabled: pending.deviceSubjectAreaMonitoringEnabled,
      deviceZoomFactor: pending.deviceZoomFactor,
      deviceWhiteBalanceGainRed: pending.deviceWhiteBalanceGainRed,
      deviceWhiteBalanceGainGreen: pending.deviceWhiteBalanceGainGreen,
      deviceWhiteBalanceGainBlue: pending.deviceWhiteBalanceGainBlue,
      exifExposureTime: exif?[kCGImagePropertyExifExposureTime as String] as? Double,
      exifExposureBiasValue: exif?[kCGImagePropertyExifExposureBiasValue as String] as? Double,
      exifBrightnessValue: exif?[kCGImagePropertyExifBrightnessValue as String] as? Double,
      meanLuma: meanLuma,
      exifExposureProgram: exif?[kCGImagePropertyExifExposureProgram as String] as? Int,
      exifMeteringMode: exif?[kCGImagePropertyExifMeteringMode as String] as? Int,
      exifISO: exifISOValue,
      fNumber: exif?[kCGImagePropertyExifFNumber as String] as? Double,
      focalLength: exif?[kCGImagePropertyExifFocalLength as String] as? Double,
      lensModel: exif?[kCGImagePropertyExifLensModel as String] as? String ?? tiff?[kCGImagePropertyTIFFModel as String] as? String,
      exifPixelXDimension: exif?[kCGImagePropertyExifPixelXDimension as String] as? Int,
      exifPixelYDimension: exif?[kCGImagePropertyExifPixelYDimension as String] as? Int,
      pixelWidth: metadata[kCGImagePropertyPixelWidth as String] as? Int,
      pixelHeight: metadata[kCGImagePropertyPixelHeight as String] as? Int,
      depthDeliverySupported: depthDiagnostics?.deliverySupported,
      depthDeliveryEnabled: depthDiagnostics?.deliveryEnabled,
      streamDepthSupported: depthDiagnostics?.streamSupported,
      streamDepthEnabled: depthDiagnostics?.streamEnabled,
      depthReferenceFrame: depthDiagnostics?.referenceFrame,
      depthDataPresent: depthDiagnostics?.dataPresent,
      depthSidecarWritten: depthDiagnostics?.sidecarWritten,
      depthSource: depthDiagnostics?.source,
      depthAggregation: depthDiagnostics?.aggregation,
      depthDataType: depthDiagnostics?.depthDataType,
      depthMapWidth: depthDiagnostics?.depthMapWidth,
      depthMapHeight: depthDiagnostics?.depthMapHeight,
      depthDataFiltered: depthDiagnostics?.depthDataFiltered,
      depthDataAccuracy: depthDiagnostics?.depthDataAccuracy,
      depthDataQuality: depthDiagnostics?.depthDataQuality,
      depthCalibrationPresent: depthDiagnostics?.depthCalibrationPresent,
      orientation: metadata[kCGImagePropertyOrientation as String] as? Int,
      resolvedMetadataOrientation: metadata[kCGImagePropertyOrientation as String] as? Int,
      requestedCaptureOrientation: pending.requestedCaptureOrientation,
      connectionRotationAngle: pending.connectionRotationAngle,
      make: tiff?[kCGImagePropertyTIFFMake as String] as? String,
      model: tiff?[kCGImagePropertyTIFFModel as String] as? String,
      software: tiff?[kCGImagePropertyTIFFSoftware as String] as? String,
      whiteBalance: exif?[kCGImagePropertyExifWhiteBalance as String] as? Int,
      dateTimeOriginal: exif?[kCGImagePropertyExifDateTimeOriginal as String] as? String,
      histogramBins: qualitySnapshot.histogramBins,
      exposureQualityState: qualitySnapshot.exposureState,
      sharpnessQualityState: qualitySnapshot.sharpnessState,
      warningMessageSnapshot: qualitySnapshot.warningMessage,
      levelAngleDegrees: qualitySnapshot.levelAngle,
      levelPitchDegrees: qualitySnapshot.levelPitch,
      singleShotTriggeredAt: pending.singleShotAssessment.map { Self.iso8601DateFormatter.string(from: $0.triggeredAt) },
      singleShotRollDegrees: pending.singleShotAssessment?.rollDegrees,
      singleShotPitchDegrees: pending.singleShotAssessment?.pitchDegrees,
      singleShotStabilityScore: pending.singleShotAssessment?.stabilityScore,
      singleShotStabilityState: pending.singleShotAssessment?.stabilityState,
      singleShotCorrectability: pending.singleShotAssessment?.status.manifestToken,
      intendedProcessing: pending.singleShotAssessment?.intendedProcessing
    )

    seriesLogQueue.async {
      self.activeSeriesLog.append(entry)
    }
  }

  private func currentQualityMetadataSnapshot() -> (
    histogramBins: [Double]?,
    exposureState: String?,
    sharpnessState: String?,
    warningMessage: String?,
    levelAngle: Double?,
    levelPitch: Double?
  ) {
    if Thread.isMainThread {
      return (
        histogramBins: histogramBins.map { Double($0) },
        exposureState: exposureQualityState.manifestToken,
        sharpnessState: sharpnessQualityState.manifestToken,
        warningMessage: warningMessage,
        levelAngle: hasLevelSample ? levelAngle : nil,
        levelPitch: hasLevelSample ? levelPitch : nil
      )
    }

    return DispatchQueue.main.sync {
      (
        histogramBins: histogramBins.map { Double($0) },
        exposureState: exposureQualityState.manifestToken,
        sharpnessState: sharpnessQualityState.manifestToken,
        warningMessage: warningMessage,
        levelAngle: hasLevelSample ? levelAngle : nil,
        levelPitch: hasLevelSample ? levelPitch : nil
      )
    }
  }

  func calculateMeanLuma(fileURL: URL) -> Double? {
    // Avoid full-resolution RAW decode (can freeze on device due to IOSurface pressure).
    if fileURL.pathExtension.lowercased() == "dng" {
      return nil
    }

    guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { return nil }
    let thumbOptions: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceThumbnailMaxPixelSize: 256,
      kCGImageSourceCreateThumbnailWithTransform: true
    ]
    guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
      return nil
    }
    let image = CIImage(cgImage: thumb)
    guard let filter = CIFilter(name: "CIAreaAverage") else { return nil }
    filter.setValue(image, forKey: kCIInputImageKey)
    filter.setValue(CIVector(cgRect: image.extent), forKey: kCIInputExtentKey)
    guard let output = filter.outputImage else { return nil }

    var rgba = [UInt8](repeating: 0, count: 4)
    ciContext.render(
      output,
      toBitmap: &rgba,
      rowBytes: 4,
      bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
      format: .RGBA8,
      colorSpace: CGColorSpaceCreateDeviceRGB()
    )
    ciContext.clearCaches()

    let r = Double(rgba[0]) / 255.0
    let g = Double(rgba[1]) / 255.0
    let b = Double(rgba[2]) / 255.0
    return (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
  }

  func taxonomyBaseName(from pending: PendingCapture) -> String {
    taxonomyBaseName(
      roomId: pending.roomId ?? RoomTaxonomy.defaultRoomId,
      floorId: pending.floorId ?? FloorTaxonomy.defaultFloorId,
      motifSequence: pending.motifSequence ?? 1,
      bracketIndex: pending.bracketIndex ?? 1,
      bracketTotal: pending.bracketTotal ?? 1
    )
  }

  func taxonomyBaseName(roomId: String, floorId: String, motifSequence: Int, bracketIndex: Int, bracketTotal: Int) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "yyyyMMdd"

    let datePrefix = formatter.string(from: Date())
    let sequence = min(max(motifSequence, 1), 999)
    let safeRoomId = RoomTaxonomy.normalizedRoomId(roomId)
    let safeFloorId = FloorTaxonomy.normalizedFloorId(floorId)
    let roomToken = safeRoomId.replacingOccurrences(of: "_", with: "-")
    let floorToken = FloorTaxonomy.floor(id: safeFloorId).fileToken
    let index = max(bracketIndex, 1)
    let total = max(bracketTotal, 1)
    return "\(datePrefix)\(String(format: "%03d", sequence))\(roomToken)-fl\(floorToken)-\(index)-\(total)"
  }

  func nextMotifSequence() -> Int {
    motifSequenceCounter = (motifSequenceCounter % 999) + 1
    return motifSequenceCounter
  }

  func interShotDelayNanoseconds(for exposure: ExposureSample) -> UInt64 {
    let perFrameSeconds = max(0.0, exposure.perFrameDuration.seconds)
    // Adaptive guard time after each shot:
    // - minimum keeps fast brackets responsive
    // - longer exposures get a slightly longer settle window
    let adaptiveSeconds = min(0.35, perFrameSeconds * 0.25)
    let totalSeconds = max(0.06, adaptiveSeconds)
    return UInt64(totalSeconds * 1_000_000_000)
  }

  private func canCaptureProRAW(device: AVCaptureDevice?) -> Bool {
    guard #available(iOS 14.3, *) else { return false }
    _ = device
    return preferredRawPixelFormatType(for: .proRaw) != nil
  }

  private func effectivePhotoFormat(for requested: PhotoFormat, device: AVCaptureDevice?) -> PhotoFormat {
    switch requested {
    case .proRaw:
      return canCaptureProRAW(device: device) ? .proRaw : .jpeg
    case .heif, .jpeg:
      return .jpeg
    }
  }

  private func fallbackWarningMessageForProRAW(device: AVCaptureDevice?) -> String {
    _ = device
    return NSLocalizedString("warning.proRawUnavailable", comment: "ProRAW unavailable warning")
  }

  private func displayFileExtension(for format: PhotoFormat) -> String {
    switch format {
    case .heif:
      return "jpg"
    case .jpeg:
      return "jpg"
    case .proRaw:
      return "jpg"
    }
  }

  func buildPhotoSettingsPlan(for format: PhotoFormat) -> PhotoSettingsPlan {
    let rawType = preferredRawPixelFormatType(for: format)
    let canUseRaw: Bool
    if #available(iOS 14.3, *) {
      canUseRaw = rawType != nil
    } else {
      canUseRaw = false
    }

    switch format {
    case .heif:
      let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
      applyMaximumPhotoDimensions(to: settings)
      configureDepthDelivery(for: settings)
      return PhotoSettingsPlan(
        settings: settings,
        displayFileExtension: "jpg",
        expectsRawCompanion: false
      )
    case .jpeg:
      let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
      applyMaximumPhotoDimensions(to: settings)
      configureDepthDelivery(for: settings)
      return PhotoSettingsPlan(
        settings: settings,
        displayFileExtension: "jpg",
        expectsRawCompanion: false
      )
    case .proRaw:
      if #available(iOS 14.3, *), canUseRaw, let rawType {
        let processedFormat: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.jpeg]
        let displayFileExtension = "jpg"
        let settings = AVCapturePhotoSettings(rawPixelFormatType: rawType, processedFormat: processedFormat)
        applyMaximumPhotoDimensions(to: settings)
        configureDepthDelivery(for: settings)
        return PhotoSettingsPlan(
          settings: settings,
          displayFileExtension: displayFileExtension,
          expectsRawCompanion: true
        )
      }
      DispatchQueue.main.async {
        self.warningMessage = NSLocalizedString("warning.proRawUnavailable", comment: "ProRAW unavailable warning")
      }
      let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
      applyMaximumPhotoDimensions(to: settings)
      configureDepthDelivery(for: settings)
      return PhotoSettingsPlan(
        settings: settings,
        displayFileExtension: "jpg",
        expectsRawCompanion: false
      )
    }
  }

  private func requestedPhotoQualityPrioritization(
    for captureMode: PhotoCaptureMode
  ) -> AVCapturePhotoOutput.QualityPrioritization {
    if captureMode != .darkRoom {
      return .speed
    }

    switch photoOutput.maxPhotoQualityPrioritization {
    case .quality:
      return .quality
    case .balanced:
      return .balanced
    case .speed:
      return .speed
    @unknown default:
      return .balanced
    }
  }

  private func clearZoomDependentRawWarningIfNeeded(for preset: Double) {
    _ = preset
    guard warningMessage == Self.rawZoomFallbackWarning else { return }
    warningMessage = nil
  }

  func fileExtension(for format: PhotoFormat) -> String {
    switch format {
    case .heif:
      return "jpg"
    case .jpeg:
      return "jpg"
    case .proRaw:
      return "dng"
    }
  }

  func renderRAWIfNeeded(data: Data, outputFormat: PhotoFormat) -> Data {
    guard outputFormat != .proRaw else { return data }
    guard let rawFilter = CIFilter(imageData: data, options: nil) else {
      return data
    }
    // Keep RAW develop defaults. Device/OS-specific KVC keys can throw NSException.
    guard let outputImage = rawFilter.outputImage else {
      return data
    }
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let sourceType = CGImageSourceGetType(source) else {
      return data
    }
    var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
    properties[kCGImagePropertyGPSDictionary] = nil
    let metadataOrientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
    let metadataPixelWidth = properties[kCGImagePropertyPixelWidth] as? Int
    let metadataPixelHeight = properties[kCGImagePropertyPixelHeight] as? Int
    let extentWidth = Int(outputImage.extent.width.rounded())
    let extentHeight = Int(outputImage.extent.height.rounded())
    let isRotated90 = metadataOrientation == 6 || metadataOrientation == 8 || metadataOrientation == 5 || metadataOrientation == 7
    var orientationToApply = metadataOrientation
    if isRotated90, let metadataPixelWidth, let metadataPixelHeight {
      if extentWidth == metadataPixelHeight, extentHeight == metadataPixelWidth {
        // Some RAW decoders already apply the EXIF orientation to the pixel buffer.
        orientationToApply = 1
      }
    }
    let orientedImage = orientationToApply == 1
      ? outputImage
      : outputImage.oriented(forExifOrientation: Int32(orientationToApply))
    guard let cgImage = ciContext.createCGImage(orientedImage, from: orientedImage.extent) else {
      return data
    }
    let destinationType: CFString
    switch outputFormat {
    case .heif:
      destinationType = UTType.jpeg.identifier as CFString
    case .jpeg:
      destinationType = UTType.jpeg.identifier as CFString
    case .proRaw:
      destinationType = sourceType
    }
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, destinationType, 1, nil) else {
      return data
    }
    let flattened = makeOpaqueCGImageIfNeeded(cgImage)
    var updatedProperties = properties
    updatedProperties[kCGImagePropertyOrientation] = 1
    updatedProperties[kCGImagePropertyPixelWidth] = flattened.width
    updatedProperties[kCGImagePropertyPixelHeight] = flattened.height
    if var exif = updatedProperties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
      exif[kCGImagePropertyExifPixelXDimension] = flattened.width
      exif[kCGImagePropertyExifPixelYDimension] = flattened.height
      updatedProperties[kCGImagePropertyExifDictionary] = exif
    }
    if var tiff = updatedProperties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
      tiff[kCGImagePropertyTIFFOrientation] = 1
      updatedProperties[kCGImagePropertyTIFFDictionary] = tiff
    }
    CGImageDestinationAddImage(destination, flattened, updatedProperties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      return data
    }
    return output as Data
  }

  func normalizeOrientationForDisplay(data: Data, outputFormat: PhotoFormat) -> Data {
    guard outputFormat != .proRaw else { return data }
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let sourceType = CGImageSourceGetType(source),
          let image = CIImage(data: data, options: [CIImageOption.applyOrientationProperty: false]) else {
      return data
    }

    let properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
    let orientationRaw = properties[kCGImagePropertyOrientation] as? Int ?? 1
    let oriented = image.oriented(forExifOrientation: Int32(orientationRaw))
    guard let cgImage = ciContext.createCGImage(oriented, from: oriented.extent) else {
      return data
    }

    let flattened = makeOpaqueCGImageIfNeeded(cgImage)
    var updatedProperties = properties
    updatedProperties[kCGImagePropertyOrientation] = 1
    updatedProperties[kCGImagePropertyPixelWidth] = flattened.width
    updatedProperties[kCGImagePropertyPixelHeight] = flattened.height
    if var exif = updatedProperties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
      exif[kCGImagePropertyExifPixelXDimension] = flattened.width
      exif[kCGImagePropertyExifPixelYDimension] = flattened.height
      updatedProperties[kCGImagePropertyExifDictionary] = exif
    }

    let destinationType: CFString
    switch outputFormat {
    case .heif:
      destinationType = UTType.jpeg.identifier as CFString
    case .jpeg:
      destinationType = UTType.jpeg.identifier as CFString
    case .proRaw:
      destinationType = sourceType
    }

    let out = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(out, destinationType, 1, nil) else {
      return data
    }
    CGImageDestinationAddImage(destination, flattened, updatedProperties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      return data
    }
    return out as Data
  }

  func makeOpaqueCGImageIfNeeded(_ image: CGImage) -> CGImage {
    switch image.alphaInfo {
    case .none, .noneSkipFirst, .noneSkipLast:
      return image
    default:
      break
    }

    let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
      data: nil,
      width: image.width,
      height: image.height,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
      return image
    }

    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return context.makeImage() ?? image
  }

  func makeDisplaySafePreviewJPEG(fromRAWAt url: URL) -> Data? {
    guard let rawData = try? Data(contentsOf: url) else { return nil }
    let rendered = renderRAWIfNeeded(data: rawData, outputFormat: .jpeg)
    let stripped = (try? MetadataStripping.stripGPS(from: rendered)) ?? rendered
    return normalizeOrientationForDisplay(data: stripped, outputFormat: .jpeg)
  }

  private func resolvedExifExposureSeconds(for pending: PendingCapture?) -> Double? {
    CaptureMetadataRewriter.resolvedExposureSeconds(
      deviceExposureSeconds: pending?.deviceExposureSeconds,
      requestedSeconds: pending?.duration.seconds
    )
  }

  private func photoDepthSidecarPayload(from photo: AVCapturePhoto) -> PhotoDepthSidecarPayload? {
    guard let depthData = photo.depthData else { return nil }
    return depthSidecarPayload(from: depthData, source: "apple_avdepthdata")
  }

  private func depthSidecarPayload(
    from depthData: AVDepthData,
    source: String
  ) -> PhotoDepthSidecarPayload? {
    let convertedDepthData = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)

    let pixelBuffer = convertedDepthData.depthDataMap
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
      return nil
    }

    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    let floatSize = MemoryLayout<Float32>.size

    var rawDepthData = Data(capacity: width * height * floatSize)
    var validPixelCount = 0
    var invalidPixelCount = 0
    var minDepthMeters = Double.greatestFiniteMagnitude
    var maxDepthMeters = 0.0
    var accumulatedDepthMeters = 0.0

    for row in 0..<height {
      let rowPointer = baseAddress
        .advanced(by: row * bytesPerRow)
        .assumingMemoryBound(to: Float32.self)
      let rowBytes = UnsafeRawPointer(rowPointer).assumingMemoryBound(to: UInt8.self)
      rawDepthData.append(rowBytes, count: width * floatSize)

      for column in 0..<width {
        let value = rowPointer[column]
        guard value.isFinite, value > 0 else {
          invalidPixelCount += 1
          continue
        }
        let depthMeters = Double(value)
        validPixelCount += 1
        accumulatedDepthMeters += depthMeters
        minDepthMeters = min(minDepthMeters, depthMeters)
        maxDepthMeters = max(maxDepthMeters, depthMeters)
      }
    }

    let statistics = PhotoDepthSidecarStatistics(
      validPixelCount: validPixelCount,
      invalidPixelCount: invalidPixelCount,
      minDepthMeters: validPixelCount > 0 ? minDepthMeters : nil,
      maxDepthMeters: validPixelCount > 0 ? maxDepthMeters : nil,
      meanDepthMeters: validPixelCount > 0
        ? accumulatedDepthMeters / Double(validPixelCount)
        : nil
    )

    return PhotoDepthSidecarPayload(
      version: "2.0",
      schema: "pixcapture.photo_depth.v2",
      source: source,
      sourceImageFilename: "",
      width: width,
      height: height,
      depthUnit: "meters",
      encoding: "base64",
      valueType: "float32_le",
      valueLayout: "row_major",
      depthDataType: depthDataTypeToken(convertedDepthData.depthDataType),
      depthDataFiltered: convertedDepthData.isDepthDataFiltered,
      depthDataAccuracy: depthDataAccuracyToken(convertedDepthData.depthDataAccuracy),
      depthDataQuality: depthDataQualityToken(convertedDepthData.depthDataQuality),
      invalidValue: "nan_or_nonpositive",
      sourceFrameCount: nil,
      aggregation: nil,
      statistics: statistics,
      calibration: depthCalibrationPayload(from: convertedDepthData.cameraCalibrationData),
      valuesBase64: rawDepthData.base64EncodedString()
    )
  }

  private func captureSharedStreamingDepthPayload() async -> PhotoDepthSidecarPayload? {
    let supported = depthStateQueue.sync { streamDepthSupported }
    guard supported else { return nil }

    let maxWaitUptime = ProcessInfo.processInfo.systemUptime + 0.35
    let maxDepthAge: TimeInterval = 0.30
    await setStreamingDepthCaptureEnabled(true)
    var resolvedPayload: PhotoDepthSidecarPayload?

    while true {
      if let frame = depthStateQueue.sync(execute: { () -> StreamingDepthFrame? in
        guard streamDepthEnabled,
              let latestStreamingDepthFrame else {
          return nil
        }
        let age = ProcessInfo.processInfo.systemUptime - latestStreamingDepthFrame.receivedAtUptime
        return age <= maxDepthAge ? latestStreamingDepthFrame : nil
      }),
         var payload = depthSidecarPayload(
           from: frame.depthData,
           source: "apple_avcapture_depth_stream"
         ) {
        payload.aggregation = "series_zero_ev_reference"
        resolvedPayload = payload
        break
      }

      if ProcessInfo.processInfo.systemUptime >= maxWaitUptime {
        break
      }
      try? await Task.sleep(nanoseconds: 40_000_000)
    }

    await setStreamingDepthCaptureEnabled(false)
    return resolvedPayload
  }

  @discardableResult
  private func writeCompanionDepthIfAvailable(
    for fileURL: URL,
    payload: PhotoDepthSidecarPayload?,
    sourceFrameCount: Int? = nil,
    aggregation: String? = nil
  ) -> Bool {
    guard var payload else { return false }
    payload.sourceImageFilename = fileURL.lastPathComponent
    if let sourceFrameCount {
      payload.sourceFrameCount = sourceFrameCount
    }
    if let aggregation, payload.aggregation == nil {
      payload.aggregation = aggregation
    }

    do {
      try FileStore.saveCompanionDepth(for: fileURL, payload: payload)
      return true
    } catch {
      DispatchQueue.main.async {
        self.warningMessage = "Depth-Sidecar konnte nicht gespeichert werden."
      }
      return false
    }
  }

  private func depthDiagnostics(
    payload: PhotoDepthSidecarPayload?,
    sidecarWritten: Bool,
    output: AVCapturePhotoOutput? = nil,
    referenceFrame: Bool = false
  ) -> DepthCaptureDiagnostics {
    let activeOutput = output ?? photoOutput
    let streamState = depthStateQueue.sync {
      (supported: streamDepthSupported, enabled: streamDepthEnabled)
    }
    return DepthCaptureDiagnostics(
      deliverySupported: activeOutput.isDepthDataDeliverySupported,
      deliveryEnabled: activeOutput.isDepthDataDeliveryEnabled,
      streamSupported: streamState.supported,
      streamEnabled: streamState.enabled,
      referenceFrame: referenceFrame,
      dataPresent: payload != nil,
      sidecarWritten: sidecarWritten,
      source: payload?.source,
      aggregation: payload?.aggregation,
      depthDataType: payload?.depthDataType,
      depthMapWidth: payload?.width,
      depthMapHeight: payload?.height,
      depthDataFiltered: payload?.depthDataFiltered,
      depthDataAccuracy: payload?.depthDataAccuracy,
      depthDataQuality: payload?.depthDataQuality,
      depthCalibrationPresent: payload?.calibration != nil
    )
  }

  private func updateStreamingDepthState(
    supported: Bool,
    enabled: Bool,
    latestFrame: StreamingDepthFrame?
  ) {
    depthStateQueue.sync {
      streamDepthSupported = supported
      streamDepthEnabled = enabled
      latestStreamingDepthFrame = latestFrame
    }
  }

  private func depthCalibrationPayload(from calibration: AVCameraCalibrationData?) -> PhotoDepthCalibrationPayload? {
    guard let calibration else { return nil }
    let intrinsic = calibration.intrinsicMatrix
    let referenceDimensions = calibration.intrinsicMatrixReferenceDimensions
    let lensDistortionCenter: [Double]? = calibration.lensDistortionCenter == .zero
      ? nil
      : [
        Double(calibration.lensDistortionCenter.x),
        Double(calibration.lensDistortionCenter.y)
      ]

    return PhotoDepthCalibrationPayload(
      referenceWidth: Int(referenceDimensions.width.rounded()),
      referenceHeight: Int(referenceDimensions.height.rounded()),
      intrinsicMatrix: [
        [intrinsic.columns.0.x, intrinsic.columns.1.x, intrinsic.columns.2.x],
        [intrinsic.columns.0.y, intrinsic.columns.1.y, intrinsic.columns.2.y],
        [intrinsic.columns.0.z, intrinsic.columns.1.z, intrinsic.columns.2.z]
      ],
      pixelSizeMillimeters: calibration.pixelSize > 0 ? calibration.pixelSize : nil,
      lensDistortionCenter: lensDistortionCenter
    )
  }

  private func depthDataTypeToken(_ type: OSType) -> String {
    switch type {
    case kCVPixelFormatType_DepthFloat16:
      return "DepthFloat16"
    case kCVPixelFormatType_DepthFloat32:
      return "DepthFloat32"
    case kCVPixelFormatType_DisparityFloat16:
      return "DisparityFloat16"
    case kCVPixelFormatType_DisparityFloat32:
      return "DisparityFloat32"
    default:
      return String(format: "0x%08x", type)
    }
  }

  private func depthDataAccuracyToken(_ accuracy: AVDepthData.Accuracy) -> String {
    switch accuracy {
    case .absolute:
      return "absolute"
    case .relative:
      return "relative"
    @unknown default:
      return "unknown"
    }
  }

  private func depthDataQualityToken(_ quality: AVDepthData.Quality) -> String {
    switch quality {
    case .high:
      return "high"
    case .low:
      return "low"
    @unknown default:
      return "unknown"
    }
  }

  private func writeCompanionXMPIfNeeded(for fileURL: URL, pending: PendingCapture?) {
    guard let pending else { return }

    let metadata = CompanionXMPMetadata(
      exposureBiasValue: pending.baseBiasEV + pending.exposureEV,
      bracketExposureEV: pending.exposureEV,
      requestedBracketExposureEV: pending.requestedExposureEV,
      absoluteRequestedExposureBiasEV: pending.baseBiasEV + pending.requestedExposureEV,
      baseExposureBiasEV: pending.baseBiasEV,
      exposureSeconds: resolvedExifExposureSeconds(for: pending),
      effectiveExposureSeconds: pending.effectiveDuration.seconds > 0 ? pending.effectiveDuration.seconds : nil,
      iso: pending.iso > 0 ? pending.iso : nil,
      bracketIndex: pending.bracketIndex,
      bracketTotal: pending.bracketTotal,
      frameCount: pending.frameCount,
      captureMode: pending.captureMode.rawValue,
      singleShotTriggeredAt: pending.singleShotAssessment?.triggeredAt,
      singleShotRollDegrees: pending.singleShotAssessment?.rollDegrees,
      singleShotPitchDegrees: pending.singleShotAssessment?.pitchDegrees,
      singleShotStabilityScore: pending.singleShotAssessment?.stabilityScore,
      singleShotStabilityState: pending.singleShotAssessment?.stabilityState,
      singleShotCorrectability: pending.singleShotAssessment?.status.manifestToken,
      intendedProcessing: pending.singleShotAssessment?.intendedProcessing
    )

    do {
      try FileStore.saveCompanionXMP(for: fileURL, metadata: metadata)
    } catch {
      DispatchQueue.main.async {
        self.warningMessage = "XMP-Metadaten konnten nicht gespeichert werden."
      }
    }
  }

  private func persistCapturedPhotoData(
    displayData: Data,
    originalData: Data,
    outputFormat: PhotoFormat,
    displayFileExtension: String,
    preferredBaseName: String,
    exposureSeconds: Double? = nil,
    iso: Float? = nil
  ) throws -> PersistedCaptureFiles {
    if outputFormat != .proRaw {
      let stampedDisplayData = CaptureMetadataRewriter.rewriteExposureMetadata(
        data: displayData,
        outputFormat: outputFormat,
        exposureSeconds: exposureSeconds,
        iso: iso
      )
      let url = try FileStore.savePhotoData(
        stampedDisplayData,
        fileExtension: displayFileExtension,
        preferredBaseName: preferredBaseName
      )
      return PersistedCaptureFiles(
        fileURL: url,
        originalFileURL: nil,
        fileDataForExifLog: stampedDisplayData
      )
    }

    let rawURL = try FileStore.savePhotoData(
      originalData,
      fileExtension: fileExtension(for: outputFormat),
      preferredBaseName: preferredBaseName
    )
    return PersistedCaptureFiles(
      fileURL: rawURL,
      originalFileURL: nil,
      fileDataForExifLog: originalData
    )
  }

  private func persistDisplayOnlyPhotoData(
    _ displayData: Data,
    outputFormat: PhotoFormat,
    displayFileExtension: String,
    preferredBaseName: String,
    exposureSeconds: Double? = nil,
    iso: Float? = nil
  ) throws -> PersistedCaptureFiles {
    let stampedDisplayData = CaptureMetadataRewriter.rewriteExposureMetadata(
      data: displayData,
      outputFormat: outputFormat,
      exposureSeconds: exposureSeconds,
      iso: iso
    )
    let url = try FileStore.savePhotoData(
      stampedDisplayData,
      fileExtension: displayFileExtension,
      preferredBaseName: preferredBaseName
    )
    return PersistedCaptureFiles(
      fileURL: url,
      originalFileURL: nil,
      fileDataForExifLog: stampedDisplayData
    )
  }

  func rewriteExifOrientationIfNeeded(data: Data, outputFormat: PhotoFormat, exifOrientation: Int?) -> Data {
    guard outputFormat == .proRaw else { return data }
    guard let exifOrientation, (1...8).contains(exifOrientation) else { return data }
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let sourceType = CGImageSourceGetType(source) else {
      return data
    }
    let destinationType = sourceType as String
    // DNG/RAW writers are not available via ImageIO on iOS; skip rewrite to avoid repeated ImageIO errors.
    guard writableImageDestinationTypes.contains(destinationType) else {
      return data
    }
    var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
    let existingOrientation = properties[kCGImagePropertyOrientation] as? Int
    let existingTiffOrientation = (properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFOrientation] as? Int
    if existingOrientation == exifOrientation, existingTiffOrientation == exifOrientation {
      return data
    }
    properties[kCGImagePropertyOrientation] = exifOrientation
    var tiff = (properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]) ?? [:]
    tiff[kCGImagePropertyTIFFOrientation] = exifOrientation
    properties[kCGImagePropertyTIFFDictionary] = tiff

    let out = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(out, sourceType, 1, nil) else {
      return data
    }
    CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      return data
    }
    return out as Data
  }
}

extension CameraError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .noDevice:
      return "Keine Kamera verfügbar."
    case .customExposureNotSupported:
      return "Manuelle Belichtungszeit wird auf diesem Gerät/Modus nicht unterstützt."
    case .photoDataUnavailable:
      return "Bilddaten konnten von der Kamera nicht geliefert werden."
    case .captureProcessingFailed:
      return "Lange Belichtungsreihe konnte nicht sauber verarbeitet werden."
    }
  }
}

private extension CameraManager {
  func finalizeCombinedRawCapture(
    uniqueID: Int64,
    pending: PendingCapture,
    continuation: CheckedContinuation<CapturedPhoto, Error>
  ) {
    guard let state = multiRepresentationCaptures.removeValue(forKey: uniqueID),
          let processedData = state.processedData else {
      continuation.resume(throwing: CameraError.photoDataUnavailable)
      return
    }

    do {
      let processedFormat: PhotoFormat = .jpeg
      let cleanedProcessed = try MetadataStripping.stripGPS(from: processedData)
      let displaySafe = normalizeOrientationForDisplay(data: cleanedProcessed, outputFormat: processedFormat)
      let preferredBaseName = taxonomyBaseName(from: pending)
      let persistedFiles: PersistedCaptureFiles
      if let rawData = state.rawData {
        let cleanedRaw = (try? MetadataStripping.stripGPS(from: rawData)) ?? rawData
        persistedFiles = try persistCapturedPhotoData(
          displayData: displaySafe,
          originalData: cleanedRaw,
          outputFormat: pending.format,
          displayFileExtension: pending.displayFileExtension,
          preferredBaseName: preferredBaseName,
          exposureSeconds: resolvedExifExposureSeconds(for: pending),
          iso: pending.iso
        )
      } else {
        persistedFiles = try persistDisplayOnlyPhotoData(
          displaySafe,
          outputFormat: processedFormat,
          displayFileExtension: pending.displayFileExtension,
          preferredBaseName: preferredBaseName,
          exposureSeconds: resolvedExifExposureSeconds(for: pending),
          iso: pending.iso
        )
      }

      let depthSidecarWritten = pending.shouldWriteDepthSidecar
        ? writeCompanionDepthIfAvailable(
          for: persistedFiles.fileURL,
          payload: state.depthSidecarPayload,
          sourceFrameCount: pending.frameCount
        )
        : false
      writeCompanionXMPIfNeeded(for: persistedFiles.fileURL, pending: pending)
      _ = FileStore.ensurePreviewExists(
        for: persistedFiles.fileURL,
        captureOrientation: pending.requestedCaptureOrientation,
        sensorRollDegrees: pending.sensorRollDegrees
      )
      if pending.includeInSeriesLog {
        seriesLogQueue.async {
          self.activeSeriesPhotoURLs.append(persistedFiles.fileURL)
        }
        recordExifLog(
          data: persistedFiles.fileDataForExifLog,
          pending: pending,
          fileURL: persistedFiles.fileURL,
          depthDiagnostics: depthDiagnostics(
            payload: state.depthSidecarPayload,
            sidecarWritten: depthSidecarWritten,
            referenceFrame: pending.shouldWriteDepthSidecar
          )
        )
      }

      let captured = CapturedPhoto(
        id: UUID(),
        fileURL: persistedFiles.fileURL,
        originalFileURL: persistedFiles.originalFileURL,
        exposureEV: pending.exposureEV,
        exposureDuration: pending.effectiveDuration,
        iso: pending.iso,
        captureOrientation: pending.requestedCaptureOrientation,
        sensorPitchDegrees: pending.sensorPitchDegrees,
        sensorRollDegrees: pending.sensorRollDegrees,
        sensorHeadingDegrees: pending.sensorHeadingDegrees,
        captureMode: pending.captureMode,
        singleShotAssessment: pending.singleShotAssessment
      )
      if pending.includeInSeriesLog {
        registerCapturedSeriesPhoto(
          captured,
          seriesId: pending.seriesId,
          roomId: pending.roomId,
          floorId: pending.floorId
        )
      }
      continuation.resume(returning: captured)
    } catch {
      continuation.resume(throwing: error)
    }
  }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
  func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
    let uniqueID = photo.resolvedSettings.uniqueID
    if let bracket = bracketContinuations[uniqueID] {
      if let error {
        bracketContinuations.removeValue(forKey: uniqueID)
        bracket.continuation.resume(throwing: error)
        return
      }
      guard let data = photo.fileDataRepresentation() else {
        bracketContinuations.removeValue(forKey: uniqueID)
        bracket.continuation.resume(throwing: CameraError.photoDataUnavailable)
        return
      }

      let index = max(photo.sequenceCount - 1, 0)
      let exposure = bracket.exposures[min(index, bracket.exposures.count - 1)]
      let shouldWriteDepthSidecar = index == preferredDepthReferenceIndex(in: bracket.exposures)
      let activeFormat = videoDevice?.activeFormat
      let pending = PendingCapture(
        seriesId: nil,
        sequenceNumber: photo.sequenceCount > 0 ? photo.sequenceCount : nil,
        roomId: bracket.roomId,
        floorId: bracket.floorId,
        motifSequence: bracket.motifSequence,
        bracketIndex: index + 1,
        bracketTotal: bracket.exposures.count,
        zone: exposure.zone.rawValue,
        frameCount: exposure.frameCount,
        exposureEV: exposure.ev,
        requestedExposureEV: exposure.requestedEV,
        baseBiasEV: bracket.baseBiasEV,
        outputAspectRatio: bracket.outputAspectRatio,
        duration: exposure.perFrameDuration,
        effectiveDuration: exposure.effectiveDuration,
        iso: exposure.perFrameISO,
        activeFormatMinISO: activeFormat?.minISO,
        activeFormatMaxISO: activeFormat?.maxISO,
        activeFormatMinExposureSeconds: activeFormat?.minExposureDuration.seconds,
        activeFormatMaxExposureSeconds: activeFormat?.maxExposureDuration.seconds,
        seriesInitialBaseISO: nil,
        seriesFinalBaseISO: nil,
        seriesUsedRecoveryISO: nil,
        deviceExposureSeconds: nil,
        deviceISO: nil,
        deviceExposureTargetBias: nil,
        deviceExposureTargetOffset: nil,
        deviceLensPosition: nil,
        deviceFocusMode: bracket.focusMode,
        deviceFocusPointX: bracket.focusPointX,
        deviceFocusPointY: bracket.focusPointY,
        deviceAdjustingFocus: bracket.adjustingFocus,
        deviceSubjectAreaMonitoringEnabled: bracket.subjectAreaMonitoringEnabled,
        deviceZoomFactor: nil,
        deviceWhiteBalanceGainRed: nil,
        deviceWhiteBalanceGainGreen: nil,
        deviceWhiteBalanceGainBlue: nil,
        sensorPitchDegrees: bracket.sensorPitchDegrees,
        sensorRollDegrees: bracket.sensorRollDegrees,
        sensorHeadingDegrees: bracket.sensorHeadingDegrees,
        requestedCaptureOrientation: bracket.requestedCaptureOrientation,
        connectionRotationAngle: bracket.connectionRotationAngle,
        exifOrientation: bracket.exifOrientation,
        format: bracket.format,
        displayFileExtension: displayFileExtension(for: bracket.format),
        expectsRawCompanion: false,
        captureMode: .standardBracket,
        singleShotAssessment: nil,
        includeInSeriesLog: true,
        shouldWriteDepthSidecar: shouldWriteDepthSidecar,
        sharedSeriesDepthPayload: nil
      )

      do {
        let rendered = renderRAWIfNeeded(data: data, outputFormat: pending.format)
        let cleaned = try MetadataStripping.stripGPS(from: rendered)
        let bracketExifOrientation = pending.exifOrientation ?? bracket.exifOrientation
        let orientationFixed = rewriteExifOrientationIfNeeded(
          data: cleaned,
          outputFormat: pending.format,
          exifOrientation: bracketExifOrientation
        )
        let displaySafe = normalizeOrientationForDisplay(data: orientationFixed, outputFormat: pending.format)
        let persistedFiles = try persistCapturedPhotoData(
          displayData: displaySafe,
          originalData: orientationFixed,
          outputFormat: pending.format,
          displayFileExtension: pending.displayFileExtension,
          preferredBaseName: taxonomyBaseName(from: pending),
          exposureSeconds: resolvedExifExposureSeconds(for: pending),
          iso: pending.iso
        )
        let depthPayload = photoDepthSidecarPayload(from: photo)
        let depthSidecarWritten = pending.shouldWriteDepthSidecar
          ? writeCompanionDepthIfAvailable(
            for: persistedFiles.fileURL,
            payload: depthPayload,
            sourceFrameCount: pending.frameCount
          )
          : false
        writeCompanionXMPIfNeeded(for: persistedFiles.fileURL, pending: pending)
        _ = FileStore.ensurePreviewExists(
          for: persistedFiles.fileURL,
          captureOrientation: pending.requestedCaptureOrientation,
          sensorRollDegrees: pending.sensorRollDegrees
        )
        seriesLogQueue.async {
          self.activeSeriesPhotoURLs.append(persistedFiles.fileURL)
        }
        recordExifLog(
          data: persistedFiles.fileDataForExifLog,
          pending: pending,
          fileURL: persistedFiles.fileURL,
          depthDiagnostics: depthDiagnostics(
            payload: depthPayload,
            sidecarWritten: depthSidecarWritten,
            output: output,
            referenceFrame: pending.shouldWriteDepthSidecar
          )
        )
        let captured = CapturedPhoto(
          id: UUID(),
          fileURL: persistedFiles.fileURL,
          originalFileURL: persistedFiles.originalFileURL,
          exposureEV: pending.exposureEV,
          exposureDuration: pending.effectiveDuration,
          iso: pending.iso,
          captureOrientation: pending.requestedCaptureOrientation,
          sensorPitchDegrees: pending.sensorPitchDegrees,
          sensorRollDegrees: pending.sensorRollDegrees,
          sensorHeadingDegrees: pending.sensorHeadingDegrees,
          captureMode: pending.captureMode,
          singleShotAssessment: pending.singleShotAssessment
        )
        self.registerCapturedSeriesPhoto(
          captured,
          seriesId: pending.seriesId,
          roomId: pending.roomId,
          floorId: pending.floorId
        )
        bracket.photos.append(captured)
        DispatchQueue.main.async {
          self.captureProgress = CaptureProgress(
            total: bracket.exposures.count,
            current: bracket.photos.count,
            ev: pending.exposureEV
          )
        }
        if bracket.photos.count >= bracket.exposures.count {
          bracketContinuations.removeValue(forKey: uniqueID)
          bracket.continuation.resume(returning: bracket.photos)
        }
      } catch {
        bracketContinuations.removeValue(forKey: uniqueID)
        bracket.continuation.resume(throwing: error)
      }
      return
    }

    let continuation = photoContinuations.removeValue(forKey: uniqueID)
    let pending = pendingCaptures.removeValue(forKey: uniqueID)

    if let error {
      multiRepresentationCaptures.removeValue(forKey: uniqueID)
      continuation?.resume(throwing: error)
      return
    }

    guard let data = photo.fileDataRepresentation() else {
      multiRepresentationCaptures.removeValue(forKey: uniqueID)
      continuation?.resume(throwing: CameraError.photoDataUnavailable)
      return
    }

    if let pending, pending.expectsRawCompanion {
      photoContinuations[uniqueID] = continuation
      pendingCaptures[uniqueID] = pending
      var state = multiRepresentationCaptures[uniqueID] ?? MultiRepresentationCaptureState()
      if photo.isRawPhoto {
        state.rawData = data
      } else {
        state.processedData = data
      }
      if state.depthSidecarPayload == nil {
        state.depthSidecarPayload = photoDepthSidecarPayload(from: photo) ?? pending.sharedSeriesDepthPayload
      }
      multiRepresentationCaptures[uniqueID] = state
      return
    }

    do {
      let format = pending?.format ?? .jpeg
      let rendered = renderRAWIfNeeded(data: data, outputFormat: format)
      let cleaned = try MetadataStripping.stripGPS(from: rendered)
      let targetExifOrientation: Int? = pending?.exifOrientation ?? exifOrientation(for: currentCaptureVideoOrientation())
      let safeOrientation = rewriteExifOrientationIfNeeded(
        data: cleaned,
        outputFormat: format,
        exifOrientation: targetExifOrientation
      )
      let displaySafe = normalizeOrientationForDisplay(data: safeOrientation, outputFormat: format)
      let preferredBaseName = pending.map { taxonomyBaseName(from: $0) } ?? UUID().uuidString
      let persistedFiles = try persistCapturedPhotoData(
        displayData: displaySafe,
        originalData: safeOrientation,
        outputFormat: format,
        displayFileExtension: pending?.displayFileExtension ?? displayFileExtension(for: format),
        preferredBaseName: preferredBaseName,
        exposureSeconds: resolvedExifExposureSeconds(for: pending),
        iso: pending?.iso
      )
      let photoDepthPayload = photoDepthSidecarPayload(from: photo)
      let depthPayload = photoDepthPayload ?? pending?.sharedSeriesDepthPayload
      let depthSidecarWritten = pending?.shouldWriteDepthSidecar == true
        ? writeCompanionDepthIfAvailable(
          for: persistedFiles.fileURL,
          payload: depthPayload,
          sourceFrameCount: pending?.frameCount
        )
        : false
      writeCompanionXMPIfNeeded(for: persistedFiles.fileURL, pending: pending)
      _ = FileStore.ensurePreviewExists(
        for: persistedFiles.fileURL,
        captureOrientation: pending?.requestedCaptureOrientation,
        sensorRollDegrees: pending?.sensorRollDegrees
      )
      if let pending, pending.includeInSeriesLog {
        seriesLogQueue.async {
          self.activeSeriesPhotoURLs.append(persistedFiles.fileURL)
        }
        recordExifLog(
          data: persistedFiles.fileDataForExifLog,
          pending: pending,
          fileURL: persistedFiles.fileURL,
          depthDiagnostics: depthDiagnostics(
            payload: depthPayload,
            sidecarWritten: depthSidecarWritten,
            output: output,
            referenceFrame: pending.shouldWriteDepthSidecar
          )
        )
      }
      let captured = CapturedPhoto(
        id: UUID(),
        fileURL: persistedFiles.fileURL,
        originalFileURL: persistedFiles.originalFileURL,
        exposureEV: pending?.exposureEV ?? 0,
        exposureDuration: pending?.effectiveDuration ?? .zero,
        iso: pending?.iso ?? 0,
        captureOrientation: pending?.requestedCaptureOrientation,
        sensorPitchDegrees: pending?.sensorPitchDegrees,
        sensorRollDegrees: pending?.sensorRollDegrees,
        sensorHeadingDegrees: pending?.sensorHeadingDegrees,
        captureMode: pending?.captureMode ?? .standardBracket,
        singleShotAssessment: pending?.singleShotAssessment
      )
      if let pending, pending.includeInSeriesLog {
        registerCapturedSeriesPhoto(
          captured,
          seriesId: pending.seriesId,
          roomId: pending.roomId,
          floorId: pending.floorId
        )
      }
      continuation?.resume(returning: captured)
    } catch {
      continuation?.resume(throwing: error)
    }
  }

  func photoOutput(
    _ output: AVCapturePhotoOutput,
    didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
    error: Error?
  ) {
    let uniqueID = resolvedSettings.uniqueID
    guard let pending = pendingCaptures[uniqueID], pending.expectsRawCompanion else { return }
    let continuation = photoContinuations.removeValue(forKey: uniqueID)
    let finalizedPending = pendingCaptures.removeValue(forKey: uniqueID)

    if let error {
      multiRepresentationCaptures.removeValue(forKey: uniqueID)
      continuation?.resume(throwing: error)
      return
    }

    guard let finalizedPending, let continuation else {
      multiRepresentationCaptures.removeValue(forKey: uniqueID)
      return
    }

    finalizeCombinedRawCapture(
      uniqueID: uniqueID,
      pending: finalizedPending,
      continuation: continuation
    )
  }
}

extension CameraManager: AVCaptureDepthDataOutputDelegate {
  func depthDataOutput(
    _ output: AVCaptureDepthDataOutput,
    didOutput depthData: AVDepthData,
    timestamp: CMTime,
    connection: AVCaptureConnection
  ) {
    depthStateQueue.sync {
      guard self.streamDepthEnabled else { return }
      self.latestStreamingDepthFrame = StreamingDepthFrame(
        depthData: depthData,
        receivedAtUptime: ProcessInfo.processInfo.systemUptime
      )
    }
  }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    let metrics = histogramProcessor.analyze(pixelBuffer: pixelBuffer)
    latestMeanLuma = metrics.meanLuminance
    latestDarkClip = metrics.darkClipRatio
    latestBrightClip = metrics.brightClipRatio
    let smoothed = smoothedMetrics(from: metrics)
    let exposureState = evaluateExposureQuality(metrics: smoothed)
    let sharpnessState = evaluateSharpnessQuality(metrics: smoothed)
    DispatchQueue.main.async {
      self.histogramBins = self.resolvedSmoothedHistogramBins(from: metrics.bins)
      self.highlightWarningActive = self.resolvedHighlightWarningActive(
        brightClipRatio: smoothed.brightClipRatio
      )
      self.highlightWarningMask = self.resolvedHighlightWarningMask(
        from: metrics.highlightWarningMask,
        active: self.highlightWarningActive
      )
      self.exposureQualityState = exposureState
      self.sharpnessQualityState = sharpnessState
    }
  }

  private func smoothedMetrics(from metrics: FrameQualityMetrics) -> FrameQualityMetrics {
    let alpha = 0.22
    smoothedMeanLuma = smooth(previous: smoothedMeanLuma, current: metrics.meanLuminance, alpha: alpha)
    smoothedDarkClip = smooth(previous: smoothedDarkClip, current: metrics.darkClipRatio, alpha: alpha)
    smoothedBrightClip = smooth(previous: smoothedBrightClip, current: metrics.brightClipRatio, alpha: alpha)
    smoothedSharpness = smooth(previous: smoothedSharpness, current: metrics.sharpnessScore, alpha: alpha)
    return FrameQualityMetrics(
      bins: metrics.bins,
      meanLuminance: smoothedMeanLuma ?? metrics.meanLuminance,
      darkClipRatio: smoothedDarkClip ?? metrics.darkClipRatio,
      brightClipRatio: smoothedBrightClip ?? metrics.brightClipRatio,
      sharpnessScore: smoothedSharpness ?? metrics.sharpnessScore,
      highlightWarningMask: metrics.highlightWarningMask
    )
  }

  private func smooth(previous: Double?, current: Double, alpha: Double) -> Double {
    guard let previous else { return current }
    return (alpha * current) + ((1.0 - alpha) * previous)
  }

  private func resolvedSmoothedHistogramBins(from bins: [CGFloat]) -> [CGFloat] {
    let alpha: CGFloat = 0.2
    guard let previous = smoothedHistogramBins, previous.count == bins.count else {
      smoothedHistogramBins = bins
      return bins
    }

    let smoothed = zip(previous, bins).map { oldValue, newValue in
      (alpha * newValue) + ((1 - alpha) * oldValue)
    }
    smoothedHistogramBins = smoothed
    return smoothed
  }

  private func resolvedHighlightWarningActive(brightClipRatio: Double) -> Bool {
    if highlightWarningLatched {
      highlightWarningLatched = brightClipRatio >= 0.012
    } else {
      highlightWarningLatched = brightClipRatio >= 0.02
    }
    return highlightWarningLatched
  }

  private func resolvedHighlightWarningMask(
    from mask: HighlightWarningMask,
    active: Bool
  ) -> HighlightWarningMask {
    guard active, mask.columns > 0, mask.rows > 0, !mask.cells.isEmpty else {
      smoothedHighlightWarningCells = nil
      return .empty
    }

    let alpha: CGFloat = 0.24
    let smoothedCells: [CGFloat]
    if let previous = smoothedHighlightWarningCells, previous.count == mask.cells.count {
      smoothedCells = zip(previous, mask.cells).map { oldValue, newValue in
        (alpha * newValue) + ((1 - alpha) * oldValue)
      }
    } else {
      smoothedCells = mask.cells
    }

    smoothedHighlightWarningCells = smoothedCells
    let quietCells = smoothedCells.map { value in
      value < 0.08 ? 0 : min(max(value, 0), 1)
    }
    return HighlightWarningMask(columns: mask.columns, rows: mask.rows, cells: quietCells)
  }

  private func isoDeviationExceedsTolerance(actualISO: Double, requestedISO: Double) -> Bool {
    guard actualISO > 0, requestedISO > 0 else { return false }
    let relativeDelta = abs(actualISO - requestedISO) / requestedISO
    if relativeDelta <= 0.12 {
      return false
    }
    let evDelta = abs(log2(actualISO / requestedISO))
    return evDelta > 0.2
  }

  private func evaluateExposureQuality(metrics: FrameQualityMetrics) -> LiveQualityState {
    let mean = metrics.meanLuminance
    let dark = metrics.darkClipRatio
    let bright = metrics.brightClipRatio

    switch qualityProfile {
    case .interior:
      if dark > 0.22 || bright > 0.16 || mean < 0.14 || mean > 0.84 { return .bad }
      if dark > 0.12 || bright > 0.09 || mean < 0.21 || mean > 0.76 { return .warning }
      return .good
    case .exterior:
      if dark > 0.30 || bright > 0.30 || mean < 0.10 || mean > 0.90 { return .bad }
      if dark > 0.17 || bright > 0.20 || mean < 0.18 || mean > 0.82 { return .warning }
      return .good
    case .other:
      if dark > 0.25 || bright > 0.22 || mean < 0.12 || mean > 0.88 { return .bad }
      if dark > 0.14 || bright > 0.12 || mean < 0.20 || mean > 0.80 { return .warning }
      return .good
    }
  }

  private func evaluateSharpnessQuality(metrics: FrameQualityMetrics) -> LiveQualityState {
    let score = metrics.sharpnessScore
    switch qualityProfile {
    case .interior:
      if score < 0.0075 { return .bad }
      if score < 0.0130 { return .warning }
      return .good
    case .exterior:
      if score < 0.0100 { return .bad }
      if score < 0.0160 { return .warning }
      return .good
    case .other:
      if score < 0.0085 { return .bad }
      if score < 0.0140 { return .warning }
      return .good
    }
  }
}
