import Foundation
import Combine
import CoreMedia

struct UploadRecord: Identifiable, Codable {
  enum Status: String, Codable {
    case pending
    case uploading
    case uploaded
    case failed
  }

  let id: UUID
  let seriesId: UUID
  let localShootId: String
  let fileURL: URL
  let originalFileURL: URL?
  let exifLogURL: URL?
  let roomId: String
  let floorId: String
  let jobLabel: String
  let jobId: String?
  let seriesIndex: Int
  let exposureEV: Double
  let exposureSeconds: Double
  let iso: Float
  let captureMode: PhotoCaptureMode
  let captureOrientation: String?
  let sensorPitchDegrees: Double?
  let sensorRollDegrees: Double?
  let sensorHeadingDegrees: Double?
  let singleShotAssessment: SingleShotCaptureAssessment?
  let metadataReady: Bool
  let createdAt: Date
  var status: Status
  var remoteKey: String?
  var savedToPhotos: Bool
  var uploadedAt: Date?

  private enum CodingKeys: String, CodingKey {
    case id
    case seriesId
    case localShootId
    case fileURL
    case originalFileURL
    case exifLogURL
    case roomId
    case floorId
    case jobLabel
    case jobId
    case seriesIndex
    case exposureEV
    case exposureSeconds
    case iso
    case captureMode
    case captureOrientation
    case sensorPitchDegrees
    case sensorRollDegrees
    case sensorHeadingDegrees
    case singleShotAssessment
    case metadataReady
    case createdAt
    case status
    case remoteKey
    case savedToPhotos
    case uploadedAt
  }

  init(id: UUID,
       seriesId: UUID,
       localShootId: String,
       fileURL: URL,
       originalFileURL: URL?,
       exifLogURL: URL?,
       roomId: String,
       floorId: String,
       jobLabel: String,
       jobId: String?,
       seriesIndex: Int,
       exposureEV: Double,
       exposureSeconds: Double,
       iso: Float,
       captureMode: PhotoCaptureMode = .standardBracket,
       captureOrientation: String?,
       sensorPitchDegrees: Double? = nil,
       sensorRollDegrees: Double? = nil,
       sensorHeadingDegrees: Double? = nil,
       singleShotAssessment: SingleShotCaptureAssessment? = nil,
       metadataReady: Bool = true,
       createdAt: Date,
       status: Status,
       remoteKey: String?,
       savedToPhotos: Bool = false,
       uploadedAt: Date? = nil) {
    self.id = id
    self.seriesId = seriesId
    self.localShootId = localShootId
    self.fileURL = fileURL
    self.originalFileURL = originalFileURL
    self.exifLogURL = exifLogURL
    self.roomId = roomId
    self.floorId = floorId
    self.jobLabel = jobLabel
    self.jobId = jobId
    self.seriesIndex = seriesIndex
    self.exposureEV = exposureEV
    self.exposureSeconds = exposureSeconds
    self.iso = iso
    self.captureMode = captureMode
    self.captureOrientation = captureOrientation
    self.sensorPitchDegrees = sensorPitchDegrees
    self.sensorRollDegrees = sensorRollDegrees
    self.sensorHeadingDegrees = sensorHeadingDegrees
    self.singleShotAssessment = singleShotAssessment
    self.metadataReady = metadataReady
    self.createdAt = createdAt
    self.status = status
    self.remoteKey = remoteKey
    self.savedToPhotos = savedToPhotos
    self.uploadedAt = uploadedAt
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    seriesId = (try? container.decode(UUID.self, forKey: .seriesId)) ?? UUID()
    if container.contains(.localShootId) {
      localShootId = (try? container.decode(String.self, forKey: .localShootId)) ?? ""
    } else {
      localShootId = ""
    }
    fileURL = try container.decode(URL.self, forKey: .fileURL)
    originalFileURL = try? container.decode(URL.self, forKey: .originalFileURL)
    exifLogURL = try? container.decode(URL.self, forKey: .exifLogURL)
    roomId = try container.decode(String.self, forKey: .roomId)
    floorId = FloorTaxonomy.normalizedFloorId(
      (try? container.decode(String.self, forKey: .floorId)) ?? FloorTaxonomy.defaultFloorId
    )
    jobLabel = (try? container.decode(String.self, forKey: .jobLabel)) ?? ""
    jobId = try? container.decode(String.self, forKey: .jobId)
    seriesIndex = (try? container.decode(Int.self, forKey: .seriesIndex)) ?? 1
    exposureEV = try container.decode(Double.self, forKey: .exposureEV)
    exposureSeconds = try container.decode(Double.self, forKey: .exposureSeconds)
    iso = try container.decode(Float.self, forKey: .iso)
    captureMode = (try? container.decode(PhotoCaptureMode.self, forKey: .captureMode)) ?? .standardBracket
    captureOrientation = try? container.decode(String.self, forKey: .captureOrientation)
    sensorPitchDegrees = try? container.decode(Double.self, forKey: .sensorPitchDegrees)
    sensorRollDegrees = try? container.decode(Double.self, forKey: .sensorRollDegrees)
    sensorHeadingDegrees = try? container.decode(Double.self, forKey: .sensorHeadingDegrees)
    singleShotAssessment = try? container.decode(SingleShotCaptureAssessment.self, forKey: .singleShotAssessment)
    createdAt = try container.decode(Date.self, forKey: .createdAt)
    status = try container.decode(Status.self, forKey: .status)
    metadataReady = (try? container.decode(Bool.self, forKey: .metadataReady)) ?? (exifLogURL != nil || status == .uploaded)
    remoteKey = try? container.decode(String.self, forKey: .remoteKey)
    savedToPhotos = (try? container.decode(Bool.self, forKey: .savedToPhotos)) ?? false
    uploadedAt = try? container.decode(Date.self, forKey: .uploadedAt)
  }
}

struct UploadQueueNotice: Codable, Identifiable, Equatable {
  enum Kind: String, Codable {
    case success
    case warning
    case error
  }

  let id: UUID
  let message: String
  let kind: Kind
  let createdAt: Date
}

struct UploadRunSkipSummary {
  let skippedCount: Int
  let skippedStackCount: Int
  let metadataPendingCount: Int
  let metadataPendingStackCount: Int
}

private struct ManagedStackUploadSummary {
  let totalStacks: Int
  let completedStacks: Int
  let failedStacks: Int
  let pendingStacks: Int
}

@MainActor
final class UploadQueue: ObservableObject {
  private static func localized(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
  }

  private static func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: localized(key), arguments: arguments)
  }

  static let uploadedRetentionDays = 7
  private static let uploadedRetentionInterval: TimeInterval = TimeInterval(uploadedRetentionDays * 24 * 60 * 60)
  private static let diagnosticsCleanupVersion = 1
  private static let diagnosticsCleanupVersionKey = "pixcapture.uploadqueue.diagnostics-cleanup-version"
  private static let localRecoveryNoQueueNoticeNeedle = "keine Upload-Liste geladen"
  @Published private(set) var records: [UploadRecord] = []
  @Published private(set) var protocolLogs: [UploadProtocolLog] = []
  @Published private(set) var latestNotice: UploadQueueNotice?
  @Published private(set) var isUploading = false
  @Published private(set) var uploadMessage: String?
  @Published private(set) var uploadProgress: PixcaptureUploadProgress?
  @Published private(set) var uploadFileErrors: [UploadFileError] = []
  @Published private(set) var localRecoveryFileCount = 0
  @Published private(set) var latestPackageExportURL: URL?
  @Published private(set) var localPackageFileCount = 0
  @Published private(set) var localPackageTotalBytes = 0
  private let store = UploadLogStore()
  private let uploadService = PixcaptureUploadService()
  private var activeUploadTask: Task<Void, Never>?
  private var activeUploadRunId: UUID?

  init() {
    let loaded = store.load()
    let captureDirectory = try? FileStore.ensureCaptureDirectory()
    let relocated = loaded.map {
      Self.relocatePersistedContainerURLsIfNeeded($0, captureDirectory: captureDirectory)
    }
    let existing = relocated.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
    var localShootIdByAssignment: [String: String] = [:]
    records = existing.map { record in
      var normalized = record
      let resolvedLocalShootId = resolvePersistedLocalShootId(
        for: normalized,
        localShootIdByAssignment: &localShootIdByAssignment
      )
      normalized = UploadRecord(
        id: normalized.id,
        seriesId: normalized.seriesId,
        localShootId: resolvedLocalShootId,
        fileURL: normalized.fileURL,
        originalFileURL: normalized.originalFileURL,
        exifLogURL: normalized.exifLogURL,
        roomId: RoomTaxonomy.normalizedRoomId(normalized.roomId),
        floorId: FloorTaxonomy.normalizedFloorId(normalized.floorId),
        jobLabel: normalized.jobLabel,
        jobId: normalized.jobId,
        seriesIndex: normalized.seriesIndex,
        exposureEV: normalized.exposureEV,
        exposureSeconds: normalized.exposureSeconds,
        iso: normalized.iso,
        captureMode: normalized.captureMode,
        captureOrientation: normalized.captureOrientation,
        sensorPitchDegrees: normalized.sensorPitchDegrees,
        sensorRollDegrees: normalized.sensorRollDegrees,
        sensorHeadingDegrees: normalized.sensorHeadingDegrees,
        singleShotAssessment: normalized.singleShotAssessment,
        metadataReady: normalized.metadataReady,
        createdAt: normalized.createdAt,
        status: normalized.status == .uploading ? .pending : normalized.status,
        remoteKey: normalized.remoteKey,
        savedToPhotos: normalized.savedToPhotos,
        uploadedAt: normalized.uploadedAt
      )
      return normalized
    }
    if records.count != loaded.count
      || relocated.map(\.fileURL) != loaded.map(\.fileURL)
      || relocated.map(\.originalFileURL) != loaded.map(\.originalFileURL)
      || relocated.map(\.exifLogURL) != loaded.map(\.exifLogURL)
      || records.map(\.roomId) != existing.map(\.roomId)
      || records.map(\.floorId) != existing.map(\.floorId)
      || records.map(\.localShootId) != existing.map(\.localShootId)
      || records.map(\.metadataReady) != existing.map(\.metadataReady)
      || existing.contains(where: { $0.status == .uploading }) {
      persistRecords(syncUserVisibleStorage: false)
    }
    protocolLogs = store.loadProtocolLogs()
    latestNotice = store.loadLatestNotice()
    performOneTimeDiagnosticsCleanupIfNeeded()
    refreshLocalRecoveryFileCount()
    refreshLocalPackageInventory()
    if records.isEmpty && localRecoveryFileCount > 0 {
      setLatestNotice(
        message: Self.localizedFormat("upload.queue.localFilesWithoutQueue.format", localRecoveryFileCount),
        kind: .warning
      )
    }
    FileStore.scheduleUserVisibleJobSync(for: records)
  }

  private static func relocatePersistedContainerURLsIfNeeded(
    _ record: UploadRecord,
    captureDirectory: URL?
  ) -> UploadRecord {
    let fileURL = relocatedCaptureURL(record.fileURL, captureDirectory: captureDirectory) ?? record.fileURL
    let originalFileURL = relocatedCaptureURL(record.originalFileURL, captureDirectory: captureDirectory)
    let exifLogURL = relocatedCaptureURL(record.exifLogURL, captureDirectory: captureDirectory)

    guard fileURL != record.fileURL
      || originalFileURL != record.originalFileURL
      || exifLogURL != record.exifLogURL else {
      return record
    }

    return UploadRecord(
      id: record.id,
      seriesId: record.seriesId,
      localShootId: record.localShootId,
      fileURL: fileURL,
      originalFileURL: originalFileURL,
      exifLogURL: exifLogURL,
      roomId: record.roomId,
      floorId: record.floorId,
      jobLabel: record.jobLabel,
      jobId: record.jobId,
      seriesIndex: record.seriesIndex,
      exposureEV: record.exposureEV,
      exposureSeconds: record.exposureSeconds,
      iso: record.iso,
      captureMode: record.captureMode,
      captureOrientation: record.captureOrientation,
      sensorPitchDegrees: record.sensorPitchDegrees,
      sensorRollDegrees: record.sensorRollDegrees,
      sensorHeadingDegrees: record.sensorHeadingDegrees,
      singleShotAssessment: record.singleShotAssessment,
      metadataReady: record.metadataReady,
      createdAt: record.createdAt,
      status: record.status,
      remoteKey: record.remoteKey,
      savedToPhotos: record.savedToPhotos,
      uploadedAt: record.uploadedAt
    )
  }

  private static func relocatedCaptureURL(_ url: URL?, captureDirectory: URL?) -> URL? {
    guard let url else { return nil }
    if FileManager.default.fileExists(atPath: url.path) {
      return url
    }
    guard let captureDirectory else { return url }
    let filename = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !filename.isEmpty else { return url }
    let candidate = captureDirectory.appendingPathComponent(filename)
    return FileManager.default.fileExists(atPath: candidate.path) ? candidate : url
  }

  func enqueue(
    _ summary: CaptureSeriesSummary,
    roomId: String,
    floorId: String,
    jobLabel: String,
    jobId: String?,
    seriesIndex: Int
  ) {
    upsert(
      summary,
      roomId: roomId,
      floorId: floorId,
      jobLabel: jobLabel,
      jobId: jobId,
      seriesIndex: seriesIndex
    )
  }

  func upsert(
    _ summary: CaptureSeriesSummary,
    roomId: String,
    floorId: String,
    jobLabel: String,
    jobId: String?,
    seriesIndex: Int
  ) {
    let normalizedJobLabel = jobLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedJobLabel = normalizedJobLabel.isEmpty ? "Ohne Job" : normalizedJobLabel
    let normalizedRoomId = RoomTaxonomy.normalizedRoomId(roomId)
    let normalizedFloorId = FloorTaxonomy.normalizedFloorId(floorId)
    let existingSeriesRecords = records.filter { $0.seriesId == summary.seriesId }
    let resolvedStoredJobLabel = existingSeriesRecords.first?.jobLabel ?? resolvedJobLabel
    let resolvedStoredJobId = existingSeriesRecords.first?.jobId ?? jobId
    let resolvedSeriesIndex = existingSeriesRecords.first?.seriesIndex ?? seriesIndex
    let localShootId = existingSeriesRecords.first?.localShootId ?? resolveLocalShootIdForAssignment(
      jobLabel: resolvedJobLabel,
      jobId: jobId
    )
    let metadataReady = summary.metadataReady

    for index in records.indices where records[index].seriesId == summary.seriesId {
      let current = records[index]
      records[index] = UploadRecord(
        id: current.id,
        seriesId: current.seriesId,
        localShootId: current.localShootId,
        fileURL: current.fileURL,
        originalFileURL: current.originalFileURL,
        exifLogURL: summary.exifLogURL ?? current.exifLogURL,
        roomId: normalizedRoomId,
        floorId: normalizedFloorId,
        jobLabel: current.jobLabel,
        jobId: current.jobId,
        seriesIndex: current.seriesIndex,
        exposureEV: current.exposureEV,
        exposureSeconds: current.exposureSeconds,
        iso: current.iso,
        captureMode: current.captureMode,
        captureOrientation: current.captureOrientation,
        sensorPitchDegrees: current.sensorPitchDegrees,
        sensorRollDegrees: current.sensorRollDegrees,
        sensorHeadingDegrees: current.sensorHeadingDegrees,
        singleShotAssessment: current.singleShotAssessment,
        metadataReady: current.metadataReady || metadataReady,
        createdAt: current.createdAt,
        status: current.status,
        remoteKey: current.remoteKey,
        savedToPhotos: current.savedToPhotos,
        uploadedAt: current.uploadedAt
      )
    }

    let existingPaths = Set(existingSeriesRecords.map { $0.fileURL.standardizedFileURL.path })
    let newRecords = summary.photos
      .filter { !existingPaths.contains($0.fileURL.standardizedFileURL.path) }
      .map {
        UploadRecord(
          id: UUID(),
          seriesId: summary.seriesId,
          localShootId: localShootId,
          fileURL: $0.fileURL,
          originalFileURL: $0.originalFileURL,
          exifLogURL: summary.exifLogURL,
          roomId: normalizedRoomId,
          floorId: normalizedFloorId,
          jobLabel: resolvedStoredJobLabel,
          jobId: resolvedStoredJobId,
          seriesIndex: resolvedSeriesIndex,
          exposureEV: $0.exposureEV,
          exposureSeconds: $0.exposureDuration.seconds,
          iso: $0.iso,
          captureMode: summary.captureMode,
          captureOrientation: $0.captureOrientation,
          sensorPitchDegrees: $0.sensorPitchDegrees,
          sensorRollDegrees: $0.sensorRollDegrees,
          sensorHeadingDegrees: $0.sensorHeadingDegrees,
          singleShotAssessment: $0.singleShotAssessment ?? summary.singleShotAssessment,
          metadataReady: metadataReady,
          createdAt: Date(),
          status: .pending,
          remoteKey: nil,
          uploadedAt: nil
        )
      }

    records.append(contentsOf: newRecords)
    persistRecords()
  }

  func markUploaded(_ recordId: UUID, remoteKey: String?) {
    guard let index = records.firstIndex(where: { $0.id == recordId }) else { return }
    records[index].status = .uploaded
    records[index].remoteKey = remoteKey
    records[index].uploadedAt = Date()
    persistRecords()
  }

  func markUploading(_ recordId: UUID) {
    guard let index = records.firstIndex(where: { $0.id == recordId }) else { return }
    records[index].status = .uploading
    persistRecords(syncUserVisibleStorage: false)
  }

  func markPending(_ recordIds: [UUID]) {
    guard !recordIds.isEmpty else { return }
    let idSet = Set(recordIds)
    var updated = false
    for index in records.indices where idSet.contains(records[index].id) {
      guard records[index].status != .pending else { continue }
      records[index].status = .pending
      updated = true
    }
    if updated {
      persistRecords()
    }
  }

  func markFailed(_ recordId: UUID) {
    guard let index = records.firstIndex(where: { $0.id == recordId }) else { return }
    records[index].status = .failed
    persistRecords()
  }

  func setUploadMessage(_ message: String) {
    uploadMessage = message
  }

  func clearTransientUploadFeedback() {
    guard !isUploading else { return }
    uploadFileErrors.removeAll()
    uploadProgress = nil
    uploadMessage = nil
  }

  func startManagedUpload(
    records pending: [UploadRecord],
    token: String,
    userId: String,
    connection: PixcaptureUploadConnection,
    identityHintsByJobId: [String: PixcaptureUploadIdentityHint],
    allowsCellularAccess: Bool,
    skipSummary: UploadRunSkipSummary,
    initialDetail: String
  ) {
    guard !isUploading else { return }
    guard !pending.isEmpty else {
      uploadMessage = Self.localized("upload.queue.noEligibleFiles")
      UploadDebugLog.write("[PIXUPLOAD] managedUpload rejected: no pending files")
      return
    }
    let runId = UUID()
    UploadDebugLog.write("[PIXUPLOAD] managedUpload start run=\(runId.uuidString) mode=\(connection.mode.rawValue) pending=\(pending.count) initial=\(initialDetail)")

    uploadFileErrors = []
    uploadProgress = PixcaptureUploadProgress(
      mode: connection.mode,
      phase: .connecting,
      filesDone: 0,
      filesTotal: pending.count,
      bytesSent: 0,
      bytesTotal: 0,
      detail: initialDetail,
      currentFileName: nil
    )

    isUploading = true
    activeUploadRunId = runId
    let pendingStackCount = stackCount(for: pending)
    var startMessage = Self.localizedFormat(
      "upload.queue.running.format",
      connection.mode.displayName,
      pendingStackCount
    )
    if skipSummary.skippedCount > 0 {
      startMessage += " " + Self.localizedFormat(
        "upload.queue.skippedNoJob.format",
        skipSummary.skippedStackCount
      )
    }
    if skipSummary.metadataPendingCount > 0 {
      startMessage += " " + Self.localizedFormat(
        "upload.queue.waitingMetadata.format",
        skipSummary.metadataPendingStackCount
      )
    }
    uploadMessage = startMessage

    activeUploadTask = Task { [weak self] in
      guard let self else { return }
      do {
        let result = try await uploadService.uploadPending(
          records: pending,
          token: token,
          userId: userId,
          connection: connection,
          progress: { snapshot in
            Task { @MainActor [weak self] in
              UploadDebugLog.write("[PIXUPLOAD] progress mode=\(snapshot.mode.rawValue) phase=\(snapshot.phase.rawValue) files=\(snapshot.filesDone)/\(snapshot.filesTotal) bytes=\(snapshot.bytesSent)/\(snapshot.bytesTotal) detail=\(snapshot.detail ?? "-")")
              self?.uploadProgress = snapshot
            }
          },
          identityHintsByJobId: identityHintsByJobId,
          allowsCellularAccess: allowsCellularAccess
        )
        guard activeUploadRunId == runId else { return }
        UploadDebugLog.write("[PIXUPLOAD] managedUpload success run=\(runId.uuidString) uploaded=\(result.uploadedRecordIds.count) failed=\(result.failedRecordIds.count) bytes=\(result.bytesSent)/\(result.bytesTotal)")
        finishManagedUpload(
          result: result,
          pending: pending,
          connection: connection,
          skipSummary: skipSummary
        )
      } catch {
        guard activeUploadRunId == runId else { return }
        UploadDebugLog.write("[PIXUPLOAD] managedUpload failure run=\(runId.uuidString) error=\(error.localizedDescription)")
        markPending(pending.map(\.id))
        let failureMessage = error.localizedDescription
        let previous = uploadProgress
        uploadProgress = PixcaptureUploadProgress(
          mode: connection.mode,
          phase: .failed,
          filesDone: previous?.filesDone ?? 0,
          filesTotal: previous?.filesTotal ?? pending.count,
          bytesSent: previous?.bytesSent ?? 0,
          bytesTotal: previous?.bytesTotal ?? 0,
          detail: failureMessage,
          currentFileName: previous?.currentFileName
        )
        uploadMessage = failureMessage
        setLatestNotice(message: failureMessage, kind: .error)
      }
      guard activeUploadRunId == runId else { return }
      isUploading = false
      activeUploadTask = nil
      activeUploadRunId = nil
    }
  }

  func cancelActiveUpload(message: String? = nil) {
    guard isUploading else { return }
    let resolvedMessage = message ?? Self.localized("upload.queue.paused")
    activeUploadTask?.cancel()
    activeUploadTask = nil
    activeUploadRunId = nil
    isUploading = false
    uploadMessage = resolvedMessage
    uploadProgress = PixcaptureUploadProgress(
      mode: uploadProgress?.mode ?? .directR2,
      phase: .failed,
      filesDone: uploadProgress?.filesDone ?? 0,
      filesTotal: uploadProgress?.filesTotal ?? records.filter { $0.status == .pending || $0.status == .failed }.count,
      bytesSent: uploadProgress?.bytesSent ?? 0,
      bytesTotal: uploadProgress?.bytesTotal ?? 0,
      detail: resolvedMessage,
      currentFileName: nil
    )
    markPending(records.filter { $0.status == .uploading }.map(\.id))
    setLatestNotice(message: resolvedMessage, kind: .warning)
  }

  private func finishManagedUpload(
    result: PixcaptureUploadResult,
    pending: [UploadRecord],
    connection: PixcaptureUploadConnection,
    skipSummary: UploadRunSkipSummary
  ) {
    let localPackageOnly: Bool
    switch connection {
    case .browserCompanion, .cablePackage:
      localPackageOnly = true
    case .webConnect, .localWiFi, .directR2, .companionWiFi:
      localPackageOnly = false
    }

    latestPackageExportURL = result.localPackageURL
    refreshLocalPackageInventory()

    if localPackageOnly {
      markPending(result.uploadedRecordIds)
    } else {
      for id in result.uploadedRecordIds {
        markUploaded(id, remoteKey: nil)
      }
    }
    for id in result.failedRecordIds {
      markFailed(id)
    }
    let resolvedRecordIds = Set(result.uploadedRecordIds).union(result.failedRecordIds)
    let retryableRecordIds = pending
      .map(\.id)
      .filter { !resolvedRecordIds.contains($0) }
    markPending(retryableRecordIds)
    appendProtocolLogs(result.protocolLogs)
    uploadFileErrors = result.fileErrors

    let modeLabel = result.mode?.displayName ?? connection.mode.displayName
    let stackSummary = summarizeStackUpload(
      pendingRecords: pending,
      uploadedRecordIds: result.uploadedRecordIds,
      failedRecordIds: result.failedRecordIds,
      pendingRecordIds: retryableRecordIds
    )
    let hasFailures = !result.failedRecordIds.isEmpty
      || !result.fileErrors.isEmpty
      || result.verificationFailed
    let noticeKind: UploadQueueNotice.Kind =
      !hasFailures
      ? (localPackageOnly ? .warning : .success)
      : (result.uploadedRecordIds.isEmpty ? .error : .warning)
    var message: String
    if case .cablePackage = connection,
       result.failedRecordIds.isEmpty,
       result.fileErrors.isEmpty,
       !result.verificationFailed {
      message = Self.localized("upload.queue.cableReady")
    } else if case .browserCompanion = connection,
              result.failedRecordIds.isEmpty,
              result.fileErrors.isEmpty,
              !result.verificationFailed {
      message = Self.localized("upload.queue.browserReady")
    } else if noticeKind == .success {
      message = Self.localizedFormat("upload.queue.completed.format", stackSummary.completedStacks)
    } else if noticeKind == .error,
              result.uploadedRecordIds.isEmpty,
              result.failedRecordIds.isEmpty,
              !result.fileErrors.isEmpty,
              !retryableRecordIds.isEmpty {
      let reason = result.fileErrors.first?.message ?? Self.localized("upload.queue.connectionFailed")
      message = Self.localizedFormat(
        "upload.queue.notTransferred.format",
        modeLabel,
        reason,
        stackSummary.totalStacks
      )
    } else {
      let resultLabel = noticeKind == .error
        ? Self.localized("upload.queue.failed")
        : Self.localized("upload.queue.partiallyCompleted")
      message = Self.localizedFormat(
        "upload.queue.summary.format",
        resultLabel,
        modeLabel,
        stackSummary.completedStacks,
        stackSummary.totalStacks,
        stackSummary.failedStacks
      )
      if stackSummary.pendingStacks > 0 {
        message += " " + Self.localizedFormat("upload.queue.retryWaiting.format", stackSummary.pendingStacks)
      }
      if !retryableRecordIds.isEmpty {
        message += " " + Self.localized("upload.queue.retryableRemain")
      }
      if result.verificationFailed {
        let verificationIssues = result.protocolLogs
          .flatMap(\.mismatches)
          .filter(Self.isCriticalMetadataMismatch)
          .count
        message += " " + Self.localizedFormat("upload.queue.metadataVerificationFailed.format", verificationIssues)
      } else if let latestLog = result.protocolLogs.first,
                latestLog.receiptPath != nil {
        message += " " + Self.localized("upload.queue.serverReceiptAvailable")
      }
      if skipSummary.skippedCount > 0 {
        message += " " + Self.localizedFormat(
          "upload.queue.skippedNoJob.format",
          skipSummary.skippedStackCount
        )
      }
      if skipSummary.metadataPendingCount > 0 {
        message += " " + Self.localizedFormat(
          "upload.queue.stillWaitingMetadata.format",
          skipSummary.metadataPendingStackCount
        )
      }
    }
    setLatestNotice(message: message, kind: noticeKind)
    let didCompleteSuccessfully = result.failedRecordIds.isEmpty
      && result.fileErrors.isEmpty
      && !result.verificationFailed
    if didCompleteSuccessfully {
      uploadProgress = nil
      uploadMessage = nil
    } else {
      uploadProgress = PixcaptureUploadProgress(
        mode: result.mode ?? connection.mode,
        phase: .failed,
        filesDone: result.filesDone,
        filesTotal: result.filesTotal,
        bytesSent: result.bytesSent,
        bytesTotal: result.bytesTotal,
        detail: message,
        currentFileName: nil
      )
      uploadMessage = message
    }
  }

  private func stackCount(for records: [UploadRecord]) -> Int {
    Set(records.map(\.seriesId)).count
  }

  private func summarizeStackUpload(
    pendingRecords: [UploadRecord],
    uploadedRecordIds: [UUID],
    failedRecordIds: [UUID],
    pendingRecordIds: [UUID]
  ) -> ManagedStackUploadSummary {
    let totalBySeries = Dictionary(grouping: pendingRecords, by: \.seriesId)
      .mapValues { $0.count }
    let seriesByRecordId = Dictionary(
      uniqueKeysWithValues: pendingRecords.map { ($0.id, $0.seriesId) }
    )

    var uploadedBySeries: [UUID: Int] = [:]
    for recordId in uploadedRecordIds {
      guard let seriesId = seriesByRecordId[recordId] else { continue }
      uploadedBySeries[seriesId, default: 0] += 1
    }

    var failedBySeries: [UUID: Int] = [:]
    for recordId in failedRecordIds {
      guard let seriesId = seriesByRecordId[recordId] else { continue }
      failedBySeries[seriesId, default: 0] += 1
    }

    var pendingBySeries: [UUID: Int] = [:]
    for recordId in pendingRecordIds {
      guard let seriesId = seriesByRecordId[recordId] else { continue }
      pendingBySeries[seriesId, default: 0] += 1
    }

    var completedStacks = 0
    var failedStacks = 0
    var pendingStacks = 0

    for (seriesId, totalFiles) in totalBySeries {
      let failedFiles = failedBySeries[seriesId, default: 0]
      let uploadedFiles = uploadedBySeries[seriesId, default: 0]
      let pendingFiles = pendingBySeries[seriesId, default: 0]
      if failedFiles > 0 {
        failedStacks += 1
      } else if uploadedFiles >= totalFiles {
        completedStacks += 1
      } else if pendingFiles > 0 {
        pendingStacks += 1
      }
    }

    return ManagedStackUploadSummary(
      totalStacks: totalBySeries.count,
      completedStacks: completedStacks,
      failedStacks: failedStacks,
      pendingStacks: pendingStacks
    )
  }

  private static func isCriticalMetadataMismatch(_ mismatch: UploadProtocolMismatch) -> Bool {
    mismatch.isCriticalForUploadCompletion
  }

  func resetFailed() {
    for index in records.indices where records[index].status == .failed {
      records[index].status = .pending
    }
    persistRecords()
  }

  @discardableResult
  func resetLocalRecordsForRecovery() -> Int {
    guard !isUploading else { return 0 }

    var updatedCount = 0
    for index in records.indices {
      guard FileManager.default.fileExists(atPath: records[index].fileURL.path) else { continue }
      guard records[index].status != .pending || records[index].remoteKey != nil || records[index].uploadedAt != nil else {
        continue
      }
      records[index].status = .pending
      records[index].remoteKey = nil
      records[index].uploadedAt = nil
      updatedCount += 1
    }

    if updatedCount > 0 {
      persistRecords()
      setLatestNotice(
        message: Self.localizedFormat("upload.queue.localFilesReset.format", updatedCount),
        kind: .warning
      )
    }
    return updatedCount
  }

  func deleteRecord(_ recordId: UUID, deleteFile: Bool) {
    guard !isUploading else { return }
    guard let index = records.firstIndex(where: { $0.id == recordId }) else { return }
    let record = records[index]
    records.remove(at: index)
    persistRecords()
    if deleteFile {
      FileStore.deleteCaptureFiles(for: [record], keeping: records)
    }
    refreshLocalRecoveryFileCount()
  }

  func markSavedToPhotos(_ recordIds: [UUID]) {
    guard !recordIds.isEmpty else { return }
    var updated = false
    for index in records.indices {
      if recordIds.contains(records[index].id) {
        records[index].savedToPhotos = true
        updated = true
      }
    }
    if updated {
      persistRecords(syncUserVisibleStorage: false)
    }
  }

  func assignJob(forSeriesIds seriesIds: Set<UUID>, jobLabel: String, jobId: String?) {
    guard !seriesIds.isEmpty else { return }
    let normalizedJobLabel = jobLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedJobLabel = normalizedJobLabel.isEmpty ? "Ohne Job" : normalizedJobLabel
    let localShootId = resolveLocalShootIdForAssignment(
      jobLabel: resolvedJobLabel,
      jobId: jobId,
      excludingSeriesIds: seriesIds
    )
    var updated = false
    for index in records.indices {
      if seriesIds.contains(records[index].seriesId) {
        let current = records[index]
        records[index] = UploadRecord(
          id: current.id,
          seriesId: current.seriesId,
          localShootId: localShootId,
          fileURL: current.fileURL,
          originalFileURL: current.originalFileURL,
          exifLogURL: current.exifLogURL,
          roomId: current.roomId,
          floorId: current.floorId,
          jobLabel: resolvedJobLabel,
          jobId: jobId,
          seriesIndex: current.seriesIndex,
          exposureEV: current.exposureEV,
          exposureSeconds: current.exposureSeconds,
          iso: current.iso,
          captureMode: current.captureMode,
          captureOrientation: current.captureOrientation,
          sensorPitchDegrees: current.sensorPitchDegrees,
          sensorRollDegrees: current.sensorRollDegrees,
          sensorHeadingDegrees: current.sensorHeadingDegrees,
          singleShotAssessment: current.singleShotAssessment,
          metadataReady: current.metadataReady,
          createdAt: current.createdAt,
          status: current.status,
          remoteKey: current.remoteKey,
          savedToPhotos: current.savedToPhotos,
          uploadedAt: current.uploadedAt
        )
        updated = true
      }
    }
    if updated {
      persistRecords()
    }
  }

  func assignRoomFloor(forSeriesIds seriesIds: Set<UUID>, roomId: String, floorId: String) {
    guard !seriesIds.isEmpty else { return }
    let normalizedRoomId = RoomTaxonomy.normalizedRoomId(roomId)
    let normalizedFloorId = FloorTaxonomy.normalizedFloorId(floorId)
    var updated = false

    for index in records.indices where seriesIds.contains(records[index].seriesId) {
      let current = records[index]
      guard current.roomId != normalizedRoomId || current.floorId != normalizedFloorId else {
        continue
      }
      records[index] = UploadRecord(
        id: current.id,
        seriesId: current.seriesId,
        localShootId: current.localShootId,
        fileURL: current.fileURL,
        originalFileURL: current.originalFileURL,
        exifLogURL: current.exifLogURL,
        roomId: normalizedRoomId,
        floorId: normalizedFloorId,
        jobLabel: current.jobLabel,
        jobId: current.jobId,
        seriesIndex: current.seriesIndex,
        exposureEV: current.exposureEV,
        exposureSeconds: current.exposureSeconds,
        iso: current.iso,
        captureMode: current.captureMode,
        captureOrientation: current.captureOrientation,
        sensorPitchDegrees: current.sensorPitchDegrees,
        sensorRollDegrees: current.sensorRollDegrees,
        sensorHeadingDegrees: current.sensorHeadingDegrees,
        singleShotAssessment: current.singleShotAssessment,
        metadataReady: current.metadataReady,
        createdAt: current.createdAt,
        status: current.status,
        remoteKey: current.remoteKey,
        savedToPhotos: current.savedToPhotos,
        uploadedAt: current.uploadedAt
      )
      updated = true
    }

    if updated {
      persistRecords()
    }
  }

  private func persistRecords(syncUserVisibleStorage: Bool = true) {
    store.save(records)
    refreshLocalRecoveryFileCount()
    if syncUserVisibleStorage {
      FileStore.scheduleUserVisibleJobSync(for: records)
    }
  }

  private func resolvePersistedLocalShootId(
    for record: UploadRecord,
    localShootIdByAssignment: inout [String: String]
  ) -> String {
    let currentLocalShootId = record.localShootId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let assignmentKey = assignmentKey(jobLabel: record.jobLabel, jobId: record.jobId)

    if !currentLocalShootId.isEmpty {
      if let assignmentKey, localShootIdByAssignment[assignmentKey] == nil {
        localShootIdByAssignment[assignmentKey] = currentLocalShootId
      }
      return currentLocalShootId
    }

    if let assignmentKey,
       let existingLocalShootId = localShootIdByAssignment[assignmentKey] {
      return existingLocalShootId
    }

    let generated = UUID().uuidString.lowercased()
    if let assignmentKey {
      localShootIdByAssignment[assignmentKey] = generated
    }
    return generated
  }

  private func resolveLocalShootIdForAssignment(
    jobLabel: String,
    jobId: String?,
    excludingSeriesIds: Set<UUID> = []
  ) -> String {
    guard let targetAssignmentKey = assignmentKey(jobLabel: jobLabel, jobId: jobId) else {
      return UUID().uuidString.lowercased()
    }

    if let existing = records.first(where: { record in
      !excludingSeriesIds.contains(record.seriesId)
        && activeForShootReuse(record.status)
        && assignmentKey(jobLabel: record.jobLabel, jobId: record.jobId) == targetAssignmentKey
        && !record.localShootId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }) {
      return existing.localShootId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // Keep one shoot ID across a multi-select reassignment when no target shoot exists yet.
    if let selected = records.first(where: { record in
      excludingSeriesIds.contains(record.seriesId)
        && !record.localShootId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }) {
      return selected.localShootId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    return UUID().uuidString.lowercased()
  }

  private func activeForShootReuse(_ status: UploadRecord.Status) -> Bool {
    status == .pending || status == .uploading || status == .failed
  }

  private func assignmentKey(jobLabel: String, jobId: String?) -> String? {
    let normalizedJobId = jobId?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let normalizedJobId, !normalizedJobId.isEmpty {
      return "id:\(normalizedJobId.lowercased())"
    }

    let normalizedLabel = jobLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedLabel.isEmpty else {
      return nil
    }
    if normalizedLabel.compare("Ohne Job", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
      return nil
    }
    return "label:\(normalizedLabel.lowercased())"
  }

  func appendProtocolLogs(_ logs: [UploadProtocolLog]) {
    guard !logs.isEmpty else { return }
    protocolLogs.insert(contentsOf: logs, at: 0)
    if protocolLogs.count > 50 {
      protocolLogs = Array(protocolLogs.prefix(50))
    }
    store.saveProtocolLogs(protocolLogs)
  }

  func setLatestNotice(message: String, kind: UploadQueueNotice.Kind) {
    let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    let notice = UploadQueueNotice(
      id: UUID(),
      message: trimmed,
      kind: kind,
      createdAt: Date()
    )
    latestNotice = notice
    store.saveLatestNotice(notice)
  }

  func refreshLocalRecoveryFileCount() {
    localRecoveryFileCount = FileStore.recoveryCandidateFileCount()
    if localRecoveryFileCount == 0,
       latestNotice?.message.contains(Self.localRecoveryNoQueueNoticeNeedle) == true {
      latestNotice = nil
      store.saveLatestNotice(nil)
      return
    }
    clearStaleLocalRecoveryNoticeIfNeeded()
  }

  func refreshLocalPackageInventory() {
    let inventory = PixcaptureUploadService.exportedPackageInventory()
    localPackageFileCount = inventory.fileCount
    localPackageTotalBytes = inventory.totalBytes
    if inventory.fileCount == 0 {
      latestPackageExportURL = nil
    } else if latestPackageExportURL == nil
              || !FileManager.default.fileExists(atPath: latestPackageExportURL?.path ?? "") {
      latestPackageExportURL = inventory.newestPackageURL
    }
  }

  func deleteLocalPackageExports() {
    do {
      try PixcaptureUploadService.deleteExportedPackages()
      latestPackageExportURL = nil
      refreshLocalPackageInventory()
      setLatestNotice(
        message: Self.localized("upload.queue.localIntakeDeleted"),
        kind: .success
      )
    } catch {
      setLatestNotice(
        message: Self.localizedFormat("upload.queue.localIntakeDeleteFailed.format", error.localizedDescription),
        kind: .error
      )
    }
  }

  func localStorageDiagnostics() -> LocalCaptureStorageDiagnostics {
    FileStore.localCaptureStorageDiagnostics(records: records)
  }

  func supportDiagnosticsText(
    accountLabel: String,
    selectedJobLabel: String,
    selectedJobId: String?
  ) -> String {
    let diagnostics = localStorageDiagnostics()
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    let cleanSelectedJobId = selectedJobId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let latestUpload = records.compactMap(\.uploadedAt).max()
    let latestCapture = records.map(\.createdAt).max()
    let jobNames = Set(records.map { record in
      let id = record.jobId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if !id.isEmpty { return id }
      let label = record.jobLabel.trimmingCharacters(in: .whitespacesAndNewlines)
      return label.isEmpty ? CaptureJobPolicy.unassignedJobLabel : label
    }).sorted()

    var lines: [String] = []
    lines.append("PixCapture Support-Diagnose")
    lines.append("Generated: \(ISO8601DateFormatter().string(from: Date()))")
    lines.append("Account: \(accountLabel)")
    lines.append("Selected Job: \(selectedJobLabel.isEmpty ? "-" : selectedJobLabel)")
    lines.append("Selected Job ID: \(cleanSelectedJobId.isEmpty ? "-" : cleanSelectedJobId)")
    lines.append("Queue Records: \(diagnostics.queueRecordCount)")
    lines.append("Series: \(diagnostics.seriesCount)")
    lines.append("Status: pending \(diagnostics.pendingRecords), uploading \(diagnostics.uploadingRecords), uploaded \(diagnostics.uploadedRecords), failed \(diagnostics.failedRecords)")
    lines.append("Local Files: \(diagnostics.localFileCount)")
    lines.append("Local Size: \(formatter.string(fromByteCount: diagnostics.localBytes))")
    lines.append("Queue-Matched Files: \(diagnostics.queueMatchedFiles)")
    lines.append("Orphan Files: \(diagnostics.orphanFiles)")
    lines.append("Orphan Size: \(formatter.string(fromByteCount: diagnostics.orphanBytes))")
    lines.append("Known Jobs: \(jobNames.isEmpty ? "-" : jobNames.joined(separator: ", "))")
    lines.append("Latest Capture: \(latestCapture.map { ISO8601DateFormatter().string(from: $0) } ?? "-")")
    lines.append("Latest Confirmed Upload: \(latestUpload.map { ISO8601DateFormatter().string(from: $0) } ?? "-")")
    if let latestNotice {
      lines.append("Latest Notice: [\(latestNotice.kind.rawValue)] \(latestNotice.message)")
    } else {
      lines.append("Latest Notice: -")
    }
    lines.append("")
    lines.append("Lokale Dateien werden erst geloescht, wenn der Nutzer das explizit bestaetigt. Der Sammelcontainer bleibt als Fallback erhalten, falls sonst Daten verloren gehen koennten.")
    return lines.joined(separator: "\n")
  }

  private func clearStaleLocalRecoveryNoticeIfNeeded() {
    guard !records.isEmpty else { return }
    guard latestNotice?.message.contains(Self.localRecoveryNoQueueNoticeNeedle) == true else { return }
    latestNotice = nil
    store.saveLatestNotice(nil)
  }

  func clearLatestNotice() {
    latestNotice = nil
    store.saveLatestNotice(nil)
  }

  func clearProtocolLogs() {
    guard !isUploading else { return }
    protocolLogs.removeAll()
    store.saveProtocolLogs(protocolLogs)
  }

  func clearFailedRecords(deleteFiles: Bool = false) {
    guard !isUploading else { return }
    guard deleteFiles else {
      resetFailed()
      return
    }
    clearRecords(where: { $0.status == .failed }, deleteFiles: deleteFiles)
  }

  func clearAllRecords(deleteFiles: Bool = false) {
    guard !isUploading else { return }
    guard deleteFiles else { return }
    clearRecords(where: { _ in true }, deleteFiles: deleteFiles)
  }

  @discardableResult
  func deleteOrphanedLocalCaptureFiles() -> LocalCaptureCleanupSummary? {
    guard !isUploading else { return nil }
    do {
      let summary = try FileStore.deleteOrphanedLocalCaptureFiles(records: records)
      refreshLocalRecoveryFileCount()
      let deletedSize = ByteCountFormatter.string(fromByteCount: summary.deletedBytes, countStyle: .file)
      let message = summary.failedFiles > 0
        ? Self.localizedFormat(
          "upload.queue.orphansDeletedPartial.format",
          summary.deletedFiles,
          deletedSize,
          summary.failedFiles
        )
        : Self.localizedFormat("upload.queue.orphansDeleted.format", summary.deletedFiles, deletedSize)
      setLatestNotice(message: message, kind: summary.failedFiles > 0 ? .warning : .success)
      return summary
    } catch {
      setLatestNotice(message: error.localizedDescription, kind: .error)
      return nil
    }
  }

  @discardableResult
  func recoverLocalCaptureRecords(jobLabel: String, jobId: String?) -> LocalCaptureRecordRecoverySummary? {
    guard !isUploading else { return nil }
    do {
      let summary = try FileStore.recoverUploadRecordsFromLocalCaptureFiles(
        existingRecords: records,
        jobLabel: jobLabel,
        jobId: jobId
      )

      guard !summary.records.isEmpty else {
        refreshLocalRecoveryFileCount()
        setLatestNotice(
          message: Self.localized("upload.queue.noRecoverableCaptures"),
          kind: .warning
        )
        return summary
      }

      records.append(contentsOf: summary.records)
      persistRecords()
      let message = Self.localizedFormat(
        "upload.queue.recovered.format",
        summary.restoredSeries,
        summary.restoredRecords
      )
      setLatestNotice(message: message, kind: .success)
      return summary
    } catch {
      setLatestNotice(message: error.localizedDescription, kind: .error)
      return nil
    }
  }

  func uploadedRecordsEligibleForDeletion(asOf now: Date = Date()) -> [UploadRecord] {
    records.filter { record in
      guard record.status == .uploaded else { return false }
      let referenceDate = record.uploadedAt ?? record.createdAt
      return now.timeIntervalSince(referenceDate) >= Self.uploadedRetentionInterval
    }
  }

  func deleteRecords(_ recordIds: [UUID], deleteFile: Bool) {
    guard !isUploading else { return }
    guard !recordIds.isEmpty else { return }
    let ids = Set(recordIds)
    let removedRecords = records.filter { ids.contains($0.id) }
    guard !removedRecords.isEmpty else { return }
    records.removeAll { ids.contains($0.id) }
    persistRecords()
    if deleteFile {
      FileStore.deleteCaptureFiles(for: removedRecords, keeping: records)
    }
    refreshLocalRecoveryFileCount()
  }

  private func clearRecords(where shouldRemove: (UploadRecord) -> Bool, deleteFiles: Bool) {
    let removedRecords = records.filter(shouldRemove)
    guard !removedRecords.isEmpty else { return }
    records.removeAll(where: shouldRemove)
    persistRecords()

    if deleteFiles {
      FileStore.deleteCaptureFiles(for: removedRecords, keeping: records)
    }
    refreshLocalRecoveryFileCount()
  }

  private func performOneTimeDiagnosticsCleanupIfNeeded() {
    let defaults = UserDefaults.standard
    let appliedVersion = defaults.integer(forKey: Self.diagnosticsCleanupVersionKey)
    guard appliedVersion < Self.diagnosticsCleanupVersion else { return }

    var didChangeRecords = false
    for index in records.indices {
      if records[index].status == .failed || records[index].status == .uploading {
        records[index].status = .pending
        didChangeRecords = true
      }
    }
    if didChangeRecords {
      persistRecords(syncUserVisibleStorage: false)
    }

    if !protocolLogs.isEmpty {
      protocolLogs.removeAll()
      store.saveProtocolLogs(protocolLogs)
    }

    latestNotice = nil
    store.saveLatestNotice(nil)

    defaults.set(Self.diagnosticsCleanupVersion, forKey: Self.diagnosticsCleanupVersionKey)
  }
}

final class UploadLogStore {
  private let fileURL: URL
  private let protocolURL: URL
  private let noticeURL: URL

  init() {
    let base = try? FileStore.ensureCaptureDirectory()
    let root = base ?? FileManager.default.temporaryDirectory
    fileURL = root.appendingPathComponent("upload-log.json")
    protocolURL = root.appendingPathComponent("upload-protocol-log.json")
    noticeURL = root.appendingPathComponent("upload-notice.json")
  }

  func load() -> [UploadRecord] {
    guard let data = try? Data(contentsOf: fileURL) else { return [] }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return (try? decoder.decode([UploadRecord].self, from: data)) ?? []
  }

  func save(_ records: [UploadRecord]) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted]
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(records) else { return }
    try? data.write(to: fileURL, options: [.atomic])
  }

  func loadProtocolLogs() -> [UploadProtocolLog] {
    guard let data = try? Data(contentsOf: protocolURL) else { return [] }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return (try? decoder.decode([UploadProtocolLog].self, from: data)) ?? []
  }

  func saveProtocolLogs(_ logs: [UploadProtocolLog]) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted]
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(logs) else { return }
    try? data.write(to: protocolURL, options: [.atomic])
  }

  func loadLatestNotice() -> UploadQueueNotice? {
    guard let data = try? Data(contentsOf: noticeURL) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(UploadQueueNotice.self, from: data)
  }

  func saveLatestNotice(_ notice: UploadQueueNotice?) {
    guard let notice else {
      try? FileManager.default.removeItem(at: noticeURL)
      return
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted]
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(notice) else { return }
    try? data.write(to: noticeURL, options: [.atomic])
  }
}
