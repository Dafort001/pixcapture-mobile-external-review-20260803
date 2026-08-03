import Foundation
import SwiftUI
import Combine

struct RecentJobSnapshot: Equatable {
  let job: JobInfo
  let lastActivityAt: Date
}

final class AppSettings: ObservableObject {
  private static let defaultHistogramOverlayPosition = CGPoint(x: 0.24, y: 0.18)

  private enum StorageKey {
    static let histogramOverlayX = "histogramOverlayX"
    static let histogramOverlayY = "histogramOverlayY"
    static let jobLabel = "jobLabel"
    static let jobId = "jobId"
    static let jobAddress = "jobAddress"
    static let recentJobScope = "recentJobScope"
    static let recentJobId = "recentJobId"
    static let recentJobLabel = "recentJobLabel"
    static let recentJobAddress = "recentJobAddress"
    static let recentJobActivityAt = "recentJobActivityAt"
    static let whiteBalanceKelvin = "whiteBalanceKelvin"
    static let galleryOrientationMode = "galleryOrientationMode"
    static let bracketCount = "bracketCount"
    static let exposureStepEV = "exposureStepEV"
    static let photoCaptureMode = "photoCaptureMode"
    static let maxExposureSeconds = "maxExposureSeconds"
    static let exposureBiasEV = "exposureBiasEV"
    static let bracketMeteringMode = "bracketMeteringMode"
    static let captureDelaySeconds = "captureDelaySeconds"
    static let gridEnabled = "gridEnabled"
    static let levelEnabled = "levelEnabled"
    static let histogramEnabled = "histogramEnabled"
    static let allowCellularUpload = "allowCellularUpload"
    static let autoUploadEnabled = "autoUploadEnabled"
    static let focusLockEnabled = "focusLockEnabled"
    static let whiteBalanceLocked = "whiteBalanceLocked"
    static let manualISOEnabled = "manualISOEnabled"
    static let manualISOValue = "manualISOValue"
    static let manualShutterSeconds = "manualShutterSeconds"
    static let exposureSliderPosition = "exposureSliderPosition"
    static let photoFormat = "photoFormat"
    static let preferredPhotoFormat = "preferredPhotoFormat"
    static let repairedTemporaryHEIFFallback = "repairedTemporaryHEIFFallback"
    static let selectedRoomId = "selectedRoomId"
    static let selectedFloorId = "selectedFloorId"
    static let lastZoomPreset = "lastZoomPreset"
    static let companionHost = "companionHost"
    static let companionPort = "companionPort"
    static let companionUseHTTPS = "companionUseHTTPS"
    static let companionPairingCode = "companionPairingCode"
    static let volumeShutterEnabled = "volumeShutterEnabled"
    static let volumeShutterKeepVolumeStable = "volumeShutterKeepVolumeStable"
    static let videoStabilizationEnabled = "videoStabilizationEnabled"
    static let seriesIndexPrefix = "seriesIndex"
    static let appLanguage = "appLanguage"
  }

  @Published var appLanguage: AppLanguage = .system {
    didSet { UserDefaults.standard.set(appLanguage.rawValue, forKey: StorageKey.appLanguage) }
  }

  @Published var bracketCount: Int = 5 {
    didSet {
      UserDefaults.standard.set(bracketCount, forKey: StorageKey.bracketCount)
    }
  }
  @Published var exposureStepEV: Double = BracketStepPolicy.denseBracketStepEV {
    didSet { UserDefaults.standard.set(exposureStepEV, forKey: StorageKey.exposureStepEV) }
  }
  @Published var photoCaptureMode: PhotoCaptureMode = .standardBracket {
    didSet {
      UserDefaults.standard.set(photoCaptureMode.rawValue, forKey: StorageKey.photoCaptureMode)
    }
  }
  @Published var maxExposureSeconds: Double = 10.0 {
    didSet { UserDefaults.standard.set(maxExposureSeconds, forKey: StorageKey.maxExposureSeconds) }
  }
  @Published var exposureBiasEV: Double = 0.0 {
    didSet { UserDefaults.standard.set(exposureBiasEV, forKey: StorageKey.exposureBiasEV) }
  }
  @Published var bracketMeteringMode: BracketMeteringMode = .previewBalanced {
    didSet { UserDefaults.standard.set(bracketMeteringMode.rawValue, forKey: StorageKey.bracketMeteringMode) }
  }
  @Published var captureDelaySeconds: Double = 0.0 {
    didSet { UserDefaults.standard.set(captureDelaySeconds, forKey: StorageKey.captureDelaySeconds) }
  }

  @Published var gridEnabled: Bool = true {
    didSet { UserDefaults.standard.set(gridEnabled, forKey: StorageKey.gridEnabled) }
  }
  @Published var levelEnabled: Bool = true {
    didSet { UserDefaults.standard.set(levelEnabled, forKey: StorageKey.levelEnabled) }
  }
  @Published var histogramEnabled: Bool = true {
    didSet { UserDefaults.standard.set(histogramEnabled, forKey: StorageKey.histogramEnabled) }
  }
  @Published var volumeShutterEnabled: Bool = false {
    didSet { UserDefaults.standard.set(volumeShutterEnabled, forKey: StorageKey.volumeShutterEnabled) }
  }
  @Published var volumeShutterKeepVolumeStable: Bool = true {
    didSet {
      UserDefaults.standard.set(volumeShutterKeepVolumeStable, forKey: StorageKey.volumeShutterKeepVolumeStable)
    }
  }
  @Published var videoStabilizationEnabled: Bool = true {
    didSet { UserDefaults.standard.set(videoStabilizationEnabled, forKey: StorageKey.videoStabilizationEnabled) }
  }

  @Published var allowCellularUpload: Bool = false {
    didSet { UserDefaults.standard.set(allowCellularUpload, forKey: StorageKey.allowCellularUpload) }
  }
  @Published var autoUploadEnabled: Bool = false {
    didSet { UserDefaults.standard.set(autoUploadEnabled, forKey: StorageKey.autoUploadEnabled) }
  }

  @Published var focusLockEnabled: Bool = false {
    didSet { UserDefaults.standard.set(focusLockEnabled, forKey: StorageKey.focusLockEnabled) }
  }
  @Published var whiteBalanceLocked: Bool = false {
    didSet { UserDefaults.standard.set(whiteBalanceLocked, forKey: StorageKey.whiteBalanceLocked) }
  }
  @Published var whiteBalanceKelvin: Double = 4500.0 {
    didSet {
      UserDefaults.standard.set(whiteBalanceKelvin, forKey: StorageKey.whiteBalanceKelvin)
    }
  }
  @Published var manualISOEnabled: Bool = true {
    didSet { UserDefaults.standard.set(manualISOEnabled, forKey: StorageKey.manualISOEnabled) }
  }
  @Published var manualISOValue: Double = 100.0 {
    didSet { UserDefaults.standard.set(manualISOValue, forKey: StorageKey.manualISOValue) }
  }
  @Published var manualShutterSeconds: Double = 1.0 / 125.0 {
    didSet { UserDefaults.standard.set(manualShutterSeconds, forKey: StorageKey.manualShutterSeconds) }
  }

  @Published var exposureSliderPosition: ExposureSliderPosition = .auto {
    didSet { UserDefaults.standard.set(exposureSliderPosition.rawValue, forKey: StorageKey.exposureSliderPosition) }
  }
  @Published var histogramOverlayPosition: CGPoint = AppSettings.defaultHistogramOverlayPosition {
    didSet {
      let defaults = UserDefaults.standard
      defaults.set(histogramOverlayPosition.x, forKey: StorageKey.histogramOverlayX)
      defaults.set(histogramOverlayPosition.y, forKey: StorageKey.histogramOverlayY)
    }
  }
  @Published var galleryOrientationMode: GalleryOrientationMode = .manualFixed {
    didSet {
      UserDefaults.standard.set(galleryOrientationMode.rawValue, forKey: StorageKey.galleryOrientationMode)
    }
  }

  @Published var photoFormat: PhotoFormat = .proRaw {
    didSet {
      guard !isApplyingProgrammaticPhotoFormatChange else { return }
      UserDefaults.standard.set(photoFormat.rawValue, forKey: StorageKey.photoFormat)
      if preferredPhotoFormat != photoFormat {
        preferredPhotoFormat = photoFormat
      }
    }
  }

  private(set) var preferredPhotoFormat: PhotoFormat = .proRaw {
    didSet {
      UserDefaults.standard.set(preferredPhotoFormat.rawValue, forKey: StorageKey.preferredPhotoFormat)
    }
  }

  private var isApplyingProgrammaticPhotoFormatChange = false

  @Published var selectedRoomId: String = RoomTaxonomy.defaultRoomId {
    didSet { UserDefaults.standard.set(selectedRoomId, forKey: StorageKey.selectedRoomId) }
  }
  @Published var selectedFloorId: String = FloorTaxonomy.defaultFloorId {
    didSet { UserDefaults.standard.set(selectedFloorId, forKey: StorageKey.selectedFloorId) }
  }
  @Published var lastZoomPreset: Double = 1.0 {
    didSet { UserDefaults.standard.set(lastZoomPreset, forKey: StorageKey.lastZoomPreset) }
  }
  @Published var companionHost: String = "" {
    didSet { UserDefaults.standard.set(companionHost, forKey: StorageKey.companionHost) }
  }
  @Published var companionPort: Int = 8080 {
    didSet { UserDefaults.standard.set(companionPort, forKey: StorageKey.companionPort) }
  }
  @Published var companionUseHTTPS: Bool = false {
    didSet { UserDefaults.standard.set(companionUseHTTPS, forKey: StorageKey.companionUseHTTPS) }
  }
  @Published var companionPairingCode: String = "" {
    didSet { UserDefaults.standard.set(companionPairingCode, forKey: StorageKey.companionPairingCode) }
  }
  @Published var jobLabel: String = "" {
    didSet {
      UserDefaults.standard.set(jobLabel, forKey: StorageKey.jobLabel)
    }
  }
  @Published var selectedJobId: String? = nil {
    didSet {
      UserDefaults.standard.set(selectedJobId, forKey: StorageKey.jobId)
    }
  }
  @Published var jobAddress: String = "" {
    didSet {
      UserDefaults.standard.set(jobAddress, forKey: StorageKey.jobAddress)
    }
  }

  private var recentJobScope: String?
  private var recentJobId: String?
  private var recentJobLabel: String = ""
  private var recentJobAddress: String = ""
  private var recentJobActivityAt: Date?

  init() {
    let defaults = UserDefaults.standard
    if let savedLanguage = defaults.string(forKey: StorageKey.appLanguage),
       let language = AppLanguage(rawValue: savedLanguage) {
      appLanguage = language
    }
    let x = defaults.object(forKey: StorageKey.histogramOverlayX) as? Double
    let y = defaults.object(forKey: StorageKey.histogramOverlayY) as? Double
    if let x, let y {
      histogramOverlayPosition = Self.normalizedHistogramOverlayPosition(CGPoint(x: x, y: y))
    }
    if let savedJob = defaults.string(forKey: StorageKey.jobLabel) {
      jobLabel = savedJob
    }
    if let savedJobId = defaults.string(forKey: StorageKey.jobId) {
      selectedJobId = savedJobId
    }
    if let savedJobAddress = defaults.string(forKey: StorageKey.jobAddress) {
      jobAddress = savedJobAddress
    }
    if let savedRecentScope = defaults.string(forKey: StorageKey.recentJobScope),
       !savedRecentScope.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      recentJobScope = savedRecentScope
    }
    if let savedRecentJobId = defaults.string(forKey: StorageKey.recentJobId),
       !savedRecentJobId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      recentJobId = savedRecentJobId
    }
    if let savedRecentJobLabel = defaults.string(forKey: StorageKey.recentJobLabel) {
      recentJobLabel = savedRecentJobLabel
    }
    if let savedRecentJobAddress = defaults.string(forKey: StorageKey.recentJobAddress) {
      recentJobAddress = savedRecentJobAddress
    }
    if defaults.object(forKey: StorageKey.recentJobActivityAt) != nil {
      let timestamp = defaults.double(forKey: StorageKey.recentJobActivityAt)
      if timestamp > 0 {
        recentJobActivityAt = Date(timeIntervalSince1970: timestamp)
      }
    }
    let savedKelvin = defaults.double(forKey: StorageKey.whiteBalanceKelvin)
    if savedKelvin > 0 {
      whiteBalanceKelvin = min(max(savedKelvin, 2000.0), 6000.0)
    }
    if let savedMode = defaults.string(forKey: StorageKey.galleryOrientationMode),
       let mode = GalleryOrientationMode(rawValue: savedMode) {
      galleryOrientationMode = mode
    }
    if let savedCount = defaults.object(forKey: StorageKey.bracketCount) as? Int {
      let allowed = [1, 3, 5, 7]
      bracketCount = allowed.contains(savedCount) ? savedCount : 5
    }
    let allowedSteps: Set<Double> = [1.0, BracketStepPolicy.denseBracketStepEV]
    let savedStep = defaults.double(forKey: StorageKey.exposureStepEV)
    if savedStep > 0 {
      if allowedSteps.contains(savedStep) {
        exposureStepEV = savedStep
      } else if abs(savedStep - 2.0) < 0.000_1 {
        exposureStepEV = BracketStepPolicy.denseBracketStepEV
      }
    }
    if let savedCaptureMode = defaults.string(forKey: StorageKey.photoCaptureMode),
       let captureMode = PhotoCaptureMode(rawValue: savedCaptureMode) {
      photoCaptureMode = captureMode
    }
    let savedMax = defaults.double(forKey: StorageKey.maxExposureSeconds)
    if savedMax > 0 {
      maxExposureSeconds = min(max(savedMax, 1.0), 30.0)
    }
    if defaults.object(forKey: StorageKey.exposureBiasEV) != nil {
      exposureBiasEV = defaults.double(forKey: StorageKey.exposureBiasEV)
    }
    if let savedMeteringMode = defaults.string(forKey: StorageKey.bracketMeteringMode),
       let meteringMode = BracketMeteringMode(rawValue: savedMeteringMode) {
      bracketMeteringMode = meteringMode
    }
    if defaults.object(forKey: StorageKey.captureDelaySeconds) != nil {
      let savedDelay = min(max(defaults.double(forKey: StorageKey.captureDelaySeconds), 0.0), 10.0)
      captureDelaySeconds = savedDelay < 1.0 ? 0.0 : savedDelay
    }
    if defaults.object(forKey: StorageKey.gridEnabled) != nil {
      gridEnabled = defaults.bool(forKey: StorageKey.gridEnabled)
    }
    if defaults.object(forKey: StorageKey.levelEnabled) != nil {
      levelEnabled = defaults.bool(forKey: StorageKey.levelEnabled)
    }
    if defaults.object(forKey: StorageKey.histogramEnabled) != nil {
      histogramEnabled = defaults.bool(forKey: StorageKey.histogramEnabled)
    }
    if defaults.object(forKey: StorageKey.volumeShutterEnabled) != nil {
      volumeShutterEnabled = defaults.bool(forKey: StorageKey.volumeShutterEnabled)
    }
    if defaults.object(forKey: StorageKey.volumeShutterKeepVolumeStable) != nil {
      volumeShutterKeepVolumeStable = defaults.bool(forKey: StorageKey.volumeShutterKeepVolumeStable)
    }
    if defaults.object(forKey: StorageKey.videoStabilizationEnabled) != nil {
      videoStabilizationEnabled = defaults.bool(forKey: StorageKey.videoStabilizationEnabled)
    }
    if defaults.object(forKey: StorageKey.allowCellularUpload) != nil {
      allowCellularUpload = defaults.bool(forKey: StorageKey.allowCellularUpload)
    }
    if defaults.object(forKey: StorageKey.autoUploadEnabled) != nil {
      autoUploadEnabled = defaults.bool(forKey: StorageKey.autoUploadEnabled)
    }
    if defaults.object(forKey: StorageKey.focusLockEnabled) != nil {
      focusLockEnabled = defaults.bool(forKey: StorageKey.focusLockEnabled)
    }
    if defaults.object(forKey: StorageKey.whiteBalanceLocked) != nil {
      whiteBalanceLocked = defaults.bool(forKey: StorageKey.whiteBalanceLocked)
    }
    if defaults.object(forKey: StorageKey.manualISOEnabled) != nil {
      manualISOEnabled = defaults.bool(forKey: StorageKey.manualISOEnabled)
    }
    let savedISO = defaults.double(forKey: StorageKey.manualISOValue)
    if savedISO > 0 {
      manualISOValue = min(max(savedISO, 50.0), 800.0)
    }
    let savedShutter = defaults.double(forKey: StorageKey.manualShutterSeconds)
    if savedShutter > 0 {
      manualShutterSeconds = min(max(savedShutter, 1.0 / 8000.0), 10.0)
    }
    let savedPreferredFormat = defaults.string(forKey: StorageKey.preferredPhotoFormat)
      .flatMap(PhotoFormat.init(rawValue:))
    let savedFormat = defaults.string(forKey: StorageKey.photoFormat)
      .flatMap(PhotoFormat.init(rawValue:))
    if shouldRepairTemporaryHEIFFallback(savedPreferredFormat: savedPreferredFormat, savedFormat: savedFormat) {
      preferredPhotoFormat = .proRaw
      applyProgrammaticPhotoFormatChange(.proRaw)
      defaults.set(PhotoFormat.proRaw.rawValue, forKey: StorageKey.photoFormat)
      defaults.set(true, forKey: StorageKey.repairedTemporaryHEIFFallback)
    } else if let savedPreferredFormat {
      let safePreferredFormat: PhotoFormat = savedPreferredFormat == .heif ? .jpeg : savedPreferredFormat
      preferredPhotoFormat = safePreferredFormat
      let loadedSavedFormat: PhotoFormat? = savedFormat == .heif ? .jpeg : savedFormat
      let loadedFormat = safePreferredFormat == .proRaw ? safePreferredFormat : (loadedSavedFormat ?? safePreferredFormat)
      applyProgrammaticPhotoFormatChange(loadedFormat)
    } else if let savedFormat {
      let safeFormat: PhotoFormat = savedFormat == .heif ? .jpeg : savedFormat
      preferredPhotoFormat = safeFormat
      applyProgrammaticPhotoFormatChange(safeFormat)
    }
    if let savedPosition = defaults.string(forKey: StorageKey.exposureSliderPosition),
       let position = ExposureSliderPosition(rawValue: savedPosition) {
      exposureSliderPosition = position
    }
    if let room = defaults.string(forKey: StorageKey.selectedRoomId), !room.isEmpty {
      selectedRoomId = RoomTaxonomy.normalizedRoomId(room)
    }
    if let floor = defaults.string(forKey: StorageKey.selectedFloorId), !floor.isEmpty {
      selectedFloorId = FloorTaxonomy.normalizedFloorId(floor)
    }
    let savedZoom = defaults.double(forKey: StorageKey.lastZoomPreset)
    if savedZoom > 0 {
      let allowed = [0.5, 1.0, 2.0, 5.0]
      lastZoomPreset = allowed.min(by: { abs($0 - savedZoom) < abs($1 - savedZoom) }) ?? 1.0
    }
    if let host = defaults.string(forKey: StorageKey.companionHost) {
      companionHost = host
    }
    if let port = defaults.object(forKey: StorageKey.companionPort) as? Int, (1...65535).contains(port) {
      companionPort = port
    }
    if defaults.object(forKey: StorageKey.companionUseHTTPS) != nil {
      companionUseHTTPS = defaults.bool(forKey: StorageKey.companionUseHTTPS)
    }
    if let code = defaults.string(forKey: StorageKey.companionPairingCode) {
      companionPairingCode = code
    }
  }

  func setCurrentJob(_ job: JobInfo, userScope: String?) {
    selectedJobId = job.id
    jobLabel = job.name
    jobAddress = job.propertyAddress ?? ""
    recordJobActivity(for: job, userScope: userScope)
  }

  func clearCurrentJobSelection() {
    selectedJobId = nil
    jobLabel = ""
    jobAddress = ""
  }

  func localized(_ key: String, comment: String = "") -> String {
    AppLocalizer.localized(key, language: appLanguage, comment: comment)
  }

  func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
    AppLocalizer.localizedFormat(key, language: appLanguage, arguments: arguments)
  }

  func touchCurrentJobActivity(userScope: String?) {
    guard let currentJob = currentJobInfo() else { return }
    recordJobActivity(for: currentJob, userScope: userScope)
  }

  func recentJobSnapshot(for userScope: String?, within interval: TimeInterval? = nil) -> RecentJobSnapshot? {
    let normalizedScope = normalizeRecentJobScope(userScope)
    guard !normalizedScope.isEmpty,
          normalizedScope == recentJobScope,
          let activityAt = recentJobActivityAt else {
      return nil
    }
    if let interval, Date().timeIntervalSince(activityAt) > interval {
      return nil
    }

    let resolvedJobId = recentJobId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let resolvedJobLabel = recentJobLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedJobAddress = recentJobAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !resolvedJobId.isEmpty || !resolvedJobLabel.isEmpty else { return nil }

    let job = JobInfo(
      id: resolvedJobId.isEmpty ? "recent-\(sanitizeRecentJobLabel(resolvedJobLabel))" : resolvedJobId,
      name: resolvedJobLabel.isEmpty ? "Job" : recentJobLabel,
      propertyAddress: resolvedJobAddress.isEmpty ? nil : recentJobAddress
    )
    return RecentJobSnapshot(job: job, lastActivityAt: activityAt)
  }

  func invalidateRecentJob(id: String?) {
    guard let id = id?.trimmingCharacters(in: .whitespacesAndNewlines),
          !id.isEmpty else { return }
    let storedId = recentJobId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard storedId == id else { return }
    clearRecentJobSnapshot()
  }

  func nextSeriesIndex(jobId: String?, jobLabel: String, roomId: String, floorId: String) -> Int {
    let key = seriesKey(jobId: jobId, jobLabel: jobLabel, roomId: roomId, floorId: floorId)
    let defaults = UserDefaults.standard
    let next = defaults.integer(forKey: key) + 1
    defaults.set(next, forKey: key)
    return next
  }

  func peekSeriesIndex(jobId: String?, jobLabel: String, roomId: String, floorId: String) -> Int {
    let key = seriesKey(jobId: jobId, jobLabel: jobLabel, roomId: roomId, floorId: floorId)
    let defaults = UserDefaults.standard
    let current = defaults.integer(forKey: key)
    return max(1, current + 1)
  }

  enum PhotoFormatAvailabilitySyncResult: Equatable {
    case unchanged
    case fellBackToJPEG
    case restored(PhotoFormat)
  }

  @discardableResult
  func syncPhotoFormatAvailability(isProRAWAvailable: Bool) -> PhotoFormatAvailabilitySyncResult {
    if isProRAWAvailable {
      guard preferredPhotoFormat == .proRaw, photoFormat != .proRaw else { return .unchanged }
      applyProgrammaticPhotoFormatChange(.proRaw)
      return .restored(.proRaw)
    }

    guard photoFormat == .proRaw else { return .unchanged }
    applyProgrammaticPhotoFormatChange(.jpeg)
    return .fellBackToJPEG
  }

  private func seriesKey(jobId: String?, jobLabel: String, roomId: String, floorId: String) -> String {
    let jobToken = (jobId?.isEmpty == false ? jobId! : jobLabel).replacingOccurrences(of: " ", with: "_")
    let safeFloorId = FloorTaxonomy.normalizedFloorId(floorId)
    return "\(StorageKey.seriesIndexPrefix).\(jobToken).\(roomId).\(safeFloorId)"
  }

  private func currentJobInfo() -> JobInfo? {
    let resolvedJobId = selectedJobId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let resolvedJobLabel = jobLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedJobAddress = jobAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !resolvedJobId.isEmpty || !resolvedJobLabel.isEmpty else { return nil }
    return JobInfo(
      id: resolvedJobId.isEmpty ? "current-\(sanitizeRecentJobLabel(resolvedJobLabel))" : resolvedJobId,
      name: resolvedJobLabel.isEmpty ? "Job" : jobLabel,
      propertyAddress: resolvedJobAddress.isEmpty ? nil : jobAddress
    )
  }

  private func recordJobActivity(for job: JobInfo, userScope: String?) {
    let normalizedScope = normalizeRecentJobScope(userScope)
    guard !normalizedScope.isEmpty else { return }

    let defaults = UserDefaults.standard
    let normalizedJobId = job.id.trimmingCharacters(in: .whitespacesAndNewlines)
    let now = Date()

    recentJobScope = normalizedScope
    recentJobId = normalizedJobId.isEmpty ? nil : normalizedJobId
    recentJobLabel = job.name
    recentJobAddress = job.propertyAddress ?? ""
    recentJobActivityAt = now

    defaults.set(normalizedScope, forKey: StorageKey.recentJobScope)
    if let recentJobId {
      defaults.set(recentJobId, forKey: StorageKey.recentJobId)
    } else {
      defaults.removeObject(forKey: StorageKey.recentJobId)
    }
    defaults.set(recentJobLabel, forKey: StorageKey.recentJobLabel)
    defaults.set(recentJobAddress, forKey: StorageKey.recentJobAddress)
    defaults.set(now.timeIntervalSince1970, forKey: StorageKey.recentJobActivityAt)
  }

  private func clearRecentJobSnapshot() {
    recentJobScope = nil
    recentJobId = nil
    recentJobLabel = ""
    recentJobAddress = ""
    recentJobActivityAt = nil

    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: StorageKey.recentJobScope)
    defaults.removeObject(forKey: StorageKey.recentJobId)
    defaults.removeObject(forKey: StorageKey.recentJobLabel)
    defaults.removeObject(forKey: StorageKey.recentJobAddress)
    defaults.removeObject(forKey: StorageKey.recentJobActivityAt)
  }

  private func normalizeRecentJobScope(_ value: String?) -> String {
    value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }

  private static func normalizedHistogramOverlayPosition(_ point: CGPoint) -> CGPoint {
    let fallback = defaultHistogramOverlayPosition
    let resolvedX = point.x.isFinite ? min(max(point.x, 0.12), 0.88) : fallback.x
    let resolvedY = point.y.isFinite ? min(max(point.y, 0.12), 0.88) : fallback.y
    return CGPoint(x: resolvedX, y: resolvedY)
  }

  private func sanitizeRecentJobLabel(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "job" }

    let allowed = CharacterSet.alphanumerics
    let sanitized = String(trimmed.unicodeScalars.map { scalar in
      allowed.contains(scalar) ? Character(scalar) : "-"
    })
      .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

    return sanitized.isEmpty ? "job" : sanitized.lowercased()
  }

  private func applyProgrammaticPhotoFormatChange(_ format: PhotoFormat) {
    guard photoFormat != format else { return }
    isApplyingProgrammaticPhotoFormatChange = true
    photoFormat = format
    isApplyingProgrammaticPhotoFormatChange = false
  }

  private func shouldRepairTemporaryHEIFFallback(
    savedPreferredFormat: PhotoFormat?,
    savedFormat: PhotoFormat?
  ) -> Bool {
    guard !UserDefaults.standard.bool(forKey: StorageKey.repairedTemporaryHEIFFallback) else { return false }
    return savedPreferredFormat == .heif && savedFormat == .heif
  }

  func resetExposureBiasToNeutral() {
    exposureBiasEV = 0
  }

  func cyclePrimaryBracketCount() {
    let sequence = [5, 3, 1]

    if bracketCount == 7 {
      bracketCount = 5
      return
    }

    let currentIndex = sequence.firstIndex(of: bracketCount) ?? 0
    let nextIndex = (currentIndex + 1) % sequence.count
    bracketCount = sequence[nextIndex]
  }

  enum ExposureSliderPosition: String, CaseIterable {
    case auto
    case left
    case right
    case top
    case bottom
  }

  enum GalleryOrientationMode: String, CaseIterable {
    case autoExif
    case manualFixed
  }
}

enum PhotoFormat: String, CaseIterable {
  case heif
  case jpeg
  case proRaw
}
