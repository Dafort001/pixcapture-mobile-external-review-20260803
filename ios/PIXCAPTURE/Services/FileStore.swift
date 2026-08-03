import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated struct PreparedSeriesExport {
  let directoryURL: URL
  let itemURLs: [URL]
}

nonisolated struct LocalCaptureCleanupSummary {
  let scannedFiles: Int
  let queueMatchedFiles: Int
  let orphanFiles: Int
  let orphanBytes: Int64
  let deletedFiles: Int
  let deletedBytes: Int64
  let failedFiles: Int
}

nonisolated struct LocalStorageResetSummary {
  let removedRoots: Int
  let failedRoots: Int
}

nonisolated struct LocalCaptureStorageDiagnostics {
  let queueRecordCount: Int
  let seriesCount: Int
  let pendingRecords: Int
  let uploadingRecords: Int
  let uploadedRecords: Int
  let failedRecords: Int
  let localFileCount: Int
  let localBytes: Int64
  let queueMatchedFiles: Int
  let orphanFiles: Int
  let orphanBytes: Int64
  let kindCounts: [String: Int]
  let orphanKindCounts: [String: Int]
}

nonisolated struct LocalCaptureRecordRecoverySummary {
  let scannedFiles: Int
  let originalFiles: Int
  let restoredRecords: Int
  let restoredSeries: Int
  let skippedFiles: Int
  let records: [UploadRecord]
}

nonisolated private struct InternalSeriesExportItem {
  let archiveName: String
  let sourceURL: URL
}

nonisolated private struct RecoveryManifest: Codable {
  let schemaVersion: Int
  let generatedAt: String
  let jobCount: Int
  let seriesCount: Int
  let recordCount: Int
  let archiveCount: Int
  let files: [RecoveryManifestFile]
  let issues: [RecoveryManifestIssue]
}

nonisolated private struct RecoveryManifestFile: Codable {
  let archive: String
  let archivePath: String
  let sourcePath: String
  let kind: String
  let bytes: Int64?
  let recordId: String?
  let seriesId: String?
  let jobId: String?
  let jobLabel: String
  let room: String
  let floor: String
  let motif: Int
  let status: String?
}

nonisolated private struct RecoveryManifestIssue: Codable {
  let level: String
  let message: String
  let recordId: String?
  let seriesId: String?
}

nonisolated private struct RecoveryFilesystemCandidate {
  let url: URL
  let relativePath: String
  let kind: String
  let bytes: Int64
}

nonisolated private struct RecoveryFilenameInfo {
  let dateToken: String
  let motifSequence: Int
  let roomId: String
  let floorId: String
  let bracketIndex: Int
  let bracketTotal: Int
  let groupingKey: String
}

nonisolated private struct RecoveryXMPInfo {
  let exposureEV: Double?
  let exposureSeconds: Double?
  let iso: Float?
  let bracketIndex: Int?
  let bracketTotal: Int?
  let captureMode: PhotoCaptureMode?
}

nonisolated private struct RecoveryOriginalCandidate {
  let url: URL
  let filenameInfo: RecoveryFilenameInfo
  let xmpURL: URL?
  let xmpInfo: RecoveryXMPInfo
  let createdAt: Date
}

nonisolated private struct RecoveryRecordListInfo {
  let record: UploadRecord
  let fileRole: String
}

nonisolated enum InternalSeriesExportError: LocalizedError {
  case missingMetadataJSON
  case missingCaptureFiles
  case duplicateFilename(String)
  case archiveItemTooLarge(String)
  case archiveTooLarge

  var errorDescription: String? {
    switch self {
    case .missingMetadataJSON:
      return "Die JSON-Metadaten sind noch nicht fertig und koennen deshalb noch nicht exportiert werden."
    case .missingCaptureFiles:
      return "Es wurden keine exportierbaren Originaldateien fuer diese Serie gefunden."
    case .duplicateFilename(let filename):
      return "Der interne Export wurde abgebrochen, weil der Dateiname mehrfach vorkommt: \(filename)"
    case .archiveItemTooLarge(let filename):
      return "Die ZIP-Datei konnte nicht erstellt werden, weil \(filename) fuer diesen Export zu gross ist."
    case .archiveTooLarge:
      return "Die ZIP-Datei konnte nicht erstellt werden, weil der Export fuer dieses Format zu gross ist."
    }
  }
}

nonisolated struct CompanionXMPMetadata {
  let exposureBiasValue: Double?
  let bracketExposureEV: Double?
  let requestedBracketExposureEV: Double?
  let absoluteRequestedExposureBiasEV: Double?
  let baseExposureBiasEV: Double?
  let exposureSeconds: Double?
  let effectiveExposureSeconds: Double?
  let iso: Float?
  let bracketIndex: Int?
  let bracketTotal: Int?
  let frameCount: Int?
  let captureMode: String?
  let singleShotTriggeredAt: Date?
  let singleShotRollDegrees: Double?
  let singleShotPitchDegrees: Double?
  let singleShotStabilityScore: Double?
  let singleShotStabilityState: String?
  let singleShotCorrectability: String?
  let intendedProcessing: String?
}

nonisolated struct PhotoDepthSidecarStatistics: Codable {
  let validPixelCount: Int
  let invalidPixelCount: Int
  let minDepthMeters: Double?
  let maxDepthMeters: Double?
  let meanDepthMeters: Double?

  enum CodingKeys: String, CodingKey {
    case validPixelCount = "valid_pixel_count"
    case invalidPixelCount = "invalid_pixel_count"
    case minDepthMeters = "min_depth_meters"
    case maxDepthMeters = "max_depth_meters"
    case meanDepthMeters = "mean_depth_meters"
  }
}

nonisolated struct PhotoDepthCalibrationPayload: Codable {
  let referenceWidth: Int
  let referenceHeight: Int
  let intrinsicMatrix: [[Float]]
  let pixelSizeMillimeters: Float?
  let lensDistortionCenter: [Double]?

  enum CodingKeys: String, CodingKey {
    case referenceWidth = "reference_width"
    case referenceHeight = "reference_height"
    case intrinsicMatrix = "intrinsic_matrix"
    case pixelSizeMillimeters = "pixel_size_millimeters"
    case lensDistortionCenter = "lens_distortion_center"
  }
}

nonisolated struct PhotoDepthSidecarPayload: Codable {
  var version: String
  var schema: String
  var source: String
  var sourceImageFilename: String
  var width: Int
  var height: Int
  var depthUnit: String
  var encoding: String
  var valueType: String
  var valueLayout: String
  var depthDataType: String
  var depthDataFiltered: Bool
  var depthDataAccuracy: String
  var depthDataQuality: String
  var invalidValue: String
  var sourceFrameCount: Int?
  var aggregation: String?
  var statistics: PhotoDepthSidecarStatistics
  var calibration: PhotoDepthCalibrationPayload?
  var valuesBase64: String

  enum CodingKeys: String, CodingKey {
    case version
    case schema
    case source
    case sourceImageFilename = "source_image_filename"
    case width
    case height
    case depthUnit = "depth_unit"
    case encoding
    case valueType = "value_type"
    case valueLayout = "value_layout"
    case depthDataType = "depth_data_type"
    case depthDataFiltered = "depth_data_filtered"
    case depthDataAccuracy = "depth_data_accuracy"
    case depthDataQuality = "depth_data_quality"
    case invalidValue = "invalid_value"
    case sourceFrameCount = "source_frame_count"
    case aggregation
    case statistics
    case calibration
    case valuesBase64 = "values_base64"
  }
}

nonisolated enum FileStore {
  private static let previewSuffix = ".preview"
  private static let depthSuffix = ".depth"
  private static let previewExtension = "jpg"
  private static let previewMaxPixelSize = 2_400
  private static let previewJPEGQuality = 0.82
  private static let previewRecipeMarkerPrefix = "pixcapture-preview-v2"
  private static let previewSourceExtensions: Set<String> = ["dng", "heic", "heif"]
  private static let internalExportStagingPrefix = "pixcapture-series-export"
  private static let recoveryExportStagingPrefix = "pixcapture-recovery-export"
  private static let zipChunkSize = 64 * 1_024
  private static let zipLocalFileHeaderSignature: UInt32 = 0x04034b50
  private static let zipCentralDirectoryHeaderSignature: UInt32 = 0x02014b50
  private static let zipEndOfCentralDirectorySignature: UInt32 = 0x06054b50
  private static let zipVersionNeeded: UInt16 = 20
  private static let zipVersionMadeBy: UInt16 = 20
  private static let zipStoredCompressionMethod: UInt16 = 0
  private static let zipUTF8Flag: UInt16 = 1 << 11
  private static let jobsFolderName = "Jobs"
  private static let managedStillsFolderName = "Stills"
  private static let jobStatusFilename = "UPLOAD_STATUS.txt"
  private static let seriesStatusFilename = "SERIES_STATUS.txt"
  private static let recoveryLocalFilesFolderName = "Local_Files"
  private static let recoveryArchiveMaxBytes: Int64 = 250 * 1_024 * 1_024
  private static let recoveryFileExtensions: Set<String> = [
    "dng", "heic", "heif", "jpg", "jpeg", "xmp", "json"
  ]
  private static let recoveryDiagnosticFilenames: Set<String> = [
    "upload-log.json", "upload-protocol-log.json", "upload-notice.json"
  ]
  private static let recoverySeriesTimeGap: TimeInterval = 10 * 60
  private static let userVisibleSyncQueue = DispatchQueue(label: "pixcapture.user-visible-sync")

  // User-accessible storage (visible in the Files app when file sharing is enabled).
  // Use for assets the user may need to export manually (e.g. video projects).
  static func ensureUserFilesDirectory() throws -> URL {
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    var dir = docs.appendingPathComponent("PixCapture", isDirectory: true)
    if !FileManager.default.fileExists(atPath: dir.path) {
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    var values = URLResourceValues()
    // User-created recordings are not reproducible. Keep them eligible for an
    // encrypted device backup until the user explicitly removes them.
    values.isExcludedFromBackup = false
    try? dir.setResourceValues(values)
    return dir
  }

  static func savePhotoData(_ data: Data, fileExtension: String = "jpg", preferredBaseName: String? = nil) throws -> URL {
    let dir = try ensureCaptureDirectory()
    let filename: String
    if let preferredBaseName, !preferredBaseName.isEmpty {
      filename = uniqueFilename(
        in: dir,
        baseName: sanitizeFilename(preferredBaseName),
        ext: fileExtension
      )
    } else {
      filename = UUID().uuidString + "." + fileExtension
    }
    let url = dir.appendingPathComponent(filename)
    try data.write(to: url, options: [.atomic])
    return url
  }

  static func deletePhoto(at url: URL) {
    if !isPreviewSidecar(url), !isXMPSidecar(url), !isDepthJSONSidecar(url) {
      if let previewURL = existingCompanionPreviewURL(for: url) {
        try? FileManager.default.removeItem(at: previewURL)
      }
      if let xmpURL = existingCompanionXMPURL(for: url) {
        try? FileManager.default.removeItem(at: xmpURL)
      }
      if let depthURL = existingCompanionDepthURL(for: url) {
        try? FileManager.default.removeItem(at: depthURL)
      }
    }
    try? FileManager.default.removeItem(at: url)
  }

  static func deleteCaptureFiles(for removedRecords: [UploadRecord], keeping remainingRecords: [UploadRecord]) {
    guard !removedRecords.isEmpty else { return }
    let protectedPaths = Set(remainingRecords.flatMap(recordFilePaths))
    var deletedPaths = Set<String>()

    for record in removedRecords {
      let photoURLs = [record.fileURL, record.originalFileURL].compactMap { $0 }
      for url in photoURLs {
        deleteFileGroupIfUnprotected(url, protectedPaths: protectedPaths, deletedPaths: &deletedPaths)
      }

      if let exifLogURL = record.exifLogURL {
        deletePlainFileIfUnprotected(exifLogURL, protectedPaths: protectedPaths, deletedPaths: &deletedPaths)
      }
    }
  }

  static func orphanedLocalCaptureCleanupSummary(records: [UploadRecord]) throws -> LocalCaptureCleanupSummary {
    let scan = try orphanedLocalCaptureCleanupScan(records: records)
    return LocalCaptureCleanupSummary(
      scannedFiles: scan.candidates.count,
      queueMatchedFiles: scan.queueMatchedFiles,
      orphanFiles: scan.orphanCandidates.count,
      orphanBytes: scan.orphanCandidates.reduce(0) { $0 + $1.bytes },
      deletedFiles: 0,
      deletedBytes: 0,
      failedFiles: 0
    )
  }

  static func deleteOrphanedLocalCaptureFiles(records: [UploadRecord]) throws -> LocalCaptureCleanupSummary {
    let scan = try orphanedLocalCaptureCleanupScan(records: records)
    let fm = FileManager.default
    var deletedFiles = 0
    var deletedBytes: Int64 = 0
    var failedFiles = 0

    for candidate in scan.orphanCandidates {
      guard fm.fileExists(atPath: candidate.url.path) else { continue }
      do {
        try fm.removeItem(at: candidate.url)
        deletedFiles += 1
        deletedBytes += candidate.bytes
      } catch {
        failedFiles += 1
      }
    }

    return LocalCaptureCleanupSummary(
      scannedFiles: scan.candidates.count,
      queueMatchedFiles: scan.queueMatchedFiles,
      orphanFiles: scan.orphanCandidates.count,
      orphanBytes: scan.orphanCandidates.reduce(0) { $0 + $1.bytes },
      deletedFiles: deletedFiles,
      deletedBytes: deletedBytes,
      failedFiles: failedFiles
    )
  }

  static func localCaptureStorageDiagnostics(records: [UploadRecord]) -> LocalCaptureStorageDiagnostics {
    let scan = (try? orphanedLocalCaptureCleanupScan(records: records))
    let candidates = scan?.candidates ?? []
    let orphanCandidates = scan?.orphanCandidates ?? []

    return LocalCaptureStorageDiagnostics(
      queueRecordCount: records.count,
      seriesCount: Set(records.map(\.seriesId)).count,
      pendingRecords: records.filter { $0.status == .pending }.count,
      uploadingRecords: records.filter { $0.status == .uploading }.count,
      uploadedRecords: records.filter { $0.status == .uploaded }.count,
      failedRecords: records.filter { $0.status == .failed }.count,
      localFileCount: candidates.count,
      localBytes: candidates.reduce(0) { $0 + $1.bytes },
      queueMatchedFiles: scan?.queueMatchedFiles ?? 0,
      orphanFiles: orphanCandidates.count,
      orphanBytes: orphanCandidates.reduce(0) { $0 + $1.bytes },
      kindCounts: recoveryKindCounts(for: candidates),
      orphanKindCounts: recoveryKindCounts(for: orphanCandidates)
    )
  }

  private static func recoveryKindCounts(for candidates: [RecoveryFilesystemCandidate]) -> [String: Int] {
    candidates.reduce(into: [:]) { counts, candidate in
      counts[candidate.kind, default: 0] += 1
    }
  }

  @MainActor
  static func recoverUploadRecordsFromLocalCaptureFiles(
    existingRecords: [UploadRecord],
    jobLabel: String,
    jobId: String?
  ) throws -> LocalCaptureRecordRecoverySummary {
    let candidates = try scanRecoveryFilesystemCandidates()
    let recordInfoByPath = recoveryRecordInfoByPath(records: existingRecords)
    let originalCandidates = candidates.filter { $0.kind == "original" }
    let resolvedJobLabel = jobLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? "Recovery"
      : jobLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedJobId = jobId?.trimmingCharacters(in: .whitespacesAndNewlines)
    var recoverable: [RecoveryOriginalCandidate] = []
    var skipped = 0

    for candidate in originalCandidates {
      let path = candidate.url.standardizedFileURL.path
      guard recordInfoByPath[path] == nil else {
        skipped += 1
        continue
      }

      let xmpURL = existingCompanionXMPURL(for: candidate.url)
      let xmpInfo = recoveryXMPInfo(at: xmpURL)
      guard let filenameInfo = recoveryFilenameInfo(for: candidate.url, xmpInfo: xmpInfo) else {
        skipped += 1
        continue
      }

      recoverable.append(
        RecoveryOriginalCandidate(
          url: candidate.url,
          filenameInfo: filenameInfo,
          xmpURL: xmpURL,
          xmpInfo: xmpInfo,
          createdAt: recoveryCreatedAt(for: candidate.url, fallbackDateToken: filenameInfo.dateToken)
        )
      )
    }

    let grouped = Dictionary(grouping: recoverable, by: { $0.filenameInfo.groupingKey })
    var recoveredRecords: [UploadRecord] = []

    for (_, groupCandidates) in grouped {
      let sorted = groupCandidates.sorted {
        if $0.createdAt == $1.createdAt {
          return $0.url.lastPathComponent < $1.url.lastPathComponent
        }
        return $0.createdAt < $1.createdAt
      }
      let clusters = recoverySeriesClusters(from: sorted)

      for (clusterIndex, cluster) in clusters.enumerated() {
        guard let seed = cluster.first else { continue }
        let seriesId = UUID()
        let localShootId = "recovery-\(seed.filenameInfo.dateToken)-\(seed.filenameInfo.motifSequence)-\(clusterIndex + 1)"

        for item in cluster {
          let bracketIndex = item.xmpInfo.bracketIndex ?? item.filenameInfo.bracketIndex
          let bracketTotal = max(item.xmpInfo.bracketTotal ?? item.filenameInfo.bracketTotal, 1)
          let fallbackEV = recoveryFallbackExposureEV(index: bracketIndex, total: bracketTotal)
          recoveredRecords.append(
            UploadRecord(
              id: UUID(),
              seriesId: seriesId,
              localShootId: localShootId,
              fileURL: item.url,
              originalFileURL: nil,
              exifLogURL: nil,
              roomId: item.filenameInfo.roomId,
              floorId: item.filenameInfo.floorId,
              jobLabel: resolvedJobLabel,
              jobId: resolvedJobId?.isEmpty == true ? nil : resolvedJobId,
              seriesIndex: item.filenameInfo.motifSequence,
              exposureEV: item.xmpInfo.exposureEV ?? fallbackEV,
              exposureSeconds: item.xmpInfo.exposureSeconds ?? 0,
              iso: item.xmpInfo.iso ?? 0,
              captureMode: item.xmpInfo.captureMode ?? .standardBracket,
              captureOrientation: nil,
              sensorPitchDegrees: nil,
              sensorRollDegrees: nil,
              sensorHeadingDegrees: nil,
              singleShotAssessment: nil,
              metadataReady: item.xmpURL != nil,
              createdAt: item.createdAt,
              status: .pending,
              remoteKey: nil
            )
          )
        }
      }
    }

    return LocalCaptureRecordRecoverySummary(
      scannedFiles: candidates.count,
      originalFiles: originalCandidates.count,
      restoredRecords: recoveredRecords.count,
      restoredSeries: Set(recoveredRecords.map(\.seriesId)).count,
      skippedFiles: skipped,
      records: recoveredRecords
    )
  }

  private static func recoveryFilenameInfo(for url: URL, xmpInfo: RecoveryXMPInfo) -> RecoveryFilenameInfo? {
    let stem = url.deletingPathExtension().lastPathComponent
    guard let floorMarkerRange = stem.range(of: "-fl") else { return nil }
    let head = String(stem[..<floorMarkerRange.lowerBound])
    guard head.count >= 11 else { return nil }

    let dateEnd = head.index(head.startIndex, offsetBy: 8)
    let sequenceEnd = head.index(dateEnd, offsetBy: 3)
    let dateToken = String(head[..<dateEnd])
    guard dateToken.allSatisfy(\.isNumber),
          let motifSequence = Int(head[dateEnd..<sequenceEnd]) else {
      return nil
    }

    let roomSlug = String(head[sequenceEnd...])
    let tail = String(stem[floorMarkerRange.upperBound...])
    guard let parsedTail = recoveryBracketTailInfo(from: tail, xmpInfo: xmpInfo) else {
      return nil
    }

    let roomId = RoomTaxonomy.normalizedRoomId(roomSlug.replacingOccurrences(of: "-", with: "_"))
    let floorId = recoveryFloorId(forFileToken: parsedTail.floorToken)
    let bracketIndex = max(xmpInfo.bracketIndex ?? parsedTail.bracketIndex, 1)
    let bracketTotal = max(xmpInfo.bracketTotal ?? parsedTail.bracketTotal, 1)
    let groupingKey = [
      dateToken,
      "\(motifSequence)",
      roomId,
      floorId,
      "\(bracketTotal)"
    ].joined(separator: "|")

    return RecoveryFilenameInfo(
      dateToken: dateToken,
      motifSequence: motifSequence,
      roomId: roomId,
      floorId: floorId,
      bracketIndex: bracketIndex,
      bracketTotal: bracketTotal,
      groupingKey: groupingKey
    )
  }

  private static func recoveryBracketTailInfo(
    from tail: String,
    xmpInfo: RecoveryXMPInfo
  ) -> (floorToken: String, bracketIndex: Int, bracketTotal: Int)? {
    let parts = tail.split(separator: "-", omittingEmptySubsequences: false).map(String.init)

    if let xmpIndex = xmpInfo.bracketIndex,
       let xmpTotal = xmpInfo.bracketTotal,
       let range = tail.range(
        of: "-\(xmpIndex)-\(xmpTotal)(-\\d+)?$",
        options: .regularExpression
       ) {
      return (
        floorToken: String(tail[..<range.lowerBound]),
        bracketIndex: xmpIndex,
        bracketTotal: xmpTotal
      )
    }

    guard parts.count >= 2 else { return nil }
    let lastThreeAreNumbers = parts.count >= 3
      && Int(parts[parts.count - 3]) != nil
      && Int(parts[parts.count - 2]) != nil
      && Int(parts[parts.count - 1]) != nil

    if lastThreeAreNumbers {
      return (
        floorToken: parts.dropLast(3).joined(separator: "-"),
        bracketIndex: Int(parts[parts.count - 3]) ?? 1,
        bracketTotal: Int(parts[parts.count - 2]) ?? 1
      )
    }

    guard let bracketIndex = Int(parts[parts.count - 2]),
          let bracketTotal = Int(parts[parts.count - 1]) else {
      return nil
    }

    return (
      floorToken: parts.dropLast(2).joined(separator: "-"),
      bracketIndex: bracketIndex,
      bracketTotal: bracketTotal
    )
  }

  private static func recoveryFloorId(forFileToken token: String) -> String {
    let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed != "-", trimmed != "--" else {
      return FloorTaxonomy.defaultFloorId
    }
    return FloorTaxonomy.floors.first(where: { $0.fileToken == trimmed })?.id ?? FloorTaxonomy.defaultFloorId
  }

  private static func recoveryXMPInfo(at url: URL?) -> RecoveryXMPInfo {
    guard let url,
          let data = try? Data(contentsOf: url),
          let text = String(data: data, encoding: .utf8) else {
      return RecoveryXMPInfo(
        exposureEV: nil,
        exposureSeconds: nil,
        iso: nil,
        bracketIndex: nil,
        bracketTotal: nil,
        captureMode: nil
      )
    }

    return RecoveryXMPInfo(
      exposureEV: recoveryXMPDouble("pixcapture:BracketExposureEV", in: text)
        ?? recoveryXMPDouble("exif:ExposureBiasValue", in: text),
      exposureSeconds: recoveryXMPDouble("pixcapture:EffectiveExposureTimeSeconds", in: text)
        ?? recoveryXMPDouble("pixcapture:ExposureTimeSeconds", in: text),
      iso: recoveryXMPDouble("pixcapture:ISO", in: text).map(Float.init),
      bracketIndex: recoveryXMPInt("pixcapture:BracketIndex", in: text),
      bracketTotal: recoveryXMPInt("pixcapture:BracketTotal", in: text),
      captureMode: recoveryXMPString("pixcapture:CaptureMode", in: text).flatMap(PhotoCaptureMode.init(rawValue:))
    )
  }

  private static func recoveryXMPDouble(_ tag: String, in text: String) -> Double? {
    recoveryXMPString(tag, in: text).flatMap(Double.init)
  }

  private static func recoveryXMPInt(_ tag: String, in text: String) -> Int? {
    recoveryXMPString(tag, in: text).flatMap(Int.init)
  }

  private static func recoveryXMPString(_ tag: String, in text: String) -> String? {
    guard let openRange = text.range(of: "<\(tag)>"),
          let closeRange = text.range(of: "</\(tag)>", range: openRange.upperBound..<text.endIndex) else {
      return nil
    }
    return String(text[openRange.upperBound..<closeRange.lowerBound])
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func recoveryCreatedAt(for url: URL, fallbackDateToken: String) -> Date {
    if let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]) {
      if let created = values.creationDate {
        return created
      }
      if let modified = values.contentModificationDate {
        return modified
      }
    }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "yyyyMMdd"
    return formatter.date(from: fallbackDateToken) ?? Date()
  }

  private static func recoverySeriesClusters(from candidates: [RecoveryOriginalCandidate]) -> [[RecoveryOriginalCandidate]] {
    var clusters: [[RecoveryOriginalCandidate]] = []
    var current: [RecoveryOriginalCandidate] = []
    var previousDate: Date?

    for candidate in candidates {
      if let previousDate,
         candidate.createdAt.timeIntervalSince(previousDate) > recoverySeriesTimeGap,
         !current.isEmpty {
        clusters.append(current)
        current = []
      }
      current.append(candidate)
      previousDate = candidate.createdAt
    }

    if !current.isEmpty {
      clusters.append(current)
    }
    return clusters
  }

  private static func recoveryFallbackExposureEV(index: Int, total: Int) -> Double {
    guard total > 1 else { return 0 }
    let center = Double(total + 1) / 2.0
    return (Double(index) - center) * 1.5
  }

  @discardableResult
  static func resetLocalPixCaptureStorageForDebugLaunch() -> LocalStorageResetSummary {
    let fm = FileManager.default
    let rootURLs = [
      fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("PixCapture", isDirectory: true),
      fm.urls(for: .documentDirectory, in: .userDomainMask).first?
        .appendingPathComponent("PixCapture", isDirectory: true),
      fm.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("PixCapture", isDirectory: true)
    ].compactMap { $0 }

    var removedRoots = 0
    var failedRoots = 0

    for url in rootURLs {
      guard fm.fileExists(atPath: url.path) else { continue }
      do {
        try fm.removeItem(at: url)
        removedRoots += 1
      } catch {
        failedRoots += 1
      }
    }

    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "pixcapture.debug.lastLocalStorageResetAt")
    UserDefaults.standard.set(removedRoots, forKey: "pixcapture.debug.lastLocalStorageResetRemovedRoots")
    UserDefaults.standard.set(failedRoots, forKey: "pixcapture.debug.lastLocalStorageResetFailedRoots")

    return LocalStorageResetSummary(removedRoots: removedRoots, failedRoots: failedRoots)
  }

  static func companionPreviewURL(for photoURL: URL) -> URL {
    let directory = photoURL.deletingLastPathComponent()
    let basename = photoURL.deletingPathExtension().lastPathComponent
    return directory.appendingPathComponent("\(basename)\(previewSuffix).\(previewExtension)")
  }

  static func existingCompanionPreviewURL(for photoURL: URL) -> URL? {
    guard shouldCreatePreview(for: photoURL) else { return nil }
    let previewURL = companionPreviewURL(for: photoURL)
    return FileManager.default.fileExists(atPath: previewURL.path) ? previewURL : nil
  }

  static func companionXMPURL(for photoURL: URL) -> URL {
    let directory = photoURL.deletingLastPathComponent()
    let basename = photoURL.deletingPathExtension().lastPathComponent
    return directory.appendingPathComponent("\(basename).xmp")
  }

  static func existingCompanionXMPURL(for photoURL: URL) -> URL? {
    let xmpURL = companionXMPURL(for: photoURL)
    return FileManager.default.fileExists(atPath: xmpURL.path) ? xmpURL : nil
  }

  static func companionDepthURL(for photoURL: URL) -> URL {
    let directory = photoURL.deletingLastPathComponent()
    let basename = photoURL.deletingPathExtension().lastPathComponent
    return directory.appendingPathComponent("\(basename)\(depthSuffix).json")
  }

  static func existingCompanionDepthURL(for photoURL: URL) -> URL? {
    let depthURL = companionDepthURL(for: photoURL)
    return FileManager.default.fileExists(atPath: depthURL.path) ? depthURL : nil
  }

  @discardableResult
  static func saveCompanionXMP(for photoURL: URL, metadata: CompanionXMPMetadata) throws -> URL {
    let xmpURL = companionXMPURL(for: photoURL)
    let data = companionXMPData(for: metadata)
    try data.write(to: xmpURL, options: [.atomic])
    markExcludedFromBackup(xmpURL)
    return xmpURL
  }

  @discardableResult
  static func saveCompanionDepth(for photoURL: URL, payload: PhotoDepthSidecarPayload) throws -> URL {
    let depthURL = companionDepthURL(for: photoURL)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(payload)
    try data.write(to: depthURL, options: [.atomic])
    markExcludedFromBackup(depthURL)
    return depthURL
  }

  static func loadCompanionDepthPayload(for photoURL: URL) -> PhotoDepthSidecarPayload? {
    guard let depthURL = existingCompanionDepthURL(for: photoURL),
          let data = try? Data(contentsOf: depthURL) else {
      return nil
    }
    let decoder = JSONDecoder()
    return try? decoder.decode(PhotoDepthSidecarPayload.self, from: data)
  }

  static func companionXMPData(for metadata: CompanionXMPMetadata) -> Data {
    var propertyLines: [String] = []

    appendRealProperty("exif:ExposureBiasValue", value: metadata.exposureBiasValue, to: &propertyLines)
    appendRealProperty("pixcapture:BracketExposureEV", value: metadata.bracketExposureEV, to: &propertyLines)
    appendRealProperty("pixcapture:RequestedBracketExposureEV", value: metadata.requestedBracketExposureEV, to: &propertyLines)
    appendRealProperty("pixcapture:AbsoluteRequestedExposureBiasEV", value: metadata.absoluteRequestedExposureBiasEV, to: &propertyLines)
    appendRealProperty("pixcapture:BaseExposureBiasEV", value: metadata.baseExposureBiasEV, to: &propertyLines)
    appendRealProperty("pixcapture:ExposureTimeSeconds", value: metadata.exposureSeconds, to: &propertyLines)
    appendRealProperty("pixcapture:EffectiveExposureTimeSeconds", value: metadata.effectiveExposureSeconds, to: &propertyLines)

    if let iso = metadata.iso, iso.isFinite, iso > 0 {
      appendIntegerProperty("pixcapture:ISO", value: Int(iso.rounded()), to: &propertyLines)
    }
    appendIntegerProperty("pixcapture:BracketIndex", value: metadata.bracketIndex, to: &propertyLines)
    appendIntegerProperty("pixcapture:BracketTotal", value: metadata.bracketTotal, to: &propertyLines)
    appendIntegerProperty("pixcapture:FrameCount", value: metadata.frameCount, to: &propertyLines)
    appendStringProperty("pixcapture:CaptureMode", value: metadata.captureMode, to: &propertyLines)
    appendStringProperty("pixcapture:IntendedProcessing", value: metadata.intendedProcessing, to: &propertyLines)
    if let triggeredAt = metadata.singleShotTriggeredAt {
      appendStringProperty("pixcapture:SingleShotTriggeredAt", value: ISO8601DateFormatter().string(from: triggeredAt), to: &propertyLines)
    }
    appendRealProperty("pixcapture:SingleShotRollDegrees", value: metadata.singleShotRollDegrees, to: &propertyLines)
    appendRealProperty("pixcapture:SingleShotPitchDegrees", value: metadata.singleShotPitchDegrees, to: &propertyLines)
    appendRealProperty("pixcapture:SingleShotStabilityScore", value: metadata.singleShotStabilityScore, to: &propertyLines)
    appendStringProperty("pixcapture:SingleShotStabilityState", value: metadata.singleShotStabilityState, to: &propertyLines)
    appendStringProperty("pixcapture:SingleShotCorrectability", value: metadata.singleShotCorrectability, to: &propertyLines)

    let propertyBlock = propertyLines.joined(separator: "\n")
    let xpacketBOM = String(UnicodeScalar(0xFEFF)!)
    let xml = """
    <?xpacket begin="\(xpacketBOM)" id="W5M0MpCehiHzreSzNTczkc9d"?>
    <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="PixCapture">
      <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
        <rdf:Description rdf:about=""
          xmlns:exif="http://ns.adobe.com/exif/1.0/"
          xmlns:pixcapture="https://pixcapture.app/ns/1.0/">
    \(propertyBlock)
        </rdf:Description>
      </rdf:RDF>
    </x:xmpmeta>
    <?xpacket end="w"?>
    """
    return Data(xml.utf8)
  }

  @discardableResult
  static func ensurePreviewExists(
    for photoURL: URL,
    captureOrientation: String? = nil,
    sensorRollDegrees: Double? = nil
  ) -> URL? {
    guard shouldCreatePreview(for: photoURL) else { return nil }
    if let existing = existingCompanionPreviewURL(for: photoURL) {
      if !previewNeedsRefresh(
        existing,
        captureOrientation: captureOrientation,
        sensorRollDegrees: sensorRollDegrees
      ) {
        return existing
      }
      try? FileManager.default.removeItem(at: existing)
    }
    guard let previewData = makePreviewJPEG(
      from: photoURL,
      captureOrientation: captureOrientation,
      sensorRollDegrees: sensorRollDegrees
    ) else { return nil }
    var previewURL = companionPreviewURL(for: photoURL)
    do {
      try previewData.write(to: previewURL, options: [.atomic])
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try? previewURL.setResourceValues(values)
      return previewURL
    } catch {
      return nil
    }
  }

  static func ensureCaptureDirectory() throws -> URL {
    // Use Application Support so captures survive across days (Caches can be purged by iOS).
    // Captures are user-created originals, not reproducible cache data. Older
    // releases excluded this directory; explicitly clear that resource flag.
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    var dir = support.appendingPathComponent("PixCapture", isDirectory: true)
    if !FileManager.default.fileExists(atPath: dir.path) {
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    var values = URLResourceValues()
    values.isExcludedFromBackup = false
    try? dir.setResourceValues(values)
    return dir
  }

  static func recoveryCandidateFileCount() -> Int {
    (try? scanRecoveryFilesystemCandidates().filter(isRecoverableOriginalCandidate).count) ?? 0
  }

  private static func ensureJobsDirectory() throws -> URL {
    let base = try ensureUserFilesDirectory()
    let dir = base.appendingPathComponent(jobsFolderName, isDirectory: true)
    try ensureDirectory(dir)
    return dir
  }

  static func scheduleUserVisibleJobSync(for records: [UploadRecord]) {
    userVisibleSyncQueue.async {
      removeUserVisibleJobCopiesNow()
    }
  }

  static func saveExifLog(seriesId: UUID, entries: [ExifLogEntry]) -> URL? {
    guard let dir = try? ensureCaptureDirectory() else { return nil }
    let url = dir.appendingPathComponent("exif-\(seriesId.uuidString).json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(entries) else { return nil }
    try? data.write(to: url, options: [.atomic])
    return url
  }

  static func prepareInternalSeriesExport(
    records: [UploadRecord],
    exifLogURL: URL?
  ) throws -> PreparedSeriesExport {
    let exportItems = try internalExportItems(records: records, exifLogURL: exifLogURL)
    let fm = FileManager.default
    let stagingDir = fm.temporaryDirectory.appendingPathComponent(
      "\(internalExportStagingPrefix)-\(UUID().uuidString)",
      isDirectory: true
    )
    try ensureDirectory(stagingDir)

    var stagedURLs: [URL] = []

    for item in exportItems {
      let destinationURL = stagingDir.appendingPathComponent(item.archiveName)
      try fm.copyItem(at: item.sourceURL, to: destinationURL)
      markExcludedFromBackup(destinationURL)
      stagedURLs.append(destinationURL)
    }

    return PreparedSeriesExport(
      directoryURL: stagingDir,
      itemURLs: stagedURLs
    )
  }

  static func prepareInternalSeriesZipExport(
    records: [UploadRecord],
    exifLogURL: URL?
  ) throws -> PreparedSeriesExport {
    let exportItems = try internalExportItems(records: records, exifLogURL: exifLogURL)
    let fm = FileManager.default
    let stagingDir = fm.temporaryDirectory.appendingPathComponent(
      "\(internalExportStagingPrefix)-\(UUID().uuidString)",
      isDirectory: true
    )
    try ensureDirectory(stagingDir)

    let archiveURL = stagingDir.appendingPathComponent(internalExportArchiveFilename(for: records))

    do {
      try createStoredZipArchive(at: archiveURL, items: exportItems)
    } catch {
      try? fm.removeItem(at: stagingDir)
      throw error
    }

    markExcludedFromBackup(archiveURL)

    return PreparedSeriesExport(
      directoryURL: stagingDir,
      itemURLs: [archiveURL]
    )
  }

  static func prepareRecoveryJobExport(records: [UploadRecord]) throws -> PreparedSeriesExport {
    let sortedRecords = records.sorted {
      if $0.createdAt == $1.createdAt {
        return $0.id.uuidString < $1.id.uuidString
      }
      return $0.createdAt < $1.createdAt
    }
    let filesystemCandidates = try scanRecoveryFilesystemCandidates()

    let fm = FileManager.default
    let stagingDir = fm.temporaryDirectory.appendingPathComponent(
      "\(recoveryExportStagingPrefix)-\(UUID().uuidString)",
      isDirectory: true
    )
    try ensureDirectory(stagingDir)

    var itemURLs: [URL] = []
    var manifestFiles: [RecoveryManifestFile] = []
    var issues: [RecoveryManifestIssue] = []
    var exportedSourcePaths = Set<String>()
    let groupedBySeries = Dictionary(grouping: sortedRecords, by: \.seriesId)

    for (seriesId, seriesRecords) in groupedBySeries.sorted(by: { left, right in
      let leftDate = left.value.map(\.createdAt).min() ?? .distantFuture
      let rightDate = right.value.map(\.createdAt).min() ?? .distantFuture
      return leftDate < rightDate
    }) {
      let seriesItems = recoveryExportItems(
        records: seriesRecords,
        issues: &issues
      )

      guard !seriesItems.isEmpty else {
        issues.append(
          RecoveryManifestIssue(
            level: "error",
            message: "Keine lokal vorhandenen Dateien fuer Serie \(seriesId.uuidString.lowercased()) gefunden.",
            recordId: nil,
            seriesId: seriesId.uuidString.lowercased()
          )
        )
        continue
      }

      let seriesChunks = chunkRecoveryExportItems(seriesItems)
      for (chunkIndex, chunk) in seriesChunks.enumerated() {
        let archiveURL = stagingDir.appendingPathComponent(
          recoveryArchiveFilename(for: seriesRecords, index: chunkIndex, total: seriesChunks.count)
        )
        do {
          try createStoredZipArchive(at: archiveURL, items: chunk.map(\.zipItem))
          markExcludedFromBackup(archiveURL)
          itemURLs.append(archiveURL)

          for item in chunk {
            manifestFiles.append(
              RecoveryManifestFile(
                archive: archiveURL.lastPathComponent,
                archivePath: item.zipItem.archiveName,
                sourcePath: item.zipItem.sourceURL.path,
                kind: item.kind,
                bytes: fileSize(at: item.zipItem.sourceURL),
                recordId: item.record?.id.uuidString.lowercased(),
                seriesId: item.record?.seriesId.uuidString.lowercased() ?? seriesId.uuidString.lowercased(),
                jobId: item.record?.jobId,
                jobLabel: item.record?.jobLabel ?? seriesRecords.first?.jobLabel ?? "",
                room: item.record.map { RoomTaxonomy.room(id: $0.roomId).displayName } ?? "",
                floor: item.record.map { FloorTaxonomy.floor(id: $0.floorId).displayName } ?? "",
                motif: item.record?.seriesIndex ?? seriesRecords.first?.seriesIndex ?? 0,
                status: item.record?.status.rawValue
              )
            )
            exportedSourcePaths.insert(item.zipItem.sourceURL.standardizedFileURL.path)
          }
        } catch {
          issues.append(
            RecoveryManifestIssue(
              level: "error",
              message: "ZIP fuer Serie \(seriesId.uuidString.lowercased()) Teil \(chunkIndex + 1) konnte nicht erstellt werden: \(error.localizedDescription)",
              recordId: nil,
              seriesId: seriesId.uuidString.lowercased()
            )
          )
        }
      }
    }

    let orphanCandidates = filesystemCandidates.filter {
      !exportedSourcePaths.contains($0.url.standardizedFileURL.path)
    }
    if !orphanCandidates.isEmpty {
      if sortedRecords.isEmpty {
        issues.append(
          RecoveryManifestIssue(
            level: "warning",
            message: "Keine Upload-Queue-Eintraege gefunden. Recovery exportiert direkt aus dem lokalen Capture-Ordner.",
            recordId: nil,
            seriesId: nil
          )
        )
      } else {
        issues.append(
          RecoveryManifestIssue(
            level: "warning",
            message: "\(orphanCandidates.count) lokale Dateien waren nicht in der Upload-Queue und wurden als Orphans exportiert.",
            recordId: nil,
            seriesId: nil
          )
        )
      }

      let orphanChunks = chunkRecoveryFilesystemCandidates(orphanCandidates)
      for (chunkIndex, chunk) in orphanChunks.enumerated() {
        var archiveNames = Set<String>()
        let zipItems = chunk.map { candidate -> InternalSeriesExportItem in
          let filename = uniqueArchiveFilename(
            candidate.url.lastPathComponent,
            existingNames: archiveNames
          )
          let archiveName = "\(recoveryLocalFilesFolderName)/\(filename)"
          archiveNames.insert(archiveName)
          return InternalSeriesExportItem(
            archiveName: archiveName,
            sourceURL: candidate.url
          )
        }
        let archiveURL = stagingDir.appendingPathComponent(
          recoveryFilesystemArchiveFilename(index: chunkIndex, total: orphanChunks.count)
        )

        do {
          try createStoredZipArchive(at: archiveURL, items: zipItems)
          markExcludedFromBackup(archiveURL)
          itemURLs.append(archiveURL)

          for (candidate, zipItem) in zip(chunk, zipItems) {
            manifestFiles.append(
              RecoveryManifestFile(
                archive: archiveURL.lastPathComponent,
                archivePath: zipItem.archiveName,
                sourcePath: candidate.url.path,
                kind: candidate.kind,
                bytes: candidate.bytes,
                recordId: nil,
                seriesId: nil,
                jobId: nil,
                jobLabel: "",
                room: "",
                floor: "",
                motif: 0,
                status: nil
              )
            )
            exportedSourcePaths.insert(candidate.url.standardizedFileURL.path)
          }
        } catch {
          issues.append(
            RecoveryManifestIssue(
              level: "error",
              message: "ZIP fuer lokale Orphan-Dateien konnte nicht erstellt werden: \(error.localizedDescription)",
              recordId: nil,
              seriesId: nil
            )
          )
        }
      }
    }

    guard !itemURLs.isEmpty else {
      try? fm.removeItem(at: stagingDir)
      throw InternalSeriesExportError.missingCaptureFiles
    }

    let manifest = RecoveryManifest(
      schemaVersion: 1,
      generatedAt: timestampString(from: Date()),
      jobCount: Set(sortedRecords.map { userVisibleJobFolderName(for: $0) }).count,
      seriesCount: groupedBySeries.count,
      recordCount: sortedRecords.count,
      archiveCount: itemURLs.count,
      files: manifestFiles,
      issues: issues
    )
    let manifestURL = stagingDir.appendingPathComponent("PIXCAPTURE_RECOVERY_MANIFEST.json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(manifest).write(to: manifestURL, options: [.atomic])
    markExcludedFromBackup(manifestURL)

    let statusURL = stagingDir.appendingPathComponent("PIXCAPTURE_RECOVERY_README.txt")
    try recoveryStatusText(
      records: sortedRecords,
      archiveCount: itemURLs.count,
      fileCount: manifestFiles.count,
      issues: issues
    ).write(to: statusURL, atomically: true, encoding: .utf8)
    markExcludedFromBackup(statusURL)

    return PreparedSeriesExport(
      directoryURL: stagingDir,
      itemURLs: [statusURL, manifestURL] + itemURLs
    )
  }

  static func prepareRecoveryFileListExport(records: [UploadRecord]) throws -> PreparedSeriesExport {
    let candidates = try scanRecoveryFilesystemCandidates()
    let recordInfoByPath = recoveryRecordInfoByPath(records: records)
    let fm = FileManager.default
    let stagingDir = fm.temporaryDirectory.appendingPathComponent(
      "\(recoveryExportStagingPrefix)-file-list-\(UUID().uuidString)",
      isDirectory: true
    )
    try ensureDirectory(stagingDir)

    let csvURL = stagingDir.appendingPathComponent("PIXCAPTURE_LOCAL_FILES.csv")
    FileManager.default.createFile(atPath: csvURL.path, contents: nil)
    let handle = try FileHandle(forWritingTo: csvURL)
    defer {
      try? handle.close()
    }

    try writeCSVLine(
      [
        "relative_path",
        "kind",
        "bytes",
        "created_at",
        "modified_at",
        "queue_match",
        "queue_file_role",
        "record_id",
        "series_id",
        "job_label",
        "job_id",
        "room",
        "floor",
        "motif",
        "status",
        "absolute_path"
      ],
      to: handle
    )

    var totalBytes: Int64 = 0
    var kindCounts: [String: Int] = [:]
    var queueMatchedCount = 0

    for candidate in candidates {
      totalBytes += candidate.bytes
      kindCounts[candidate.kind, default: 0] += 1

      let values = try? candidate.url.resourceValues(forKeys: [
        .creationDateKey,
        .contentModificationDateKey
      ])
      let info = recordInfoByPath[candidate.url.standardizedFileURL.path]
      if info != nil {
        queueMatchedCount += 1
      }
      let record = info?.record

      try writeCSVLine(
        [
          candidate.relativePath,
          candidate.kind,
          "\(candidate.bytes)",
          values?.creationDate.map { timestampString(from: $0) } ?? "",
          values?.contentModificationDate.map { timestampString(from: $0) } ?? "",
          info == nil ? "no" : "yes",
          info?.fileRole ?? "",
          record?.id.uuidString.lowercased() ?? "",
          record?.seriesId.uuidString.lowercased() ?? "",
          record?.jobLabel ?? "",
          record?.jobId ?? "",
          record.map { RoomTaxonomy.room(id: $0.roomId).displayName } ?? "",
          record.map { FloorTaxonomy.floor(id: $0.floorId).displayName } ?? "",
          record.map { "\($0.seriesIndex)" } ?? "",
          record?.status.rawValue ?? "",
          candidate.url.path
        ],
        to: handle
      )
    }

    markExcludedFromBackup(csvURL)

    let summaryURL = stagingDir.appendingPathComponent("PIXCAPTURE_LOCAL_FILES_README.txt")
    let kindSummary = kindCounts
      .sorted { $0.key < $1.key }
      .map { "- \($0.key): \($0.value)" }
      .joined(separator: "\n")
    let summary = """
    PixCapture Local File List
    Generated: \(timestampString(from: Date()))
    Local files: \(candidates.count)
    Queue records: \(records.count)
    Queue matched files: \(queueMatchedCount)
    Total bytes: \(totalBytes)

    Kinds:
    \(kindSummary.isEmpty ? "- none: 0" : kindSummary)

    Diese Liste enthaelt nur Dateimetadaten. Es wurden keine Bilder dekodiert und keine ZIP-Dateien erstellt.
    Oeffne PIXCAPTURE_LOCAL_FILES.csv, um zu sehen, ob die Dateien zu aktuellen Serien/Jobs gehoeren oder alte lokale Reste sind.
    """
    try summary.write(to: summaryURL, atomically: true, encoding: .utf8)
    markExcludedFromBackup(summaryURL)

    return PreparedSeriesExport(
      directoryURL: stagingDir,
      itemURLs: [summaryURL, csvURL]
    )
  }

  private static func sanitizeFilename(_ value: String) -> String {
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
    let normalized = value.replacingOccurrences(of: "_", with: "-")
    let filtered = normalized.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
    let collapsed = String(filtered).replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
    return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
  }

  private static func appendRealProperty(_ name: String, value: Double?, to lines: inout [String]) {
    guard let value, value.isFinite else { return }
    lines.append("      <\(name)>\(xmpDecimalString(value))</\(name)>")
  }

  private static func appendIntegerProperty(_ name: String, value: Int?, to lines: inout [String]) {
    guard let value else { return }
    lines.append("      <\(name)>\(value)</\(name)>")
  }

  private static func appendStringProperty(_ name: String, value: String?, to lines: inout [String]) {
    guard let value, !value.isEmpty else { return }
    lines.append("      <\(name)>\(xmlEscaped(value))</\(name)>")
  }

  private static func xmpDecimalString(_ value: Double) -> String {
    var result = String(format: "%.6f", value)
    while result.contains("."), result.last == "0" {
      result.removeLast()
    }
    if result.last == "." {
      result.removeLast()
    }
    return result
  }

  private static func xmlEscaped(_ value: String) -> String {
    value
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&apos;")
  }

  private static func isXMPSidecar(_ url: URL) -> Bool {
    url.pathExtension.lowercased() == "xmp"
  }

  private static func isDepthJSONSidecar(_ url: URL) -> Bool {
    url.pathExtension.lowercased() == "json"
      && url.deletingPathExtension().lastPathComponent.hasSuffix(depthSuffix)
  }

  private static func internalExportItems(
    records: [UploadRecord],
    exifLogURL: URL?
  ) throws -> [InternalSeriesExportItem] {
    guard let exifLogURL,
          FileManager.default.fileExists(atPath: exifLogURL.path) else {
      throw InternalSeriesExportError.missingMetadataJSON
    }

    let sourceURLs = internalExportSourceURLs(for: records)
    guard !sourceURLs.isEmpty else {
      throw InternalSeriesExportError.missingCaptureFiles
    }

    var exportItems: [InternalSeriesExportItem] = []
    var stagedNames = Set<String>()

    for sourceURL in [exifLogURL] + sourceURLs {
      let archiveName = sourceURL.lastPathComponent
      guard stagedNames.insert(archiveName).inserted else {
        throw InternalSeriesExportError.duplicateFilename(archiveName)
      }
      exportItems.append(
        InternalSeriesExportItem(
          archiveName: archiveName,
          sourceURL: sourceURL
        )
      )
    }

    return exportItems
  }

  nonisolated private struct RecoveryExportItem {
    let zipItem: InternalSeriesExportItem
    let kind: String
    let record: UploadRecord?
  }

  private static func internalExportArchiveFilename(for records: [UploadRecord]) -> String {
    guard let seed = records.sorted(by: { $0.createdAt < $1.createdAt }).first else {
      return "PixCapture_Export.zip"
    }
    return "PixCapture_\(userVisibleSeriesFolderName(for: seed)).zip"
  }

  private static func recoveryArchiveFilename(for records: [UploadRecord], index: Int, total: Int) -> String {
    guard let seed = records.sorted(by: { $0.createdAt < $1.createdAt }).first else {
      return total > 1
        ? "PixCapture_Recovery_Export_\(index + 1)_of_\(total).zip"
        : "PixCapture_Recovery_Export.zip"
    }
    let base = "PixCapture_Recovery_\(userVisibleSeriesFolderName(for: seed))"
    return total > 1
      ? "\(base)_\(index + 1)_of_\(total).zip"
      : "\(base).zip"
  }

  private static func recoveryFilesystemArchiveFilename(index: Int, total: Int) -> String {
    guard total > 1 else {
      return "PixCapture_Recovery_Local_Files.zip"
    }
    return "PixCapture_Recovery_Local_Files_\(index + 1)_of_\(total).zip"
  }

  private static func scanRecoveryFilesystemCandidates() throws -> [RecoveryFilesystemCandidate] {
    let fm = FileManager.default
    let captureDirectory = try ensureCaptureDirectory()
    guard let enumerator = fm.enumerator(
      at: captureDirectory,
      includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
      options: [.skipsHiddenFiles]
    ) else {
      return []
    }

    var candidates: [RecoveryFilesystemCandidate] = []
    for case let url as URL in enumerator {
      let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
      guard values?.isRegularFile == true else { continue }
      let filename = url.lastPathComponent
      let ext = url.pathExtension.lowercased()
      let isDiagnostic = recoveryDiagnosticFilenames.contains(filename)
      guard isDiagnostic || recoveryFileExtensions.contains(ext) else { continue }

      let relativePath = relativeRecoveryPath(for: url, base: captureDirectory)
      let bytes = Int64(values?.fileSize ?? 0)
      candidates.append(
        RecoveryFilesystemCandidate(
          url: url,
          relativePath: relativePath,
          kind: isDiagnostic ? "diagnostic" : recoveryKind(forExtension: ext, filename: filename),
          bytes: bytes
        )
      )
    }

    return candidates.sorted {
      if $0.relativePath == $1.relativePath {
        return $0.url.path < $1.url.path
      }
      return $0.relativePath < $1.relativePath
    }
  }

  private static func relativeRecoveryPath(for url: URL, base: URL) -> String {
    let basePath = base.standardizedFileURL.path
    let path = url.standardizedFileURL.path
    guard path.hasPrefix(basePath + "/") else {
      return url.lastPathComponent
    }
    return String(path.dropFirst(basePath.count + 1))
  }

  private static func recoveryKind(forExtension ext: String, filename: String) -> String {
    if filename.hasSuffix(previewSuffix + "." + previewExtension) {
      return "preview"
    }
    if filename.hasSuffix(depthSuffix + ".json") {
      return "depth"
    }
    switch ext {
    case "dng", "heic", "heif":
      return "original"
    case "jpg", "jpeg":
      return "preview"
    case "xmp":
      return "xmp"
    case "json":
      return "json"
    default:
      return "file"
    }
  }

  private static func isRecoverableOriginalCandidate(_ candidate: RecoveryFilesystemCandidate) -> Bool {
    candidate.kind == "original"
  }

  private static func chunkRecoveryFilesystemCandidates(
    _ candidates: [RecoveryFilesystemCandidate]
  ) -> [[RecoveryFilesystemCandidate]] {
    var chunks: [[RecoveryFilesystemCandidate]] = []
    var current: [RecoveryFilesystemCandidate] = []
    var currentBytes: Int64 = 0

    for candidate in candidates {
      if !current.isEmpty,
         currentBytes + candidate.bytes > recoveryArchiveMaxBytes {
        chunks.append(current)
        current = []
        currentBytes = 0
      }
      current.append(candidate)
      currentBytes += candidate.bytes
    }

    if !current.isEmpty {
      chunks.append(current)
    }
    return chunks
  }

  private static func chunkRecoveryExportItems(
    _ items: [RecoveryExportItem]
  ) -> [[RecoveryExportItem]] {
    var chunks: [[RecoveryExportItem]] = []
    var current: [RecoveryExportItem] = []
    var currentBytes: Int64 = 0

    for item in items {
      let itemBytes = fileSize(at: item.zipItem.sourceURL) ?? 0
      if !current.isEmpty,
         currentBytes + itemBytes > recoveryArchiveMaxBytes {
        chunks.append(current)
        current = []
        currentBytes = 0
      }
      current.append(item)
      currentBytes += itemBytes
    }

    if !current.isEmpty {
      chunks.append(current)
    }
    return chunks
  }

  private static func recoveryRecordInfoByPath(records: [UploadRecord]) -> [String: RecoveryRecordListInfo] {
    var result: [String: RecoveryRecordListInfo] = [:]

    func insert(_ url: URL?, role: String, record: UploadRecord) {
      guard let url else { return }
      let path = url.standardizedFileURL.path
      guard FileManager.default.fileExists(atPath: path) else { return }
      result[path] = RecoveryRecordListInfo(record: record, fileRole: role)
    }

    for record in records {
      insert(record.originalFileURL, role: "original", record: record)
      insert(record.fileURL, role: "file", record: record)
      insert(record.exifLogURL, role: "exif-log", record: record)
      insert(existingCompanionPreviewURL(for: record.fileURL), role: "preview", record: record)
      insert(existingCompanionXMPURL(for: record.fileURL), role: "xmp", record: record)
      insert(existingCompanionDepthURL(for: record.fileURL), role: "depth", record: record)
    }

    return result
  }

  private static func orphanedLocalCaptureCleanupScan(
    records: [UploadRecord]
  ) throws -> (
    candidates: [RecoveryFilesystemCandidate],
    orphanCandidates: [RecoveryFilesystemCandidate],
    queueMatchedFiles: Int
  ) {
    let candidates = try scanRecoveryFilesystemCandidates()
    let recordInfoByPath = recoveryRecordInfoByPath(records: records)
    var queueMatchedFiles = 0
    var orphanCandidates: [RecoveryFilesystemCandidate] = []

    for candidate in candidates {
      let path = candidate.url.standardizedFileURL.path
      if recordInfoByPath[path] != nil {
        queueMatchedFiles += 1
      } else if candidate.kind != "diagnostic" {
        orphanCandidates.append(candidate)
      }
    }

    return (candidates, orphanCandidates, queueMatchedFiles)
  }

  private static func recordFilePaths(for record: UploadRecord) -> [String] {
    var urls = [record.fileURL]
    if let originalFileURL = record.originalFileURL {
      urls.append(originalFileURL)
    }
    if let exifLogURL = record.exifLogURL {
      urls.append(exifLogURL)
    }

    for sourceURL in [record.fileURL, record.originalFileURL].compactMap({ $0 }) {
      urls.append(companionPreviewURL(for: sourceURL))
      urls.append(companionXMPURL(for: sourceURL))
      urls.append(companionDepthURL(for: sourceURL))
    }

    return urls.map { $0.standardizedFileURL.path }
  }

  private static func deleteFileGroupIfUnprotected(
    _ url: URL,
    protectedPaths: Set<String>,
    deletedPaths: inout Set<String>
  ) {
    for candidateURL in [
      url,
      companionPreviewURL(for: url),
      companionXMPURL(for: url),
      companionDepthURL(for: url)
    ] {
      deletePlainFileIfUnprotected(
        candidateURL,
        protectedPaths: protectedPaths,
        deletedPaths: &deletedPaths
      )
    }
  }

  private static func deletePlainFileIfUnprotected(
    _ url: URL,
    protectedPaths: Set<String>,
    deletedPaths: inout Set<String>
  ) {
    let path = url.standardizedFileURL.path
    guard !protectedPaths.contains(path), !deletedPaths.contains(path) else { return }
    guard FileManager.default.fileExists(atPath: path) else { return }
    try? FileManager.default.removeItem(at: url)
    deletedPaths.insert(path)
  }

  private static func writeCSVLine(_ fields: [String], to handle: FileHandle) throws {
    let line = fields.map(csvEscaped).joined(separator: ",") + "\n"
    try handle.write(contentsOf: Data(line.utf8))
  }

  private static func csvEscaped(_ value: String) -> String {
    if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
      return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
    return value
  }

  private static func createStoredZipArchive(
    at archiveURL: URL,
    items: [InternalSeriesExportItem]
  ) throws {
    FileManager.default.createFile(atPath: archiveURL.path, contents: nil)
    let archiveHandle = try FileHandle(forWritingTo: archiveURL)
    defer {
      try? archiveHandle.close()
    }

    var centralDirectoryEntries: [ZipCentralDirectoryEntry] = []
    var currentOffset: UInt64 = 0

    for item in items {
      let entryInfo = try analyzeStoredZipEntry(at: item.sourceURL, entryName: item.archiveName)
      guard currentOffset <= UInt64(UInt32.max) else {
        throw InternalSeriesExportError.archiveTooLarge
      }

      let timestamp = zipTimestamp(for: entryInfo.modificationDate)
      let entryNameData = Data(item.archiveName.utf8)
      guard entryNameData.count <= Int(UInt16.max) else {
        throw InternalSeriesExportError.archiveTooLarge
      }

      let localHeaderOffset = UInt32(currentOffset)
      let localHeader = localZipHeaderData(
        entryNameData: entryNameData,
        crc32: entryInfo.crc32,
        size: entryInfo.size,
        modificationTime: timestamp.time,
        modificationDate: timestamp.date
      )
      try archiveHandle.write(contentsOf: localHeader)
      currentOffset += UInt64(localHeader.count)

      try streamFile(at: item.sourceURL, to: archiveHandle)
      currentOffset += UInt64(entryInfo.size)

      centralDirectoryEntries.append(
        ZipCentralDirectoryEntry(
          entryNameData: entryNameData,
          crc32: entryInfo.crc32,
          size: entryInfo.size,
          modificationTime: timestamp.time,
          modificationDate: timestamp.date,
          localHeaderOffset: localHeaderOffset
        )
      )
    }

    guard centralDirectoryEntries.count <= Int(UInt16.max),
          currentOffset <= UInt64(UInt32.max) else {
      throw InternalSeriesExportError.archiveTooLarge
    }

    let centralDirectoryOffset = UInt32(currentOffset)
    var centralDirectorySize: UInt64 = 0

    for entry in centralDirectoryEntries {
      let centralDirectoryRecord = centralDirectoryRecordData(for: entry)
      try archiveHandle.write(contentsOf: centralDirectoryRecord)
      currentOffset += UInt64(centralDirectoryRecord.count)
      centralDirectorySize += UInt64(centralDirectoryRecord.count)
    }

    guard centralDirectorySize <= UInt64(UInt32.max) else {
      throw InternalSeriesExportError.archiveTooLarge
    }

    let endOfCentralDirectory = endOfCentralDirectoryData(
      entryCount: UInt16(centralDirectoryEntries.count),
      centralDirectorySize: UInt32(centralDirectorySize),
      centralDirectoryOffset: centralDirectoryOffset
    )
    try archiveHandle.write(contentsOf: endOfCentralDirectory)
  }

  private static func analyzeStoredZipEntry(
    at sourceURL: URL,
    entryName: String
  ) throws -> StoredZipEntryInfo {
    let fileHandle = try FileHandle(forReadingFrom: sourceURL)
    defer {
      try? fileHandle.close()
    }

    let modificationDate = (try? sourceURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
      ?? Date()

    var crc32 = CRC32()
    var size: UInt64 = 0

    while true {
      let chunk = try fileHandle.read(upToCount: zipChunkSize) ?? Data()
      if chunk.isEmpty {
        break
      }

      crc32.update(with: chunk)
      size += UInt64(chunk.count)

      if size > UInt64(UInt32.max) {
        throw InternalSeriesExportError.archiveItemTooLarge(entryName)
      }
    }

    return StoredZipEntryInfo(
      crc32: crc32.finalized,
      size: UInt32(size),
      modificationDate: modificationDate
    )
  }

  private static func streamFile(at sourceURL: URL, to destinationHandle: FileHandle) throws {
    let sourceHandle = try FileHandle(forReadingFrom: sourceURL)
    defer {
      try? sourceHandle.close()
    }

    while true {
      let chunk = try sourceHandle.read(upToCount: zipChunkSize) ?? Data()
      if chunk.isEmpty {
        break
      }
      try destinationHandle.write(contentsOf: chunk)
    }
  }

  private static func localZipHeaderData(
    entryNameData: Data,
    crc32: UInt32,
    size: UInt32,
    modificationTime: UInt16,
    modificationDate: UInt16
  ) -> Data {
    var data = Data()
    data.appendLittleEndian(zipLocalFileHeaderSignature)
    data.appendLittleEndian(zipVersionNeeded)
    data.appendLittleEndian(zipUTF8Flag)
    data.appendLittleEndian(zipStoredCompressionMethod)
    data.appendLittleEndian(modificationTime)
    data.appendLittleEndian(modificationDate)
    data.appendLittleEndian(crc32)
    data.appendLittleEndian(size)
    data.appendLittleEndian(size)
    data.appendLittleEndian(UInt16(entryNameData.count))
    data.appendLittleEndian(UInt16(0))
    data.append(entryNameData)
    return data
  }

  private static func centralDirectoryRecordData(for entry: ZipCentralDirectoryEntry) -> Data {
    var data = Data()
    data.appendLittleEndian(zipCentralDirectoryHeaderSignature)
    data.appendLittleEndian(zipVersionMadeBy)
    data.appendLittleEndian(zipVersionNeeded)
    data.appendLittleEndian(zipUTF8Flag)
    data.appendLittleEndian(zipStoredCompressionMethod)
    data.appendLittleEndian(entry.modificationTime)
    data.appendLittleEndian(entry.modificationDate)
    data.appendLittleEndian(entry.crc32)
    data.appendLittleEndian(entry.size)
    data.appendLittleEndian(entry.size)
    data.appendLittleEndian(UInt16(entry.entryNameData.count))
    data.appendLittleEndian(UInt16(0))
    data.appendLittleEndian(UInt16(0))
    data.appendLittleEndian(UInt16(0))
    data.appendLittleEndian(UInt16(0))
    data.appendLittleEndian(UInt32(0))
    data.appendLittleEndian(entry.localHeaderOffset)
    data.append(entry.entryNameData)
    return data
  }

  private static func endOfCentralDirectoryData(
    entryCount: UInt16,
    centralDirectorySize: UInt32,
    centralDirectoryOffset: UInt32
  ) -> Data {
    var data = Data()
    data.appendLittleEndian(zipEndOfCentralDirectorySignature)
    data.appendLittleEndian(UInt16(0))
    data.appendLittleEndian(UInt16(0))
    data.appendLittleEndian(entryCount)
    data.appendLittleEndian(entryCount)
    data.appendLittleEndian(centralDirectorySize)
    data.appendLittleEndian(centralDirectoryOffset)
    data.appendLittleEndian(UInt16(0))
    return data
  }

  private static func zipTimestamp(for date: Date) -> (date: UInt16, time: UInt16) {
    let calendar = Calendar(identifier: .gregorian)
    let components = calendar.dateComponents(
      [.year, .month, .day, .hour, .minute, .second],
      from: date
    )

    let year = min(max(components.year ?? 1980, 1980), 2107)
    let month = min(max(components.month ?? 1, 1), 12)
    let day = min(max(components.day ?? 1, 1), 31)
    let hour = min(max(components.hour ?? 0, 0), 23)
    let minute = min(max(components.minute ?? 0, 0), 59)
    let second = min(max(components.second ?? 0, 0), 59)

    let dosDate = UInt16(((year - 1980) << 9) | (month << 5) | day)
    let dosTime = UInt16((hour << 11) | (minute << 5) | (second / 2))
    return (date: dosDate, time: dosTime)
  }

  private static func syncUserVisibleJobCopiesNow(for records: [UploadRecord]) {
    guard let jobsRoot = try? ensureJobsDirectory() else { return }

    let groupedByJob = Dictionary(grouping: records) { userVisibleJobFolderName(for: $0) }

    for (jobFolderName, jobRecords) in groupedByJob {
      let jobRoot = jobsRoot.appendingPathComponent(jobFolderName, isDirectory: true)
      let stillsRoot = jobRoot.appendingPathComponent(managedStillsFolderName, isDirectory: true)
      try? ensureDirectory(jobRoot)
      try? ensureDirectory(stillsRoot)
      syncManagedStills(jobRoot: jobRoot, stillsRoot: stillsRoot, records: jobRecords)
    }

    cleanupStaleManagedJobFolders(in: jobsRoot, expectedJobFolderNames: Set(groupedByJob.keys))
  }

  private static func removeUserVisibleJobCopiesNow() {
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let jobsRoot = docs
      .appendingPathComponent("PixCapture", isDirectory: true)
      .appendingPathComponent(jobsFolderName, isDirectory: true)
    guard FileManager.default.fileExists(atPath: jobsRoot.path) else { return }
    try? FileManager.default.removeItem(at: jobsRoot)
  }

  private static func syncManagedStills(jobRoot: URL, stillsRoot: URL, records: [UploadRecord]) {
    let groupedBySeries = Dictionary(grouping: records) { $0.seriesId }
    var expectedSeriesFolderNames = Set<String>()

    for seriesRecords in groupedBySeries.values {
      guard let seed = seriesRecords.sorted(by: { $0.createdAt < $1.createdAt }).first else { continue }
      let seriesFolderName = userVisibleSeriesFolderName(for: seed)
      let seriesFolder = stillsRoot.appendingPathComponent(seriesFolderName, isDirectory: true)
      try? ensureDirectory(seriesFolder)
      expectedSeriesFolderNames.insert(seriesFolderName)

      var expectedFiles = Set<String>()

      for record in seriesRecords.sorted(by: { $0.createdAt < $1.createdAt }) {
        for sourceURL in mirrorSourceURLs(for: record) {
          let destinationURL = seriesFolder.appendingPathComponent(sourceURL.lastPathComponent)
          copyItemIfNeeded(from: sourceURL, to: destinationURL)
          expectedFiles.insert(destinationURL.lastPathComponent)
        }
      }

      if let exifLogURL = seriesRecords.compactMap(\.exifLogURL).first {
        let destinationURL = seriesFolder.appendingPathComponent(exifLogURL.lastPathComponent)
        copyItemIfNeeded(from: exifLogURL, to: destinationURL)
        expectedFiles.insert(destinationURL.lastPathComponent)
      }

      let seriesStatusURL = seriesFolder.appendingPathComponent(seriesStatusFilename)
      writeTextIfNeeded(seriesStatusText(for: seriesRecords), to: seriesStatusURL)
      expectedFiles.insert(seriesStatusURL.lastPathComponent)

      cleanupManagedFiles(in: seriesFolder, expectedFileNames: expectedFiles)
    }

    cleanupStaleSeriesFolders(in: stillsRoot, expectedSeriesFolderNames: expectedSeriesFolderNames)

    let jobStatusURL = jobRoot.appendingPathComponent(jobStatusFilename)
    writeTextIfNeeded(jobStatusText(for: records), to: jobStatusURL)
  }

  private static func mirrorSourceURLs(for record: UploadRecord) -> [URL] {
    var urls: [URL] = []
    urls.append(record.fileURL)

    if let previewURL = ensurePreviewExists(
      for: record.fileURL,
      captureOrientation: record.captureOrientation,
      sensorRollDegrees: record.sensorRollDegrees
    ),
       !urls.contains(where: { $0.standardizedFileURL.path == previewURL.standardizedFileURL.path }) {
      urls.append(previewURL)
    }

    if let depthURL = existingCompanionDepthURL(for: record.fileURL),
       !urls.contains(where: { $0.standardizedFileURL.path == depthURL.standardizedFileURL.path }) {
      urls.append(depthURL)
    }

    return urls.filter { FileManager.default.fileExists(atPath: $0.path) }
  }

  private static func internalExportSourceURLs(for records: [UploadRecord]) -> [URL] {
    var urls: [URL] = []
    var seenPaths = Set<String>()

    for record in records.sorted(by: { $0.createdAt < $1.createdAt }) {
      let candidates = [record.originalFileURL, record.fileURL].compactMap { $0 }
      guard let sourceURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
        continue
      }

      let standardizedPath = sourceURL.standardizedFileURL.path
      guard seenPaths.insert(standardizedPath).inserted else { continue }
      urls.append(sourceURL)

      if let previewURL = ensurePreviewExists(
        for: record.fileURL,
        captureOrientation: record.captureOrientation,
        sensorRollDegrees: record.sensorRollDegrees
      ) {
        let previewPath = previewURL.standardizedFileURL.path
        if seenPaths.insert(previewPath).inserted {
          urls.append(previewURL)
        }
      }

      if let xmpURL = existingCompanionXMPURL(for: record.fileURL) {
        let xmpPath = xmpURL.standardizedFileURL.path
        if seenPaths.insert(xmpPath).inserted {
          urls.append(xmpURL)
        }
      }

      if let depthURL = existingCompanionDepthURL(for: record.fileURL) {
        let depthPath = depthURL.standardizedFileURL.path
        if seenPaths.insert(depthPath).inserted {
          urls.append(depthURL)
        }
      }
    }

    return urls
  }

  private static func recoveryExportItems(
    records: [UploadRecord],
    issues: inout [RecoveryManifestIssue]
  ) -> [RecoveryExportItem] {
    guard let seed = records.sorted(by: { $0.createdAt < $1.createdAt }).first else { return [] }

    let seriesFolderName = userVisibleSeriesFolderName(for: seed)
    var items: [RecoveryExportItem] = []
    var archiveNames = Set<String>()
    var sourcePaths = Set<String>()

    if let exifLogURL = records.compactMap(\.exifLogURL).first,
       FileManager.default.fileExists(atPath: exifLogURL.path) {
      appendRecoveryItem(
        sourceURL: exifLogURL,
        folderName: seriesFolderName,
        kind: "exif-log",
        record: nil,
        archiveNames: &archiveNames,
        sourcePaths: &sourcePaths,
        items: &items
      )
    } else {
      issues.append(
        RecoveryManifestIssue(
          level: "warning",
          message: "EXIF-JSON fehlt fuer Serie \(seed.seriesId.uuidString.lowercased()). Originaldateien werden trotzdem exportiert.",
          recordId: nil,
          seriesId: seed.seriesId.uuidString.lowercased()
        )
      )
    }

    for record in records.sorted(by: { $0.createdAt < $1.createdAt }) {
      let primaryCandidates = [record.originalFileURL, record.fileURL].compactMap { $0 }
      if let primaryURL = primaryCandidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
        appendRecoveryItem(
          sourceURL: primaryURL,
          folderName: seriesFolderName,
          kind: "original",
          record: record,
          archiveNames: &archiveNames,
          sourcePaths: &sourcePaths,
          items: &items
        )
      } else {
        issues.append(
          RecoveryManifestIssue(
            level: "error",
            message: "Originaldatei fehlt lokal: \(record.fileURL.lastPathComponent)",
            recordId: record.id.uuidString.lowercased(),
            seriesId: record.seriesId.uuidString.lowercased()
          )
        )
      }

      if let previewURL = existingCompanionPreviewURL(for: record.fileURL) {
        appendRecoveryItem(
          sourceURL: previewURL,
          folderName: seriesFolderName,
          kind: "preview",
          record: record,
          archiveNames: &archiveNames,
          sourcePaths: &sourcePaths,
          items: &items
        )
      }

      if let xmpURL = existingCompanionXMPURL(for: record.fileURL) {
        appendRecoveryItem(
          sourceURL: xmpURL,
          folderName: seriesFolderName,
          kind: "xmp",
          record: record,
          archiveNames: &archiveNames,
          sourcePaths: &sourcePaths,
          items: &items
        )
      }

      if let depthURL = existingCompanionDepthURL(for: record.fileURL) {
        appendRecoveryItem(
          sourceURL: depthURL,
          folderName: seriesFolderName,
          kind: "depth",
          record: record,
          archiveNames: &archiveNames,
          sourcePaths: &sourcePaths,
          items: &items
        )
      }
    }

    return items
  }

  private static func appendRecoveryItem(
    sourceURL: URL,
    folderName: String,
    kind: String,
    record: UploadRecord?,
    archiveNames: inout Set<String>,
    sourcePaths: inout Set<String>,
    items: inout [RecoveryExportItem]
  ) {
    guard FileManager.default.fileExists(atPath: sourceURL.path) else { return }
    let sourcePath = sourceURL.standardizedFileURL.path
    guard sourcePaths.insert(sourcePath).inserted else { return }

    let filename = uniqueArchiveFilename(
      sourceURL.lastPathComponent,
      existingNames: archiveNames
    )
    let archiveName = "\(folderName)/\(filename)"
    archiveNames.insert(archiveName)
    items.append(
      RecoveryExportItem(
        zipItem: InternalSeriesExportItem(archiveName: archiveName, sourceURL: sourceURL),
        kind: kind,
        record: record
      )
    )
  }

  private static func uniqueArchiveFilename(_ filename: String, existingNames: Set<String>) -> String {
    guard existingNames.allSatisfy({ !$0.hasSuffix("/\(filename)") }) else {
      let basename = (filename as NSString).deletingPathExtension
      let ext = (filename as NSString).pathExtension
      var counter = 2
      while true {
        let candidate = ext.isEmpty ? "\(basename)-\(counter)" : "\(basename)-\(counter).\(ext)"
        if existingNames.allSatisfy({ !$0.hasSuffix("/\(candidate)") }) {
          return candidate
        }
        counter += 1
      }
    }
    return filename
  }

  private static func fileSize(at url: URL) -> Int64? {
    guard let value = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
    return Int64(value)
  }

  private static func recoveryStatusText(
    records: [UploadRecord],
    archiveCount: Int,
    fileCount: Int,
    issues: [RecoveryManifestIssue]
  ) -> String {
    let jobNames = Set(records.map { userVisibleJobFolderName(for: $0) }).sorted()
    let seriesCount = Set(records.map(\.seriesId)).count
    let pending = records.filter { $0.status == .pending }.count
    let uploading = records.filter { $0.status == .uploading }.count
    let uploaded = records.filter { $0.status == .uploaded }.count
    let failed = records.filter { $0.status == .failed }.count

    var lines: [String] = []
    lines.append("PixCapture Recovery Export")
    lines.append("Generated: \(timestampString(from: Date()))")
    lines.append("Jobs: \(jobNames.joined(separator: ", "))")
    lines.append("Series: \(seriesCount)")
    lines.append("Upload Records: \(records.count)")
    lines.append("Exported Files: \(fileCount)")
    lines.append("ZIP Archives: \(archiveCount)")
    lines.append("Status Counts: pending \(pending), uploading \(uploading), uploaded \(uploaded), failed \(failed)")
    lines.append("")
    lines.append("Dieses Paket ist ein Best-Effort-Notexport aus dem lokalen App-Speicher.")
    lines.append("Ein fehlendes JSON/XMP/Preview blockiert nicht die Originaldateien anderer Aufnahmen.")
    lines.append("PIXCAPTURE_RECOVERY_MANIFEST.json enthaelt die genaue Zuordnung.")
    if !issues.isEmpty {
      lines.append("")
      lines.append("Issues:")
      for issue in issues {
        lines.append("- [\(issue.level)] \(issue.message)")
      }
    }
    return lines.joined(separator: "\n") + "\n"
  }

  private static func userVisibleJobFolderName(for record: UploadRecord) -> String {
    let normalizedJobId = record.jobId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !normalizedJobId.isEmpty {
      return sanitizeFilename(normalizedJobId)
    }

    let normalizedLabel = record.jobLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    if normalizedLabel.isEmpty
      || normalizedLabel.compare("Ohne Job", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
      return "Ohne-Job"
    }

    let sanitized = sanitizeFilename(normalizedLabel)
    return sanitized.isEmpty ? "Ohne-Job" : sanitized
  }

  private static func userVisibleSeriesFolderName(for record: UploadRecord) -> String {
    let roomToken = sanitizeFilename(RoomTaxonomy.room(id: record.roomId).displayName)
    let floorToken = sanitizeFilename(FloorTaxonomy.floor(id: record.floorId).displayName)
    let motifToken = "Motif-\(record.seriesIndex)"
    let seriesToken = record.seriesId.uuidString.lowercased()
    return [roomToken, floorToken, motifToken, seriesToken]
      .filter { !$0.isEmpty }
      .joined(separator: "-")
  }

  private static func jobStatusText(for records: [UploadRecord]) -> String {
    let sorted = records.sorted(by: { $0.createdAt < $1.createdAt })
    let seed = sorted.first
    let seriesCount = Set(records.map(\.seriesId)).count
    let uploadedFiles = records.filter { $0.status == .uploaded }.count
    let localOnlyFiles = records.filter { $0.status != .uploaded }.count
    let latestUpload = records.compactMap(\.uploadedAt).max()
    let jobId = seed?.jobId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let jobLabel = seed?.jobLabel.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    var lines: [String] = []
    lines.append("PixCapture Upload Status")
    lines.append("Generated: \(timestampString(from: Date()))")
    lines.append("Job ID: \(jobId.isEmpty ? "-" : jobId)")
    lines.append("Job Label: \(jobLabel.isEmpty ? "Ohne Job" : jobLabel)")
    lines.append("Series: \(seriesCount)")
    lines.append("Files Total: \(records.count)")
    lines.append("Files Uploaded: \(uploadedFiles)")
    lines.append("Files Local Only: \(localOnlyFiles)")
    if let latestUpload {
      lines.append("Last Confirmed Upload: \(timestampString(from: latestUpload))")
    } else {
      lines.append("Last Confirmed Upload: not yet")
    }
    lines.append("Visible Files: \(managedStillsFolderName)/")
    return lines.joined(separator: "\n") + "\n"
  }

  private static func seriesStatusText(for records: [UploadRecord]) -> String {
    let aggregateStatus = aggregateUploadStatus(for: records)
    let latestUpload = records.compactMap(\.uploadedAt).max()
    let seed = records.sorted(by: { $0.createdAt < $1.createdAt }).first

    var lines: [String] = []
    lines.append("PixCapture Series Status")
    lines.append("Series ID: \(seed?.seriesId.uuidString.lowercased() ?? "-")")
    lines.append("Room: \(RoomTaxonomy.room(id: seed?.roomId ?? RoomTaxonomy.defaultRoomId).displayName)")
    lines.append("Floor: \(FloorTaxonomy.floor(id: seed?.floorId ?? FloorTaxonomy.defaultFloorId).displayName)")
    lines.append("Motif: \(seed?.seriesIndex ?? 0)")
    lines.append("Files: \(records.count)")
    lines.append("Status: \(statusDescription(for: aggregateStatus))")
    if let latestUpload {
      lines.append("Server Confirmed: \(timestampString(from: latestUpload))")
    } else {
      lines.append("Server Confirmed: not yet")
    }
    return lines.joined(separator: "\n") + "\n"
  }

  private static func aggregateUploadStatus(for records: [UploadRecord]) -> UploadRecord.Status {
    if records.contains(where: { $0.status == .failed }) { return .failed }
    if records.contains(where: { $0.status == .uploading }) { return .uploading }
    if records.contains(where: { $0.status == .pending }) { return .pending }
    return .uploaded
  }

  private static func statusDescription(for status: UploadRecord.Status) -> String {
    switch status {
    case .pending:
      return "stored locally"
    case .uploading:
      return "upload in progress"
    case .uploaded:
      return "server copy confirmed"
    case .failed:
      return "upload failed, local copy kept"
    }
  }

  private static func timestampString(from date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
  }

  private static func copyItemIfNeeded(from sourceURL: URL, to destinationURL: URL) {
    guard FileManager.default.fileExists(atPath: sourceURL.path) else { return }
    try? ensureDirectory(destinationURL.deletingLastPathComponent())

    if let sourceValues = try? sourceURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
       let destinationValues = try? destinationURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
       FileManager.default.fileExists(atPath: destinationURL.path),
       sourceValues.fileSize == destinationValues.fileSize,
       sourceValues.contentModificationDate == destinationValues.contentModificationDate {
      return
    }

    if FileManager.default.fileExists(atPath: destinationURL.path) {
      try? FileManager.default.removeItem(at: destinationURL)
    }

    do {
      try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
      markExcludedFromBackup(destinationURL)
    } catch {
      return
    }
  }

  private static func writeTextIfNeeded(_ text: String, to url: URL) {
    let data = Data(text.utf8)
    if let existingData = try? Data(contentsOf: url), existingData == data {
      return
    }
    try? ensureDirectory(url.deletingLastPathComponent())
    try? data.write(to: url, options: [.atomic])
    markExcludedFromBackup(url)
  }

  private static func cleanupManagedFiles(in directory: URL, expectedFileNames: Set<String>) {
    let items = (try? FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    )) ?? []

    for item in items {
      let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
      if isDirectory {
        continue
      }
      if !expectedFileNames.contains(item.lastPathComponent) {
        try? FileManager.default.removeItem(at: item)
      }
    }
  }

  private static func cleanupStaleSeriesFolders(in stillsRoot: URL, expectedSeriesFolderNames: Set<String>) {
    let items = (try? FileManager.default.contentsOfDirectory(
      at: stillsRoot,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    )) ?? []

    for item in items {
      let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
      guard isDirectory else { continue }
      if !expectedSeriesFolderNames.contains(item.lastPathComponent) {
        try? FileManager.default.removeItem(at: item)
      }
    }
  }

  private static func cleanupStaleManagedJobFolders(in jobsRoot: URL, expectedJobFolderNames: Set<String>) {
    let items = (try? FileManager.default.contentsOfDirectory(
      at: jobsRoot,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    )) ?? []

    for item in items {
      let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
      guard isDirectory else { continue }
      if !expectedJobFolderNames.contains(item.lastPathComponent) {
        let stillsRoot = item.appendingPathComponent(managedStillsFolderName, isDirectory: true)
        if FileManager.default.fileExists(atPath: stillsRoot.path) {
          try? FileManager.default.removeItem(at: stillsRoot)
        }
        let statusURL = item.appendingPathComponent(jobStatusFilename)
        if FileManager.default.fileExists(atPath: statusURL.path) {
          try? FileManager.default.removeItem(at: statusURL)
        }
      }
    }
  }

  private static func ensureDirectory(_ url: URL) throws {
    if !FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    markExcludedFromBackup(url)
  }

  private static func markExcludedFromBackup(_ url: URL) {
    var mutableURL = url
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? mutableURL.setResourceValues(values)
  }

  private static func makePreviewJPEG(
    from photoURL: URL,
    captureOrientation: String?,
    sensorRollDegrees: Double?
  ) -> Data? {
    let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
    guard let source = CGImageSourceCreateWithURL(photoURL as CFURL, sourceOptions as CFDictionary) else {
      return nil
    }
    let thumbnailOptions: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceThumbnailMaxPixelSize: previewMaxPixelSize,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: false
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
      return nil
    }
    let normalizedImage = normalizePreviewOrientationIfNeeded(
      cgImage,
      captureOrientation: captureOrientation,
      sensorRollDegrees: sensorRollDegrees
    )
    let outputImage = makeOpaquePreviewImageIfNeeded(normalizedImage)
    let recipeMarker = previewRecipeMarker(
      captureOrientation: captureOrientation,
      sensorRollDegrees: sensorRollDegrees
    )
    let previewData = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
      previewData,
      UTType.jpeg.identifier as CFString,
      1,
      nil
    ) else {
      return nil
    }
    let destinationOptions: [CFString: Any] = [
      kCGImageDestinationLossyCompressionQuality: previewJPEGQuality,
      kCGImagePropertyOrientation: 1,
      kCGImagePropertyTIFFDictionary: [
        kCGImagePropertyTIFFImageDescription: recipeMarker
      ]
    ]
    CGImageDestinationAddImage(destination, outputImage, destinationOptions as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      return nil
    }
    return previewData as Data
  }

  private static func shouldCreatePreview(for photoURL: URL) -> Bool {
    previewSourceExtensions.contains(photoURL.pathExtension.lowercased()) && !isPreviewSidecar(photoURL)
  }

  private static func previewNeedsRefresh(
    _ previewURL: URL,
    captureOrientation: String?,
    sensorRollDegrees: Double?
  ) -> Bool {
    guard let source = CGImageSourceCreateWithURL(previewURL as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
      return false
    }
    let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
    let imageDescription = tiff?[kCGImagePropertyTIFFImageDescription] as? String
    let expectedRecipeMarker = previewRecipeMarker(
      captureOrientation: captureOrientation,
      sensorRollDegrees: sensorRollDegrees
    )
    if imageDescription != expectedRecipeMarker {
      return true
    }
    guard let expectedOrientation = inferredPreviewOrientation(
      captureOrientation: captureOrientation,
      sensorRollDegrees: sensorRollDegrees
    ) else { return false }
    let width = (properties[kCGImagePropertyPixelWidth] as? Int) ?? 0
    let height = (properties[kCGImagePropertyPixelHeight] as? Int) ?? 0
    guard width > 0, height > 0 else { return false }
    switch expectedOrientation.aspect {
    case .landscape:
      return width < height
    case .portrait:
      return height < width
    }
  }

  private static func normalizePreviewOrientationIfNeeded(
    _ image: CGImage,
    captureOrientation: String?,
    sensorRollDegrees: Double?
  ) -> CGImage {
    guard let expectedOrientation = inferredPreviewOrientation(
      captureOrientation: captureOrientation,
      sensorRollDegrees: sensorRollDegrees
    ) else {
      return image
    }
    switch expectedOrientation {
    case .portrait:
      guard image.width > image.height else { return image }
      return rotate90Clockwise(image) ?? image
    case .portraitUpsideDown:
      guard image.width > image.height else { return image }
      return rotate90CounterClockwise(image) ?? image
    case .landscapeRight:
      guard image.height > image.width else { return image }
      return rotate90Clockwise(image) ?? image
    case .landscapeLeft:
      guard image.height > image.width else { return image }
      return rotate90CounterClockwise(image) ?? image
    }
  }

  private static func makeOpaquePreviewImageIfNeeded(_ image: CGImage) -> CGImage {
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
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return context.makeImage() ?? image
  }

  private static func rotate90CounterClockwise(_ image: CGImage) -> CGImage? {
    renderRotatedImage(
      image,
      width: image.height,
      height: image.width
    ) { context in
      context.translateBy(x: 0, y: CGFloat(image.width))
      context.rotate(by: -.pi / 2)
    }
  }

  private static func rotate90Clockwise(_ image: CGImage) -> CGImage? {
    renderRotatedImage(
      image,
      width: image.height,
      height: image.width
    ) { context in
      context.translateBy(x: CGFloat(image.height), y: 0)
      context.rotate(by: .pi / 2)
    }
  }

  private static func renderRotatedImage(
    _ image: CGImage,
    width: Int,
    height: Int,
    transform: (CGContext) -> Void
  ) -> CGImage? {
    let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
      return nil
    }
    transform(context)
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return context.makeImage()
  }

  static func inferredPreviewOrientation(
    captureOrientation: String?,
    sensorRollDegrees: Double?
  ) -> PreviewDisplayOrientation? {
    switch captureOrientation {
    case "portrait":
      return .portrait
    case "portraitUpsideDown":
      return .portraitUpsideDown
    case "landscapeLeft":
      return .landscapeLeft
    case "landscapeRight":
      return .landscapeRight
    default:
      break
    }
    if let sensorRollDegrees, sensorRollDegrees.isFinite {
      if abs(sensorRollDegrees) > 45 {
        return sensorRollDegrees < 0 ? .landscapeRight : .landscapeLeft
      }
      return .portrait
    }
    return nil
  }

  private static func previewRecipeMarker(
    captureOrientation: String?,
    sensorRollDegrees: Double?
  ) -> String {
    guard let orientation = inferredPreviewOrientation(
      captureOrientation: captureOrientation,
      sensorRollDegrees: sensorRollDegrees
    ) else {
      return previewRecipeMarkerPrefix
    }
    return "\(previewRecipeMarkerPrefix):\(orientation.rawValue)"
  }

  private static func isPreviewSidecar(_ url: URL) -> Bool {
    url.deletingPathExtension().lastPathComponent.hasSuffix(previewSuffix)
  }

  private static func uniqueFilename(in dir: URL, baseName: String, ext: String) -> String {
    let cleanBase = baseName.isEmpty ? UUID().uuidString : baseName
    let cleanExt = ext.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    var candidate = "\(cleanBase).\(cleanExt)"
    var counter = 2
    while FileManager.default.fileExists(atPath: dir.appendingPathComponent(candidate).path) {
      candidate = "\(cleanBase)-\(counter).\(cleanExt)"
      counter += 1
    }
    return candidate
  }
}

nonisolated private struct StoredZipEntryInfo {
  let crc32: UInt32
  let size: UInt32
  let modificationDate: Date
}

nonisolated private struct ZipCentralDirectoryEntry {
  let entryNameData: Data
  let crc32: UInt32
  let size: UInt32
  let modificationTime: UInt16
  let modificationDate: UInt16
  let localHeaderOffset: UInt32
}

nonisolated private struct CRC32 {
  private static let polynomial: UInt32 = 0xedb88320
  private static let table: [UInt32] = (0..<256).map { index in
    var value = UInt32(index)
    for _ in 0..<8 {
      if (value & 1) == 1 {
        value = polynomial ^ (value >> 1)
      } else {
        value >>= 1
      }
    }
    return value
  }

  private var accumulator: UInt32 = 0xffffffff

  mutating func update(with data: Data) {
    for byte in data {
      let index = Int((accumulator ^ UInt32(byte)) & 0xff)
      accumulator = CRC32.table[index] ^ (accumulator >> 8)
    }
  }

  var finalized: UInt32 {
    accumulator ^ 0xffffffff
  }
}

private extension Data {
  nonisolated mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
    var littleEndianValue = value.littleEndian
    Swift.withUnsafeBytes(of: &littleEndianValue) { rawBuffer in
      append(contentsOf: rawBuffer)
    }
  }
}

nonisolated enum PreviewAspect {
  case portrait
  case landscape
}

nonisolated enum PreviewDisplayOrientation {
  case portrait
  case portraitUpsideDown
  case landscapeLeft
  case landscapeRight

  var rawValue: String {
    switch self {
    case .portrait:
      return "portrait"
    case .portraitUpsideDown:
      return "portraitUpsideDown"
    case .landscapeLeft:
      return "landscapeLeft"
    case .landscapeRight:
      return "landscapeRight"
    }
  }

  var aspect: PreviewAspect {
    switch self {
    case .portrait, .portraitUpsideDown:
      return .portrait
    case .landscapeLeft, .landscapeRight:
      return .landscape
    }
  }
}
