import Foundation
import CryptoKit
import UIKit
import ImageIO
import Security

enum PixcaptureUploadMode: String, Codable {
  case localWifi = "LOCAL_WIFI"
  case directR2 = "DIRECT_R2"
  case webConnect = "WEB_CONNECT"
  case cablePackage = "CABLE_PACKAGE"
  case companionWifi = "COMPANION_WIFI"

  var displayName: String {
    switch self {
    case .localWifi:
      return "Direkt in die Cloud"
    case .directR2:
      return "Direkt ohne Portal-QR"
    case .webConnect:
      return "Web-Connect"
    case .cablePackage:
      return "Kabel-Option"
    case .companionWifi:
      return "WLAN-Option"
    }
  }
}

enum PixcaptureUploadPhase: String, Codable {
  case preparing = "PREPARING"
  case connecting = "CONNECTING"
  case waitingForApproval = "WAITING_FOR_APPROVAL"
  case uploading = "UPLOADING"
  case finalizing = "FINALIZING"
  case completed = "COMPLETED"
  case failed = "FAILED"
}

struct LocalWiFiUploadHandshake: Equatable {
  let sessionId: String
  let transferToken: String
  let expiresAt: String
  let uploadMode: PixcaptureUploadMode
  let ip: String?
  let port: Int?
  let baseURL: String?
}

struct PixcapturePackageKeyMaterial: Equatable {
  let schema: String?
  let packageId: String
  let keyId: String
  let algorithm: String
  let keyBase64: String
  let expiresAt: String?

  var keyData: Data? {
    Data(base64Encoded: keyBase64)
  }
}

struct WebConnectUploadHandshake: Equatable {
  let action: String
  let customerCode: String
  let jobCode: String
  let webSessionId: String
  let endpoint: URL
  let schema: String?
  let jobId: String?
  let namingVersion: String?
  let taxonomyVersion: String?
  let requiresViewId: Bool?
  let companionTransport: String?
  let expiresAt: String?
  let packageKey: PixcapturePackageKeyMaterial?
  let cableReceiverToken: String?

  init(
    action: String,
    customerCode: String,
    jobCode: String,
    webSessionId: String,
    endpoint: URL,
    schema: String? = nil,
    jobId: String? = nil,
    namingVersion: String? = nil,
    taxonomyVersion: String? = nil,
    requiresViewId: Bool? = nil,
    companionTransport: String? = nil,
    expiresAt: String? = nil,
    packageKey: PixcapturePackageKeyMaterial? = nil,
    cableReceiverToken: String? = nil
  ) {
    self.action = action
    self.customerCode = customerCode
    self.jobCode = jobCode
    self.webSessionId = webSessionId
    self.endpoint = endpoint
    self.schema = schema
    self.jobId = jobId
    self.namingVersion = namingVersion
    self.taxonomyVersion = taxonomyVersion
    self.requiresViewId = requiresViewId
    self.companionTransport = companionTransport
    self.expiresAt = expiresAt
    self.packageKey = packageKey
    self.cableReceiverToken = cableReceiverToken
  }
}

struct CompanionWiFiUploadHandshake: Equatable {
  let host: String
  let port: Int
  let useHTTPS: Bool
  let pairingCode: String?

  var baseURL: URL? {
    var components = URLComponents()
    components.scheme = useHTTPS ? "https" : "http"
    components.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
    components.port = port
    return components.url
  }
}

enum PixcaptureUploadConnection {
  case localWiFi(LocalWiFiUploadHandshake)
  case directR2
  case webConnect(WebConnectUploadHandshake)
  case cablePackage(WebConnectUploadHandshake)
  case companionWiFi(CompanionWiFiUploadHandshake)
  case browserCompanion(WebConnectUploadHandshake)

  var mode: PixcaptureUploadMode {
    switch self {
    case .localWiFi:
      return .localWifi
    case .directR2:
      return .directR2
    case .webConnect:
      return .webConnect
    case .cablePackage:
      return .cablePackage
    case .companionWiFi:
      return .companionWifi
    case .browserCompanion:
      return .companionWifi
    }
  }
}

struct PixcaptureUploadProgress {
  let mode: PixcaptureUploadMode
  let phase: PixcaptureUploadPhase
  let filesDone: Int
  let filesTotal: Int
  let bytesSent: Int
  let bytesTotal: Int
  let detail: String?
  let currentFileName: String?

  var fractionCompleted: Double {
    let normalizedBytesTotal = max(bytesTotal, bytesSent)
    if normalizedBytesTotal > 0 {
      return min(max(Double(bytesSent) / Double(normalizedBytesTotal), 0), 1)
    }
    let normalizedFilesTotal = max(filesTotal, filesDone)
    if normalizedFilesTotal > 0 {
      return min(max(Double(filesDone) / Double(normalizedFilesTotal), 0), 1)
    }
    return phase == .completed ? 1 : 0
  }
}

struct PixcapturePackageExportInventory {
  let fileCount: Int
  let totalBytes: Int
  let newestPackageURL: URL?
}

struct UploadFileError: Identifiable, Codable {
  let relativePath: String
  let message: String

  var id: String {
    "\(relativePath)|\(message)"
  }
}

struct PixcaptureUploadResult {
  let uploadedRecordIds: [UUID]
  let failedRecordIds: [UUID]
  let protocolLogs: [UploadProtocolLog]
  let fileErrors: [UploadFileError]
  let localPackageURL: URL?
  let mode: PixcaptureUploadMode?
  let filesDone: Int
  let filesTotal: Int
  let bytesSent: Int
  let bytesTotal: Int
  let verificationFailed: Bool

  init(
    uploadedRecordIds: [UUID],
    failedRecordIds: [UUID],
    protocolLogs: [UploadProtocolLog],
    fileErrors: [UploadFileError] = [],
    localPackageURL: URL? = nil,
    mode: PixcaptureUploadMode? = nil,
    filesDone: Int = 0,
    filesTotal: Int = 0,
    bytesSent: Int = 0,
    bytesTotal: Int = 0,
    verificationFailed: Bool = false
  ) {
    self.uploadedRecordIds = uploadedRecordIds
    self.failedRecordIds = failedRecordIds
    self.protocolLogs = protocolLogs
    self.fileErrors = fileErrors
    self.localPackageURL = localPackageURL
    self.mode = mode
    self.filesDone = filesDone
    self.filesTotal = filesTotal
    self.bytesSent = bytesSent
    self.bytesTotal = bytesTotal
    self.verificationFailed = verificationFailed
  }
}

struct PixcaptureUploadIdentityHint {
  let cust3: String?
  let job5: String?
}

struct UploadProtocolLog: Identifiable, Codable {
  let id: UUID
  let uploadId: String
  let jobId: String
  let createdAt: Date
  let expectedFileCount: Int
  let expectedTotalBytes: Int
  let receivedFileCount: Int
  let receivedTotalBytes: Int
  let complete: Bool
  let mismatches: [UploadProtocolMismatch]
  let manifestPath: String?
  let receiptPath: String?
  let filesDetailed: [UploadProtocolReceiptFile]?
}

struct UploadProtocolMismatch: Codable {
  let fileId: String
  let reason: String
}

extension UploadProtocolMismatch {
  var isCriticalForUploadCompletion: Bool {
    reason.hasPrefix("Receipt fehlt:")
      || reason.contains("receipt_path fehlt")
      || reason.contains("files_detailed fehlt")
      || reason.contains("Session-Mapping")
      || reason.localizedCaseInsensitiveContains("sha256")
      || reason.localizedCaseInsensitiveContains("prüfsumme")
      || reason.localizedCaseInsensitiveContains("groesse")
      || reason.localizedCaseInsensitiveContains("größe")
      || reason.localizedCaseInsensitiveContains("unvollständig")
  }
}

struct UploadProtocolReceiptFile: Codable, Identifiable {
  let itemId: String
  let fileId: String
  let originalFilename: String
  let relativePath: String
  let originalObjectKey: String
  let canonicalFilename: String
  let canonicalObjectKey: String
  let roomId: String?
  let roomName: String?
  let captureType: String
  let captureId: String?
  let captureSubtype: String?
  let roomType: String?
  let roomVariant: Int?
  let sensorData: UploadSessionSensorData?
  let exposureValue: Double?
  let motifIndex: Int?
  let exposureIndex: Int?
  let cameraMetadata: UploadSessionCameraMetadata?
  let videoMetadata: JSONValue?
  let motionMetadata: JSONValue?
  let intrinsicsMetadata: JSONValue?
  let trackingMetadata: JSONValue?
  let floorplanMetadata: JSONValue?
  let fileMetadata: JSONValue?
  let mimeType: String?
  let stylePreset: String?
  let mergedTasks: [String]?
  let checksumSha256: String?
  let sizeBytes: Int?

  var id: String { itemId }

  private enum CodingKeys: String, CodingKey {
    case itemId
    case fileId
    case originalFilename
    case relativePath
    case originalObjectKey
    case canonicalFilename
    case canonicalObjectKey
    case roomId
    case roomName
    case captureType
    case captureId
    case captureSubtype
    case roomType
    case roomVariant
    case sensorData
    case exposureValue
    case motifIndex
    case exposureIndex
    case cameraMetadata
    case videoMetadata
    case motionMetadata
    case intrinsicsMetadata
    case trackingMetadata
    case floorplanMetadata
    case fileMetadata
    case mimeType
    case stylePreset
    case mergedTasks
    case checksumSha256
    case sizeBytes
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    itemId = try container.decodeIfPresent(String.self, forKey: .itemId) ?? UUID().uuidString
    fileId = try container.decodeIfPresent(String.self, forKey: .fileId) ?? itemId
    originalFilename = try container.decodeIfPresent(String.self, forKey: .originalFilename) ?? ""
    relativePath = try container.decodeIfPresent(String.self, forKey: .relativePath) ?? originalFilename
    originalObjectKey = try container.decodeIfPresent(String.self, forKey: .originalObjectKey) ?? ""
    canonicalFilename = try container.decodeIfPresent(String.self, forKey: .canonicalFilename) ?? originalFilename
    canonicalObjectKey = try container.decodeIfPresent(String.self, forKey: .canonicalObjectKey) ?? originalObjectKey
    roomId = try container.decodeIfPresent(String.self, forKey: .roomId)
    roomName = try container.decodeIfPresent(String.self, forKey: .roomName)
    captureType = try container.decodeIfPresent(String.self, forKey: .captureType) ?? "encrypted_package"
    captureId = try container.decodeIfPresent(String.self, forKey: .captureId)
    captureSubtype = try container.decodeIfPresent(String.self, forKey: .captureSubtype)
    roomType = try container.decodeIfPresent(String.self, forKey: .roomType)
    roomVariant = try container.decodeIfPresent(Int.self, forKey: .roomVariant)
    sensorData = try container.decodeIfPresent(UploadSessionSensorData.self, forKey: .sensorData)
    exposureValue = try container.decodeIfPresent(Double.self, forKey: .exposureValue)
    motifIndex = try container.decodeIfPresent(Int.self, forKey: .motifIndex)
    exposureIndex = try container.decodeIfPresent(Int.self, forKey: .exposureIndex)
    cameraMetadata = try container.decodeIfPresent(UploadSessionCameraMetadata.self, forKey: .cameraMetadata)
    videoMetadata = try container.decodeIfPresent(JSONValue.self, forKey: .videoMetadata)
    motionMetadata = try container.decodeIfPresent(JSONValue.self, forKey: .motionMetadata)
    intrinsicsMetadata = try container.decodeIfPresent(JSONValue.self, forKey: .intrinsicsMetadata)
    trackingMetadata = try container.decodeIfPresent(JSONValue.self, forKey: .trackingMetadata)
    floorplanMetadata = try container.decodeIfPresent(JSONValue.self, forKey: .floorplanMetadata)
    fileMetadata = try container.decodeIfPresent(JSONValue.self, forKey: .fileMetadata)
    mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
    stylePreset = try container.decodeIfPresent(String.self, forKey: .stylePreset)
    mergedTasks = try container.decodeIfPresent([String].self, forKey: .mergedTasks)
    checksumSha256 = try container.decodeIfPresent(String.self, forKey: .checksumSha256)
    sizeBytes = try container.decodeIfPresent(Int.self, forKey: .sizeBytes)
  }
}

enum PixcaptureUploadError: LocalizedError {
  case missingAuth
  case noPendingFiles
  case metadataPending
  case qrExpired
  case api(String)
  case apiStatus(code: Int, message: String)
  case invalidResponse
  case invalidResponseDetail(String)

  var errorDescription: String? {
    switch self {
    case .missingAuth:
      return NSLocalizedString("upload.error.authIncomplete", comment: "")
    case .noPendingFiles:
      return NSLocalizedString("upload.error.noPendingFiles", comment: "")
    case .metadataPending:
      return NSLocalizedString("upload.error.metadataPending", comment: "")
    case .qrExpired:
      return NSLocalizedString("upload.error.qrExpired", comment: "")
    case .api(let message):
      return message
    case .apiStatus(_, let message):
      return message
    case .invalidResponse:
      return NSLocalizedString("upload.error.invalidServerResponse", comment: "")
    case .invalidResponseDetail(let message):
      return message
    }
  }
}

struct PhotoUploadIndices: Equatable {
  let motifIndex: Int
  let exposureIndex: Int
}

func resolvePhotoUploadIndices(records: [UploadRecord]) -> [UUID: PhotoUploadIndices] {
  let recordsBySeries = Dictionary(grouping: records, by: \.seriesId)
  var indicesByRecordId: [UUID: PhotoUploadIndices] = [:]
  indicesByRecordId.reserveCapacity(records.count)

  for seriesRecords in recordsBySeries.values {
    let sortedSeriesRecords = seriesRecords.sorted { lhs, rhs in
      if lhs.exposureEV == rhs.exposureEV {
        let leftName = lhs.fileURL.lastPathComponent
        let rightName = rhs.fileURL.lastPathComponent
        if leftName == rightName {
          let leftPath = lhs.fileURL.standardizedFileURL.path
          let rightPath = rhs.fileURL.standardizedFileURL.path
          if leftPath == rightPath {
            return lhs.id.uuidString.lowercased() < rhs.id.uuidString.lowercased()
          }
          return leftPath < rightPath
        }
        return leftName < rightName
      }
      return lhs.exposureEV < rhs.exposureEV
    }

    for (index, record) in sortedSeriesRecords.enumerated() {
      indicesByRecordId[record.id] = PhotoUploadIndices(
        motifIndex: max(1, record.seriesIndex),
        exposureIndex: index + 1
      )
    }
  }

  return indicesByRecordId
}

final class PixcaptureUploadService {
  private static func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), arguments: arguments)
  }

  private enum UploadTransportPolicy {
    case allowsCellular
    case wifiOnly
  }

  private struct UploadSessionManifestNamingOverride {
    let cust3: String?
    let job5: String?
  }

  private let baseURL = URL(string: "https://api.pixcapture.app")!
  private let checksumBestEffortLimitBytes = 150 * 1024 * 1024
  private let directUploadMaxBytes = 100 * 1024 * 1024
  private let targetMultipartPartBytes = 200 * 1024 * 1024
  private let finalizeTolerancePercent = 1
  private let customerCodeStoragePrefix = "pixcapture.customer3Code."
  private let webConnectHandshakeSchema = "pixcapture.mobile-handshake.v2"
  private let webConnectNamingVersion = "capture-v2"
  private let webConnectPollIntervalNanos: UInt64 = 2_000_000_000
  private let webConnectPollTimeoutNanos: UInt64 = 10 * 60 * 1_000_000_000
  private let retryBackoffNanos: [UInt64] = [500_000_000, 1_500_000_000, 4_000_000_000]
  private var transportPolicy: UploadTransportPolicy = .allowsCellular
  private lazy var cellularCapableSession: URLSession = {
    let configuration = URLSessionConfiguration.default
    configuration.allowsCellularAccess = true
    if #available(iOS 13.0, *) {
      configuration.allowsExpensiveNetworkAccess = true
      configuration.allowsConstrainedNetworkAccess = true
    }
    return URLSession(configuration: configuration)
  }()
  private lazy var wifiOnlySession: URLSession = {
    let configuration = URLSessionConfiguration.default
    configuration.allowsCellularAccess = false
    if #available(iOS 13.0, *) {
      configuration.allowsExpensiveNetworkAccess = false
      configuration.allowsConstrainedNetworkAccess = false
    }
    return URLSession(configuration: configuration)
  }()

  static func exportedPackageInventory() -> PixcapturePackageExportInventory {
    let root = exportedPackageDirectoryURL()
    let packageURLs = exportedPackageURLs(in: root)
    var totalBytes = 0
    var newest: (url: URL, date: Date)?

    for url in packageURLs {
      guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else {
        continue
      }
      totalBytes += values.fileSize ?? 0
      let modifiedAt = values.contentModificationDate ?? .distantPast
      if newest == nil || modifiedAt > newest!.date {
        newest = (url, modifiedAt)
      }
    }

    return PixcapturePackageExportInventory(
      fileCount: packageURLs.count,
      totalBytes: totalBytes,
      newestPackageURL: newest?.url
    )
  }

  static func deleteExportedPackages() throws {
    let root = exportedPackageDirectoryURL()
    for url in exportedPackageURLs(in: root) {
      try FileManager.default.removeItem(at: url)
    }
  }

  private var networkSession: URLSession {
    switch transportPolicy {
    case .allowsCellular:
      return cellularCapableSession
    case .wifiOnly:
      return wifiOnlySession
    }
  }

  private func makeProgress(
    mode: PixcaptureUploadMode,
    phase: PixcaptureUploadPhase,
    filesDone: Int = 0,
    filesTotal: Int = 0,
    bytesSent: Int = 0,
    bytesTotal: Int = 0,
    detail: String? = nil,
    currentFileName: String? = nil
  ) -> PixcaptureUploadProgress {
    PixcaptureUploadProgress(
      mode: mode,
      phase: phase,
      filesDone: filesDone,
      filesTotal: max(filesTotal, filesDone),
      bytesSent: bytesSent,
      bytesTotal: max(bytesTotal, bytesSent),
      detail: detail,
      currentFileName: currentFileName
    )
  }

  func uploadPending(
    records: [UploadRecord],
    token: String,
    userId: String,
    webSessionId: String? = nil,
    allowsCellularAccess: Bool = true
  ) async throws -> PixcaptureUploadResult {
    if let webSessionId, !webSessionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return try await uploadPending(
        records: records,
        token: token,
        userId: userId,
        connection: .webConnect(
          WebConnectUploadHandshake(
            action: "connect",
            customerCode: "",
            jobCode: "",
            webSessionId: webSessionId,
            endpoint: baseURL
          )
        ),
        progress: nil,
        allowsCellularAccess: allowsCellularAccess
      )
    }
    return try await uploadPending(
      records: records,
      token: token,
      userId: userId,
      connection: .directR2,
      progress: nil,
      allowsCellularAccess: allowsCellularAccess
    )
  }

  func uploadPending(
    records: [UploadRecord],
    token: String,
    userId: String,
    connection: PixcaptureUploadConnection,
    progress: ((PixcaptureUploadProgress) -> Void)?,
    identityHintsByJobId: [String: PixcaptureUploadIdentityHint] = [:],
    allowsCellularAccess: Bool = true
  ) async throws -> PixcaptureUploadResult {
    let previousTransportPolicy = transportPolicy
    transportPolicy = allowsCellularAccess ? .allowsCellular : .wifiOnly
    defer {
      transportPolicy = previousTransportPolicy
    }

    let uploadableRecords = records.filter { isUploadableRecord($0, connection: connection) }
    let metadataReadyCandidates = uploadableRecords.filter(hasRequiredMetadata)
    let missingLocalRecords = metadataReadyCandidates.filter { !hasLocalUploadSource($0) }
    let candidates = metadataReadyCandidates.filter(hasLocalUploadSource)
    guard !candidates.isEmpty else {
      if !missingLocalRecords.isEmpty {
        return PixcaptureUploadResult(
          uploadedRecordIds: [],
          failedRecordIds: missingLocalRecords.map(\.id),
          protocolLogs: [],
          fileErrors: missingLocalRecords.map {
            UploadFileError(
              relativePath: $0.fileURL.lastPathComponent,
              message: "Lokale Originaldatei fehlt. Bitte Altbestand bereinigen oder Motiv neu aufnehmen."
            )
          },
          mode: connection.mode,
          filesDone: 0,
          filesTotal: missingLocalRecords.count,
          bytesSent: 0,
          bytesTotal: 0
        )
      }
      if !uploadableRecords.isEmpty {
        throw PixcaptureUploadError.metadataPending
      }
      throw PixcaptureUploadError.noPendingFiles
    }

    var uploaded: [UUID] = []
    var failed: [UUID] = missingLocalRecords.map(\.id)
    var protocolLogs: [UploadProtocolLog] = []
    var fileErrors: [UploadFileError] = missingLocalRecords.map {
      UploadFileError(
        relativePath: $0.fileURL.lastPathComponent,
        message: "Lokale Originaldatei fehlt. Dieser Record wurde uebersprungen."
      )
    }
    var filesDone = 0
    var filesTotal = missingLocalRecords.count
    var bytesSent = 0
    var bytesTotal = 0

    progress?(
      makeProgress(
        mode: connection.mode,
        phase: .preparing,
        detail: "Upload wird vorbereitet."
      )
    )

    let groups: [String: [UploadRecord]]
    switch connection {
    case .directR2, .cablePackage, .companionWiFi, .browserCompanion:
      groups = Dictionary(grouping: candidates, by: directSyncGroupingToken)
    case .localWiFi, .webConnect:
      groups = Dictionary(grouping: candidates, by: groupingToken)
    }
    if case .cablePackage = connection {
      try cleanupExportedPackagesForNewCableRun()
    }
    for (groupToken, jobRecords) in groups {
      let logicalJobId = resolvedLogicalJobId(for: jobRecords, fallbackGroupToken: groupToken)
      let identityHint = uploadIdentityHint(
        for: logicalJobId,
        records: jobRecords,
        hintsByJobId: identityHintsByJobId
      )
      do {
        let perJob: PixcaptureUploadResult
        switch connection {
        case .webConnect(let handshake):
          try validateWebConnectHandshake(handshake)
          try validateWebConnectIdentity(
            handshake,
            identityHint: identityHint,
            modeLabel: "Web-Connect"
          )
          perJob = try await upload(
            jobId: logicalJobId,
            records: jobRecords,
            token: token,
            userId: userId,
            webSessionId: handshake.webSessionId,
            apiBaseURL: handshake.endpoint,
            identityHint: PixcaptureUploadIdentityHint(
              cust3: handshake.customerCode,
              job5: handshake.jobCode.isEmpty ? identityHint?.job5 : handshake.jobCode
            ),
            progress: progress
          )
        case .localWiFi:
          perJob = try await uploadLocalContractV2(
            jobId: logicalJobId,
            records: jobRecords,
            token: token,
            userId: userId,
            connection: connection,
            progress: progress
          )
        case .directR2:
          perJob = try await upload(
            jobId: logicalJobId,
            records: jobRecords,
            token: token,
            userId: userId,
            webSessionId: nil,
            apiBaseURL: nil,
            identityHint: identityHint,
            progress: progress
          )
        case .cablePackage(let handshake):
          try validateWebConnectHandshake(handshake)
          try validateWebConnectIdentity(
            handshake,
            identityHint: identityHint,
            modeLabel: "Kabel-Option"
          )
          perJob = try await uploadEncryptedPackage(
            jobId: logicalJobId,
            records: jobRecords,
            token: token,
            userId: userId,
            identityHint: PixcaptureUploadIdentityHint(
              cust3: handshake.customerCode.isEmpty ? identityHint?.cust3 : handshake.customerCode,
              job5: handshake.jobCode.isEmpty ? identityHint?.job5 : handshake.jobCode
            ),
            webConnectHandshake: handshake,
            progress: progress
          )
        case .companionWiFi(let handshake):
          perJob = try await uploadEncryptedPackageToCompanion(
            jobId: logicalJobId,
            records: jobRecords,
            token: token,
            userId: userId,
            identityHint: identityHint,
            handshake: handshake,
            progress: progress
          )
        case .browserCompanion(let handshake):
          try validateWebConnectIdentity(
            handshake,
            identityHint: identityHint,
            modeLabel: "WLAN-Option"
          )
          perJob = try await uploadEncryptedPackageToBrowserCompanion(
            jobId: logicalJobId,
            records: jobRecords,
            token: token,
            userId: userId,
            identityHint: identityHint,
            handshake: handshake,
            progress: progress
          )
        }
        uploaded.append(contentsOf: perJob.uploadedRecordIds)
        failed.append(contentsOf: perJob.failedRecordIds)
        protocolLogs.append(contentsOf: perJob.protocolLogs)
        fileErrors.append(contentsOf: perJob.fileErrors)
        filesDone += perJob.filesDone
        filesTotal += perJob.filesTotal
        bytesSent += perJob.bytesSent
        bytesTotal += perJob.bytesTotal
      } catch {
        UploadDebugLog.write("[PIXUPLOAD] job upload failed job=\(logicalJobId) mode=\(connection.mode.rawValue) error=\(failureReason(error))")
        fileErrors.append(
          UploadFileError(
            relativePath: "job:\(logicalJobId)",
            message: failureReason(error)
          )
        )
        if !shouldKeepPendingAfterConnectionError(error) {
          failed.append(contentsOf: jobRecords.map(\.id))
        }
      }
    }

    return PixcaptureUploadResult(
      uploadedRecordIds: uploaded,
      failedRecordIds: failed,
      protocolLogs: protocolLogs,
      fileErrors: fileErrors,
      mode: connection.mode,
      filesDone: filesDone,
      filesTotal: max(filesTotal, filesDone),
      bytesSent: bytesSent,
      bytesTotal: max(bytesTotal, bytesSent)
    )
  }

  private func hasUploadAssignment(_ record: UploadRecord) -> Bool {
    if let jobId = normalizedToken(record.jobId), !jobId.isEmpty {
      return true
    }
    guard let jobLabel = normalizedToken(record.jobLabel), !jobLabel.isEmpty else {
      return false
    }
    return jobLabel.compare("ohne job", options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame
  }

  private func isUploadableRecord(
    _ record: UploadRecord,
    connection: PixcaptureUploadConnection
  ) -> Bool {
    if hasUploadAssignment(record) {
      return true
    }
    switch connection {
    case .cablePackage, .companionWiFi, .browserCompanion, .webConnect:
      return true
    case .directR2, .localWiFi:
      return false
    }
  }

  private func hasRequiredMetadata(_ record: UploadRecord) -> Bool {
    record.metadataReady
  }

  private func hasLocalUploadSource(_ record: UploadRecord) -> Bool {
    FileManager.default.fileExists(atPath: record.fileURL.path)
  }

  private func groupingToken(for record: UploadRecord) -> String {
    if let jobId = normalizedToken(record.jobId), !jobId.isEmpty {
      return "job:\(jobId.lowercased())"
    }
    if let jobLabel = normalizedToken(record.jobLabel), !jobLabel.isEmpty {
      return "label:\(jobLabel.lowercased())"
    }
    return "series:\(record.seriesId.uuidString.lowercased())"
  }

  private func directSyncGroupingToken(for record: UploadRecord) -> String {
    if let localShootId = normalizedToken(record.localShootId) {
      return "shoot:\(localShootId.lowercased())"
    }
    return "series:\(record.seriesId.uuidString.lowercased())"
  }

  private func resolvedLogicalJobId(
    for records: [UploadRecord],
    fallbackGroupToken: String
  ) -> String {
    if let firstJobId = records
      .compactMap({ normalizedToken($0.jobId) })
      .first(where: { !$0.isEmpty }) {
      return firstJobId
    }
    if let firstLabel = records
      .compactMap({ normalizedToken($0.jobLabel) })
      .first(where: { !$0.isEmpty && $0.compare("ohne job", options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame }) {
      return firstLabel
    }
    if let fallbackToken = normalizedToken(fallbackGroupToken),
       fallbackToken.hasPrefix("shoot:") || fallbackToken.hasPrefix("series:") {
      let suffix = fallbackToken.split(separator: ":", maxSplits: 1).last.map(String.init)
      if let suffix, !suffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return suffix
      }
    }
    let fallbackSeriesId = records.first?.seriesId.uuidString.lowercased() ?? UUID().uuidString.lowercased()
    return normalizedToken(fallbackGroupToken) ?? fallbackSeriesId
  }

  private func normalizedToken(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    return value
  }

  private func uploadIdentityHint(
    for logicalJobId: String,
    records: [UploadRecord],
    hintsByJobId: [String: PixcaptureUploadIdentityHint]
  ) -> PixcaptureUploadIdentityHint? {
    let candidateIds = ([logicalJobId] + records.compactMap(\.jobId))
      .compactMap { normalizedToken($0)?.lowercased() }
    for candidateId in candidateIds {
      if let hint = hintsByJobId[candidateId] {
        return hint
      }
    }
    return nil
  }

  private func validateWebConnectIdentity(
    _ handshake: WebConnectUploadHandshake,
    identityHint: PixcaptureUploadIdentityHint?,
    modeLabel: String
  ) throws {
    let qrCustomerCode = normalizedManifestIdentityCode(handshake.customerCode, expectedLength: 3)
    let localCustomerCode = normalizedManifestIdentityCode(identityHint?.cust3, expectedLength: 3)
    if let qrCustomerCode,
       let localCustomerCode,
       qrCustomerCode != localCustomerCode {
      throw PixcaptureUploadError.api(
        String(
          format: NSLocalizedString("upload.error.customerMismatch.format", comment: ""),
          modeLabel,
          qrCustomerCode,
          localCustomerCode
        )
      )
    }

    let qrJobCode = normalizedManifestIdentityCode(handshake.jobCode, expectedLength: 5)
    let localJobCode = normalizedManifestIdentityCode(identityHint?.job5, expectedLength: 5)
    if let qrJobCode,
       let localJobCode,
       qrJobCode != localJobCode {
      throw PixcaptureUploadError.api(
        String(
          format: NSLocalizedString("upload.error.jobMismatch.format", comment: ""),
          modeLabel,
          qrJobCode,
          localJobCode
        )
      )
    }
  }

  private func uploadLocalContractV2(
    jobId: String,
    records: [UploadRecord],
    token: String,
    userId: String,
    connection: PixcaptureUploadConnection,
    progress: ((PixcaptureUploadProgress) -> Void)?
  ) async throws -> PixcaptureUploadResult {
    let preparedTargets = try prepareSessionTargets(jobId: jobId, records: records)
    let recordsById = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
    let shootCode = makeShootCode(jobId: jobId, records: records)
    let customerId = userId.trimmingCharacters(in: .whitespacesAndNewlines)
    let shootId = jobId.trimmingCharacters(in: .whitespacesAndNewlines)
    let items = try makeContractTransferItems(
      preparedTargets: preparedTargets,
      recordsById: recordsById,
      customerId: customerId,
      shootId: shootId,
      shootCode: shootCode
    )
    guard !items.isEmpty else {
      throw PixcaptureUploadError.noPendingFiles
    }

    let manifest = makeExpectedManifest(
      customerId: customerId,
      shootId: shootId,
      shootCode: shootCode,
      items: items
    )
    let manifestData = try encodeExpectedManifest(manifest)
    _ = persistExpectedManifest(manifestData, shootId: shootId)

    var fileStates: [String: ContractTransferState] = [:]
    for item in items {
      fileStates[item.relativePath] = .pending
    }
    var uploadedRecordIds = Set<UUID>()
    var failedRecordIds = Set<UUID>()
    var fileErrors: [UploadFileError] = []
    var filesDone = 0
    var bytesSent = 0
    let filesTotal = items.count
    let expectedTotalBytes = items.reduce(0) { $0 + $1.sizeBytes }
    let sortedItems = items.sorted { lhs, rhs in
      if lhs.sizeBytes == rhs.sizeBytes {
        return lhs.relativePath < rhs.relativePath
      }
      return lhs.sizeBytes < rhs.sizeBytes
    }

    var progressPhase: PixcaptureUploadPhase = .connecting
    var progressDetail: String = {
      switch connection {
      case .localWiFi:
        return "Verbinde lokalen Empfaenger."
      case .directR2:
        return "Bereite Direkt-Upload vor."
      case .webConnect:
        return "Bereite Web-Connect vor."
      case .cablePackage:
        return "Bereite verschluesseltes Paket vor."
      case .companionWiFi:
        return "Bereite Paket fuer diesen Rechner vor."
      case .browserCompanion:
        return "Bereite Verbindung zu diesem Rechner vor."
      }
    }()
    var currentFileName: String?

    func emitProgress() {
      progress?(
        makeProgress(
          mode: connection.mode,
          phase: progressPhase,
          filesDone: filesDone,
          filesTotal: filesTotal,
          bytesSent: bytesSent,
          bytesTotal: expectedTotalBytes,
          detail: progressDetail,
          currentFileName: currentFileName
        )
      )
    }

    emitProgress()

    switch connection {
    case .localWiFi(let handshake):
      try validateLocalWiFiHandshake(handshake)
      let localBaseURL = try resolveLocalWiFiBaseURL(handshake)
      try await sendLocalExpectedManifest(
        baseURL: localBaseURL,
        handshake: handshake,
        data: manifestData
      )
      progressPhase = .uploading
      progressDetail = "Verbindung hergestellt. Dateien werden lokal uebertragen."
      currentFileName = nil
      emitProgress()

      for item in sortedItems {
        fileStates[item.relativePath] = .uploading
        currentFileName = item.relativePath
        progressDetail = "Uebertrage \(item.relativePath)"
        emitProgress()
        do {
          try await retryUploadOperation {
            try await self.sendLocalFile(
              baseURL: localBaseURL,
              handshake: handshake,
              item: item
            )
          }
          fileStates[item.relativePath] = .done
          if let recordId = item.recordId {
            uploadedRecordIds.insert(recordId)
          }
          filesDone += 1
          bytesSent += item.sizeBytes
        } catch {
          fileStates[item.relativePath] = .failed
          if let recordId = item.recordId {
            failedRecordIds.insert(recordId)
          }
          fileErrors.append(
            UploadFileError(relativePath: item.relativePath, message: failureReason(error))
          )
        }
        emitProgress()
      }

    case .directR2:
      let session = try await startDirectR2Session(customerId: customerId, shootId: shootId, token: token)
      let sessionId = session.sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !sessionId.isEmpty else {
        throw invalidResponse("Direkt-Upload-Session ohne sessionId.")
      }
      if let expiresAt = session.expiresAt,
         let expiresDate = parseIsoDate(expiresAt),
         expiresDate < Date() {
        throw PixcaptureUploadError.api("Upload-Session abgelaufen. Bitte erneut starten.")
      }

      try await registerExpectedManifest(
        sessionId: sessionId,
        manifestData: manifestData,
        token: token
      )
      progressPhase = .uploading
      progressDetail = "Verbindung hergestellt. Dateien werden direkt uebertragen."
      currentFileName = nil
      emitProgress()

      var signedURLCache = Dictionary(uniqueKeysWithValues: session.signedURLs.map { ($0.relativePath, $0) })

      for item in sortedItems {
        fileStates[item.relativePath] = .uploading
        currentFileName = item.relativePath
        progressDetail = "Uebertrage \(item.relativePath)"
        emitProgress()
        do {
          let signedURL = try await resolveSignedURL(
            sessionId: sessionId,
            item: item,
            token: token,
            cache: &signedURLCache
          )

          let response = try await retryUploadOperation {
            try await self.putTransferItem(item: item, signedURL: signedURL)
          }

          let etag = extractETag(from: response)
          try await retryUploadOperation {
            try await self.markDirectFileUploaded(
              sessionId: sessionId,
              item: item,
              etag: etag,
              token: token
            )
          }

          fileStates[item.relativePath] = .done
          if let recordId = item.recordId {
            uploadedRecordIds.insert(recordId)
          }
          filesDone += 1
          bytesSent += item.sizeBytes
        } catch {
          fileStates[item.relativePath] = .failed
          if let recordId = item.recordId {
            failedRecordIds.insert(recordId)
          }
          fileErrors.append(
            UploadFileError(relativePath: item.relativePath, message: failureReason(error))
          )
        }
        emitProgress()
      }
    case .cablePackage:
      throw PixcaptureUploadError.api("Die Kabel-Option nutzt den verschluesselten Package-Upload-Flow.")
    case .companionWiFi:
      throw PixcaptureUploadError.api("Die WLAN-Option nutzt den verschluesselten Package-Upload-Flow.")
    case .browserCompanion:
      throw PixcaptureUploadError.api("Die WLAN-Option nutzt den verschluesselten Package-Upload-Flow.")
    case .webConnect:
      throw PixcaptureUploadError.api("Web-Connect nutzt den Upload-Session-Flow.")
    }

    let unresolvedRecords = records
      .filter { !uploadedRecordIds.contains($0.id) }
      .map(\.id)
    for recordId in unresolvedRecords {
      if !uploadedRecordIds.contains(recordId) {
        failedRecordIds.insert(recordId)
      }
    }

    let protocolLog = UploadProtocolLog(
      id: UUID(),
      uploadId: shootId,
      jobId: jobId,
      createdAt: Date(),
      expectedFileCount: filesTotal,
      expectedTotalBytes: expectedTotalBytes,
      receivedFileCount: filesDone,
      receivedTotalBytes: bytesSent,
      complete: fileErrors.isEmpty && filesDone == filesTotal,
      mismatches: fileErrors.map {
        UploadProtocolMismatch(fileId: $0.relativePath, reason: $0.message)
      },
      manifestPath: nil,
      receiptPath: nil,
      filesDetailed: nil
    )

    return PixcaptureUploadResult(
      uploadedRecordIds: Array(uploadedRecordIds),
      failedRecordIds: Array(failedRecordIds),
      protocolLogs: [protocolLog],
      fileErrors: fileErrors,
      mode: connection.mode,
      filesDone: filesDone,
      filesTotal: filesTotal,
      bytesSent: bytesSent,
      bytesTotal: expectedTotalBytes
    )
  }

  private func retryUploadOperation<T>(
    maxRetries: Int = 3,
    operation: () async throws -> T
  ) async throws -> T {
    var attempt = 0
    while true {
      do {
        return try await operation()
      } catch {
        if attempt >= maxRetries || !shouldRetryUploadOperation(after: error) {
          throw error
        }
        let delay = retryBackoffNanos[min(attempt, retryBackoffNanos.count - 1)]
        attempt += 1
        try await Task.sleep(nanoseconds: delay)
      }
    }
  }

  private func validateLocalWiFiHandshake(_ handshake: LocalWiFiUploadHandshake) throws {
    let sessionId = handshake.sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
    let transferToken = handshake.transferToken.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sessionId.isEmpty, !transferToken.isEmpty else {
      throw PixcaptureUploadError.api(NSLocalizedString("upload.error.qrIncomplete", comment: ""))
    }
    guard handshake.uploadMode == .localWifi else {
      throw PixcaptureUploadError.api(NSLocalizedString("upload.error.qrWrongMode", comment: ""))
    }
    guard let expiresAt = parseIsoDate(handshake.expiresAt) else {
      throw PixcaptureUploadError.api(NSLocalizedString("upload.error.qrExpiryInvalid", comment: ""))
    }
    if expiresAt < Date() {
      throw PixcaptureUploadError.qrExpired
    }
  }

  private func validateWebConnectHandshake(_ handshake: WebConnectUploadHandshake) throws {
    let sessionId = handshake.webSessionId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sessionId.isEmpty else {
      throw PixcaptureUploadError.api(NSLocalizedString("upload.error.connectQRIncomplete", comment: ""))
    }
    if let expiresAt = handshake.expiresAt?.trimmingCharacters(in: .whitespacesAndNewlines),
       !expiresAt.isEmpty {
      guard let expiresDate = parseIsoDate(expiresAt) else {
        throw PixcaptureUploadError.api("CONNECT-QR enthaelt kein gueltiges Ablaufdatum.")
      }
      if expiresDate < Date() {
        throw PixcaptureUploadError.qrExpired
      }
    }
    if let schema = handshake.schema?.trimmingCharacters(in: .whitespacesAndNewlines),
       !schema.isEmpty,
       schema != "pixcapture.connect-qr.v2" {
      throw PixcaptureUploadError.api(NSLocalizedString("upload.error.connectQRSchema", comment: ""))
    }
    if let namingVersion = handshake.namingVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
       !namingVersion.isEmpty,
       namingVersion != webConnectNamingVersion {
      throw PixcaptureUploadError.api(NSLocalizedString("upload.error.connectQRNaming", comment: ""))
    }
    if handshake.requiresViewId == true {
      throw PixcaptureUploadError.api(NSLocalizedString("upload.error.connectQRViewId", comment: ""))
    }
  }

  private func resolveLocalWiFiBaseURL(_ handshake: LocalWiFiUploadHandshake) throws -> URL {
    if let raw = handshake.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines),
       !raw.isEmpty,
       let url = URL(string: raw) {
      return url
    }
    if let ip = handshake.ip?.trimmingCharacters(in: .whitespacesAndNewlines),
       !ip.isEmpty {
      var components = URLComponents()
      components.scheme = "http"
      components.host = ip
      if let port = handshake.port {
        components.port = port
      }
      if let url = components.url {
        return url
      }
    }
    return baseURL
  }

  private func sendLocalExpectedManifest(
    baseURL: URL,
    handshake: LocalWiFiUploadHandshake,
    data: Data
  ) async throws {
    let endpoint = baseURL
      .appendingPathComponent("local-upload")
      .appendingPathComponent(handshake.sessionId)
      .appendingPathComponent("expected-manifest")

    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    applyLocalHandshakeHeaders(&request, handshake: handshake)
    request.httpBody = data

    let (_, response) = try await networkSession.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw invalidResponse("Lokaler Manifest-Upload lieferte keinen HTTP-Status.")
    }
    guard (200...299).contains(http.statusCode) else {
      throw PixcaptureUploadError.apiStatus(code: http.statusCode, message: "Manifest-Upload fehlgeschlagen.")
    }
  }

  private func sendLocalFile(
    baseURL: URL,
    handshake: LocalWiFiUploadHandshake,
    item: ContractTransferItem
  ) async throws {
    let endpoint = baseURL
      .appendingPathComponent("local-upload")
      .appendingPathComponent(handshake.sessionId)
      .appendingPathComponent("file")
    var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
    components?.queryItems = [URLQueryItem(name: "path", value: item.relativePath)]
    guard let finalURL = components?.url else {
      throw invalidResponse("Lokale Upload-URL für \(item.relativePath) ist ungültig.")
    }

    var request = URLRequest(url: finalURL)
    request.httpMethod = "POST"
    request.setValue(item.mimeType, forHTTPHeaderField: "Content-Type")
    request.setValue("\(item.sizeBytes)", forHTTPHeaderField: "Content-Length")
    applyLocalHandshakeHeaders(&request, handshake: handshake)

    let response: URLResponse
    if let uploadData = item.uploadData {
      request.httpBody = uploadData
      (_, response) = try await networkSession.data(for: request)
    } else {
      (_, response) = try await networkSession.upload(for: request, fromFile: item.fileURL)
    }

    guard let http = response as? HTTPURLResponse else {
      throw invalidResponse("Lokaler Datei-Upload für \(item.relativePath) lieferte keinen HTTP-Status.")
    }
    guard (200...299).contains(http.statusCode) else {
      throw PixcaptureUploadError.apiStatus(code: http.statusCode, message: "Datei-Upload fehlgeschlagen.")
    }
  }

  private func applyLocalHandshakeHeaders(_ request: inout URLRequest, handshake: LocalWiFiUploadHandshake) {
    request.setValue(handshake.transferToken, forHTTPHeaderField: "X-Transfer-Token")
    request.setValue(handshake.sessionId, forHTTPHeaderField: "X-Session-Id")
    request.setValue("Bearer \(handshake.transferToken)", forHTTPHeaderField: "Authorization")
  }

  private func startDirectR2Session(
    customerId: String,
    shootId: String,
    token: String
  ) async throws -> DirectR2SessionStartResponse {
    try await apiRequest(
      path: "/api/sessions/direct",
      method: "POST",
      token: token,
      body: DirectR2SessionStartRequest(
        customer_id: customerId,
        shoot_id: shootId
      )
    )
  }

  private func registerExpectedManifest(
    sessionId: String,
    manifestData: Data,
    token: String
  ) async throws {
    try await apiRequestVoid(
      path: "/api/sessions/\(sessionId)/expected-manifest",
      method: "POST",
      token: token,
      rawBody: manifestData
    )
  }

  private func resolveSignedURL(
    sessionId: String,
    item: ContractTransferItem,
    token: String,
    cache: inout [String: DirectR2SignedURL]
  ) async throws -> DirectR2SignedURL {
    if let cached = cache[item.relativePath] {
      return cached
    }

    let requestBody = DirectR2SignedURLRequest(
      relative_path: item.relativePath,
      size_bytes: item.sizeBytes
    )
    let candidates = [
      "/api/sessions/\(sessionId)/files/signed-url",
      "/api/sessions/\(sessionId)/files/presign",
      "/api/sessions/\(sessionId)/files/sign"
    ]

    for path in candidates {
      if let resolved = try? await fetchSignedURL(path: path, token: token, body: requestBody) {
        cache[item.relativePath] = resolved
        return resolved
      }
    }

    throw PixcaptureUploadError.api("Keine Signed URL für \(item.relativePath) verfügbar.")
  }

  private func fetchSignedURL(
    path: String,
    token: String,
    body: DirectR2SignedURLRequest
  ) async throws -> DirectR2SignedURL {
    let response: DirectR2SignedURLResponse = try await apiRequest(
      path: path,
      method: "POST",
      token: token,
      body: body
    )
    if let signed = response.toSignedURL() {
      return signed
    }
    throw invalidResponse("Signed-URL-Antwort fuer \(body.relative_path) enthält keine Upload-URL.")
  }

  private func putTransferItem(
    item: ContractTransferItem,
    signedURL: DirectR2SignedURL
  ) async throws -> HTTPURLResponse {
    guard let uploadURL = URL(string: signedURL.url) else {
      throw invalidResponse("Signed URL fuer \(item.relativePath) ist ungültig.")
    }
    var request = URLRequest(url: uploadURL)
    request.httpMethod = "PUT"
    request.setValue(item.mimeType, forHTTPHeaderField: "Content-Type")
    request.setValue("\(item.sizeBytes)", forHTTPHeaderField: "Content-Length")
    for (header, value) in signedURL.headers {
      if request.value(forHTTPHeaderField: header) == nil {
        request.setValue(value, forHTTPHeaderField: header)
      }
    }

    let response: URLResponse
    if let uploadData = item.uploadData {
      request.httpBody = uploadData
      (_, response) = try await networkSession.data(for: request)
    } else {
      (_, response) = try await networkSession.upload(for: request, fromFile: item.fileURL)
    }

    guard let http = response as? HTTPURLResponse else {
      throw invalidResponse("Datei-Upload fuer \(item.relativePath) lieferte keinen HTTP-Status.")
    }
    guard (200...299).contains(http.statusCode) else {
      throw PixcaptureUploadError.apiStatus(
        code: http.statusCode,
        message: "Upload fehlgeschlagen (\(http.statusCode))."
      )
    }
    return http
  }

  private func markDirectFileUploaded(
    sessionId: String,
    item: ContractTransferItem,
    etag: String?,
    token: String
  ) async throws {
    try await apiRequestVoid(
      path: "/api/sessions/\(sessionId)/files/mark-uploaded",
      method: "POST",
      token: token,
      body: DirectR2MarkUploadedRequest(
        relative_path: item.relativePath,
        size_bytes: item.sizeBytes,
        sha256: item.sha256,
        etag: etag
      )
    )
  }

  private func upload(
    jobId: String,
    records: [UploadRecord],
    token: String,
    userId: String,
    webSessionId: String?,
    apiBaseURL: URL?,
    identityHint: PixcaptureUploadIdentityHint?,
    progress: ((PixcaptureUploadProgress) -> Void)?
  ) async throws -> PixcaptureUploadResult {
    let preparedTargets = try prepareSessionTargets(jobId: jobId, records: records)
    let photoRecordIds = records.map(\.id)
    let plannedBytes = preparedTargets.reduce(0) { $0 + $1.sizeBytes }

    let normalizedWebSessionId = webSessionId?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if let webSession = normalizedWebSessionId, !webSession.isEmpty {
      progress?(
        makeProgress(
          mode: .webConnect,
          phase: .connecting,
          filesDone: 0,
          filesTotal: preparedTargets.count,
          bytesSent: 0,
          bytesTotal: plannedBytes,
          detail: "Verbinde Upload mit Browser-Session."
        )
      )
      let context = try await createUploadSessionContextViaWebConnect(
        jobId: jobId,
        preparedTargets: preparedTargets,
        token: token,
        userId: userId,
        webSessionId: webSession,
        apiBaseURL: apiBaseURL,
        identityHint: identityHint,
        progress: progress
      )
      return await uploadViaSession(
        context: context,
        jobId: jobId,
        preparedTargets: preparedTargets,
        photoRecordIds: photoRecordIds,
        token: token,
        apiBaseURL: apiBaseURL,
        mode: .webConnect,
        progress: progress
      )
    }

    progress?(
      makeProgress(
        mode: .directR2,
        phase: .connecting,
        filesDone: 0,
        filesTotal: preparedTargets.count,
        bytesSent: 0,
        bytesTotal: plannedBytes,
        detail: "Erzeuge Upload-Session."
      )
    )

    let context = try await createUploadSessionContext(
      jobId: jobId,
      preparedTargets: preparedTargets,
      token: token,
      userId: userId,
      identityHint: identityHint
    )

    return await uploadViaSession(
      context: context,
      jobId: jobId,
      preparedTargets: preparedTargets,
      photoRecordIds: records.map(\.id),
      token: token,
      apiBaseURL: nil,
      mode: .directR2,
      progress: progress
    )
  }

  private func uploadEncryptedPackage(
    jobId: String,
    records: [UploadRecord],
    token: String,
    userId: String,
    identityHint: PixcaptureUploadIdentityHint?,
    webConnectHandshake: WebConnectUploadHandshake,
    progress: ((PixcaptureUploadProgress) -> Void)?
  ) async throws -> PixcaptureUploadResult {
    UploadDebugLog.write("[PIXUPLOAD] cablePackage begin job=\(jobId) session=\(webConnectHandshake.webSessionId) records=\(records.count)")
    guard webConnectHandshake.companionTransport == "cable_package" else {
      throw PixcaptureUploadError.api("Bitte zuerst den Kabel-QR aus dem Web-Portal scannen.")
    }
    let preparedTargets = try prepareSessionTargets(jobId: jobId, records: records)
    guard !preparedTargets.isEmpty else {
      UploadDebugLog.write("[PIXUPLOAD] cablePackage no prepared targets")
      throw PixcaptureUploadError.noPendingFiles
    }

    let sourceBytes = preparedTargets.reduce(0) { $0 + $1.sizeBytes }
    UploadDebugLog.write("[PIXUPLOAD] cablePackage prepared targets=\(preparedTargets.count) sourceBytes=\(sourceBytes)")
    let manifest = makeUploadSessionManifest(
      jobId: jobId,
      userId: userId,
      preparedTargets: preparedTargets,
      webConnectHandshake: webConnectHandshake,
      namingOverride: identityHint.map {
        UploadSessionManifestNamingOverride(cust3: $0.cust3, job5: $0.job5)
      }
    )
    await postCableCompanionTransferSignal(
      handshake: webConnectHandshake,
      payload: [
        "status": "phone_preparing",
        "bytesExpected": sourceBytes,
        "bytesReceived": 0,
        "motifCount": Set(preparedTargets.map(\.capture.captureId)).count,
        "technicalFileCount": preparedTargets.count,
        "sourceTotalBytes": sourceBytes
      ]
    )

    guard let packageKey = webConnectHandshake.packageKey else {
      throw PixcaptureUploadError.api(
        NSLocalizedString("upload.error.cableMaterial", comment: "")
      )
    }
    UploadDebugLog.write("[PIXUPLOAD] cablePackage sessionKey packageId=\(packageKey.packageId) keyId=\(packageKey.keyId)")
    progress?(
      makeProgress(
        mode: .cablePackage,
        phase: .preparing,
        filesDone: 0,
        filesTotal: 1,
        bytesSent: 0,
        bytesTotal: sourceBytes,
        detail: "Bereite das lokale Kabel-Paket vor."
      )
    )

    guard packageKey.algorithm.uppercased() == "AES-256-GCM" else {
      throw invalidResponse(NSLocalizedString("upload.error.cableAlgorithm", comment: ""))
    }
    guard let keyData = packageKey.keyData, keyData.count == 32 else {
      throw invalidResponse("Kabel-Paketmaterial enthält keinen gueltigen Paket-Schluessel.")
    }

    progress?(
      makeProgress(
        mode: .cablePackage,
        phase: .preparing,
        filesDone: 0,
        filesTotal: 1,
        bytesSent: 0,
        bytesTotal: sourceBytes,
        detail: NSLocalizedString("upload.progress.creatingEncryptedPackage", comment: "")
      )
    )

    let packageURL = try writeEncryptedPackage(
      jobId: jobId,
      manifest: manifest,
      preparedTargets: preparedTargets,
      packageId: packageKey.packageId,
      keyId: packageKey.keyId,
      keyData: keyData,
      exportToDocuments: true
    )
    let packageSize = try fileSizeBytes(packageURL)
    let packageChecksum = try sha256Hex(fileURL: packageURL)
    let packageFilename = packageURL.lastPathComponent
    await postCableCompanionTransferSignal(
      handshake: webConnectHandshake,
      payload: [
        "status": "phone_package_ready",
        "filename": packageFilename,
        "packageId": packageKey.packageId,
        "keyId": packageKey.keyId,
        "sha256": packageChecksum,
        "bytesExpected": packageSize,
        "bytesReceived": 0,
        "motifCount": Set(preparedTargets.map(\.capture.captureId)).count,
        "technicalFileCount": preparedTargets.count,
        "sourceTotalBytes": sourceBytes,
        "selectedCaptureIds": Array(Set(preparedTargets.map(\.capture.captureId))).sorted(),
        "manifest": try jsonObjectForBrowserCompanion(manifest)
      ]
    )

    progress?(
      makeProgress(
        mode: .cablePackage,
        phase: .preparing,
        filesDone: 0,
        filesTotal: 1,
        bytesSent: 0,
        bytesTotal: packageSize,
        detail: NSLocalizedString("upload.progress.cablePackageReady", comment: ""),
        currentFileName: packageURL.lastPathComponent
      )
    )

    let protocolUploadId = webConnectHandshake.webSessionId
    UploadDebugLog.write("[PIXUPLOAD] cablePackage offlinePackageReady packageId=\(packageKey.packageId) filename=\(packageFilename) size=\(packageSize)")

    progress?(
      makeProgress(
        mode: .cablePackage,
        phase: .completed,
        filesDone: 1,
        filesTotal: 1,
        bytesSent: packageSize,
        bytesTotal: packageSize,
        detail: NSLocalizedString("upload.progress.cableHandoffReady", comment: ""),
        currentFileName: packageFilename
      )
    )

    let protocolLog = UploadProtocolLog(
      id: UUID(),
      uploadId: protocolUploadId,
      jobId: jobId,
      createdAt: Date(),
      expectedFileCount: 1,
      expectedTotalBytes: packageSize,
      receivedFileCount: 1,
      receivedTotalBytes: packageSize,
      complete: true,
      mismatches: [],
      manifestPath: nil,
      receiptPath: packageURL.path,
      filesDetailed: nil
    )

    return PixcaptureUploadResult(
      uploadedRecordIds: records.map(\.id),
      failedRecordIds: [],
      protocolLogs: [protocolLog],
      fileErrors: [],
      localPackageURL: packageURL,
      mode: .cablePackage,
      filesDone: 1,
      filesTotal: 1,
      bytesSent: packageSize,
      bytesTotal: packageSize,
      verificationFailed: false
    )
  }

  private func postCableCompanionTransferSignal(
    handshake: WebConnectUploadHandshake,
    payload: [String: Any]
  ) async {
    let sessionId = handshake.webSessionId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sessionId.isEmpty else { return }
    let url = handshake.endpoint
      .appendingPathComponent("api")
      .appendingPathComponent("v2")
      .appendingPathComponent("web-connect")
      .appendingPathComponent("sessions")
      .appendingPathComponent(sessionId)
      .appendingPathComponent("companion-signal")
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: [
        "role": "mobile",
        "type": "transfer",
        "payload": payload
      ])
      let (_, response) = try await networkSession.data(for: request)
      guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        UploadDebugLog.write("[PIXUPLOAD] cablePackage signal skipped status=\(status)")
        return
      }
      UploadDebugLog.write("[PIXUPLOAD] cablePackage signal status=\(payload["status"] ?? "-") session=\(sessionId)")
    } catch {
      UploadDebugLog.write("[PIXUPLOAD] cablePackage signal skipped error=\(error.localizedDescription)")
    }
  }

  private func validatePackagePrepareResponse(
    _ response: PixcapturePackagePrepareResponse,
    expectedPackageId: String,
    expectedKeyId: String,
    expectedSizeBytes: Int
  ) throws {
    guard response.success ?? true else {
      throw PixcaptureUploadError.api("Backend hat die Paket-Vorbereitung abgelehnt.")
    }
    guard response.package.packageId == expectedPackageId,
          response.package.keyId == expectedKeyId else {
      throw invalidResponse("Backend-Paketantwort passt nicht zum erzeugten Paket.")
    }
    if let expectedFiles = response.expectedFiles, expectedFiles != 1 {
      throw invalidResponse("Backend erwartet eine falsche Paketanzahl.")
    }
    if let totalBytesExpected = response.totalBytesExpected,
       totalBytesExpected != expectedSizeBytes {
      throw invalidResponse("Backend erwartet eine andere Paketgroesse.")
    }
    let sessionId = response.sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sessionId.isEmpty else {
      throw invalidResponse("Backend-Paketantwort ohne Upload-Session.")
    }
  }

  private func uploadEncryptedPackageToCompanion(
    jobId: String,
    records: [UploadRecord],
    token: String,
    userId: String,
    identityHint: PixcaptureUploadIdentityHint?,
    handshake: CompanionWiFiUploadHandshake,
    progress: ((PixcaptureUploadProgress) -> Void)?
  ) async throws -> PixcaptureUploadResult {
    guard let companionBaseURL = handshake.baseURL else {
      throw PixcaptureUploadError.api(NSLocalizedString("upload.error.companionHostInvalid", comment: ""))
    }
    guard let pairingCode = handshake.pairingCode?.trimmingCharacters(in: .whitespacesAndNewlines),
          !pairingCode.isEmpty else {
      throw PixcaptureUploadError.api("Der Companion-Pairing-Code ist erforderlich.")
    }

    let preparedTargets = try prepareSessionTargets(jobId: jobId, records: records)
    guard !preparedTargets.isEmpty else {
      throw PixcaptureUploadError.noPendingFiles
    }

    let sourceBytes = preparedTargets.reduce(0) { $0 + $1.sizeBytes }
    let manifest = makeUploadSessionManifest(
      jobId: jobId,
      userId: userId,
      preparedTargets: preparedTargets,
      namingOverride: identityHint.map {
        UploadSessionManifestNamingOverride(cust3: $0.cust3, job5: $0.job5)
      }
    )

    progress?(
      makeProgress(
        mode: .companionWifi,
        phase: .connecting,
        filesDone: 0,
        filesTotal: 1,
        bytesSent: 0,
        bytesTotal: sourceBytes,
        detail: NSLocalizedString("upload.progress.fetchingPackageKey", comment: "")
      )
    )

    let keyResponse: PixcapturePackageKeyResponse = try await apiRequest(
      path: "/api/v2/mobile/package/key",
      method: "POST",
      token: token,
      body: PixcapturePackageKeyRequest(
        client_type: "pixcapture_ios_companion",
        app_version: currentAppVersionString()
      )
    )

    guard let keyData = Data(base64Encoded: keyResponse.encryption.keyBase64), keyData.count == 32 else {
      throw invalidResponse(NSLocalizedString("upload.error.invalidPackageKey", comment: ""))
    }

    progress?(
      makeProgress(
        mode: .companionWifi,
        phase: .preparing,
        filesDone: 0,
        filesTotal: 1,
        bytesSent: 0,
        bytesTotal: sourceBytes,
        detail: NSLocalizedString("upload.progress.creatingLocalData", comment: "")
      )
    )

    let packageURL = try writeEncryptedPackage(
      jobId: jobId,
      manifest: manifest,
      preparedTargets: preparedTargets,
      packageId: keyResponse.packageId,
      keyId: keyResponse.keyId,
      keyData: keyData
    )
    let packageSize = try fileSizeBytes(packageURL)
    let packageFilename = packageURL.lastPathComponent
    let packageChecksum = try sha256Hex(fileURL: packageURL)

    progress?(
      makeProgress(
        mode: .companionWifi,
        phase: .preparing,
        filesDone: 0,
        filesTotal: 1,
        bytesSent: 0,
        bytesTotal: packageSize,
        detail: NSLocalizedString("upload.progress.calculatingChecksum", comment: ""),
        currentFileName: packageFilename
      )
    )

    progress?(
      makeProgress(
        mode: .companionWifi,
        phase: .uploading,
        filesDone: 0,
        filesTotal: 1,
        bytesSent: 0,
        bytesTotal: packageSize,
        detail: NSLocalizedString("upload.progress.sendingLocalWifi", comment: ""),
        currentFileName: packageFilename
      )
    )

    let receiveResponse = try await sendCompanionPackage(
      baseURL: companionBaseURL,
      pairingCode: pairingCode,
      packageURL: packageURL,
      filename: packageFilename,
      packageId: keyResponse.packageId,
      keyId: keyResponse.keyId,
      sha256: packageChecksum,
      sizeBytes: packageSize,
      motifCount: Set(records.map(\.seriesId)).count,
      technicalFileCount: preparedTargets.count,
      sourceTotalBytes: sourceBytes
    )

    progress?(
      makeProgress(
        mode: .companionWifi,
        phase: .finalizing,
        filesDone: 1,
        filesTotal: 1,
        bytesSent: packageSize,
        bytesTotal: packageSize,
        detail: NSLocalizedString("upload.progress.localReceiptWritingLog", comment: ""),
        currentFileName: packageFilename
      )
    )

    let warnings = receiveResponse.warnings ?? []
    let mismatches = warnings.map {
      UploadProtocolMismatch(fileId: keyResponse.packageId, reason: $0)
    }
    let protocolLog = UploadProtocolLog(
      id: UUID(),
      uploadId: receiveResponse.packageId ?? keyResponse.packageId,
      jobId: jobId,
      createdAt: Date(),
      expectedFileCount: 1,
      expectedTotalBytes: packageSize,
      receivedFileCount: 1,
      receivedTotalBytes: receiveResponse.sizeBytes ?? packageSize,
      complete: true,
      mismatches: mismatches,
      manifestPath: nil,
      receiptPath: receiveResponse.storedPath,
      filesDetailed: nil
    )

    return PixcaptureUploadResult(
      uploadedRecordIds: records.map(\.id),
      failedRecordIds: [],
      protocolLogs: [protocolLog],
      fileErrors: [],
      mode: .companionWifi,
      filesDone: 1,
      filesTotal: 1,
      bytesSent: packageSize,
      bytesTotal: packageSize
    )
  }

  private func uploadEncryptedPackageToBrowserCompanion(
    jobId: String,
    records: [UploadRecord],
    token: String,
    userId: String,
    identityHint: PixcaptureUploadIdentityHint?,
    handshake: WebConnectUploadHandshake,
    progress: ((PixcaptureUploadProgress) -> Void)?
  ) async throws -> PixcaptureUploadResult {
    UploadDebugLog.write("[PIXUPLOAD] browserCompanion begin job=\(jobId) session=\(handshake.webSessionId) endpoint=\(handshake.endpoint.absoluteString) records=\(records.count)")
    let preparedTargets = try prepareSessionTargets(jobId: jobId, records: records)
    guard !preparedTargets.isEmpty else {
      UploadDebugLog.write("[PIXUPLOAD] browserCompanion no prepared targets")
      throw PixcaptureUploadError.noPendingFiles
    }

    let sourceBytes = preparedTargets.reduce(0) { $0 + $1.sizeBytes }
    UploadDebugLog.write("[PIXUPLOAD] browserCompanion prepared targets=\(preparedTargets.count) sourceBytes=\(sourceBytes)")
    let manifest = makeUploadSessionManifest(
      jobId: jobId,
      userId: userId,
      preparedTargets: preparedTargets,
      namingOverride: identityHint.map {
        UploadSessionManifestNamingOverride(cust3: $0.cust3, job5: $0.job5)
      }
    )

    progress?(
      makeProgress(
        mode: .companionWifi,
        phase: .connecting,
        filesDone: 0,
        filesTotal: 1,
        bytesSent: 0,
        bytesTotal: sourceBytes,
        detail: NSLocalizedString("upload.progress.fetchingPackageKey", comment: "")
      )
    )

    let keyResponse: PixcapturePackageKeyResponse = try await apiRequest(
      path: "/api/v2/mobile/package/key",
      method: "POST",
      token: token,
      body: PixcapturePackageKeyRequest(
        client_type: "pixcapture_ios_browser_companion",
        app_version: currentAppVersionString()
      )
    )

    guard let keyData = Data(base64Encoded: keyResponse.encryption.keyBase64), keyData.count == 32 else {
      throw invalidResponse(NSLocalizedString("upload.error.invalidPackageKey", comment: ""))
    }

    progress?(
      makeProgress(
        mode: .companionWifi,
        phase: .preparing,
        filesDone: 0,
        filesTotal: 1,
        bytesSent: 0,
        bytesTotal: sourceBytes,
        detail: NSLocalizedString("upload.progress.creatingBrowserData", comment: "")
      )
    )

    let packageURL = try writeEncryptedPackage(
      jobId: jobId,
      manifest: manifest,
      preparedTargets: preparedTargets,
      packageId: keyResponse.packageId,
      keyId: keyResponse.keyId,
      keyData: keyData
    )
    let packageSize = try fileSizeBytes(packageURL)
    let packageFilename = packageURL.lastPathComponent
    let packageChecksum = try sha256Hex(fileURL: packageURL)
    let manifestJSON = try jsonObjectForBrowserCompanion(manifest)
    UploadDebugLog.write("[PIXUPLOAD] browserCompanion package filename=\(packageFilename) size=\(packageSize) sha256=\(packageChecksum.prefix(12))...")

    progress?(
      makeProgress(
        mode: .companionWifi,
        phase: .uploading,
        filesDone: 0,
        filesTotal: 1,
        bytesSent: 0,
        bytesTotal: packageSize,
        detail: NSLocalizedString("upload.progress.connectingComputer", comment: ""),
        currentFileName: packageFilename
      )
    )

    let bridge = BrowserCompanionWebRTCBridge()
    UploadDebugLog.write("[PIXUPLOAD] browserCompanion bridge transfer start")
    let receipt = try await bridge.transferPackage(
      endpoint: handshake.endpoint,
      webSessionId: handshake.webSessionId,
      packageURL: packageURL,
      filename: packageFilename,
      packageId: keyResponse.packageId,
      keyId: keyResponse.keyId,
      sha256: packageChecksum,
      manifest: manifestJSON,
      motifCount: Set(records.map(\.seriesId)).count,
      technicalFileCount: preparedTargets.count,
      sourceTotalBytes: sourceBytes,
      sizeBytes: packageSize,
      progress: { sent in
        if sent == packageSize || sent % (1024 * 1024) < 64 * 1024 {
          UploadDebugLog.write("[PIXUPLOAD] browserCompanion sent=\(sent)/\(packageSize)")
        }
        progress?(
          self.makeProgress(
            mode: .companionWifi,
            phase: .uploading,
            filesDone: 0,
            filesTotal: 1,
            bytesSent: sent,
            bytesTotal: packageSize,
            detail: NSLocalizedString("upload.progress.sendingBrowserData", comment: ""),
            currentFileName: packageFilename
          )
        )
      }
    )
    UploadDebugLog.write(
      "[PIXUPLOAD] browserCompanion bridge transfer verified bytes=\(receipt.sizeBytes) sha256=\(receipt.sha256.prefix(12))..."
    )

    progress?(
      makeProgress(
        mode: .companionWifi,
        phase: .finalizing,
        filesDone: 1,
        filesTotal: 1,
        bytesSent: packageSize,
        bytesTotal: packageSize,
        detail: NSLocalizedString("upload.progress.browserReceiptVerified", comment: ""),
        currentFileName: packageFilename
      )
    )

    let protocolLog = UploadProtocolLog(
      id: UUID(),
      uploadId: handshake.webSessionId,
      jobId: jobId,
      createdAt: Date(),
      expectedFileCount: 1,
      expectedTotalBytes: packageSize,
      receivedFileCount: 1,
      receivedTotalBytes: receipt.sizeBytes,
      complete: true,
      mismatches: [],
      manifestPath: nil,
      receiptPath: "browser-companion:\(handshake.webSessionId):\(receipt.packageId)",
      filesDetailed: nil
    )

    return PixcaptureUploadResult(
      uploadedRecordIds: records.map(\.id),
      failedRecordIds: [],
      protocolLogs: [protocolLog],
      fileErrors: [],
      mode: .companionWifi,
      filesDone: receipt.sizeBytes == packageSize ? 1 : 0,
      filesTotal: 1,
      bytesSent: packageSize,
      bytesTotal: packageSize
    )
  }

  private func sendCompanionPackage(
    baseURL: URL,
    pairingCode: String?,
    packageURL: URL,
    filename: String,
    packageId: String,
    keyId: String,
    sha256: String,
    sizeBytes: Int,
    motifCount: Int,
    technicalFileCount: Int,
    sourceTotalBytes: Int
  ) async throws -> CompanionPackageReceiveResponse {
    var request = URLRequest(url: baseURL.appendingPathComponent("packages"))
    request.httpMethod = "POST"
    request.timeoutInterval = 15 * 60
    request.setValue("application/vnd.pixcapture.package", forHTTPHeaderField: "Content-Type")
    request.setValue("\(sizeBytes)", forHTTPHeaderField: "Content-Length")
    request.setValue(filename, forHTTPHeaderField: "X-PixCapture-Filename")
    request.setValue(packageId, forHTTPHeaderField: "X-PixCapture-Package-Id")
    request.setValue(keyId, forHTTPHeaderField: "X-PixCapture-Key-Id")
    request.setValue(sha256, forHTTPHeaderField: "X-PixCapture-SHA256")
    request.setValue("\(motifCount)", forHTTPHeaderField: "X-PixCapture-Motif-Count")
    request.setValue("\(technicalFileCount)", forHTTPHeaderField: "X-PixCapture-Technical-File-Count")
    request.setValue("\(sourceTotalBytes)", forHTTPHeaderField: "X-PixCapture-Source-Total-Bytes")
    if let pairingCode = pairingCode?.trimmingCharacters(in: .whitespacesAndNewlines),
       !pairingCode.isEmpty {
      request.setValue(pairingCode, forHTTPHeaderField: "X-PixCapture-Pairing-Code")
    }

    let (data, response) = try await networkSession.upload(for: request, fromFile: packageURL)
    guard let http = response as? HTTPURLResponse else {
      throw invalidResponse(NSLocalizedString("upload.error.companionNoHTTPStatus", comment: ""))
    }
    guard http.statusCode == 200 else {
      let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
      throw PixcaptureUploadError.apiStatus(
        code: http.statusCode,
        message: message?.isEmpty == false
          ? message!
          : Self.localizedFormat("upload.error.companionStatus.format", http.statusCode)
      )
    }

    let receipt: CompanionPackageReceiveResponse
    do {
      let decoder = JSONDecoder()
      decoder.keyDecodingStrategy = .convertFromSnakeCase
      receipt = try decoder.decode(CompanionPackageReceiveResponse.self, from: data)
    } catch {
      throw invalidResponse(
        Self.localizedFormat("upload.error.companionResponse.format", error.localizedDescription)
      )
    }
    do {
      try CompanionPackageReceiptValidator.validate(
        receipt,
        expectedPackageId: packageId,
        expectedSizeBytes: sizeBytes,
        expectedSHA256: sha256
      )
    } catch let error as CompanionPackageReceiptValidationError {
      switch error {
      case .notAccepted:
        throw invalidResponse(NSLocalizedString("upload.error.companionNotAccepted", comment: ""))
      case .wrongPackageId:
        throw invalidResponse(NSLocalizedString("upload.error.companionWrongPackageId", comment: ""))
      case .wrongSize(let received, let expected):
        throw invalidResponse(
          String(
            format: NSLocalizedString("upload.error.companionWrongSize.format", comment: ""),
            received ?? -1,
            expected
          )
        )
      case .wrongChecksum:
        throw invalidResponse(NSLocalizedString("upload.error.companionWrongChecksum", comment: ""))
      case .warnings(let warnings):
        throw invalidResponse(
          Self.localizedFormat(
            "upload.error.companionWarnings.format",
            warnings.joined(separator: ", ")
          )
        )
      }
    }
    return receipt
  }

  private func prepareSessionTargets(
    jobId: String,
    records: [UploadRecord]
  ) throws -> [PreparedUploadTarget] {
    var targets = try preparePhotoSessionTargets(records)
    targets.append(contentsOf: prepareVideoSessionTargets(jobId: jobId))
    targets.append(contentsOf: preparePanoramaSessionTargets(jobId: jobId))

    return targets.sorted { lhs, rhs in
      if lhs.capture.captureTimestamp == rhs.capture.captureTimestamp {
        return lhs.fileId < rhs.fileId
      }
      return lhs.capture.captureTimestamp < rhs.capture.captureTimestamp
    }
  }

  private func makePackageUploadTarget(
    fileId: String,
    fileURL: URL,
    filename: String,
    sizeBytes: Int,
    checksumSha256: String,
    fallbackCapture: SessionCaptureDescriptor?
  ) -> PreparedUploadTarget {
    PreparedUploadTarget(
      fileId: fileId,
      recordId: nil,
      fileURL: fileURL,
      relativePath: "packages/\(filename)",
      filename: filename,
      mimeType: "application/vnd.pixcapture.package",
      sizeBytes: sizeBytes,
      checksumSha256: checksumSha256,
      capture: fallbackCapture ?? SessionCaptureDescriptor(
        roomId: "package",
        floorId: "unknown",
        roomName: "Package",
        roomType: "package",
        roomVariant: 1,
        captureId: fileId,
        captureType: "encrypted_package",
        captureSubtype: "pixcapturepkg",
        captureTimestamp: Date(),
        tasks: [],
        stylePreset: nil,
        sensorData: nil,
        intendedProcessing: "package_transport"
      ),
      motifIndex: nil,
      exposureIndex: nil,
      cameraMetadata: nil,
      videoMetadata: nil,
      motionMetadata: nil,
      intrinsicsMetadata: nil,
      trackingMetadata: nil,
      floorplanMetadata: nil,
      fileMetadata: .object([
        "metadata_role": .string("encrypted_package"),
        "package_format": .string("pixcapturepkg-v1")
      ]),
      projectNameHint: nil
    )
  }

  private func writeEncryptedPackage(
    jobId: String,
    manifest: UploadSessionManifestPayload,
    preparedTargets: [PreparedUploadTarget],
    packageId: String,
    keyId: String,
    keyData: Data,
    exportToDocuments: Bool = false
  ) throws -> URL {
    let packageRoot = try exportToDocuments ? packageExportDirectory() : packageCacheDirectory()
    let safeJob = sanitizeManifestToken(jobId)
    if exportToDocuments {
      try removeExportedPackages(matchingJobToken: safeJob, in: packageRoot)
    }
    let filename = "\(safeJob.isEmpty ? "pixcapture" : safeJob)-\(packageId).pixcapturepkg"
    let packageURL = packageRoot.appendingPathComponent(filename)
    FileManager.default.createFile(atPath: packageURL.path, contents: nil)

    guard let handle = try? FileHandle(forWritingTo: packageURL) else {
      throw PixcaptureUploadError.api("Kabeldaten konnten nicht vorbereitet werden.")
    }
    defer {
      try? handle.close()
    }

    let key = SymmetricKey(data: keyData)
    let fileDescriptors = preparedTargets.map { target in
      PixcapturePackageSourceFile(
        file_id: target.fileId,
        filename: target.filename,
        relative_path: target.relativePath,
        mime_type: target.mimeType,
        size_bytes: target.sizeBytes,
        checksum_sha256: target.checksumSha256,
        capture_id: target.capture.captureId,
        capture_type: target.capture.captureType,
        room_id: target.capture.roomId,
        room_name: target.capture.roomName,
        floor_id: target.capture.floorId,
        motif_index: target.motifIndex,
        exposure_index: target.exposureIndex
      )
    }
    let previews = preparedTargets.compactMap { target -> PixcapturePackagePreview? in
      guard target.fileId.hasPrefix("preview_"),
            target.mimeType.lowercased().hasPrefix("image/"),
            let data = packagePreviewEnvelopeData(for: target.fileURL) else {
        return nil
      }
      return PixcapturePackagePreview(
        capture_id: target.capture.captureId,
        filename: target.filename,
        mime_type: target.mimeType,
        size_bytes: data.count,
        data_base64: data.base64EncodedString(),
        room_name: target.capture.roomName,
        floor_id: target.capture.floorId,
        motif_index: target.motifIndex
      )
    }
    let envelope = PixcapturePackageEnvelope(
      schema: "pixcapturepkg-v1",
      package_id: packageId,
      key_id: keyId,
      encryption_algorithm: "AES-256-GCM",
      app_version: currentAppVersionString(),
      created_at: isoTimestamp(Date()),
      source_file_count: preparedTargets.count,
      source_total_bytes: preparedTargets.reduce(0) { $0 + $1.sizeBytes },
      manifest: manifest,
      files: fileDescriptors,
      previews: previews
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let envelopeData = try encoder.encode(envelope)

    handle.write(Data("PIXCAPPKG1\n".utf8))
    try writePackageChunk(envelopeData, to: handle)

    for target in preparedTargets {
      // CryptoKit's AES.GCM API is one-shot. Memory-map the source where iOS
      // permits it and drain temporary objects after every entry so a DNG
      // bracket does not retain previous plaintext/ciphertext buffers.
      try autoreleasepool {
        let plainData = try Data(contentsOf: target.fileURL, options: [.mappedIfSafe])
        let header = PixcapturePackageEntryHeader(
          file_id: target.fileId,
          filename: target.filename,
          relative_path: target.relativePath,
          mime_type: target.mimeType,
          size_bytes: plainData.count,
          checksum_sha256: sha256Hex(plainData)
        )
        let headerData = try encoder.encode(header)
        let sealed = try AES.GCM.seal(plainData, using: key, authenticating: headerData)
        guard let combined = sealed.combined else {
          throw PixcaptureUploadError.api("Paketverschluesselung konnte keinen Payload erzeugen.")
        }

        try writePackageChunk(headerData, to: handle)
        try writePackageChunk(combined, to: handle)
      }
    }

    return packageURL
  }

  private func packagePreviewEnvelopeData(for fileURL: URL) -> Data? {
    guard let image = UIImage(contentsOfFile: fileURL.path) else {
      guard let data = try? Data(contentsOf: fileURL), data.count <= 512 * 1024 else {
        return nil
      }
      return data
    }

    let maxDimension: CGFloat = 520
    let originalSize = image.size
    guard originalSize.width > 0, originalSize.height > 0 else { return nil }

    let scale = min(1, maxDimension / max(originalSize.width, originalSize.height))
    let targetSize = CGSize(
      width: max(1, floor(originalSize.width * scale)),
      height: max(1, floor(originalSize.height * scale))
    )
    let renderer = UIGraphicsImageRenderer(size: targetSize)
    return renderer.jpegData(withCompressionQuality: 0.72) { _ in
      image.draw(in: CGRect(origin: .zero, size: targetSize))
    }
  }

  private func packageCacheDirectory() throws -> URL {
    let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    let packageRoot = root.appendingPathComponent("PixCapturePackages", isDirectory: true)
    try FileManager.default.createDirectory(at: packageRoot, withIntermediateDirectories: true)
    return packageRoot
  }

  private func packageExportDirectory() throws -> URL {
    let packageRoot = Self.exportedPackageDirectoryURL()
    try FileManager.default.createDirectory(at: packageRoot, withIntermediateDirectories: true)
    return packageRoot
  }

  private func cleanupExportedPackagesForNewCableRun() throws {
    try Self.deleteExportedPackages()
  }

  private func removeExportedPackages(matchingJobToken jobToken: String, in packageRoot: URL) throws {
    let normalizedJobToken = jobToken.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedJobToken.isEmpty else { return }
    let prefix = "\(normalizedJobToken)-pkg_"
    for url in Self.exportedPackageURLs(in: packageRoot) where url.lastPathComponent.hasPrefix(prefix) {
      try FileManager.default.removeItem(at: url)
    }
  }

  private static func exportedPackageDirectoryURL() -> URL {
    let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return root.appendingPathComponent("PixCapturePackages", isDirectory: true)
  }

  private static func exportedPackageURLs(in root: URL) -> [URL] {
    guard let urls = try? FileManager.default.contentsOfDirectory(
      at: root,
      includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
      options: [.skipsHiddenFiles]
    ) else {
      return []
    }
    return urls.filter { $0.pathExtension.lowercased() == "pixcapturepkg" }
  }

  private func writePackageChunk(_ data: Data, to handle: FileHandle) throws {
    var length = UInt64(data.count).bigEndian
    let lengthData = withUnsafeBytes(of: &length) { Data($0) }
    handle.write(lengthData)
    handle.write(data)
  }

  private func preparePhotoSessionTargets(_ records: [UploadRecord]) throws -> [PreparedUploadTarget] {
    let captureTimestampBySeries = Dictionary(grouping: records, by: { $0.seriesId }).mapValues { grouped in
      grouped.map(\.createdAt).min() ?? Date()
    }
    let uploadIndicesByRecordId = resolvePhotoUploadIndices(records: records)

    let sortedRecords = records.sorted { lhs, rhs in
      if lhs.seriesId == rhs.seriesId {
        if lhs.exposureEV == rhs.exposureEV {
          return lhs.fileURL.lastPathComponent < rhs.fileURL.lastPathComponent
        }
        return lhs.exposureEV < rhs.exposureEV
      }
      return lhs.createdAt < rhs.createdAt
    }

    var prepared: [PreparedUploadTarget] = []
    prepared.reserveCapacity(sortedRecords.count + max(1, captureTimestampBySeries.count))
    var includedPreviewPaths: Set<String> = []
    var includedXMPPaths: Set<String> = []
    var includedDepthPaths: Set<String> = []

    var firstRecordBySeries: [UUID: UploadRecord] = [:]
    for record in sortedRecords {
      if firstRecordBySeries[record.seriesId] == nil {
        firstRecordBySeries[record.seriesId] = record
      }
      let uploadIndices = uploadIndicesByRecordId[record.id]
      let exifSnapshot = readPhotoExifSnapshot(record.fileURL)
      let capture = photoCaptureDescriptorForManifest(
        record: record,
        captureTimestampBySeries: captureTimestampBySeries
      )
      let target = try makePreparedTarget(
        fileId: record.id.uuidString.lowercased(),
        recordId: record.id,
        fileURL: record.fileURL,
        relativePath: photoRelativePath(for: record, fileURL: record.fileURL),
        capture: capture,
        motifIndex: uploadIndices?.motifIndex,
        exposureIndex: uploadIndices?.exposureIndex,
        cameraMetadata: cameraMetadataForManifest(record: record, exifSnapshot: exifSnapshot),
        videoMetadata: nil,
        motionMetadata: nil,
        intrinsicsMetadata: nil,
        trackingMetadata: nil,
        floorplanMetadata: nil,
        fileMetadata: photoFileMetadataForManifest(
          record: record,
          exifSnapshot: exifSnapshot,
          uploadIndices: uploadIndices
        ),
        projectNameHint: record.jobLabel
      )
      prepared.append(target)

      if let previewURL = FileStore.ensurePreviewExists(
        for: record.fileURL,
        captureOrientation: record.captureOrientation,
        sensorRollDegrees: record.sensorRollDegrees
      ) {
        let normalizedPreviewPath = previewURL.standardizedFileURL.path
        if !includedPreviewPaths.contains(normalizedPreviewPath) {
          includedPreviewPaths.insert(normalizedPreviewPath)
          let previewTarget = try makePreparedTarget(
            fileId: "preview_\(record.id.uuidString.lowercased())",
            recordId: record.id,
            fileURL: previewURL,
            relativePath: photoRelativePath(for: record, fileURL: previewURL),
            capture: capture,
            motifIndex: uploadIndices?.motifIndex,
            exposureIndex: uploadIndices?.exposureIndex,
            cameraMetadata: nil,
            videoMetadata: nil,
            motionMetadata: nil,
            intrinsicsMetadata: nil,
            trackingMetadata: nil,
            floorplanMetadata: nil,
            fileMetadata: previewSidecarMetadataForManifest(record: record, uploadIndices: uploadIndices),
            projectNameHint: record.jobLabel
          )
          prepared.append(previewTarget)
        }
      }

      if let xmpURL = companionXMPURL(for: record.fileURL) {
        let normalizedXMPPath = xmpURL.standardizedFileURL.path
        if !includedXMPPaths.contains(normalizedXMPPath) {
          includedXMPPaths.insert(normalizedXMPPath)
          let xmpTarget = try makePreparedTarget(
            fileId: "xmp_\(record.id.uuidString.lowercased())",
            recordId: record.id,
            fileURL: xmpURL,
            relativePath: photoRelativePath(for: record, fileURL: xmpURL),
            capture: capture,
            motifIndex: uploadIndices?.motifIndex,
            exposureIndex: uploadIndices?.exposureIndex,
            cameraMetadata: nil,
            videoMetadata: nil,
            motionMetadata: nil,
            intrinsicsMetadata: nil,
            trackingMetadata: nil,
            floorplanMetadata: nil,
            fileMetadata: xmpSidecarMetadataForManifest(record: record, uploadIndices: uploadIndices),
            projectNameHint: record.jobLabel
          )
          prepared.append(xmpTarget)
        }
      }

      if let depthURL = companionDepthURL(for: record.fileURL) {
        let normalizedDepthPath = depthURL.standardizedFileURL.path
        if !includedDepthPaths.contains(normalizedDepthPath) {
          includedDepthPaths.insert(normalizedDepthPath)
          let depthTarget = try makePreparedTarget(
            fileId: "depth_\(record.id.uuidString.lowercased())",
            recordId: record.id,
            fileURL: depthURL,
            relativePath: photoRelativePath(for: record, fileURL: depthURL),
            capture: capture,
            motifIndex: uploadIndices?.motifIndex,
            exposureIndex: uploadIndices?.exposureIndex,
            cameraMetadata: nil,
            videoMetadata: nil,
            motionMetadata: nil,
            intrinsicsMetadata: nil,
            trackingMetadata: nil,
            floorplanMetadata: nil,
            fileMetadata: depthSidecarMetadataForManifest(record: record, uploadIndices: uploadIndices),
            projectNameHint: record.jobLabel
          )
          prepared.append(depthTarget)
        }
      }
    }

    for (seriesId, firstRecord) in firstRecordBySeries {
      guard let exifLogURL = firstRecord.exifLogURL,
            FileManager.default.fileExists(atPath: exifLogURL.path) else {
        continue
      }
      let capture = photoCaptureDescriptorForManifest(
        record: firstRecord,
        captureTimestampBySeries: captureTimestampBySeries
      )
      if let sidecar = try? makePreparedTarget(
        fileId: "exif_\(seriesId.uuidString.lowercased())",
        recordId: nil,
        fileURL: exifLogURL,
        relativePath: photoRelativePath(for: firstRecord, fileURL: exifLogURL),
        capture: capture,
        cameraMetadata: nil,
        videoMetadata: nil,
        motionMetadata: nil,
        intrinsicsMetadata: nil,
        trackingMetadata: nil,
        floorplanMetadata: nil,
        fileMetadata: exifSidecarMetadataForManifest(seriesId: seriesId),
        projectNameHint: firstRecord.jobLabel
      ) {
        prepared.append(sidecar)
      }
    }

    return prepared
  }

  private func prepareVideoSessionTargets(jobId: String) -> [PreparedUploadTarget] {
    guard let projectId = loadVideoProjectId(jobId: jobId) else {
      return []
    }
    guard let projectPaths = try? VideoProjectStore.createProjectPaths(projectId: projectId) else {
      return []
    }
    guard let takes = try? VideoProjectStore.loadCaptures(projectId: projectId), !takes.isEmpty else {
      return []
    }

    let motionColumns = [
      "timestamp", "acc_x", "acc_y", "acc_z",
      "gyro_x", "gyro_y", "gyro_z",
      "quat_w", "quat_x", "quat_y", "quat_z"
    ]

    var targets: [PreparedUploadTarget] = []
    for take in takes.sorted(by: { $0.createdAt < $1.createdAt }) {
      let roomId = RoomTaxonomy.normalizedRoomId(take.roomId)
      let floorId = FloorTaxonomy.normalizedFloorId(take.floorId)
      let videoURL = resolveExistingRelativeFile(root: projectPaths.root, relativePath: take.videoRelativePath)
      let motionURL = resolveExistingRelativeFile(root: projectPaths.root, relativePath: take.motionRelativePath)
      let intrinsicsURL = resolveExistingRelativeFile(root: projectPaths.root, relativePath: take.intrinsicsRelativePath)
      let trackingURL = resolveExistingRelativeFile(root: projectPaths.root, relativePath: take.trackingRelativePath)
      let trackingObject = trackingURL.flatMap(readJSONObject)
      let captureSensorData = sensorDataFromTrackingObject(trackingObject)
        ?? sensorDataFromMotionCSV(motionURL)

      let capture = SessionCaptureDescriptor(
        roomId: roomId,
        floorId: floorId,
        roomName: roomNameForManifest(roomId: roomId, floorId: floorId),
        roomType: roomTypeForManifest(roomId: roomId),
        roomVariant: 1,
        captureId: "cap_video_\(take.id.uuidString.lowercased())",
        captureType: "video_walkthrough",
        captureSubtype: take.kind.rawValue,
        captureTimestamp: take.createdAt,
        tasks: ["stabilization"],
        stylePreset: nil,
        sensorData: captureSensorData,
        intendedProcessing: nil
      )

      if let videoURL {
        var metadata: [String: JSONValue] = [
          "capture_kind": .string(take.kind.rawValue),
          "final_role": .string(take.finalRole.rawValue),
          "priority_score": .number(Double(take.priorityScore)),
          "sequence_index": .number(Double(take.sequenceIndex))
        ]
        if let duration = take.durationSeconds {
          metadata["duration_seconds"] = .number(duration)
        }
        if !take.editorNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          metadata["editor_note"] = .string(take.editorNote)
        }

        if let prepared = try? makePreparedTarget(
          fileId: "video_\(take.id.uuidString.lowercased())_main",
          recordId: nil,
          fileURL: videoURL,
          relativePath: take.videoRelativePath,
          capture: capture,
          cameraMetadata: nil,
          videoMetadata: .object(metadata),
          motionMetadata: nil,
          intrinsicsMetadata: nil,
          trackingMetadata: nil,
          floorplanMetadata: nil,
          fileMetadata: nil
        ) {
          targets.append(prepared)
        }
      }

      if let motionURL {
        let motionMetadata = JSONValue.object([
          "columns": .array(motionColumns.map { .string($0) })
        ])
        if let prepared = try? makePreparedTarget(
          fileId: "video_\(take.id.uuidString.lowercased())_motion",
          recordId: nil,
          fileURL: motionURL,
          relativePath: take.motionRelativePath,
          capture: capture,
          cameraMetadata: nil,
          videoMetadata: nil,
          motionMetadata: motionMetadata,
          intrinsicsMetadata: nil,
          trackingMetadata: nil,
          floorplanMetadata: nil,
          fileMetadata: nil
        ) {
          targets.append(prepared)
        }
      }

      if let intrinsicsURL {
        let intrinsicsMetadata = jsonValueFromFile(intrinsicsURL)
        if let prepared = try? makePreparedTarget(
          fileId: "video_\(take.id.uuidString.lowercased())_intrinsics",
          recordId: nil,
          fileURL: intrinsicsURL,
          relativePath: take.intrinsicsRelativePath,
          capture: capture,
          cameraMetadata: nil,
          videoMetadata: nil,
          motionMetadata: nil,
          intrinsicsMetadata: intrinsicsMetadata,
          trackingMetadata: nil,
          floorplanMetadata: nil,
          fileMetadata: nil
        ) {
          targets.append(prepared)
        }
      }

      if let trackingURL {
        let trackingMetadata = trackingObject.flatMap { JSONValue(any: $0) } ?? jsonValueFromFile(trackingURL)
        if let prepared = try? makePreparedTarget(
          fileId: "video_\(take.id.uuidString.lowercased())_tracking",
          recordId: nil,
          fileURL: trackingURL,
          relativePath: take.trackingRelativePath,
          capture: capture,
          cameraMetadata: nil,
          videoMetadata: nil,
          motionMetadata: nil,
          intrinsicsMetadata: nil,
          trackingMetadata: trackingMetadata,
          floorplanMetadata: nil,
          fileMetadata: nil
        ) {
          targets.append(prepared)
        }
      }
    }

    return targets
  }

  private func prepareFloorplanSessionTargets(jobId: String, records: [UploadRecord]) -> [PreparedUploadTarget] {
    guard let existing = try? FloorplanProjectStore.loadExisting(projectKey: jobId) else {
      return []
    }
    let project = existing.project
    let paths = existing.paths

    ensureFloorplanExportArtifacts(jobId: jobId, project: project, paths: paths, records: records)

    var targets: [PreparedUploadTarget] = []

    let projectCapture = SessionCaptureDescriptor(
      roomId: "floorplan_project",
      floorId: FloorTaxonomy.defaultFloorId,
      roomName: "Floorplan Project",
      roomType: nil,
      roomVariant: 1,
      captureId: "cap_floorplan_project_\(normalizedProjectKeyToken(jobId))",
      captureType: "lidar_scan",
      captureSubtype: "floorplan_project",
      captureTimestamp: project.createdAt,
      tasks: ["floorplan_generation"],
      stylePreset: nil,
      sensorData: nil,
      intendedProcessing: nil
    )

    func appendProjectArtifact(
      suffix: String,
      fileURL: URL,
      relativePath: String,
      artifactKind: String,
      floorplanMetadata: JSONValue? = nil
    ) {
      guard FileManager.default.fileExists(atPath: fileURL.path),
            let prepared = try? makePreparedTarget(
              fileId: "floorplan_project_\(normalizedProjectKeyToken(jobId))_\(suffix)",
              recordId: nil,
              fileURL: fileURL,
              relativePath: relativePath,
              capture: projectCapture,
              cameraMetadata: nil,
              videoMetadata: nil,
              motionMetadata: nil,
              intrinsicsMetadata: nil,
              trackingMetadata: nil,
              floorplanMetadata: floorplanMetadata,
              fileMetadata: .object([
                "artifact_kind": .string(artifactKind),
                "artifact_scope": .string("project_export")
              ])
            ) else {
        return
      }
      targets.append(prepared)
    }

    appendProjectArtifact(
      suffix: "json",
      fileURL: paths.projectJSON,
      relativePath: "project.json",
      artifactKind: "project_json",
      floorplanMetadata: jsonValueFromFile(paths.projectJSON)
    )
    appendProjectArtifact(
      suffix: "png",
      fileURL: paths.combinedPNG,
      relativePath: "floorplan.png",
      artifactKind: "floorplan_png"
    )
    appendProjectArtifact(
      suffix: "pdf",
      fileURL: paths.combinedPDF,
      relativePath: "floorplan.pdf",
      artifactKind: "floorplan_combined_pdf"
    )
    appendProjectArtifact(
      suffix: "plan_pdf",
      fileURL: paths.visualPDF,
      relativePath: "floorplan_plan.pdf",
      artifactKind: "floorplan_visual_pdf"
    )
    appendProjectArtifact(
      suffix: "data_pdf",
      fileURL: paths.dataPDF,
      relativePath: "floorplan_data.pdf",
      artifactKind: "floorplan_data_pdf"
    )
    appendProjectArtifact(
      suffix: "data_csv",
      fileURL: paths.dataCSV,
      relativePath: "floorplan_data.csv",
      artifactKind: "floorplan_data_csv"
    )
    appendProjectArtifact(
      suffix: "summary_csv",
      fileURL: paths.summaryCSV,
      relativePath: "floorplan_summary.csv",
      artifactKind: "floorplan_summary_csv"
    )
    appendProjectArtifact(
      suffix: "rooms_csv",
      fileURL: paths.roomsCSV,
      relativePath: "floorplan_rooms.csv",
      artifactKind: "floorplan_rooms_csv"
    )
    appendProjectArtifact(
      suffix: "crm_property_csv",
      fileURL: paths.crmPropertyCSV,
      relativePath: "floorplan_crm_property_import.csv",
      artifactKind: "floorplan_crm_property_csv"
    )
    appendProjectArtifact(
      suffix: "crm_rooms_csv",
      fileURL: paths.crmRoomsCSV,
      relativePath: "floorplan_crm_rooms_import.csv",
      artifactKind: "floorplan_crm_rooms_csv"
    )
    appendProjectArtifact(
      suffix: "openimmo_xml",
      fileURL: paths.openImmoXML,
      relativePath: "floorplan_openimmo.xml",
      artifactKind: "floorplan_openimmo_xml"
    )

    for scan in project.roomScans.sorted(by: { $0.createdAt < $1.createdAt }) {
      let roomId = RoomTaxonomy.normalizedRoomId(scan.roomId)
      let floorId = FloorTaxonomy.normalizedFloorId(scan.floorId)
      let capture = SessionCaptureDescriptor(
        roomId: roomId,
        floorId: floorId,
        roomName: roomNameForManifest(roomId: roomId, floorId: floorId),
        roomType: roomTypeForManifest(roomId: roomId),
        roomVariant: 1,
        captureId: "cap_scan_\(scan.id.uuidString.lowercased())",
        captureType: "lidar_scan",
        captureSubtype: "roomplan_scan",
        captureTimestamp: scan.createdAt,
        tasks: ["floorplan_generation", "mesh_reconstruction"],
        stylePreset: nil,
        sensorData: sensorDataFromFloorplanTransform(scan.transform),
        intendedProcessing: nil
      )

      if let usdzURL = try? FloorplanProjectStore.resolve(projectKey: jobId, relativePath: scan.usdzPath),
         FileManager.default.fileExists(atPath: usdzURL.path),
         let prepared = try? makePreparedTarget(
          fileId: "scan_\(scan.id.uuidString.lowercased())_usdz",
          recordId: nil,
          fileURL: usdzURL,
          relativePath: scan.usdzPath,
          capture: capture,
          cameraMetadata: nil,
          videoMetadata: nil,
          motionMetadata: nil,
          intrinsicsMetadata: nil,
          trackingMetadata: nil,
          floorplanMetadata: nil,
          fileMetadata: nil
         ) {
        targets.append(prepared)
      }

      if let pngURL = try? FloorplanProjectStore.resolve(projectKey: jobId, relativePath: scan.floorplanPNGPath),
         FileManager.default.fileExists(atPath: pngURL.path),
         let prepared = try? makePreparedTarget(
          fileId: "scan_\(scan.id.uuidString.lowercased())_png",
          recordId: nil,
          fileURL: pngURL,
          relativePath: scan.floorplanPNGPath,
          capture: capture,
          cameraMetadata: nil,
          videoMetadata: nil,
          motionMetadata: nil,
          intrinsicsMetadata: nil,
          trackingMetadata: nil,
          floorplanMetadata: nil,
          fileMetadata: nil
         ) {
        targets.append(prepared)
      }

      if let segmentsURL = try? FloorplanProjectStore.resolve(projectKey: jobId, relativePath: scan.segmentsJSONPath),
         FileManager.default.fileExists(atPath: segmentsURL.path) {
        let segmentsMetadata = floorplanSegmentsMetadata(segmentsURL)
        if let prepared = try? makePreparedTarget(
          fileId: "scan_\(scan.id.uuidString.lowercased())_segments",
          recordId: nil,
          fileURL: segmentsURL,
          relativePath: scan.segmentsJSONPath,
          capture: capture,
          cameraMetadata: nil,
          videoMetadata: nil,
          motionMetadata: nil,
          intrinsicsMetadata: nil,
          trackingMetadata: nil,
          floorplanMetadata: segmentsMetadata,
          fileMetadata: nil
        ) {
          targets.append(prepared)
        }
      }
    }

    return targets
  }

  private func ensureFloorplanExportArtifacts(
    jobId: String,
    project: FloorplanProject,
    paths: FloorplanProjectPaths,
    records: [UploadRecord]
  ) {
    guard !project.roomScans.isEmpty else { return }
    _ = jobId
    _ = records

    _ = try? FloorplanComposerRenderer.exportCombinedFloorplan(
      project: project,
      outputPNG: paths.combinedPNG,
      outputVisualPDF: paths.visualPDF,
      legacyOutputURLs: FloorplanProjectStore.legacyExportURLs(paths: paths),
      exportTitle: "PIXCAPTURE Grundriss",
      resolveURL: { rel in try FloorplanProjectStore.resolve(projectKey: project.projectKey, relativePath: rel) }
    )
  }

  private func preparePanoramaSessionTargets(jobId: String) -> [PreparedUploadTarget] {
    guard let userFiles = try? FileStore.ensureUserFilesDirectory() else {
      return []
    }

    let panoramaRoot = userFiles.appendingPathComponent("PanoramaTours", isDirectory: true)
    guard FileManager.default.fileExists(atPath: panoramaRoot.path) else {
      return []
    }

    let expectedProjectKey = jobId.trimmingCharacters(in: .whitespacesAndNewlines)
    let entries = (try? FileManager.default.contentsOfDirectory(
      at: panoramaRoot,
      includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
      options: [.skipsHiddenFiles]
    )) ?? []

    var targets: [PreparedUploadTarget] = []

    for bundleURL in entries {
      let isDirectory = (try? bundleURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
      guard isDirectory else { continue }

      let metadataURL = bundleURL.appendingPathComponent("metadata.json")
      guard FileManager.default.fileExists(atPath: metadataURL.path) else { continue }
      let metadataObject = readJSONObject(metadataURL)

      let linkedFloorplan = metadataObject?["linked_floorplan"] as? [String: Any]
      let linkedProject = (linkedFloorplan?["project_key"] as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard let linkedProject, !linkedProject.isEmpty, linkedProject == expectedProjectKey else {
        continue
      }

      let createdAt = parseIsoDate(metadataObject?["created_at"] as? String)
        ?? ((try? bundleURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date())
      let panoramaSensorData = sensorDataFromPanoramaMetadata(metadataObject)

      let capture = SessionCaptureDescriptor(
        roomId: "panorama",
        floorId: FloorTaxonomy.defaultFloorId,
        roomName: "Panorama Tour",
        roomType: nil,
        roomVariant: 1,
        captureId: "cap_panorama_\(bundleURL.lastPathComponent.lowercased())",
        captureType: "video_walkthrough",
        captureSubtype: "panorama_tour",
        captureTimestamp: createdAt,
        tasks: ["stabilization"],
        stylePreset: nil,
        sensorData: panoramaSensorData,
        intendedProcessing: nil
      )

      let bundleFiles = (try? FileManager.default.contentsOfDirectory(
        at: bundleURL,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
      )) ?? []

      let videoFiles = bundleFiles.filter { url in
        let ext = url.pathExtension.lowercased()
        return ext == "mp4" || ext == "mov"
      }.sorted { $0.lastPathComponent < $1.lastPathComponent }

      if let videoURL = videoFiles.first {
        var videoMetaPayload: [String: JSONValue] = [:]
        if let fps = metadataObject?["fps"] as? NSNumber {
          videoMetaPayload["fps"] = .number(fps.doubleValue)
        }
        if let codec = metadataObject?["codec"] as? String, !codec.isEmpty {
          videoMetaPayload["codec"] = .string(codec)
        }
        if let profile = metadataObject?["codec_profile"] as? String, !profile.isEmpty {
          videoMetaPayload["codec_profile"] = .string(profile)
        }

        if let prepared = try? makePreparedTarget(
          fileId: "panorama_\(bundleURL.lastPathComponent.lowercased())_video",
          recordId: nil,
          fileURL: videoURL,
          relativePath: "PanoramaTours/\(bundleURL.lastPathComponent)/\(videoURL.lastPathComponent)",
          capture: capture,
          cameraMetadata: nil,
          videoMetadata: videoMetaPayload.isEmpty ? nil : .object(videoMetaPayload),
          motionMetadata: nil,
          intrinsicsMetadata: nil,
          trackingMetadata: nil,
          floorplanMetadata: nil,
          fileMetadata: nil
        ) {
          targets.append(prepared)
        }
      }

      // `metadata.json` is intentionally not transferred: it contains the internal
      // `linked_floorplan` key used only to find the tour on-device. The media
      // package must never carry a floorplan, its project key, or its metadata.
    }

    return targets
  }

  private func createUploadSessionContext(
    jobId: String,
    preparedTargets: [PreparedUploadTarget],
    token: String,
    userId: String,
    identityHint: PixcaptureUploadIdentityHint?
  ) async throws -> UploadSessionContext {
    let manifest = makeUploadSessionManifest(
      jobId: jobId,
      userId: userId,
      preparedTargets: preparedTargets,
      namingOverride: identityHint.map {
        UploadSessionManifestNamingOverride(cust3: $0.cust3, job5: $0.job5)
      }
    )
    let body = UploadSessionCreateEnvelope(
      job_id: jobId,
      client_type: "pixcapture_ios",
      include_upload_urls: false,
      manifest: manifest
    )

    let response: UploadSessionCreateResponse = try await apiRequest(
      path: "/api/upload-sessions",
      method: "POST",
      token: token,
      body: body
    )

    let sessionId = response.sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sessionId.isEmpty else {
      throw invalidResponse("Upload-Session-Antwort ohne sessionId.")
    }

    return try buildUploadSessionContext(
      sessionId: sessionId,
      expectedFileCount: response.expectedFiles,
      expectedTotalBytes: response.totalBytesExpected,
      manifestPath: response.manifestSidecarPath,
      files: response.files,
      filesToUpload: response.filesToUpload,
      preparedTargets: preparedTargets,
      initialWarnings: response.warnings ?? []
    )
  }

  private func createUploadSessionContextViaWebConnect(
    jobId: String,
    preparedTargets: [PreparedUploadTarget],
    token: String,
    userId: String,
    webSessionId: String,
    apiBaseURL: URL?,
    identityHint: PixcaptureUploadIdentityHint?,
    progress: ((PixcaptureUploadProgress) -> Void)?
  ) async throws -> UploadSessionContext {
    let manifest = makeUploadSessionManifest(
      jobId: jobId,
      userId: userId,
      preparedTargets: preparedTargets,
      namingOverride: UploadSessionManifestNamingOverride(
        cust3: identityHint?.cust3,
        job5: identityHint?.job5
      )
    )
    let body = MobileWebConnectHandshakeRequest(
      schema: webConnectHandshakeSchema,
      web_session_id: webSessionId,
      project_id: manifest.project_id,
      job_id: jobId,
      cust3: manifest.cust3,
      job5: manifest.job5,
      naming_version: webConnectNamingVersion,
      client_type: "pixcapture_ios",
      app_version: currentAppVersionString(),
      capabilities: MobileWebConnectHandshakeCapabilities(
        supports_capture_v2: true,
        supports_floor_id: true,
        supports_view_id: false,
        supports_raw_brackets: true
      ),
      manifest_summary: MobileWebConnectHandshakeManifestSummary(
        capture_count: Set(preparedTargets.map(\.capture.captureId)).count,
        file_count: preparedTargets.count,
        total_bytes: preparedTargets.reduce(0) { $0 + $1.sizeBytes }
      ),
      manifest: manifest
    )

    let handshake: MobileWebConnectHandshakeResponse = try await apiRequest(
      path: "/api/v2/mobile/handshake",
      method: "POST",
      token: token,
      body: body,
      apiBaseURL: apiBaseURL
    )

    let uploadSessionId = handshake.uploadSessionId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !uploadSessionId.isEmpty else {
      throw invalidResponse("Handshake-Antwort ohne upload_session_id.")
    }

    var warnings = handshake.warnings ?? []
    if let resolved = handshake.resolved {
      let resolvedJobId = resolved.jobId.trimmingCharacters(in: .whitespacesAndNewlines)
      if !resolvedJobId.isEmpty, resolvedJobId != jobId {
        warnings.append("web_connect.resolved_job_id:\(resolvedJobId)")
      }
      if let resolvedCust3 = normalizedManifestIdentityCode(resolved.cust3, expectedLength: 3),
         let manifestCust3 = normalizedManifestIdentityCode(manifest.cust3, expectedLength: 3),
         resolvedCust3 != manifestCust3 {
        warnings.append("web_connect.resolved_cust3:\(resolvedCust3)")
      }
      if let resolvedJob5 = normalizedManifestIdentityCode(resolved.job5, expectedLength: 5),
         let manifestJob5 = normalizedManifestIdentityCode(manifest.job5, expectedLength: 5),
         resolvedJob5 != manifestJob5 {
        warnings.append("web_connect.resolved_job5:\(resolvedJob5)")
      }
      if let resolvedNamingVersion = resolved.namingVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
         !resolvedNamingVersion.isEmpty,
         resolvedNamingVersion != webConnectNamingVersion {
        throw PixcaptureUploadError.api("Web-Connect verwendet eine nicht unterstützte Naming-Version.")
      }
    }
    if handshake.requirements?.viewIdRequired == true {
      throw PixcaptureUploadError.api("Diese Web-Connect-Session verlangt view_id. Die aktuelle App-Version unterstützt das noch nicht.")
    }
    var command = handshake.command?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "wait"
    if command != "go" {
      progress?(
        makeProgress(
          mode: .webConnect,
          phase: .waitingForApproval,
          filesDone: 0,
          filesTotal: handshake.expectedFiles ?? preparedTargets.count,
          bytesSent: 0,
          bytesTotal: handshake.totalBytesExpected ?? preparedTargets.reduce(0) { $0 + $1.sizeBytes },
          detail: "Manifest empfangen. Upload wird vorbereitet."
        )
      )
      let commandResponse = try await waitForWebConnectGoCommand(
        webSessionId: webSessionId,
        token: token,
        apiBaseURL: apiBaseURL
      )
      if commandResponse.requirements?.viewIdRequired == true {
        throw PixcaptureUploadError.api("Die Web-Connect-Session verlangt view_id. Bitte die App aktualisieren.")
      }
      command = commandResponse.command?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "wait"
      if let commandWarnings = commandResponse.warnings {
        warnings.append(contentsOf: commandWarnings)
      }
    }
    if command != "go" {
      throw PixcaptureUploadError.api("Web-Connect-Startsignal nicht erhalten.")
    }

    progress?(
      makeProgress(
        mode: .webConnect,
        phase: .uploading,
        filesDone: 0,
        filesTotal: handshake.expectedFiles ?? preparedTargets.count,
        bytesSent: 0,
        bytesTotal: handshake.totalBytesExpected ?? preparedTargets.reduce(0) { $0 + $1.sizeBytes },
        detail: NSLocalizedString("upload.progress.manifestConfirmed", comment: "")
      )
    )

    return try buildUploadSessionContext(
      sessionId: uploadSessionId,
      expectedFileCount: handshake.expectedFiles,
      expectedTotalBytes: handshake.totalBytesExpected,
      manifestPath: handshake.manifestSidecarPath,
      files: handshake.files,
      filesToUpload: handshake.filesToUpload,
      preparedTargets: preparedTargets,
      initialWarnings: warnings
    )
  }

  private func waitForWebConnectGoCommand(
    webSessionId: String,
    token: String,
    apiBaseURL: URL?
  ) async throws -> MobileWebConnectCommandResponse {
    let deadline = DispatchTime.now().uptimeNanoseconds + webConnectPollTimeoutNanos

    while true {
      let response: MobileWebConnectCommandResponse = try await apiRequest(
        path: "/api/v2/mobile/web-connect/\(webSessionId)/command",
        method: "GET",
        token: token,
        apiBaseURL: apiBaseURL
      )
      let command = response.command?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "wait"
      if command == "go" {
        return response
      }

      if DispatchTime.now().uptimeNanoseconds >= deadline {
        break
      }
      try await Task.sleep(nanoseconds: webConnectPollIntervalNanos)
    }

    throw PixcaptureUploadError.api("Upload-Start Timeout.")
  }

  private func buildUploadSessionContext(
    sessionId: String,
    expectedFileCount: Int?,
    expectedTotalBytes: Int?,
    manifestPath: String?,
    files: [UploadSessionCreateFileInfo]?,
    filesToUpload: [UploadSessionCreateFileToUpload]?,
    preparedTargets: [PreparedUploadTarget],
    initialWarnings: [String]
  ) throws -> UploadSessionContext {
    var sessionWarnings = initialWarnings
    var itemIdByFileId: [String: String] = [:]
    for target in files ?? [] {
      if let fileId = target.fileId {
        itemIdByFileId[fileId] = target.itemId
      }
    }

    if let filesToUpload, !filesToUpload.isEmpty {
      var uniqueFileIdByFilename: [String: String] = [:]
      var duplicateFilenameTokens = Set<String>()
      for prepared in preparedTargets {
        let token = normalizedFilenameToken(prepared.filename)
        if uniqueFileIdByFilename[token] == nil {
          uniqueFileIdByFilename[token] = prepared.fileId
        } else {
          duplicateFilenameTokens.insert(token)
        }
      }
      for token in duplicateFilenameTokens {
        uniqueFileIdByFilename.removeValue(forKey: token)
      }

      for target in filesToUpload {
        guard let filename = target.originalFilename else { continue }
        guard let fileId = uniqueFileIdByFilename[normalizedFilenameToken(filename)] else {
          continue
        }
        if itemIdByFileId[fileId] == nil {
          itemIdByFileId[fileId] = target.itemId
          sessionWarnings.append("session_mapping_fallback_by_filename:\(filename)")
        }
      }
    }

    guard !itemIdByFileId.isEmpty else {
      throw invalidResponse("Session-Antwort enthaelt kein Dateimapping fuer den Upload.")
    }

    for prepared in preparedTargets where itemIdByFileId[prepared.fileId] == nil {
      sessionWarnings.append("session_mapping_missing:\(prepared.fileId):\(prepared.filename)")
    }

    return UploadSessionContext(
      sessionId: sessionId,
      expectedFileCount: expectedFileCount ?? preparedTargets.count,
      expectedTotalBytes: expectedTotalBytes ?? preparedTargets.reduce(0) { $0 + $1.sizeBytes },
      itemIdByFileId: itemIdByFileId,
      sessionWarnings: sessionWarnings,
      manifestPath: normalizedNonEmptyPath(manifestPath)
    )
  }

  private func uploadViaSession(
    context: UploadSessionContext,
    jobId: String,
    preparedTargets: [PreparedUploadTarget],
    photoRecordIds: [UUID],
    token: String,
    apiBaseURL: URL?,
    mode: PixcaptureUploadMode,
    progress: ((PixcaptureUploadProgress) -> Void)?
  ) async -> PixcaptureUploadResult {
    var verifiedFileIds: Set<String> = []
    var verifiedPhotoRecordIds: Set<UUID> = []
    var failedPhotoRecordIds: Set<UUID> = []
    var verifiedTotalBytes = 0
    var mismatches: [UploadProtocolMismatch] = context.sessionWarnings.map(sessionWarningMismatch(_:))

    let mappedTargets = preparedTargets.filter { context.itemIdByFileId[$0.fileId] != nil }
    let mappedPhotoRecordIds = Set(mappedTargets.compactMap(\.recordId))
    let unmappedPhotoRecordIds = Set(photoRecordIds).subtracting(mappedPhotoRecordIds)
    failedPhotoRecordIds.formUnion(unmappedPhotoRecordIds)

    func emitProgress(
      phase: PixcaptureUploadPhase,
      detail: String,
      currentFileName: String? = nil
    ) {
      progress?(
        makeProgress(
          mode: mode,
          phase: phase,
          filesDone: verifiedFileIds.count,
          filesTotal: mappedTargets.count,
          bytesSent: verifiedTotalBytes,
          bytesTotal: context.expectedTotalBytes,
          detail: detail,
          currentFileName: currentFileName
        )
      )
    }

    for prepared in preparedTargets where context.itemIdByFileId[prepared.fileId] == nil {
      mismatches.append(
        UploadProtocolMismatch(
          fileId: prepared.fileId,
          reason: "item_id fehlt in Session-Antwort (Soft-Fallback: Datei wird übersprungen)"
        )
      )
    }

    emitProgress(phase: .uploading, detail: "Upload-Session bereit. Dateien werden uebertragen.")

    for prepared in mappedTargets {
      guard let itemId = context.itemIdByFileId[prepared.fileId] else {
        mismatches.append(
          UploadProtocolMismatch(
            fileId: prepared.fileId,
            reason: "item_id fehlt in Session-Antwort"
          )
        )
        continue
      }

      emitProgress(
        phase: .uploading,
        detail: "Uebertrage \(prepared.filename)",
        currentFileName: prepared.filename
      )
      do {
        let completionWarnings = try await retryUploadOperation(maxRetries: 2) {
          try await self.uploadSessionFile(
            sessionId: context.sessionId,
            itemId: itemId,
            prepared: prepared,
            token: token,
            apiBaseURL: apiBaseURL
          )
        }
        verifiedFileIds.insert(prepared.fileId)
        if let recordId = prepared.recordId {
          verifiedPhotoRecordIds.insert(recordId)
        }
        verifiedTotalBytes += prepared.sizeBytes
        for warning in completionWarnings where !warning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          mismatches.append(
            UploadProtocolMismatch(fileId: prepared.fileId, reason: warning)
          )
        }
      } catch {
        if let recordId = prepared.recordId {
          failedPhotoRecordIds.insert(recordId)
        }
        mismatches.append(
          UploadProtocolMismatch(
            fileId: prepared.fileId,
            reason: failureReason(error)
          )
        )
      }
      emitProgress(
        phase: .uploading,
        detail: "Datei verarbeitet: \(prepared.filename)",
        currentFileName: prepared.filename
      )
    }

    let finalizeMetrics = UploadSessionFinalizeMetrics(
      total: mappedTargets.count,
      verified: verifiedFileIds.count,
      failed: max(0, mappedTargets.count - verifiedFileIds.count)
    )

    var finalizeResponse: UploadSessionFinalizeResponse?
    emitProgress(phase: .finalizing, detail: "Server prueft Upload und finalisiert.")
    do {
      let maxFinalizeAttempts = mode == .cablePackage || mode == .companionWifi ? 20 : 3
      for attempt in 1...maxFinalizeAttempts {
        let response = try await finalizeUploadSession(
          sessionId: context.sessionId,
          token: token,
          metrics: finalizeMetrics,
          apiBaseURL: apiBaseURL
        )
        finalizeResponse = response

        let status = response.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let phase = response.phase?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isProcessing = status == "processing"
          || status == "package_extracting"
          || status == "package_ready_for_finalize"
          || phase == "package_extracting"
          || phase == "package_ready_for_finalize"

        guard isProcessing else {
          break
        }

        let detail = response.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        emitProgress(
          phase: .finalizing,
          detail: detail?.isEmpty == false
            ? detail!
            : "Server entpackt das verschluesselte Paket. Runde \(attempt)/\(maxFinalizeAttempts)."
        )

        if attempt < maxFinalizeAttempts {
          try await Task.sleep(nanoseconds: 2_000_000_000)
        }
      }
    } catch {
      mismatches.append(
        UploadProtocolMismatch(
          fileId: "session",
          reason: "Finalize fehlgeschlagen: \(failureReason(error))"
        )
      )
    }

    if let finalizeResponse {
      if let warnings = finalizeResponse.warnings {
        mismatches.append(contentsOf: warnings.map {
          UploadProtocolMismatch(fileId: "session", reason: $0)
        })
      }

      if let files = finalizeResponse.files, !files.isEmpty {
        let finalizedItemIds = Set(files.map(\.itemId))
        for prepared in mappedTargets {
          guard let itemId = context.itemIdByFileId[prepared.fileId] else { continue }
          guard !finalizedItemIds.contains(itemId) else { continue }
          mismatches.append(
            UploadProtocolMismatch(
              fileId: itemId,
              reason: "Finalize enthält kein canonical Mapping für dieses Item."
            )
          )
        }
      }

      if let status = finalizeResponse.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
         status != "completed" && status != "selecting" {
        mismatches.append(
          UploadProtocolMismatch(fileId: "session", reason: "Finalize-Status: \(status)")
        )
      }

      if let metricsMatch = finalizeResponse.metricsMatch, metricsMatch == false {
        mismatches.append(
          UploadProtocolMismatch(fileId: "session", reason: "Finalize-Metrics stimmen nicht mit dem Serverstand überein.")
        )
      }

      if let serverVerified = finalizeResponse.serverVerified,
         serverVerified != verifiedFileIds.count {
        mismatches.append(
          UploadProtocolMismatch(
            fileId: "session",
            reason: "Server meldet \(serverVerified) verifizierte Dateien, App \(verifiedFileIds.count)."
          )
        )
      }
    }

    let receiptVerificationMismatches = verifyRequiredMetadataReceipt(
      finalizeResponse: finalizeResponse,
      context: context,
      preparedTargets: mappedTargets
    )
    mismatches.append(contentsOf: receiptVerificationMismatches)
    let verificationFailed = receiptVerificationMismatches.contains { $0.isCriticalForUploadCompletion }

    let unresolvedPhotoRecordIds = Set(photoRecordIds)
      .subtracting(verifiedPhotoRecordIds)
      .subtracting(failedPhotoRecordIds)
    failedPhotoRecordIds.formUnion(unresolvedPhotoRecordIds)

    let finalReceivedBytes = finalizeResponse?.actualTotalSizeBytes ?? verifiedTotalBytes
    let finalReceivedFileCount = finalizeResponse?.filesDetailed?.count
      ?? finalizeResponse?.files?.count
      ?? verifiedFileIds.count
    let protocolLog = UploadProtocolLog(
      id: UUID(),
      uploadId: context.sessionId,
      jobId: jobId,
      createdAt: Date(),
      expectedFileCount: context.expectedFileCount,
      expectedTotalBytes: context.expectedTotalBytes,
      receivedFileCount: finalReceivedFileCount,
      receivedTotalBytes: finalReceivedBytes,
      complete: failedPhotoRecordIds.isEmpty && finalizeResponse != nil && !verificationFailed,
      mismatches: mismatches,
      manifestPath: context.manifestPath,
      receiptPath: normalizedNonEmptyPath(finalizeResponse?.receiptPath),
      filesDetailed: finalizeResponse?.filesDetailed
    )

    return PixcaptureUploadResult(
      uploadedRecordIds: Array(verifiedPhotoRecordIds),
      failedRecordIds: Array(failedPhotoRecordIds),
      protocolLogs: [protocolLog],
      mode: mode,
      filesDone: mappedTargets.count,
      filesTotal: mappedTargets.count,
      bytesSent: verifiedTotalBytes,
      bytesTotal: context.expectedTotalBytes,
      verificationFailed: verificationFailed
    )
  }

  private func uploadSessionFile(
    sessionId: String,
    itemId: String,
    prepared: PreparedUploadTarget,
    token: String,
    apiBaseURL: URL?,
    progress: ((Int, Int) -> Void)? = nil
  ) async throws -> [String] {
    let presign: UploadSessionPresignResponse
    do {
      presign = try await presignUploadSessionFile(
        sessionId: sessionId,
        itemId: itemId,
        sizeBytes: prepared.sizeBytes,
        token: token,
        apiBaseURL: apiBaseURL
      )
    } catch PixcaptureUploadError.apiStatus(let code, let message) where code == 409 {
      return ["Item bereits verifiziert (Presign \(code): \(message))"]
    }

    let multipartPayload: UploadSessionMultipartCompletePayload?
    switch presign.uploadType.lowercased() {
    case "direct":
      guard let uploadURL = presign.uploadUrl, !uploadURL.isEmpty else {
        throw invalidResponse("Presign-Antwort fuer \(prepared.filename) enthaelt keine uploadUrl.")
      }
      _ = try await putFile(urlString: uploadURL, fileURL: prepared.fileURL, mimeType: prepared.mimeType)
      progress?(prepared.sizeBytes, prepared.sizeBytes)
      multipartPayload = nil

    case "multipart":
      guard let uploadId = presign.uploadId, !uploadId.isEmpty,
            let parts = presign.parts, !parts.isEmpty else {
        throw invalidResponse("Multipart-Presign fuer \(prepared.filename) ist unvollstaendig (uploadId/parts fehlen).")
      }
      let uploadedParts = try await uploadMultipartFile(
        fileURL: prepared.fileURL,
        sizeBytes: prepared.sizeBytes,
        mimeType: prepared.mimeType,
        parts: parts,
        progress: progress
      )
      multipartPayload = UploadSessionMultipartCompletePayload(
        upload_id: uploadId,
        parts: uploadedParts
      )

    default:
      throw PixcaptureUploadError.api("Unbekannter Upload-Typ: \(presign.uploadType)")
    }

    let complete = try await completeUploadSessionFile(
      sessionId: sessionId,
      itemId: itemId,
      checksumSha256: prepared.checksumSha256,
      sizeBytes: prepared.sizeBytes,
      multipart: multipartPayload,
      token: token,
      apiBaseURL: apiBaseURL
    )

    if let status = complete.status?.lowercased(), status != "verified" {
      throw PixcaptureUploadError.api("Complete-Status ist nicht verified (\(status)).")
    }

    return complete.warnings ?? []
  }

  private func verifyRequiredMetadataReceipt(
    finalizeResponse: UploadSessionFinalizeResponse?,
    context: UploadSessionContext,
    preparedTargets: [PreparedUploadTarget]
  ) -> [UploadProtocolMismatch] {
    guard finalizeResponse != nil else {
      return []
    }

    var mismatches: [UploadProtocolMismatch] = []

    if normalizedNonEmptyPath(finalizeResponse?.receiptPath) == nil {
      mismatches.append(
        UploadProtocolMismatch(
          fileId: "session",
          reason: "Pflicht-Metadaten fehlen: receipt_path fehlt im Finalize-Response."
        )
      )
    }

    guard let receiptFiles = finalizeResponse?.filesDetailed, !receiptFiles.isEmpty else {
      mismatches.append(
        UploadProtocolMismatch(
          fileId: "session",
          reason: "Pflicht-Metadaten fehlen: files_detailed fehlt im Finalize-Response."
        )
      )
      return mismatches
    }

    let receiptByItemId = Dictionary(uniqueKeysWithValues: receiptFiles.map { ($0.itemId, $0) })
    for prepared in preparedTargets {
      guard let itemId = context.itemIdByFileId[prepared.fileId] else { continue }
      guard let receipt = receiptByItemId[itemId] else {
        mismatches.append(
          UploadProtocolMismatch(
            fileId: prepared.fileId,
            reason: "Receipt fehlt: Kein files_detailed-Eintrag fuer \(prepared.filename)."
          )
        )
        continue
      }

      let missingKeys = missingReceiptMetadata(for: prepared, receipt: receipt)
      if !missingKeys.isEmpty {
        mismatches.append(
          UploadProtocolMismatch(
            fileId: prepared.fileId,
            reason: "Pflicht-Metadaten fehlen: \(missingKeys.joined(separator: ", "))"
          )
        )
      }
    }

    return mismatches
  }

  private func sessionWarningMismatch(_ warning: String) -> UploadProtocolMismatch {
    if warning.hasPrefix("session_mapping_missing:") {
      let components = warning.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
      let filename = components.count >= 3 ? String(components[2]) : "unbekannte Datei"
      return UploadProtocolMismatch(
        fileId: "session",
        reason: "Pflicht-Metadaten fehlen: Session-Mapping fuer \(filename) fehlt."
      )
    }
    if warning.hasPrefix("session_mapping_fallback_by_filename:") {
      let filename = warning.replacingOccurrences(of: "session_mapping_fallback_by_filename:", with: "")
      return UploadProtocolMismatch(
        fileId: "session",
        reason: "Session-Mapping per Dateiname verwendet: \(filename)"
      )
    }
    return UploadProtocolMismatch(fileId: "session", reason: warning)
  }

  private func missingReceiptMetadata(
    for prepared: PreparedUploadTarget,
    receipt: UploadProtocolReceiptFile
  ) -> [String] {
    var missing: [String] = []

    if prepared.capture.sensorData != nil && receipt.sensorData == nil {
      missing.append("sensor_data")
    }
    if prepared.cameraMetadata != nil && receipt.cameraMetadata == nil {
      missing.append("camera_metadata")
    }
    if prepared.videoMetadata != nil && receipt.videoMetadata == nil {
      missing.append("video_metadata")
    }
    if prepared.motionMetadata != nil && receipt.motionMetadata == nil {
      missing.append("motion_metadata")
    }
    if prepared.intrinsicsMetadata != nil && receipt.intrinsicsMetadata == nil {
      missing.append("intrinsics_metadata")
    }
    if prepared.trackingMetadata != nil && receipt.trackingMetadata == nil {
      missing.append("tracking_metadata")
    }
    if prepared.floorplanMetadata != nil && receipt.floorplanMetadata == nil {
      missing.append("floorplan_metadata")
    }
    if prepared.fileMetadata != nil && receipt.fileMetadata == nil {
      missing.append("file_metadata")
    }

    if let expectedMetadataRole = metadataRole(in: prepared.fileMetadata),
       metadataRole(in: receipt.fileMetadata) != expectedMetadataRole {
      missing.append("file_metadata.metadata_role=\(expectedMetadataRole)")
    }

    return missing
  }

  private func metadataRole(in metadata: JSONValue?) -> String? {
    metadata?.objectValue?["metadata_role"]?.stringValue
  }

  private func normalizedNonEmptyPath(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
          !trimmed.isEmpty else {
      return nil
    }
    return trimmed
  }

  private func presignUploadSessionFile(
    sessionId: String,
    itemId: String,
    sizeBytes: Int,
    token: String,
    apiBaseURL: URL?
  ) async throws -> UploadSessionPresignResponse {
    let partsHint: Int?
    if sizeBytes > directUploadMaxBytes {
      partsHint = max(2, Int(ceil(Double(sizeBytes) / Double(targetMultipartPartBytes))))
    } else {
      partsHint = nil
    }

    return try await apiRequest(
      path: "/api/upload-sessions/\(sessionId)/files/\(itemId)/presign",
      method: "POST",
      token: token,
      body: UploadSessionPresignRequest(parts: partsHint),
      apiBaseURL: apiBaseURL
    )
  }

  private func completeUploadSessionFile(
    sessionId: String,
    itemId: String,
    checksumSha256: String?,
    sizeBytes: Int,
    multipart: UploadSessionMultipartCompletePayload?,
    token: String,
    apiBaseURL: URL?
  ) async throws -> UploadSessionCompleteResponse {
    let body = UploadSessionCompleteRequest(
      checksum_sha256: checksumSha256,
      size_bytes: sizeBytes,
      multipart: multipart
    )

    return try await apiRequest(
      path: "/api/upload-sessions/\(sessionId)/files/\(itemId)/complete",
      method: "POST",
      token: token,
      body: body,
      apiBaseURL: apiBaseURL
    )
  }

  private func finalizeUploadSession(
    sessionId: String,
    token: String,
    metrics: UploadSessionFinalizeMetrics,
    apiBaseURL: URL?
  ) async throws -> UploadSessionFinalizeResponse {
    let body = UploadSessionFinalizeRequest(
      apply_renaming: true,
      total_size_tolerance_percent: finalizeTolerancePercent,
      metrics: metrics
    )

    return try await apiRequest(
      path: "/api/upload-sessions/\(sessionId)/finalize",
      method: "POST",
      token: token,
      body: body,
      apiBaseURL: apiBaseURL
    )
  }

  private func uploadMultipartFile(
    fileURL: URL,
    sizeBytes: Int,
    mimeType: String,
    parts: [UploadSessionPresignPart],
    progress: ((Int, Int) -> Void)? = nil
  ) async throws -> [UploadSessionMultipartPart] {
    let sortedParts = parts.sorted { $0.partNumber < $1.partNumber }
    guard !sortedParts.isEmpty else {
      throw invalidResponse("Multipart-Presign enthaelt keine Parts.")
    }

    let handle = try FileHandle(forReadingFrom: fileURL)
    defer {
      try? handle.close()
    }

    var uploadedBytes = 0
    var completedParts: [UploadSessionMultipartPart] = []

    for (index, part) in sortedParts.enumerated() {
      let remainingBytes = sizeBytes - uploadedBytes
      let remainingParts = sortedParts.count - index
      guard remainingBytes > 0 else {
        throw invalidResponse("Multipart-Upload ist inkonsistent: keine Restbytes mehr vorhanden.")
      }

      let chunkSize = max(1, Int(ceil(Double(remainingBytes) / Double(remainingParts))))
      guard let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty else {
        throw invalidResponse("Datei konnte fuer Multipart-Upload nicht gelesen werden.")
      }

      let response = try await putFile(
        urlString: part.uploadUrl,
        data: chunk,
        mimeType: mimeType
      )

      guard let etag = extractETag(from: response) else {
        throw invalidResponse("Upload erfolgreich, aber ETag fehlt fuer einen Multipart-Teil.")
      }

      completedParts.append(
        UploadSessionMultipartPart(part_number: part.partNumber, etag: etag)
      )
      uploadedBytes += chunk.count
      progress?(uploadedBytes, sizeBytes)
    }

    if uploadedBytes != sizeBytes {
      throw invalidResponse("Multipart-Upload unvollstaendig uebertragen.")
    }

    return completedParts
  }

  private func extractETag(from response: HTTPURLResponse) -> String? {
    guard let raw = response.value(forHTTPHeaderField: "ETag") else {
      return nil
    }
    let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return token.isEmpty ? nil : token
  }

  @discardableResult
  private func putFile(urlString: String, data: Data, mimeType: String) async throws -> HTTPURLResponse {
    guard let url = URL(string: urlString) else {
      throw invalidResponse(NSLocalizedString("upload.error.invalidUploadURL", comment: ""))
    }
    var request = URLRequest(url: url)
    request.httpMethod = "PUT"
    request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
    request.httpBody = data
    let (responseData, response) = try await networkSession.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw invalidResponse("Upload-URL lieferte keinen HTTP-Status.")
    }
    guard (200...299).contains(http.statusCode) else {
      let message = uploadHTTPFailureMessage(
        statusCode: http.statusCode,
        responseData: responseData,
        requestURL: url,
        mimeType: mimeType
      )
      throw PixcaptureUploadError.apiStatus(code: http.statusCode, message: message)
    }
    return http
  }

  @discardableResult
  private func putFile(urlString: String, fileURL: URL, mimeType: String) async throws -> HTTPURLResponse {
    guard let url = URL(string: urlString) else {
      throw invalidResponse(NSLocalizedString("upload.error.invalidUploadURL", comment: ""))
    }
    var request = URLRequest(url: url)
    request.httpMethod = "PUT"
    request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
    let (responseData, response) = try await networkSession.upload(for: request, fromFile: fileURL)
    guard let http = response as? HTTPURLResponse else {
      throw invalidResponse("Upload-URL lieferte keinen HTTP-Status.")
    }
    guard (200...299).contains(http.statusCode) else {
      let message = uploadHTTPFailureMessage(
        statusCode: http.statusCode,
        responseData: responseData,
        requestURL: url,
        mimeType: mimeType
      )
      throw PixcaptureUploadError.apiStatus(code: http.statusCode, message: message)
    }
    return http
  }

  private func apiRequest<T: Decodable, B: Encodable>(
    path: String,
    method: String,
    token: String,
    body: B,
    apiBaseURL: URL? = nil
  ) async throws -> T {
    let resolvedBaseURL = apiBaseURL ?? baseURL
    guard let url = URL(string: path, relativeTo: resolvedBaseURL) else {
      throw invalidResponse("Interne Request-URL ist ungültig (\(path)).")
    }

    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.httpBody = try JSONEncoder().encode(body)

    let (data, response) = try await networkSession.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw invalidResponse("Serverantwort fuer \(path) enthaelt keinen HTTP-Status.")
    }

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    guard (200...299).contains(http.statusCode) else {
      let rawMessage = (try? decoder.decode(APIError.self, from: data).error) ?? "Serverfehler (\(http.statusCode))."
      let message = normalizedAPIErrorMessage(rawMessage, statusCode: http.statusCode)
      throw PixcaptureUploadError.apiStatus(code: http.statusCode, message: message)
    }

    do {
      return try decoder.decode(T.self, from: data)
    } catch {
      throw invalidResponse("Serverantwort fuer \(path) konnte nicht gelesen werden: \(decodingFailureReason(error)).")
    }
  }

  private func apiRequestVoid<B: Encodable>(
    path: String,
    method: String,
    token: String,
    body: B,
    apiBaseURL: URL? = nil
  ) async throws {
    let rawBody = try JSONEncoder().encode(body)
    try await apiRequestVoid(path: path, method: method, token: token, rawBody: rawBody, apiBaseURL: apiBaseURL)
  }

  private func apiRequestVoid(
    path: String,
    method: String,
    token: String,
    rawBody: Data,
    apiBaseURL: URL? = nil
  ) async throws {
    let resolvedBaseURL = apiBaseURL ?? baseURL
    guard let url = URL(string: path, relativeTo: resolvedBaseURL) else {
      throw invalidResponse("Interne Request-URL ist ungültig (\(path)).")
    }

    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.httpBody = rawBody

    let (data, response) = try await networkSession.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw invalidResponse("Serverantwort fuer \(path) enthaelt keinen HTTP-Status.")
    }

    if !(200...299).contains(http.statusCode) {
      let decoder = JSONDecoder()
      decoder.keyDecodingStrategy = .convertFromSnakeCase
      let rawMessage = (try? decoder.decode(APIError.self, from: data).error) ?? "Serverfehler (\(http.statusCode))."
      let message = normalizedAPIErrorMessage(rawMessage, statusCode: http.statusCode)
      throw PixcaptureUploadError.apiStatus(code: http.statusCode, message: message)
    }
  }

  private func apiRequest<T: Decodable>(
    path: String,
    method: String,
    token: String,
    apiBaseURL: URL? = nil
  ) async throws -> T {
    let resolvedBaseURL = apiBaseURL ?? baseURL
    guard let url = URL(string: path, relativeTo: resolvedBaseURL) else {
      throw invalidResponse("Interne Request-URL ist ungültig (\(path)).")
    }

    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

    let (data, response) = try await networkSession.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw invalidResponse("Serverantwort fuer \(path) enthaelt keinen HTTP-Status.")
    }

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    guard (200...299).contains(http.statusCode) else {
      let rawMessage = (try? decoder.decode(APIError.self, from: data).error) ?? "Serverfehler (\(http.statusCode))."
      let message = normalizedAPIErrorMessage(rawMessage, statusCode: http.statusCode)
      throw PixcaptureUploadError.apiStatus(code: http.statusCode, message: message)
    }

    do {
      return try decoder.decode(T.self, from: data)
    } catch {
      throw invalidResponse("Serverantwort fuer \(path) konnte nicht gelesen werden: \(decodingFailureReason(error)).")
    }
  }

  private func makeUploadSessionManifest(
    jobId: String,
    userId: String,
    preparedTargets: [PreparedUploadTarget],
    webConnectHandshake: WebConnectUploadHandshake? = nil,
    namingOverride: UploadSessionManifestNamingOverride? = nil
  ) -> UploadSessionManifestPayload {
    let createdAt = preparedTargets.map { $0.capture.captureTimestamp }.min() ?? Date()
    let totalSizeBytes = preparedTargets.reduce(0) { $0 + $1.sizeBytes }
    let totalFiles = preparedTargets.count
    let namingTokens = uploadNamingTokens(jobId: jobId, userId: userId)
    let overrideCust3 = namingOverride?.cust3?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let overrideJob5 = namingOverride?.job5?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedCust3 = (overrideCust3?.isEmpty == false ? overrideCust3 : nil) ?? namingTokens.cust3
    let resolvedJob5 = (overrideJob5?.isEmpty == false ? overrideJob5 : nil) ?? namingTokens.job5
    let projectName = preparedTargets
      .compactMap(\.projectNameHint)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first(where: { !$0.isEmpty })

    let groupedByRoom = Dictionary(grouping: preparedTargets) {
      RoomBucketKey(
        roomId: normalizedManifestRoomId($0.capture.roomId),
        floorId: FloorTaxonomy.normalizedFloorId($0.capture.floorId)
      )
    }

    let sortedRoomKeys = groupedByRoom.keys.sorted { lhs, rhs in
      if lhs.roomId == rhs.roomId {
        return lhs.floorId < rhs.floorId
      }
      return lhs.roomId < rhs.roomId
    }

    var rooms: [UploadSessionManifestRoom] = []
    for roomKey in sortedRoomKeys {
      guard let roomTargets = groupedByRoom[roomKey], !roomTargets.isEmpty else { continue }

      let capturesById = Dictionary(grouping: roomTargets) { $0.capture.captureId }
      let sortedCaptureIds = capturesById.keys.sorted { lhs, rhs in
        let leftTimestamp = capturesById[lhs]?.first?.capture.captureTimestamp ?? Date.distantFuture
        let rightTimestamp = capturesById[rhs]?.first?.capture.captureTimestamp ?? Date.distantFuture
        if leftTimestamp == rightTimestamp {
          return lhs < rhs
        }
        return leftTimestamp < rightTimestamp
      }

      var captures: [UploadSessionCapture] = []
      for captureId in sortedCaptureIds {
        guard let captureTargets = capturesById[captureId], !captureTargets.isEmpty else { continue }
        let sortedCaptureTargets = captureTargets.sorted { lhs, rhs in
          if lhs.filename == rhs.filename {
            return lhs.fileId < rhs.fileId
          }
          return lhs.filename < rhs.filename
        }
        let captureTime = sortedCaptureTargets.map { $0.capture.captureTimestamp }.min() ?? createdAt
        guard let firstCaptureTarget = sortedCaptureTargets.first else { continue }

        let files = sortedCaptureTargets.map {
          UploadSessionManifestFile(
            file_id: $0.fileId,
            filename: $0.filename,
            relative_path: $0.relativePath,
            motif_index: $0.motifIndex,
            exposure_index: $0.exposureIndex,
            type: $0.mimeType,
            size_bytes: $0.sizeBytes,
            checksum_sha256: $0.checksumSha256,
            camera_metadata: $0.cameraMetadata,
            video_metadata: $0.videoMetadata,
            motion_metadata: $0.motionMetadata,
            intrinsics_metadata: $0.intrinsicsMetadata,
            tracking_metadata: $0.trackingMetadata,
            floorplan_metadata: $0.floorplanMetadata,
            file_metadata: $0.fileMetadata
          )
        }

        captures.append(
          UploadSessionCapture(
            capture_id: firstCaptureTarget.capture.captureId,
            capture_type: firstCaptureTarget.capture.captureType,
            capture_subtype: firstCaptureTarget.capture.captureSubtype,
            timestamp: isoTimestamp(captureTime),
            tasks: firstCaptureTarget.capture.tasks.isEmpty ? nil : firstCaptureTarget.capture.tasks,
            style_preset: firstCaptureTarget.capture.stylePreset,
            sensor_data: firstCaptureTarget.capture.sensorData,
            intended_processing: firstCaptureTarget.capture.intendedProcessing,
            files: files
          )
        )
      }

      guard let firstRoomTarget = roomTargets.first else { continue }

      let room = UploadSessionManifestRoom(
        room_id: roomKey.roomId,
        floor_id: roomKey.floorId,
        room_name: firstRoomTarget.capture.roomName,
        room_type: firstRoomTarget.capture.roomType,
        room_variant: firstRoomTarget.capture.roomVariant,
        captures: captures
      )
      rooms.append(room)
    }

    return UploadSessionManifestPayload(
      version: "2.0",
      project_id: jobId,
      cust3: resolvedCust3,
      job5: resolvedJob5,
      project_name: (projectName?.isEmpty == false) ? projectName : nil,
      web_session_id: webConnectHandshake?.webSessionId,
      web_job_id: webConnectHandshake?.jobId,
      companion_transport: webConnectHandshake?.companionTransport,
      cable_receiver_token: webConnectHandshake?.cableReceiverToken,
      shot_id: namingTokens.shotId,
      created_at: isoTimestamp(createdAt),
      total_size_bytes: totalSizeBytes,
      total_files: totalFiles,
      device_info: deviceInfoForManifest(),
      rooms: rooms,
      global_preferences: globalPreferencesForManifest()
    )
  }

  private func deviceInfoForManifest() -> UploadSessionDeviceInfo {
    return UploadSessionDeviceInfo(
      model: UIDevice.current.model,
      os_version: UIDevice.current.systemVersion,
      app_version: currentAppVersionString()
    )
  }

  private func roomTypeForManifest(roomId: String) -> String? {
    let normalizedRoomId = RoomTaxonomy.normalizedRoomId(roomId)
    return normalizedRoomId.isEmpty ? nil : normalizedRoomId
  }

  private func normalizedManifestRoomId(_ roomId: String) -> String {
    let trimmed = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty {
      return trimmed
    }
    return RoomTaxonomy.defaultRoomId
  }

  private func roomNameForManifest(roomId: String, floorId: String) -> String {
    let room = RoomTaxonomy.room(id: roomId)
    let floor = FloorTaxonomy.floor(id: floorId)
    if floorId == FloorTaxonomy.defaultFloorId {
      return room.nameEN
    }
    return "\(room.nameEN) (\(floor.shortEN))"
  }

  private func photoCaptureDescriptorForManifest(
    record: UploadRecord,
    captureTimestampBySeries: [UUID: Date]
  ) -> SessionCaptureDescriptor {
    let roomId = RoomTaxonomy.normalizedRoomId(record.roomId)
    let floorId = FloorTaxonomy.normalizedFloorId(record.floorId)
    return SessionCaptureDescriptor(
      roomId: roomId,
      floorId: floorId,
      roomName: roomNameForManifest(roomId: roomId, floorId: floorId),
      roomType: roomTypeForManifest(roomId: roomId),
      roomVariant: 1,
      captureId: "cap_\(record.seriesId.uuidString.lowercased())",
      captureType: record.captureMode == .singleShot ? "single_photo" : "bracketed_photo",
      captureSubtype: record.captureMode.manifestSubtype,
      captureTimestamp: captureTimestampBySeries[record.seriesId] ?? record.createdAt,
      tasks: tasksForPhotoCapture(record.captureMode),
      stylePreset: nil,
      sensorData: sensorDataForManifest(record: record),
      intendedProcessing: record.singleShotAssessment?.intendedProcessing
    )
  }

  private func tasksForPhotoCapture(_ mode: PhotoCaptureMode) -> [String] {
    switch mode {
    case .darkRoom:
      return ["low_light_capture"]
    case .singleShot:
      return [SingleShotCorrectionPolicy.intendedProcessing]
    case .standardBracket:
      return ["hdr_merge"]
    }
  }

  private func photoRelativeDirectory(for record: UploadRecord) -> String {
    let roomId = pathToken(RoomTaxonomy.normalizedRoomId(record.roomId))
    let floorId = pathToken(FloorTaxonomy.normalizedFloorId(record.floorId))
    let seriesToken = record.seriesId.uuidString.lowercased()
    if FloorTaxonomy.normalizedFloorId(record.floorId) == FloorTaxonomy.defaultFloorId {
      return "photo/\(roomId)/series-\(seriesToken)"
    }
    return "photo/\(floorId)/\(roomId)/series-\(seriesToken)"
  }

  private func photoRelativePath(for record: UploadRecord, fileURL: URL) -> String {
    "\(photoRelativeDirectory(for: record))/\(fileURL.lastPathComponent)"
  }

  private func companionXMPURL(for fileURL: URL) -> URL? {
    let directory = fileURL.deletingLastPathComponent()
    let basename = fileURL.deletingPathExtension().lastPathComponent
    let candidate = directory.appendingPathComponent("\(basename).xmp")
    guard FileManager.default.fileExists(atPath: candidate.path) else {
      return nil
    }
    return candidate
  }

  private func companionDepthURL(for fileURL: URL) -> URL? {
    let candidate = FileStore.companionDepthURL(for: fileURL)
    guard FileManager.default.fileExists(atPath: candidate.path) else {
      return nil
    }
    return candidate
  }

  private func cameraMetadataForManifest(
    record: UploadRecord,
    exifSnapshot: PhotoExifSnapshot?
  ) -> UploadSessionCameraMetadata {
    let shutter = shutterSpeedString(seconds: record.exposureSeconds)
    let roundedISO = Int(record.iso.rounded())
    let exifISO = exifSnapshot?.iso.flatMap { Int($0.rounded()) }
    let resolvedISO: Int?
    if roundedISO > 0 {
      resolvedISO = roundedISO
    } else if let exifISO, exifISO > 0 {
      resolvedISO = exifISO
    } else {
      resolvedISO = nil
    }
    return UploadSessionCameraMetadata(
      exposureValue: record.exposureEV,
      iso: resolvedISO,
      shutterSpeed: shutter,
      aperture: normalizedPositiveNumber(exifSnapshot?.fNumber),
      whiteBalanceKelvin: currentWhiteBalanceKelvinForManifest(),
      focalLengthMm: normalizedPositiveNumber(exifSnapshot?.focalLength),
      lensModel: normalizedStringToken(exifSnapshot?.lensModel),
      captureOrientation: normalizedStringToken(record.captureOrientation),
      whiteBalanceMode: whiteBalanceModeForManifest(exifWhiteBalanceCode: exifSnapshot?.whiteBalance)
    )
  }

  private func sensorDataForManifest(record: UploadRecord) -> UploadSessionSensorData? {
    let pitch = normalizedSensorDegree(record.sensorPitchDegrees)
    let roll = normalizedSensorDegree(record.sensorRollDegrees)
    let heading = normalizedHeadingDegree(record.sensorHeadingDegrees)
    if pitch == nil, roll == nil, heading == nil, record.singleShotAssessment == nil {
      return nil
    }
    return UploadSessionSensorData(
      pitchDegrees: pitch,
      rollDegrees: roll,
      headingDegrees: heading,
      singleShotAssessment: record.singleShotAssessment
    )
  }

  private func normalizedSensorDegree(_ value: Double?) -> Double? {
    guard let value, value.isFinite else { return nil }
    return value
  }

  private func normalizedHeadingDegree(_ value: Double?) -> Double? {
    guard let normalized = normalizedSensorDegree(value) else { return nil }
    var heading = normalized.truncatingRemainder(dividingBy: 360)
    if heading < 0 {
      heading += 360
    }
    return heading
  }

  private func normalizedPositiveNumber(_ value: Double?) -> Double? {
    guard let value, value.isFinite, value > 0 else { return nil }
    return value
  }

  private func normalizedStringToken(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private func whiteBalanceModeForManifest(exifWhiteBalanceCode: Int?) -> String {
    let defaults = UserDefaults.standard
    if defaults.object(forKey: "whiteBalanceLocked") != nil {
      return defaults.bool(forKey: "whiteBalanceLocked") ? "locked" : "awb"
    }
    if let exifWhiteBalanceCode {
      return exifWhiteBalanceCode == 1 ? "locked" : "awb"
    }
    return "awb"
  }

  private func photoFileMetadataForManifest(
    record: UploadRecord,
    exifSnapshot: PhotoExifSnapshot?,
    uploadIndices: PhotoUploadIndices?
  ) -> JSONValue? {
    let exifLogEntry = readExifLogEntry(for: record)
    var payload: [String: JSONValue] = [
      "series_id": .string(record.seriesId.uuidString.lowercased()),
      "series_index": .number(Double(record.seriesIndex)),
      "capture_mode": .string(record.captureMode.rawValue)
    ]
    if record.captureMode == .singleShot {
      payload["bracket_count"] = .number(1.0)
    }
    if let intendedProcessing = record.singleShotAssessment?.intendedProcessing {
      payload["intended_processing"] = .string(intendedProcessing)
    }
    if let assessment = record.singleShotAssessment {
      payload["single_shot_correctability"] = .string(assessment.status.manifestToken)
      payload["single_shot_triggered_at"] = .string(isoTimestamp(assessment.triggeredAt))
      payload["single_shot_roll_degrees"] = .number(assessment.rollDegrees)
      payload["single_shot_pitch_degrees"] = .number(assessment.pitchDegrees)
      if let stabilityScore = assessment.stabilityScore {
        payload["single_shot_stability_score"] = .number(stabilityScore)
      }
      if let stabilityState = assessment.stabilityState {
        payload["single_shot_stability_state"] = .string(stabilityState)
      }
    }
    appendPhotoUploadIndices(to: &payload, uploadIndices: uploadIndices)
    if let captureOrientation = normalizedStringToken(record.captureOrientation) {
      payload["capture_orientation"] = .string(captureOrientation)
    }
    if let make = normalizedStringToken(exifSnapshot?.make) {
      payload["camera_make"] = .string(make)
    }
    if let model = normalizedStringToken(exifSnapshot?.model) {
      payload["camera_model"] = .string(model)
    }
    if let orientation = exifSnapshot?.orientationCode {
      payload["metadata_orientation"] = .number(Double(orientation))
    }
    if !record.localShootId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      payload["local_shoot_id"] = .string(record.localShootId)
    }
    if let captureEvidence = captureEvidenceForManifest(
      record: record,
      exifSnapshot: exifSnapshot,
      exifLogEntry: exifLogEntry,
      uploadIndices: uploadIndices
    ) {
      payload["capture_evidence"] = captureEvidence
    }
    return payload.isEmpty ? nil : .object(payload)
  }

  private func readExifLogEntry(for record: UploadRecord) -> ExifLogEntry? {
    guard let exifLogURL = record.exifLogURL,
          FileManager.default.fileExists(atPath: exifLogURL.path),
          let data = try? Data(contentsOf: exifLogURL),
          let entries = try? JSONDecoder().decode([ExifLogEntry].self, from: data) else {
      return nil
    }
    let filename = record.fileURL.lastPathComponent
    return entries.first { $0.fileName == filename } ?? entries.first
  }

  private func captureEvidenceForManifest(
    record: UploadRecord,
    exifSnapshot: PhotoExifSnapshot?,
    exifLogEntry: ExifLogEntry?,
    uploadIndices: PhotoUploadIndices?
  ) -> JSONValue? {
    var evidence: [String: JSONValue] = [
      "schema_version": .string("pixcapture.capture_evidence.v1"),
      "local_capture_id": .string(record.id.uuidString.lowercased()),
      "local_series_id": .string(record.seriesId.uuidString.lowercased()),
      "source_role": .string(record.exposureEV == 0 ? "source_0ev" : "source_bracket_member"),
      "capture_mode": .string(record.captureMode.rawValue),
      "created_at": .string(isoTimestamp(record.createdAt))
    ]
    appendPhotoUploadIndices(to: &evidence, uploadIndices: uploadIndices)

    var roomContext: [String: JSONValue] = [
      "room_id": .string(RoomTaxonomy.normalizedRoomId(record.roomId)),
      "floor_id": .string(FloorTaxonomy.normalizedFloorId(record.floorId))
    ]
    if let roomType = roomTypeForManifest(roomId: record.roomId) {
      roomContext["room_type"] = .string(roomType)
    }
    evidence["room_context"] = .object(roomContext)

    if let camera = captureEvidenceCameraObject(
      record: record,
      exifSnapshot: exifSnapshot,
      exifLogEntry: exifLogEntry
    ) {
      evidence["camera"] = camera
    }
    if let motion = captureEvidenceMotionObject(record: record, exifLogEntry: exifLogEntry) {
      evidence["motion_summary"] = motion
    }
    if let quality = captureEvidenceQualityObject(exifLogEntry: exifLogEntry) {
      evidence["quality_metrics"] = quality
    }
    if let depth = captureEvidenceDepthObject(exifLogEntry: exifLogEntry) {
      evidence["depth_summary"] = depth
    }
    if let sanitizedExif = captureEvidenceSanitizedExifObject(
      exifSnapshot: exifSnapshot,
      exifLogEntry: exifLogEntry
    ) {
      evidence["exif_sanitized"] = sanitizedExif
    }
    if let provenance = captureEvidenceProvenanceObject(exifLogEntry: exifLogEntry) {
      evidence["provenance"] = provenance
    }

    evidence["arkit_summary"] = .object([
      "available": .bool(false),
      "source": .string("not_recorded_for_photo_capture")
    ])
    evidence["missing_fields"] = .array([
      .string("arkit_camera_height_m"),
      .string("arkit_world_mapping_status"),
      .string("arkit_feature_points_summary"),
      .string("lidar_point_cloud_summary"),
      .string("room_plane_geometry")
    ])
    return .object(evidence)
  }

  private func captureEvidenceProvenanceObject(exifLogEntry: ExifLogEntry?) -> JSONValue? {
    guard let exifLogEntry else { return nil }
    var provenance: [String: JSONValue] = [:]
    if let schemaVersion = exifLogEntry.schemaVersion {
      provenance["capture_log_schema_version"] = .number(Double(schemaVersion))
    }
    appendString(exifLogEntry.pixcaptureVersion, key: "pixcapture_version", to: &provenance)
    appendString(exifLogEntry.pixcaptureBuild, key: "pixcapture_build", to: &provenance)
    appendString(exifLogEntry.levelCoordinateSystem, key: "level_coordinate_system", to: &provenance)
    if let rawPixelFormatType = exifLogEntry.rawPixelFormatType {
      provenance["raw_pixel_format_type"] = .number(Double(rawPixelFormatType))
    }
    appendString(exifLogEntry.rawPixelFormatFourCC, key: "raw_pixel_format_fourcc", to: &provenance)
    appendString(exifLogEntry.rawCaptureKind, key: "raw_capture_kind", to: &provenance)
    appendString(exifLogEntry.previewRawDecoderVersion, key: "preview_raw_decoder", to: &provenance)
    return provenance.isEmpty ? nil : .object(provenance)
  }

  private func captureEvidenceCameraObject(
    record: UploadRecord,
    exifSnapshot: PhotoExifSnapshot?,
    exifLogEntry: ExifLogEntry?
  ) -> JSONValue? {
    var camera: [String: JSONValue] = [
      "exposure_ev": .number(record.exposureEV),
      "white_balance_mode": .string(whiteBalanceModeForManifest(exifWhiteBalanceCode: exifSnapshot?.whiteBalance))
    ]
    appendNumber(record.exposureSeconds, key: "shutter_seconds", to: &camera)
    appendNumber(Double(record.iso), key: "iso", to: &camera)
    appendNumber(exifSnapshot?.fNumber ?? exifLogEntry?.fNumber, key: "aperture", to: &camera)
    appendNumber(exifSnapshot?.focalLength ?? exifLogEntry?.focalLength, key: "focal_length_mm", to: &camera)
    appendString(exifSnapshot?.lensModel ?? exifLogEntry?.lensModel, key: "lens_model", to: &camera)
    appendString(record.captureOrientation, key: "orientation", to: &camera)
    appendNumber(exifLogEntry?.requestedBiasEV, key: "requested_bias_ev", to: &camera)
    appendNumber(exifLogEntry?.requestedExposureEV, key: "requested_exposure_ev", to: &camera)
    appendNumber(exifLogEntry?.effectiveSeconds, key: "effective_seconds", to: &camera)
    appendNumber(exifLogEntry?.deviceExposureSeconds, key: "device_exposure_seconds", to: &camera)
    appendNumber(exifLogEntry?.deviceISO.map(Double.init), key: "device_iso", to: &camera)
    appendNumber(exifLogEntry?.deviceZoomFactor, key: "device_zoom_factor", to: &camera)
    appendNumber(exifLogEntry?.deviceLensPosition.map(Double.init), key: "device_lens_position", to: &camera)
    appendString(exifLogEntry?.deviceFocusMode, key: "device_focus_mode", to: &camera)
    appendNumber(exifLogEntry?.deviceFocusPointX, key: "device_focus_point_x", to: &camera)
    appendNumber(exifLogEntry?.deviceFocusPointY, key: "device_focus_point_y", to: &camera)
    appendNumber(exifLogEntry?.deviceWhiteBalanceGainRed.map(Double.init), key: "white_balance_gain_red", to: &camera)
    appendNumber(exifLogEntry?.deviceWhiteBalanceGainGreen.map(Double.init), key: "white_balance_gain_green", to: &camera)
    appendNumber(exifLogEntry?.deviceWhiteBalanceGainBlue.map(Double.init), key: "white_balance_gain_blue", to: &camera)
    return camera.isEmpty ? nil : .object(camera)
  }

  private func captureEvidenceMotionObject(
    record: UploadRecord,
    exifLogEntry: ExifLogEntry?
  ) -> JSONValue? {
    var motion: [String: JSONValue] = [:]
    appendNumber(normalizedSensorDegree(record.sensorPitchDegrees), key: "pitch_degrees", to: &motion)
    appendNumber(normalizedSensorDegree(record.sensorRollDegrees), key: "roll_degrees", to: &motion)
    appendNumber(normalizedHeadingDegree(record.sensorHeadingDegrees), key: "heading_degrees", to: &motion)
    appendNumber(exifLogEntry?.levelAngleDegrees, key: "level_angle_degrees", to: &motion)
    appendNumber(exifLogEntry?.levelPitchDegrees, key: "level_pitch_degrees", to: &motion)
    appendNumber(exifLogEntry?.singleShotRollDegrees, key: "single_shot_roll_degrees", to: &motion)
    appendNumber(exifLogEntry?.singleShotPitchDegrees, key: "single_shot_pitch_degrees", to: &motion)
    appendNumber(exifLogEntry?.singleShotStabilityScore, key: "single_shot_stability_score", to: &motion)
    appendString(exifLogEntry?.singleShotStabilityState, key: "single_shot_stability_state", to: &motion)
    appendString(exifLogEntry?.singleShotCorrectability, key: "single_shot_correctability", to: &motion)
    return motion.isEmpty ? nil : .object(motion)
  }

  private func captureEvidenceQualityObject(exifLogEntry: ExifLogEntry?) -> JSONValue? {
    guard let exifLogEntry else { return nil }
    var quality: [String: JSONValue] = [:]
    appendNumber(exifLogEntry.meanLuma, key: "mean_luma", to: &quality)
    appendString(exifLogEntry.exposureQualityState, key: "exposure_quality_state", to: &quality)
    appendString(exifLogEntry.sharpnessQualityState, key: "sharpness_quality_state", to: &quality)
    appendString(exifLogEntry.warningMessageSnapshot, key: "warning_message", to: &quality)
    if let bins = exifLogEntry.histogramBins, !bins.isEmpty {
      quality["histogram_bins"] = .array(bins.map { .number($0) })
      if let first = bins.first {
        quality["shadow_clipping_percent"] = .number(first * 100.0)
      }
      if let last = bins.last {
        quality["highlight_clipping_percent"] = .number(last * 100.0)
      }
    }
    return quality.isEmpty ? nil : .object(quality)
  }

  private func captureEvidenceDepthObject(exifLogEntry: ExifLogEntry?) -> JSONValue? {
    guard let exifLogEntry else { return nil }
    var depth: [String: JSONValue] = [:]
    appendBool(exifLogEntry.depthDeliverySupported, key: "delivery_supported", to: &depth)
    appendBool(exifLogEntry.depthDeliveryEnabled, key: "delivery_enabled", to: &depth)
    appendBool(exifLogEntry.streamDepthSupported, key: "stream_supported", to: &depth)
    appendBool(exifLogEntry.streamDepthEnabled, key: "stream_enabled", to: &depth)
    appendBool(exifLogEntry.depthReferenceFrame, key: "reference_frame", to: &depth)
    appendBool(exifLogEntry.depthDataPresent, key: "data_present", to: &depth)
    appendBool(exifLogEntry.depthSidecarWritten, key: "sidecar_written", to: &depth)
    appendString(exifLogEntry.depthSource, key: "source", to: &depth)
    appendString(exifLogEntry.depthAggregation, key: "aggregation", to: &depth)
    appendString(exifLogEntry.depthDataType, key: "data_type", to: &depth)
    appendNumber(exifLogEntry.depthMapWidth.map(Double.init), key: "map_width", to: &depth)
    appendNumber(exifLogEntry.depthMapHeight.map(Double.init), key: "map_height", to: &depth)
    appendBool(exifLogEntry.depthDataFiltered, key: "data_filtered", to: &depth)
    appendString(exifLogEntry.depthDataAccuracy, key: "data_accuracy", to: &depth)
    appendString(exifLogEntry.depthDataQuality, key: "data_quality", to: &depth)
    appendBool(exifLogEntry.depthCalibrationPresent, key: "calibration_present", to: &depth)
    return depth.isEmpty ? nil : .object(depth)
  }

  private func captureEvidenceSanitizedExifObject(
    exifSnapshot: PhotoExifSnapshot?,
    exifLogEntry: ExifLogEntry?
  ) -> JSONValue? {
    var exif: [String: JSONValue] = [
      "gps_stripped": .bool(true)
    ]
    appendString(exifSnapshot?.make ?? exifLogEntry?.make, key: "make", to: &exif)
    appendString(exifSnapshot?.model ?? exifLogEntry?.model, key: "model", to: &exif)
    appendString(exifLogEntry?.software, key: "software", to: &exif)
    appendString(exifLogEntry?.dateTimeOriginal, key: "date_time_original", to: &exif)
    appendNumber(exifSnapshot?.orientationCode.map(Double.init) ?? exifLogEntry?.resolvedMetadataOrientation.map(Double.init), key: "orientation", to: &exif)
    appendNumber(exifLogEntry?.exifExposureTime, key: "exposure_time", to: &exif)
    appendNumber(exifLogEntry?.exifExposureBiasValue, key: "exposure_bias_value", to: &exif)
    appendNumber(exifLogEntry?.exifBrightnessValue, key: "brightness_value", to: &exif)
    appendNumber(exifSnapshot?.iso ?? exifLogEntry?.exifISO, key: "iso", to: &exif)
    appendNumber(exifSnapshot?.fNumber ?? exifLogEntry?.fNumber, key: "f_number", to: &exif)
    appendNumber(exifSnapshot?.focalLength ?? exifLogEntry?.focalLength, key: "focal_length", to: &exif)
    appendNumber(exifLogEntry?.exifPixelXDimension.map(Double.init), key: "pixel_x_dimension", to: &exif)
    appendNumber(exifLogEntry?.exifPixelYDimension.map(Double.init), key: "pixel_y_dimension", to: &exif)
    appendNumber(exifLogEntry?.pixelWidth.map(Double.init), key: "pixel_width", to: &exif)
    appendNumber(exifLogEntry?.pixelHeight.map(Double.init), key: "pixel_height", to: &exif)
    return exif.isEmpty ? nil : .object(exif)
  }

  private func appendString(_ value: String?, key: String, to payload: inout [String: JSONValue]) {
    guard let value = normalizedStringToken(value) else { return }
    payload[key] = .string(value)
  }

  private func appendNumber(_ value: Double?, key: String, to payload: inout [String: JSONValue]) {
    guard let value, value.isFinite else { return }
    payload[key] = .number(value)
  }

  private func appendBool(_ value: Bool?, key: String, to payload: inout [String: JSONValue]) {
    guard let value else { return }
    payload[key] = .bool(value)
  }

  private func exifSidecarMetadataForManifest(seriesId: UUID) -> JSONValue {
    .object([
      "metadata_role": .string("exif_series_log"),
      "schema": .string("pixcapture.exif_log.v2"),
      "series_id": .string(seriesId.uuidString.lowercased())
    ])
  }

  private func xmpSidecarMetadataForManifest(
    record: UploadRecord,
    uploadIndices: PhotoUploadIndices?
  ) -> JSONValue {
    var payload: [String: JSONValue] = [
      "metadata_role": .string("xmp_sidecar"),
      "schema": .string("pixcapture.xmp_sidecar.v2"),
      "series_id": .string(record.seriesId.uuidString.lowercased()),
      "series_index": .number(Double(record.seriesIndex)),
      "source_file_id": .string(record.id.uuidString.lowercased()),
      "source_filename": .string(record.fileURL.lastPathComponent)
    ]
    appendPhotoUploadIndices(to: &payload, uploadIndices: uploadIndices)
    return .object(payload)
  }

  private func previewSidecarMetadataForManifest(
    record: UploadRecord,
    uploadIndices: PhotoUploadIndices?
  ) -> JSONValue {
    var payload: [String: JSONValue] = [
      "metadata_role": .string("preview_sidecar"),
      "schema": .string("pixcapture.preview_sidecar.v2"),
      "series_id": .string(record.seriesId.uuidString.lowercased()),
      "series_index": .number(Double(record.seriesIndex)),
      "source_file_id": .string(record.id.uuidString.lowercased()),
      "source_filename": .string(record.fileURL.lastPathComponent),
      "preview_filename": .string(FileStore.companionPreviewURL(for: record.fileURL).lastPathComponent)
    ]
    appendPhotoUploadIndices(to: &payload, uploadIndices: uploadIndices)
    return .object(payload)
  }

  private func depthSidecarMetadataForManifest(
    record: UploadRecord,
    uploadIndices: PhotoUploadIndices?
  ) -> JSONValue {
    var payload: [String: JSONValue] = [
      "metadata_role": .string("depth_sidecar"),
      "schema": .string("pixcapture.photo_depth_sidecar.v2"),
      "series_id": .string(record.seriesId.uuidString.lowercased()),
      "series_index": .number(Double(record.seriesIndex)),
      "source_file_id": .string(record.id.uuidString.lowercased()),
      "source_filename": .string(record.fileURL.lastPathComponent),
      "depth_filename": .string(FileStore.companionDepthURL(for: record.fileURL).lastPathComponent)
    ]
    appendPhotoUploadIndices(to: &payload, uploadIndices: uploadIndices)
    return .object(payload)
  }

  private func appendPhotoUploadIndices(
    to payload: inout [String: JSONValue],
    uploadIndices: PhotoUploadIndices?
  ) {
    guard let uploadIndices else { return }
    payload["motif_index"] = .number(Double(uploadIndices.motifIndex))
    payload["exposure_index"] = .number(Double(uploadIndices.exposureIndex))
  }

  private func globalPreferencesForManifest() -> UploadSessionGlobalPreferences? {
    let stylePreset = normalizedPreferenceToken(
      firstDefaultStringValue(keys: [
        "upload.stylePreset",
        "manifest.stylePreset",
        "stylePreset",
        "webConnectStylePreset"
      ])
    )
    let tasks = normalizedPreferenceTokens(
      firstDefaultStringArray(keys: [
        "upload.tasks",
        "manifest.tasks",
        "webConnectTasks"
      ])
    )
    let deliveryFormat = normalizedPreferenceTokens(
      firstDefaultStringArray(keys: [
        "upload.delivery_format",
        "upload.deliveryFormats",
        "manifest.delivery_format",
        "manifest.deliveryFormats"
      ])
    )

    if stylePreset == nil, tasks == nil, deliveryFormat == nil {
      return nil
    }
    return UploadSessionGlobalPreferences(
      style_preset: stylePreset,
      tasks: tasks,
      delivery_format: deliveryFormat
    )
  }

  private func firstDefaultStringValue(keys: [String]) -> String? {
    let defaults = UserDefaults.standard
    for key in keys {
      guard let value = defaults.object(forKey: key) else { continue }
      if let stringValue = value as? String {
        let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
          return trimmed
        }
      }
    }
    return nil
  }

  private func firstDefaultStringArray(keys: [String]) -> [String]? {
    let defaults = UserDefaults.standard
    for key in keys {
      guard let value = defaults.object(forKey: key) else { continue }
      if let list = value as? [String] {
        let normalized = list
          .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
          .filter { !$0.isEmpty }
        if !normalized.isEmpty {
          return normalized
        }
      }
      if let csv = value as? String {
        let values = csv
          .split(separator: ",")
          .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
          .filter { !$0.isEmpty }
        if !values.isEmpty {
          return values
        }
      }
    }
    return nil
  }

  private func normalizedPreferenceToken(_ value: String?) -> String? {
    guard let value else { return nil }
    let token = value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: "[^a-z0-9_-]+", with: "_", options: .regularExpression)
      .replacingOccurrences(of: "_{2,}", with: "_", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    return token.isEmpty ? nil : token
  }

  private func normalizedPreferenceTokens(_ values: [String]?) -> [String]? {
    guard let values else { return nil }
    let normalized = values.compactMap { normalizedPreferenceToken($0) }
    let unique = Array(Set(normalized)).sorted()
    return unique.isEmpty ? nil : unique
  }

  private func readPhotoExifSnapshot(_ fileURL: URL) -> PhotoExifSnapshot? {
    guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
          let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
      return nil
    }
    let exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any]
    let tiff = metadata[kCGImagePropertyTIFFDictionary as String] as? [String: Any]

    let iso: Double? = {
      if let list = exif?[kCGImagePropertyExifISOSpeedRatings as String] as? [Double] {
        return list.first
      }
      if let list = exif?[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber] {
        return list.first?.doubleValue
      }
      if let number = exif?[kCGImagePropertyExifISOSpeedRatings as String] as? NSNumber {
        return number.doubleValue
      }
      return nil
    }()

    return PhotoExifSnapshot(
      iso: iso,
      fNumber: metadataDouble(exif?[kCGImagePropertyExifFNumber as String]),
      focalLength: metadataDouble(exif?[kCGImagePropertyExifFocalLength as String]),
      lensModel: normalizedStringToken(
        exif?[kCGImagePropertyExifLensModel as String] as? String
          ?? tiff?[kCGImagePropertyTIFFModel as String] as? String
      ),
      whiteBalance: metadataInt(exif?[kCGImagePropertyExifWhiteBalance as String]),
      orientationCode: metadataInt(metadata[kCGImagePropertyOrientation as String]),
      make: normalizedStringToken(tiff?[kCGImagePropertyTIFFMake as String] as? String),
      model: normalizedStringToken(tiff?[kCGImagePropertyTIFFModel as String] as? String)
    )
  }

  private func metadataDouble(_ value: Any?) -> Double? {
    switch value {
    case let number as NSNumber:
      return number.doubleValue
    case let number as Double:
      return number
    case let number as Float:
      return Double(number)
    case let number as Int:
      return Double(number)
    case let text as String:
      return Double(text)
    default:
      return nil
    }
  }

  private func metadataInt(_ value: Any?) -> Int? {
    switch value {
    case let number as NSNumber:
      return number.intValue
    case let number as Int:
      return number
    case let text as String:
      return Int(text)
    default:
      return nil
    }
  }

  private func sensorDataFromTrackingObject(_ trackingObject: [String: Any]?) -> UploadSessionSensorData? {
    guard let trackingObject,
          let samples = trackingObject["samples"] as? [[String: Any]] else {
      return nil
    }
    for sample in samples {
      guard let rotation = doubleArray(from: sample["rotation"]), rotation.count >= 4 else {
        continue
      }
      if let sensor = sensorDataFromQuaternion(
        qx: rotation[0],
        qy: rotation[1],
        qz: rotation[2],
        qw: rotation[3]
      ) {
        return sensor
      }
    }
    return nil
  }

  private func sensorDataFromMotionCSV(_ motionURL: URL?) -> UploadSessionSensorData? {
    guard let motionURL,
          let content = try? String(contentsOf: motionURL, encoding: .utf8) else {
      return nil
    }
    let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
    for line in lines.dropFirst() {
      let fields = line.split(separator: ",", omittingEmptySubsequences: false)
      guard fields.count >= 11,
            let qw = Double(fields[7]),
            let qx = Double(fields[8]),
            let qy = Double(fields[9]),
            let qz = Double(fields[10]) else {
        continue
      }
      if let sensor = sensorDataFromQuaternion(qx: qx, qy: qy, qz: qz, qw: qw) {
        return sensor
      }
    }
    return nil
  }

  private func sensorDataFromPanoramaMetadata(_ metadataObject: [String: Any]?) -> UploadSessionSensorData? {
    guard let metadataObject,
          let frames = metadataObject["frames"] as? [[String: Any]] else {
      return nil
    }
    for frame in frames {
      guard let matrix = doubleMatrix(from: frame["transform"]),
            matrix.count >= 3,
            matrix[0].count >= 3,
            matrix[1].count >= 3,
            matrix[2].count >= 3 else {
        continue
      }
      let m00 = matrix[0][0]
      let m01 = matrix[1][0]
      let m02 = matrix[2][0]
      let m10 = matrix[0][1]
      let m11 = matrix[1][1]
      let m12 = matrix[2][1]
      let m20 = matrix[0][2]
      let m21 = matrix[1][2]
      let m22 = matrix[2][2]
      if let quat = quaternionFromRotationMatrix(
        m00: m00, m01: m01, m02: m02,
        m10: m10, m11: m11, m12: m12,
        m20: m20, m21: m21, m22: m22
      ) {
        if let sensor = sensorDataFromQuaternion(qx: quat.qx, qy: quat.qy, qz: quat.qz, qw: quat.qw) {
          return sensor
        }
      }
    }
    return nil
  }

  private func sensorDataFromFloorplanTransform(_ transform: FloorplanRoomTransform) -> UploadSessionSensorData? {
    let heading = normalizedHeadingDegree(transform.rotationRadians * 180 / .pi)
    if heading == nil {
      return nil
    }
    return UploadSessionSensorData(
      pitchDegrees: nil,
      rollDegrees: nil,
      headingDegrees: heading
    )
  }

  private func sensorDataFromQuaternion(
    qx: Double,
    qy: Double,
    qz: Double,
    qw: Double
  ) -> UploadSessionSensorData? {
    guard qx.isFinite, qy.isFinite, qz.isFinite, qw.isFinite else {
      return nil
    }
    let sinrCosp = 2 * (qw * qx + qy * qz)
    let cosrCosp = 1 - 2 * (qx * qx + qy * qy)
    let roll = atan2(sinrCosp, cosrCosp)

    let sinp = 2 * (qw * qy - qz * qx)
    let pitch: Double
    if abs(sinp) >= 1 {
      pitch = copysign(Double.pi / 2, sinp)
    } else {
      pitch = asin(sinp)
    }

    let sinyCosp = 2 * (qw * qz + qx * qy)
    let cosyCosp = 1 - 2 * (qy * qy + qz * qz)
    let yaw = atan2(sinyCosp, cosyCosp)

    let pitchDegrees = normalizedSensorDegree(pitch * 180 / .pi)
    let rollDegrees = normalizedSensorDegree(roll * 180 / .pi)
    let headingDegrees = normalizedHeadingDegree(yaw * 180 / .pi)
    if pitchDegrees == nil, rollDegrees == nil, headingDegrees == nil {
      return nil
    }
    return UploadSessionSensorData(
      pitchDegrees: pitchDegrees,
      rollDegrees: rollDegrees,
      headingDegrees: headingDegrees
    )
  }

  private func quaternionFromRotationMatrix(
    m00: Double, m01: Double, m02: Double,
    m10: Double, m11: Double, m12: Double,
    m20: Double, m21: Double, m22: Double
  ) -> (qx: Double, qy: Double, qz: Double, qw: Double)? {
    guard m00.isFinite, m01.isFinite, m02.isFinite,
          m10.isFinite, m11.isFinite, m12.isFinite,
          m20.isFinite, m21.isFinite, m22.isFinite else {
      return nil
    }
    let trace = m00 + m11 + m22
    if trace > 0 {
      let s = sqrt(trace + 1.0) * 2
      return (
        qx: (m21 - m12) / s,
        qy: (m02 - m20) / s,
        qz: (m10 - m01) / s,
        qw: 0.25 * s
      )
    }
    if m00 > m11, m00 > m22 {
      let s = sqrt(1.0 + m00 - m11 - m22) * 2
      return (
        qx: 0.25 * s,
        qy: (m01 + m10) / s,
        qz: (m02 + m20) / s,
        qw: (m21 - m12) / s
      )
    }
    if m11 > m22 {
      let s = sqrt(1.0 + m11 - m00 - m22) * 2
      return (
        qx: (m01 + m10) / s,
        qy: 0.25 * s,
        qz: (m12 + m21) / s,
        qw: (m02 - m20) / s
      )
    }
    let s = sqrt(1.0 + m22 - m00 - m11) * 2
    return (
      qx: (m02 + m20) / s,
      qy: (m12 + m21) / s,
      qz: 0.25 * s,
      qw: (m10 - m01) / s
    )
  }

  private func doubleArray(from value: Any?) -> [Double]? {
    if let list = value as? [Double] {
      return list
    }
    if let list = value as? [NSNumber] {
      return list.map(\.doubleValue)
    }
    if let list = value as? [Any] {
      let mapped = list.compactMap { metadataDouble($0) }
      return mapped.count == list.count ? mapped : nil
    }
    return nil
  }

  private func doubleMatrix(from value: Any?) -> [[Double]]? {
    guard let rows = value as? [Any] else { return nil }
    let matrix = rows.compactMap { row -> [Double]? in
      if let doubles = row as? [Double] {
        return doubles
      }
      if let numbers = row as? [NSNumber] {
        return numbers.map(\.doubleValue)
      }
      if let anyRow = row as? [Any] {
        let converted = anyRow.compactMap { metadataDouble($0) }
        return converted.count == anyRow.count ? converted : nil
      }
      return nil
    }
    return matrix.count == rows.count ? matrix : nil
  }

  private func currentWhiteBalanceKelvinForManifest() -> Int? {
    let defaults = UserDefaults.standard
    let kelvin = defaults.double(forKey: "whiteBalanceKelvin")
    guard kelvin.isFinite, kelvin > 0 else { return nil }
    return Int(kelvin.rounded())
  }

  private func shutterSpeedString(seconds: Double) -> String? {
    guard seconds.isFinite, seconds > 0 else {
      return nil
    }

    if seconds >= 1 {
      if abs(seconds.rounded() - seconds) < 0.001 {
        return "\(Int(seconds.rounded()))s"
      }
      return String(format: "%.2fs", seconds)
    }

    let reciprocal = Int((1.0 / seconds).rounded())
    guard reciprocal > 0 else {
      return nil
    }
    return "1/\(reciprocal)"
  }

  private func uploadNamingTokens(jobId: String, userId: String) -> (cust3: String, job5: String, shotId: String) {
    let cust3 = loadOrCreateCustomerCode(userId: userId)
    let job5 = normalizeBase36Code(
      rawValue: jobId,
      length: 5,
      fallbackSeed: "manifest:job5:\(jobId):\(userId)"
    )
    return (cust3, job5, cust3)
  }

  private func loadOrCreateCustomerCode(userId: String) -> String {
    let userKey = normalizedCustomerUserKey(userId)
    let storageKey = "\(customerCodeStoragePrefix)\(userKey)"
    let defaults = UserDefaults.standard

    if let stored = defaults.string(forKey: storageKey), !stored.isEmpty {
      let normalized = normalizeBase36Code(
        rawValue: stored,
        length: 3,
        fallbackSeed: "manifest:cust3:stored:\(userKey)"
      )
      if normalized != stored {
        defaults.set(normalized, forKey: storageKey)
      }
      return normalized
    }

    let existingCodes = Set(
      defaults.dictionaryRepresentation().compactMap { entry -> String? in
        guard entry.key.hasPrefix(customerCodeStoragePrefix) else { return nil }
        guard let raw = entry.value as? String else { return nil }
        let normalized = normalizeBase36Code(
          rawValue: raw,
          length: 3,
          fallbackSeed: "manifest:cust3:existing:\(entry.key)"
        )
        return normalized
      }
    )

    let generated = generateUniqueCustomerCode(excluding: existingCodes, seed: userKey)
    defaults.set(generated, forKey: storageKey)
    return generated
  }

  private func normalizedCustomerUserKey(_ userId: String) -> String {
    let trimmed = userId.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      return "unknown"
    }
    return sanitizeProjectKey(trimmed).lowercased()
  }

  private func generateUniqueCustomerCode(excluding existingCodes: Set<String>, seed: String) -> String {
    let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    if !alphabet.isEmpty {
      for _ in 0..<32 {
        var code = ""
        for _ in 0..<3 {
          if let token = alphabet.randomElement() {
            code.append(token)
          }
        }
        if code.count == 3 && !existingCodes.contains(code) {
          return code
        }
      }
    }

    let fallback = normalizeBase36Code(
      rawValue: stableBase36Hash("manifest:cust3:fallback:\(seed)"),
      length: 3,
      fallbackSeed: "manifest:cust3:fallback-seed:\(seed)"
    )
    if existingCodes.contains(fallback) {
      for index in 0..<36 {
        let base = String(index, radix: 36).uppercased()
        let padded = String(repeating: "0", count: max(0, 2 - base.count)) + base
        let candidate = "\(fallback.prefix(1))\(padded)"
        if candidate.count == 3 && !existingCodes.contains(candidate) {
          return candidate
        }
      }
    }
    return fallback
  }

  private func normalizeBase36Code(rawValue: String?, length: Int, fallbackSeed: String) -> String {
    let base36 = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    let uppercase = (rawValue ?? "").uppercased()
    let scalars = uppercase.unicodeScalars.filter { base36.contains($0) }
    let sanitized = String(String.UnicodeScalarView(scalars))

    if sanitized.count == length {
      return sanitized
    }

    var token = sanitized + stableBase36Hash("\(fallbackSeed):\(sanitized)")
    if token.count < length {
      token += String(repeating: "0", count: length - token.count)
    }
    return String(token.prefix(length))
  }

  private func stableBase36Hash(_ seed: String) -> String {
    var hash: UInt32 = 0x811C9DC5
    for byte in seed.utf8 {
      hash ^= UInt32(byte)
      hash = hash &* 0x01000193
    }
    return String(hash, radix: 36).uppercased()
  }

  private func isoTimestamp(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }

  private func makeContractTransferItems(
    preparedTargets: [PreparedUploadTarget],
    recordsById: [UUID: UploadRecord],
    customerId: String,
    shootId: String,
    shootCode: String
  ) throws -> [ContractTransferItem] {
    var usedRelativePaths = Set<String>()
    var imageIndex = 0
    var hasPrimaryArkitTracking = false
    var items: [ContractTransferItem] = []
    items.reserveCapacity(preparedTargets.count)

    for target in preparedTargets {
      let record = target.recordId.flatMap { recordsById[$0] }
      let extensionToken = normalizedFileExtension(target.fileURL.pathExtension)
      let timestamp = target.capture.captureTimestamp

      if record != nil, ["heic", "heif"].contains(extensionToken) {
        throw NSError(
          domain: "PixcaptureUploadService.PhotoFormat",
          code: 1,
          userInfo: [
            NSLocalizedDescriptionKey:
              NSLocalizedString("upload.error.heifUnsupported", comment: "")
          ]
        )
      }

      let relativePath: String
      let kind: String
      let roomTypeEn: String?
      let roomLabelDe: String?
      let stackId: String?
      let imageId: String
      let evValue: Double?

      if let record {
        let normalizedRoomId = RoomTaxonomy.normalizedRoomId(record.roomId)
        let room = RoomTaxonomy.room(id: normalizedRoomId)
        roomTypeEn = normalizedRoomId
        roomLabelDe = room.nameDE
        stackId = String(format: "g%03d", max(1, record.seriesIndex))
        imageId = record.id.uuidString.lowercased()
        evValue = record.exposureEV

        if extensionToken == "dng" {
          kind = "raw"
          let evToken = evPathToken(record.exposureEV)
          relativePath = "raw/\(stackId!)-e\(evToken).dng"
        } else {
          kind = "image"
          imageIndex += 1
          let dateToken = datePathToken(timestamp)
          let indexToken = String(format: "%03d", imageIndex)
          let roomPathToken = pathToken(normalizedRoomId)
          relativePath = "images/\(dateToken)-\(shootCode)-\(roomPathToken)-\(indexToken)-v1.\(extensionToken)"
        }
      } else {
        let normalizedRel = (target.relativePath ?? target.filename).lowercased()
        let rawFilename = (normalizedRel as NSString).lastPathComponent
        let basename = sanitizeManifestToken((rawFilename as NSString).deletingPathExtension)
        let fallbackName = basename.isEmpty ? "file-\(items.count + 1)" : basename
        let isArkit = looksLikeArkitPayload(relativePath: normalizedRel, filename: target.filename)
        roomTypeEn = nil
        roomLabelDe = nil
        stackId = nil
        imageId = target.fileId
        evValue = nil

        if isArkit {
          kind = "arkit"
          if !hasPrimaryArkitTracking, normalizedRel.contains("tracking") {
            hasPrimaryArkitTracking = true
            relativePath = "arkit/arkit-tracking.json"
          } else {
            relativePath = "arkit/\(fallbackName).\(extensionToken)"
          }
        } else {
          kind = "metadata"
          relativePath = "meta/\(fallbackName).\(extensionToken)"
        }
      }

      let uniquePath = uniqueRelativePath(relativePath, used: &usedRelativePaths)
      let uploadData = dataWithStrippedGPSIfNeeded(target: target)
      let resolvedSizeBytes = uploadData?.count ?? target.sizeBytes
      let resolvedSha256 = uploadData.flatMap(bestEffortSha256)
        ?? target.checksumSha256
        ?? bestEffortSha256(fileURL: target.fileURL, sizeBytes: resolvedSizeBytes)

      items.append(
        ContractTransferItem(
          fileId: target.fileId,
          recordId: target.recordId,
          fileURL: target.fileURL,
          uploadData: uploadData,
          relativePath: uniquePath,
          kind: kind,
          mimeType: target.mimeType,
          sizeBytes: resolvedSizeBytes,
          sha256: resolvedSha256,
          metadata: ExpectedManifestFileMetadata(
            customer_id: customerId,
            shoot_id: shootId,
            shoot_code: shootCode,
            room_type_en: roomTypeEn,
            room_label_de: roomLabelDe,
            stack_id: stackId,
            image_id: imageId,
            timestamp: isoTimestamp(timestamp),
            ev_value: evValue
          )
        )
      )
    }

    return items
  }

  private func dataWithStrippedGPSIfNeeded(target: PreparedUploadTarget) -> Data? {
    let ext = target.fileURL.pathExtension.lowercased()
    guard ["jpg", "jpeg", "heic", "heif"].contains(ext) else {
      return nil
    }
    guard let original = try? Data(contentsOf: target.fileURL) else {
      return nil
    }
    guard let stripped = try? MetadataStripping.stripGPS(from: original) else {
      return nil
    }
    if stripped == original {
      return nil
    }
    return stripped
  }

  private func makeExpectedManifest(
    customerId: String,
    shootId: String,
    shootCode: String,
    items: [ContractTransferItem]
  ) -> ExpectedManifestV2 {
    let createdAt = items
      .compactMap { parseIsoDate($0.metadata.timestamp) }
      .min() ?? Date()
    return ExpectedManifestV2(
      schema_version: "upload-contract-v2",
      app_version: currentAppVersionString(),
      customer_id: customerId,
      shoot_id: shootId,
      shoot_code: shootCode,
      created_at: isoTimestamp(createdAt),
      files: items.map {
        ExpectedManifestFileV2(
          kind: $0.kind,
          relative_path: $0.relativePath,
          size_bytes: $0.sizeBytes,
          sha256: $0.sha256,
          customer_id: $0.metadata.customer_id,
          shoot_id: $0.metadata.shoot_id,
          shoot_code: $0.metadata.shoot_code,
          room_type_en: $0.metadata.room_type_en,
          room_label_de: $0.metadata.room_label_de,
          stack_id: $0.metadata.stack_id,
          image_id: $0.metadata.image_id,
          timestamp: $0.metadata.timestamp,
          ev_value: $0.metadata.ev_value
        )
      }
    )
  }

  private func encodeExpectedManifest(_ manifest: ExpectedManifestV2) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(manifest)
  }

  @discardableResult
  private func persistExpectedManifest(_ data: Data, shootId: String) -> URL? {
    guard let captureRoot = try? FileStore.ensureCaptureDirectory() else {
      return nil
    }
    let manifestRoot = captureRoot.appendingPathComponent("upload-manifests-v2", isDirectory: true)
    try? FileManager.default.createDirectory(at: manifestRoot, withIntermediateDirectories: true)
    let safeShoot = sanitizeManifestToken(shootId)
    let filename = safeShoot.isEmpty ? "expected_manifest.json" : "\(safeShoot)-expected_manifest.json"
    let fileURL = manifestRoot.appendingPathComponent(filename)
    try? data.write(to: fileURL, options: .atomic)
    return fileURL
  }

  private func makeShootCode(jobId: String, records: [UploadRecord]) -> String {
    let preferred = records
      .map(\.jobLabel)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first(where: { !$0.isEmpty })
    let base = preferred ?? jobId
    let token = base
      .uppercased()
      .replacingOccurrences(of: "[^A-Z0-9]+", with: "", options: .regularExpression)
    if !token.isEmpty {
      return String(token.prefix(12))
    }
    let fallback = jobId
      .uppercased()
      .replacingOccurrences(of: "[^A-Z0-9]+", with: "", options: .regularExpression)
    if !fallback.isEmpty {
      return String(fallback.prefix(8))
    }
    return "SHOOT"
  }

  private func currentAppVersionString() -> String {
    (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
      ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
      ?? "unknown"
  }

  private func normalizedManifestIdentityCode(_ value: String?, expectedLength: Int) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
          trimmed.count == expectedLength else {
      return nil
    }
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789")
    let scalars = trimmed.unicodeScalars.filter { allowed.contains($0) }
    let normalized = String(String.UnicodeScalarView(scalars))
    guard normalized.count == expectedLength else {
      return nil
    }
    return normalized
  }

  private func normalizedFileExtension(_ raw: String) -> String {
    let token = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if token.isEmpty {
      return "bin"
    }
    return token
  }

  private func sanitizeManifestToken(_ value: String) -> String {
    value
      .lowercased()
      .replacingOccurrences(of: "_", with: "-")
      .replacingOccurrences(of: "[^a-z0-9-]+", with: "-", options: .regularExpression)
      .replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
  }

  private func pathToken(_ value: String) -> String {
    sanitizeManifestToken(value)
  }

  private func datePathToken(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd"
    return formatter.string(from: date)
  }

  private func evPathToken(_ value: Double) -> String {
    if value.rounded(.towardZero) == value {
      return String(Int(value))
    }
    let formatted = String(format: "%.1f", value)
    return formatted.replacingOccurrences(of: ".", with: "-")
  }

  private func uniqueRelativePath(_ relativePath: String, used: inout Set<String>) -> String {
    let normalized = relativePath
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "\\", with: "/")
    if !used.contains(normalized) {
      used.insert(normalized)
      return normalized
    }

    let ns = normalized as NSString
    let directory = ns.deletingLastPathComponent
    let extensionToken = ns.pathExtension
    let baseName = ns.deletingPathExtension
    var suffix = 2
    while true {
      let candidateBase = "\(baseName)-\(suffix)"
      let filename = extensionToken.isEmpty ? candidateBase : "\(candidateBase).\(extensionToken)"
      let candidate = directory == "." ? filename : "\(directory)/\(filename)"
      if !used.contains(candidate) {
        used.insert(candidate)
        return candidate
      }
      suffix += 1
    }
  }

  private func looksLikeArkitPayload(relativePath: String, filename: String) -> Bool {
    let token = "\(relativePath.lowercased()) \(filename.lowercased())"
    return token.contains("tracking")
      || token.contains("arkit")
      || token.contains("intrinsics")
      || token.contains("mesh")
      || token.contains("depth")
      || token.contains("segments")
  }

  private func parseIsoDate(_ raw: String?) -> Date? {
    guard let raw else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let parsed = fractional.date(from: trimmed) {
      return parsed
    }

    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: trimmed)
  }

  private func normalizedFilenameToken(_ value: String) -> String {
    value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "\\", with: "/")
      .components(separatedBy: "/")
      .last?
      .lowercased() ?? value.lowercased()
  }

  private func failureReason(_ error: Error) -> String {
    if let uploadError = error as? PixcaptureUploadError {
      return uploadError.errorDescription ?? "Unbekannter Fehler"
    }
    if let urlError = error as? URLError {
      switch urlError.code {
      case .notConnectedToInternet:
        return "Backend nicht erreichbar. Das iPhone konnte den Paket-Schluessel nicht vom PixCapture-Server holen."
      case .timedOut:
        return "Zeitueberschreitung bei der Serververbindung."
      case .cannotFindHost, .cannotConnectToHost:
        return "Server oder Empfaenger ist nicht erreichbar."
      case .networkConnectionLost:
        return "Die Netzwerkverbindung wurde unterbrochen."
      default:
        break
      }
    }
    return error.localizedDescription
  }

  private func invalidResponse(_ detail: String) -> PixcaptureUploadError {
    PixcaptureUploadError.invalidResponseDetail(detail)
  }

  private func decodingFailureReason(_ error: Error) -> String {
    switch error {
    case DecodingError.keyNotFound(let key, _):
      return "Pflichtfeld '\(key.stringValue)' fehlt"
    case DecodingError.typeMismatch(_, let context):
      return "Datentyp stimmt nicht fuer '\(codingPathDescription(context.codingPath))'"
    case DecodingError.valueNotFound(_, let context):
      return "Wert fehlt fuer '\(codingPathDescription(context.codingPath))'"
    case DecodingError.dataCorrupted(let context):
      return context.debugDescription
    default:
      return "Format nicht lesbar"
    }
  }

  private func codingPathDescription(_ path: [CodingKey]) -> String {
    let joined = path.map(\.stringValue).joined(separator: ".")
    return joined.isEmpty ? "response" : joined
  }

  private func shouldRetryUploadOperation(after error: Error) -> Bool {
    if let urlError = error as? URLError {
      switch urlError.code {
      case .notConnectedToInternet,
           .timedOut,
           .cannotFindHost,
           .cannotConnectToHost,
           .networkConnectionLost:
        return true
      default:
        return false
      }
    }

    if let uploadError = error as? PixcaptureUploadError {
      switch uploadError {
      case .apiStatus(let code, _):
        return code == 408 || code == 425 || code == 429 || (500...599).contains(code)
      default:
        return false
      }
    }

    return false
  }

  private func shouldKeepPendingAfterConnectionError(_ error: Error) -> Bool {
    if let urlError = error as? URLError {
      switch urlError.code {
      case .notConnectedToInternet,
           .timedOut,
           .cannotFindHost,
           .cannotConnectToHost,
           .networkConnectionLost:
        return true
      default:
        break
      }
    }

    if let uploadError = error as? PixcaptureUploadError {
      switch uploadError {
      case .qrExpired:
        return true
      case .api(let message):
        return isRecoverableSessionErrorMessage(message)
      case .apiStatus(let code, let message):
        if code == 408 || code == 425 || code == 429 || (500...599).contains(code) {
          return true
        }
        if code == 404 || code == 409 {
          return isRecoverableSessionErrorMessage(message)
        }
        return false
      default:
        return false
      }
    }

    return false
  }

  private func normalizedAPIErrorMessage(_ message: String, statusCode: Int) -> String {
    let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalized = trimmed.lowercased()

    if normalized.contains("unknown web_session_id")
      || normalized.contains("web session not found or expired")
      || (statusCode == 404 && normalized.contains("web session")) {
      return "Web-Connect-Session nicht mehr gueltig. Bitte den QR-Code im Browser neu erzeugen und erneut scannen."
    }

    if statusCode == 409 && normalized.contains("mobile handshake missing") {
      return "Der Browser wartet noch auf das Telefon. QR bitte neu scannen und die Verbindung erneut starten."
    }

    return trimmed
  }

  private func isRecoverableSessionErrorMessage(_ message: String) -> Bool {
    let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalized.contains("unknown web_session_id")
      || normalized.contains("web session not found or expired")
      || normalized.contains("web-connect-session nicht mehr gueltig")
      || normalized.contains("mobile handshake missing")
      || normalized.contains("upload-session abgelaufen")
      || normalized.contains("web-freigabe timeout")
  }

  private func makePreparedTarget(
    fileId: String,
    recordId: UUID?,
    fileURL: URL,
    relativePath: String?,
    capture: SessionCaptureDescriptor,
    motifIndex: Int? = nil,
    exposureIndex: Int? = nil,
    cameraMetadata: UploadSessionCameraMetadata?,
    videoMetadata: JSONValue?,
    motionMetadata: JSONValue?,
    intrinsicsMetadata: JSONValue?,
    trackingMetadata: JSONValue?,
    floorplanMetadata: JSONValue?,
    fileMetadata: JSONValue?,
    projectNameHint: String? = nil
  ) throws -> PreparedUploadTarget {
    let sizeBytes = try fileSizeBytes(fileURL)
    return PreparedUploadTarget(
      fileId: fileId,
      recordId: recordId,
      fileURL: fileURL,
      relativePath: relativePath,
      filename: fileURL.lastPathComponent,
      mimeType: mimeType(for: fileURL),
      sizeBytes: sizeBytes,
      checksumSha256: bestEffortSha256(fileURL: fileURL, sizeBytes: sizeBytes),
      capture: capture,
      motifIndex: motifIndex,
      exposureIndex: exposureIndex,
      cameraMetadata: cameraMetadata,
      videoMetadata: videoMetadata,
      motionMetadata: motionMetadata,
      intrinsicsMetadata: intrinsicsMetadata,
      trackingMetadata: trackingMetadata,
      floorplanMetadata: floorplanMetadata,
      fileMetadata: mergedFileMetadata(fileMetadata, capture: capture),
      projectNameHint: projectNameHint
    )
  }

  private func mergedFileMetadata(_ base: JSONValue?, capture: SessionCaptureDescriptor) -> JSONValue? {
    var context: [String: JSONValue] = [
      "room_id": .string(capture.roomId),
      "room_name": .string(capture.roomName),
      "room_variant": .number(Double(capture.roomVariant)),
      "capture_id": .string(capture.captureId),
      "capture_type": .string(capture.captureType),
      "capture_timestamp": .string(isoTimestamp(capture.captureTimestamp))
    ]
    if !capture.floorId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      context["floor_id"] = .string(capture.floorId)
    }
    if let roomType = normalizedStringToken(capture.roomType) {
      context["room_type"] = .string(roomType)
    }
    if let captureSubtype = normalizedStringToken(capture.captureSubtype) {
      context["capture_subtype"] = .string(captureSubtype)
    }
    if let intendedProcessing = normalizedStringToken(capture.intendedProcessing) {
      context["intended_processing"] = .string(intendedProcessing)
    }

    guard let base else {
      return context.isEmpty ? nil : .object(context)
    }

    if var object = base.objectValue {
      for (key, value) in context where object[key] == nil {
        object[key] = value
      }
      return .object(object)
    }

    context["payload"] = base
    return .object(context)
  }

  private func resolveExistingRelativeFile(root: URL, relativePath: String) -> URL? {
    let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "\\", with: "/")
    guard !trimmed.isEmpty, !trimmed.contains("..") else {
      return nil
    }
    let url = root.appendingPathComponent(trimmed)
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
  }

  private func floorplanSegmentsMetadata(_ segmentsURL: URL) -> JSONValue? {
    guard let data = try? Data(contentsOf: segmentsURL) else {
      return nil
    }

    if let decoded = try? JSONDecoder().decode(FloorplanSegmentsFile.self, from: data) {
      var payload: [String: JSONValue] = [
        "version": .number(Double(decoded.version)),
        "has_doors": .bool(!(decoded.doors ?? []).isEmpty),
        "has_openings": .bool(!(decoded.openings ?? []).isEmpty),
        "has_windows": .bool(!(decoded.windows ?? []).isEmpty),
        "perimeter_meters": .number(decoded.metrics.perimeterMeters),
        "area_sqm_approx": .number(decoded.metrics.areaSqmApprox)
      ]
      if let trackingSessionId = decoded.trackingSessionId,
         !trackingSessionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        payload["tracking_session_id"] = .string(trackingSessionId)
      }
      return .object(payload)
    }

    return jsonValueFromFile(segmentsURL)
  }

  private func panoramaMetadataSummary(_ metadataObject: [String: Any]?) -> JSONValue? {
    guard let metadataObject else { return nil }

    var payload: [String: JSONValue] = [:]
    if let frameCount = metadataObject["frame_count"] as? NSNumber {
      payload["frame_count"] = .number(frameCount.doubleValue)
    }
    if let markerCount = metadataObject["marker_count"] as? NSNumber {
      payload["marker_count"] = .number(markerCount.doubleValue)
    }
    if let eventCount = metadataObject["event_count"] as? NSNumber {
      payload["event_count"] = .number(eventCount.doubleValue)
    }
    if let markerDictionary = metadataObject["marker_dictionary"] as? String, !markerDictionary.isEmpty {
      payload["marker_dictionary"] = .string(markerDictionary)
    }
    if let openCVEnabled = metadataObject["opencv_enabled"] as? NSNumber {
      payload["opencv_enabled"] = .bool(openCVEnabled.boolValue)
    }
    if let linked = metadataObject["linked_floorplan"], let linkedValue = JSONValue(any: linked) {
      payload["linked_floorplan"] = linkedValue
    }

    return payload.isEmpty ? nil : .object(payload)
  }

  private func jsonValueFromFile(_ fileURL: URL) -> JSONValue? {
    guard let data = try? Data(contentsOf: fileURL),
          let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
      return nil
    }
    return JSONValue(any: object)
  }

  private func readJSONObject(_ fileURL: URL) -> [String: Any]? {
    guard let data = try? Data(contentsOf: fileURL),
          let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [String: Any] else {
      return nil
    }
    return object
  }

  private func loadVideoProjectId(jobId: String) -> UUID? {
    let token = sanitizeProjectKey(jobId)
    let key = "video.project-id.\(token)"
    guard let raw = UserDefaults.standard.string(forKey: key),
          let uuid = UUID(uuidString: raw) else {
      return nil
    }
    return uuid
  }

  private func normalizedProjectKeyToken(_ value: String) -> String {
    let token = sanitizeProjectKey(value)
    return token.isEmpty ? "project" : token
  }

  private func sanitizeProjectKey(_ value: String) -> String {
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
    let filtered = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
    let collapsed = String(filtered).replacingOccurrences(of: "__+", with: "_", options: .regularExpression)
    return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
  }

  private func bestEffortSha256(fileURL: URL, sizeBytes: Int) -> String? {
    if sizeBytes > checksumBestEffortLimitBytes {
      return nil
    }
    guard let data = try? Data(contentsOf: fileURL) else {
      return nil
    }
    return sha256Hex(data)
  }

  private func bestEffortSha256(_ data: Data) -> String? {
    if data.count > checksumBestEffortLimitBytes {
      return nil
    }
    return sha256Hex(data)
  }

  private func fileSizeBytes(_ fileURL: URL) throws -> Int {
    let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
    if let fileSize = values.fileSize {
      return fileSize
    }

    let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    if let number = attrs[.size] as? NSNumber {
      return number.intValue
    }
    throw PixcaptureUploadError.api(
      String(
        format: NSLocalizedString("upload.error.fileSize.format", comment: ""),
        fileURL.lastPathComponent
      )
    )
  }

  private func uploadHTTPFailureMessage(
    statusCode: Int,
    responseData: Data,
    requestURL: URL,
    mimeType: String
  ) -> String {
    let responseText = decodedUploadResponseText(from: responseData)
    let r2Code = firstXMLTagValue("Code", in: responseText)
    let r2Message = firstXMLTagValue("Message", in: responseText)
    let bodySummary = uploadResponseSummary(from: responseText)
    let codePart = r2Code.map { " R2-Code=\($0)." } ?? ""
    let messagePart = r2Message.map { " R2-Message=\($0)." } ?? ""
    let bodyPart = bodySummary.map { " Body=\($0)" } ?? ""
    print(
      """
      [PixcaptureUploadService] PUT failed
        URL: \(requestURL.absoluteString)
        Status: \(statusCode)
        Content-Type: \(mimeType)
        R2-Code: \(r2Code ?? "-")
        R2-Message: \(r2Message ?? "-")
        Response: \(bodySummary ?? "<leer>")
      """
    )
    return "Upload fehlgeschlagen (\(statusCode)). Content-Type=\(mimeType).\(codePart)\(messagePart)\(bodyPart)"
  }

  private func decodedUploadResponseText(from data: Data) -> String? {
    guard !data.isEmpty else { return nil }
    if let utf8 = String(data: data, encoding: .utf8), !utf8.isEmpty {
      return utf8
    }
    if let isoLatin1 = String(data: data, encoding: .isoLatin1), !isoLatin1.isEmpty {
      return isoLatin1
    }
    return nil
  }

  private func uploadResponseSummary(from text: String?) -> String? {
    guard let text else { return nil }
    let singleLine = text
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: "\r", with: " ")
      .replacingOccurrences(of: "\t", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !singleLine.isEmpty else { return nil }
    if singleLine.count <= 320 {
      return singleLine
    }
    let endIndex = singleLine.index(singleLine.startIndex, offsetBy: 320)
    return String(singleLine[..<endIndex]) + "..."
  }

  private func firstXMLTagValue(_ tag: String, in text: String?) -> String? {
    guard let text else { return nil }
    guard let openRange = text.range(of: "<\(tag)>"),
          let closeRange = text.range(of: "</\(tag)>", range: openRange.upperBound..<text.endIndex) else {
      return nil
    }
    let value = text[openRange.upperBound..<closeRange.lowerBound]
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : String(value)
  }

  private func mimeType(for url: URL) -> String {
    switch url.pathExtension.lowercased() {
    case "jpg", "jpeg": return "image/jpeg"
    case "heic": return "image/heic"
    case "dng": return "image/x-adobe-dng"
    case "png": return "image/png"
    case "pdf": return "application/pdf"
    case "mov": return "video/quicktime"
    case "mp4": return "video/mp4"
    case "csv": return "text/csv"
    case "json": return "application/json"
    case "xmp": return "application/xmp+xml"
    case "usdz": return "model/vnd.usdz+zip"
    case "pixcapturepkg": return "application/vnd.pixcapture.package"
    default: return "application/octet-stream"
    }
  }

  private func sha256Hex(_ data: Data) -> String {
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  private func jsonObjectForBrowserCompanion<T: Encodable>(_ value: T) throws -> Any {
    let data = try JSONEncoder().encode(value)
    return try JSONSerialization.jsonObject(with: data)
  }

  private func sha256Hex(fileURL: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: fileURL)
    defer {
      try? handle.close()
    }
    var hasher = SHA256()
    while autoreleasepool(invoking: {
      let data = handle.readData(ofLength: 4 * 1024 * 1024)
      if data.isEmpty {
        return false
      }
      hasher.update(data: data)
      return true
    }) {}
    let digest = hasher.finalize()
    return digest.map { String(format: "%02x", $0) }.joined()
  }
}

private struct PreparedUploadTarget {
  let fileId: String
  let recordId: UUID?
  let fileURL: URL
  let relativePath: String?
  let filename: String
  let mimeType: String
  let sizeBytes: Int
  let checksumSha256: String?
  let capture: SessionCaptureDescriptor
  let motifIndex: Int?
  let exposureIndex: Int?
  let cameraMetadata: UploadSessionCameraMetadata?
  let videoMetadata: JSONValue?
  let motionMetadata: JSONValue?
  let intrinsicsMetadata: JSONValue?
  let trackingMetadata: JSONValue?
  let floorplanMetadata: JSONValue?
  let fileMetadata: JSONValue?
  let projectNameHint: String?
}

private struct SessionCaptureDescriptor {
  let roomId: String
  let floorId: String
  let roomName: String
  let roomType: String?
  let roomVariant: Int
  let captureId: String
  let captureType: String
  let captureSubtype: String?
  let captureTimestamp: Date
  let tasks: [String]
  let stylePreset: String?
  let sensorData: UploadSessionSensorData?
  let intendedProcessing: String?
}

private struct UploadSessionContext {
  let sessionId: String
  let expectedFileCount: Int
  let expectedTotalBytes: Int
  let itemIdByFileId: [String: String]
  let sessionWarnings: [String]
  let manifestPath: String?
}

private struct RoomBucketKey: Hashable {
  let roomId: String
  let floorId: String
}

private struct UploadSessionCreateEnvelope: Encodable {
  let job_id: String
  let client_type: String
  let include_upload_urls: Bool
  let manifest: UploadSessionManifestPayload
}

private struct UploadSessionManifestPayload: Encodable {
  let version: String
  let project_id: String
  let cust3: String?
  let job5: String?
  let project_name: String?
  let web_session_id: String?
  let web_job_id: String?
  let companion_transport: String?
  let cable_receiver_token: String?
  let shot_id: String?
  let created_at: String
  let total_size_bytes: Int
  let total_files: Int
  let device_info: UploadSessionDeviceInfo
  let rooms: [UploadSessionManifestRoom]
  let global_preferences: UploadSessionGlobalPreferences?
}

private struct UploadSessionDeviceInfo: Encodable {
  let model: String
  let os_version: String
  let app_version: String
}

private struct UploadSessionGlobalPreferences: Encodable {
  let style_preset: String?
  let tasks: [String]?
  let delivery_format: [String]?
}

private struct UploadSessionManifestRoom: Encodable {
  let room_id: String
  let floor_id: String
  let room_name: String
  let room_type: String?
  let room_variant: Int
  let captures: [UploadSessionCapture]
}

private struct UploadSessionCapture: Encodable {
  let capture_id: String
  let capture_type: String
  let capture_subtype: String?
  let timestamp: String
  let tasks: [String]?
  let style_preset: String?
  let sensor_data: UploadSessionSensorData?
  let intended_processing: String?
  let files: [UploadSessionManifestFile]
}

private struct UploadSessionManifestFile: Encodable {
  let file_id: String
  let filename: String
  let relative_path: String?
  let motif_index: Int?
  let exposure_index: Int?
  let type: String
  let size_bytes: Int
  let checksum_sha256: String?
  let camera_metadata: UploadSessionCameraMetadata?
  let video_metadata: JSONValue?
  let motion_metadata: JSONValue?
  let intrinsics_metadata: JSONValue?
  let tracking_metadata: JSONValue?
  let floorplan_metadata: JSONValue?
  let file_metadata: JSONValue?
}

struct UploadSessionSensorData: Codable {
  let pitchDegrees: Double?
  let rollDegrees: Double?
  let headingDegrees: Double?
  let singleShotCorrectability: String?
  let singleShotTriggeredAt: String?
  let singleShotStabilityScore: Double?
  let singleShotStabilityState: String?

  init(
    pitchDegrees: Double?,
    rollDegrees: Double?,
    headingDegrees: Double?,
    singleShotAssessment: SingleShotCaptureAssessment? = nil
  ) {
    self.pitchDegrees = pitchDegrees
    self.rollDegrees = rollDegrees
    self.headingDegrees = headingDegrees
    self.singleShotCorrectability = singleShotAssessment?.status.manifestToken
    self.singleShotTriggeredAt = singleShotAssessment.map { ISO8601DateFormatter().string(from: $0.triggeredAt) }
    self.singleShotStabilityScore = singleShotAssessment?.stabilityScore
    self.singleShotStabilityState = singleShotAssessment?.stabilityState
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: FlexibleCodingKey.self)
    pitchDegrees = container.decodeIfPresent(Double.self, forKeys: ["pitchDegrees", "pitch_degrees"])
    rollDegrees = container.decodeIfPresent(Double.self, forKeys: ["rollDegrees", "roll_degrees"])
    headingDegrees = container.decodeIfPresent(Double.self, forKeys: ["headingDegrees", "heading_degrees"])
    singleShotCorrectability = container.decodeIfPresent(String.self, forKeys: ["singleShotCorrectability", "single_shot_correctability"])
    singleShotTriggeredAt = container.decodeIfPresent(String.self, forKeys: ["singleShotTriggeredAt", "single_shot_triggered_at"])
    singleShotStabilityScore = container.decodeIfPresent(Double.self, forKeys: ["singleShotStabilityScore", "single_shot_stability_score"])
    singleShotStabilityState = container.decodeIfPresent(String.self, forKeys: ["singleShotStabilityState", "single_shot_stability_state"])
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: FlexibleCodingKey.self)
    try container.encodeIfPresent(pitchDegrees, forKey: FlexibleCodingKey("pitch_degrees"))
    try container.encodeIfPresent(rollDegrees, forKey: FlexibleCodingKey("roll_degrees"))
    try container.encodeIfPresent(headingDegrees, forKey: FlexibleCodingKey("heading_degrees"))
    try container.encodeIfPresent(singleShotCorrectability, forKey: FlexibleCodingKey("single_shot_correctability"))
    try container.encodeIfPresent(singleShotTriggeredAt, forKey: FlexibleCodingKey("single_shot_triggered_at"))
    try container.encodeIfPresent(singleShotStabilityScore, forKey: FlexibleCodingKey("single_shot_stability_score"))
    try container.encodeIfPresent(singleShotStabilityState, forKey: FlexibleCodingKey("single_shot_stability_state"))
  }
}

struct UploadSessionCameraMetadata: Codable {
  let exposureValue: Double?
  let iso: Int?
  let shutterSpeed: String?
  let aperture: Double?
  let whiteBalanceKelvin: Int?
  let focalLengthMm: Double?
  let lensModel: String?
  let captureOrientation: String?
  let whiteBalanceMode: String?

  init(
    exposureValue: Double?,
    iso: Int?,
    shutterSpeed: String?,
    aperture: Double?,
    whiteBalanceKelvin: Int?,
    focalLengthMm: Double?,
    lensModel: String?,
    captureOrientation: String?,
    whiteBalanceMode: String?
  ) {
    self.exposureValue = exposureValue
    self.iso = iso
    self.shutterSpeed = shutterSpeed
    self.aperture = aperture
    self.whiteBalanceKelvin = whiteBalanceKelvin
    self.focalLengthMm = focalLengthMm
    self.lensModel = lensModel
    self.captureOrientation = captureOrientation
    self.whiteBalanceMode = whiteBalanceMode
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: FlexibleCodingKey.self)
    exposureValue = container.decodeIfPresent(Double.self, forKeys: ["exposureValue", "exposure_value"])
    iso = container.decodeIfPresent(Int.self, forKeys: ["iso"])
    shutterSpeed = container.decodeIfPresent(String.self, forKeys: ["shutterSpeed", "shutter_speed"])
    aperture = container.decodeIfPresent(Double.self, forKeys: ["aperture"])
    whiteBalanceKelvin = container.decodeIfPresent(Int.self, forKeys: ["whiteBalanceKelvin", "white_balance_kelvin"])
    focalLengthMm = container.decodeIfPresent(Double.self, forKeys: ["focalLengthMm", "focal_length_mm"])
    lensModel = container.decodeIfPresent(String.self, forKeys: ["lensModel", "lens_model"])
    captureOrientation = container.decodeIfPresent(String.self, forKeys: ["captureOrientation", "capture_orientation"])
    whiteBalanceMode = container.decodeIfPresent(String.self, forKeys: ["whiteBalanceMode", "white_balance_mode"])
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: FlexibleCodingKey.self)
    try container.encodeIfPresent(exposureValue, forKey: FlexibleCodingKey("exposure_value"))
    try container.encodeIfPresent(iso, forKey: FlexibleCodingKey("iso"))
    try container.encodeIfPresent(shutterSpeed, forKey: FlexibleCodingKey("shutter_speed"))
    try container.encodeIfPresent(aperture, forKey: FlexibleCodingKey("aperture"))
    try container.encodeIfPresent(whiteBalanceKelvin, forKey: FlexibleCodingKey("white_balance_kelvin"))
    try container.encodeIfPresent(focalLengthMm, forKey: FlexibleCodingKey("focal_length_mm"))
    try container.encodeIfPresent(lensModel, forKey: FlexibleCodingKey("lens_model"))
    try container.encodeIfPresent(captureOrientation, forKey: FlexibleCodingKey("capture_orientation"))
    try container.encodeIfPresent(whiteBalanceMode, forKey: FlexibleCodingKey("white_balance_mode"))
  }
}

private struct PhotoExifSnapshot {
  let iso: Double?
  let fNumber: Double?
  let focalLength: Double?
  let lensModel: String?
  let whiteBalance: Int?
  let orientationCode: Int?
  let make: String?
  let model: String?
}

private struct FlexibleCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int?

  init(_ stringValue: String) {
    self.stringValue = stringValue
    self.intValue = nil
  }

  init?(stringValue: String) {
    self.init(stringValue)
  }

  init?(intValue: Int) {
    self.stringValue = String(intValue)
    self.intValue = intValue
  }
}

private extension KeyedDecodingContainer where Key == FlexibleCodingKey {
  func decodeIfPresent<T: Decodable>(_ type: T.Type, forKeys keys: [String]) -> T? {
    for key in keys {
      if let value = try? decodeIfPresent(type, forKey: FlexibleCodingKey(key)) {
        return value
      }
    }
    return nil
  }
}

enum JSONValue: Codable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case object([String: JSONValue])
  case array([JSONValue])
  case null

  init?(any: Any) {
    if any is NSNull {
      self = .null
      return
    }
    if let value = any as? String {
      self = .string(value)
      return
    }
    if let value = any as? Bool {
      self = .bool(value)
      return
    }
    if let value = any as? NSNumber {
      if CFGetTypeID(value) == CFBooleanGetTypeID() {
        self = .bool(value.boolValue)
      } else {
        self = .number(value.doubleValue)
      }
      return
    }
    if let value = any as? [String: Any] {
      var mapped: [String: JSONValue] = [:]
      for (key, rawValue) in value {
        guard let converted = JSONValue(any: rawValue) else { continue }
        mapped[key] = converted
      }
      self = .object(mapped)
      return
    }
    if let value = any as? [Any] {
      self = .array(value.compactMap { JSONValue(any: $0) })
      return
    }
    return nil
  }

  var objectValue: [String: JSONValue]? {
    if case .object(let value) = self {
      return value
    }
    return nil
  }

  var stringValue: String? {
    if case .string(let value) = self {
      return value
    }
    return nil
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    if container.decodeNil() {
      self = .null
      return
    }
    if let value = try? container.decode(Bool.self) {
      self = .bool(value)
      return
    }
    if let value = try? container.decode(Double.self) {
      self = .number(value)
      return
    }
    if let value = try? container.decode(String.self) {
      self = .string(value)
      return
    }
    if let value = try? container.decode([String: JSONValue].self) {
      self = .object(value)
      return
    }
    if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
      return
    }

    throw DecodingError.dataCorruptedError(
      in: container,
      debugDescription: "Unsupported JSON value"
    )
  }

  func encode(to encoder: Encoder) throws {
    switch self {
    case .string(let value):
      var container = encoder.singleValueContainer()
      try container.encode(value)
    case .number(let value):
      var container = encoder.singleValueContainer()
      try container.encode(value)
    case .bool(let value):
      var container = encoder.singleValueContainer()
      try container.encode(value)
    case .object(let value):
      var container = encoder.singleValueContainer()
      try container.encode(value)
    case .array(let value):
      var container = encoder.singleValueContainer()
      try container.encode(value)
    case .null:
      var container = encoder.singleValueContainer()
      try container.encodeNil()
    }
  }
}

private enum ContractTransferState {
  case pending
  case uploading
  case done
  case failed
}

private struct ContractTransferItem {
  let fileId: String
  let recordId: UUID?
  let fileURL: URL
  let uploadData: Data?
  let relativePath: String
  let kind: String
  let mimeType: String
  let sizeBytes: Int
  let sha256: String?
  let metadata: ExpectedManifestFileMetadata
}

private struct ExpectedManifestV2: Encodable {
  let schema_version: String
  let app_version: String
  let customer_id: String
  let shoot_id: String
  let shoot_code: String
  let created_at: String
  let files: [ExpectedManifestFileV2]
}

private struct ExpectedManifestFileV2: Encodable {
  let kind: String
  let relative_path: String
  let size_bytes: Int
  let sha256: String?
  let customer_id: String
  let shoot_id: String
  let shoot_code: String
  let room_type_en: String?
  let room_label_de: String?
  let stack_id: String?
  let image_id: String
  let timestamp: String
  let ev_value: Double?
}

private struct ExpectedManifestFileMetadata {
  let customer_id: String
  let shoot_id: String
  let shoot_code: String
  let room_type_en: String?
  let room_label_de: String?
  let stack_id: String?
  let image_id: String
  let timestamp: String
  let ev_value: Double?
}

private struct DirectR2SessionStartRequest: Encodable {
  let customer_id: String
  let shoot_id: String
}

private struct DirectR2SessionStartResponse: Decodable {
  let sessionId: String
  let expiresAt: String?
  let r2PrefixStaging: String?
  let signedURLs: [DirectR2SignedURL]

  private enum CodingKeys: String, CodingKey {
    case sessionId
    case expiresAt
    case r2PrefixStaging
    case signedURLs
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    sessionId = try container.decode(String.self, forKey: .sessionId)
    expiresAt = try container.decodeIfPresent(String.self, forKey: .expiresAt)
    r2PrefixStaging = try container.decodeIfPresent(String.self, forKey: .r2PrefixStaging)

    if let list = try? container.decode([DirectR2SignedURLEntry].self, forKey: .signedURLs) {
      signedURLs = list.compactMap { entry in
        let trimmed = entry.url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        return DirectR2SignedURL(relativePath: entry.relativePath, url: trimmed, headers: entry.headers ?? [:])
      }
      return
    }

    if let dictionary = try? container.decode([String: String].self, forKey: .signedURLs) {
      signedURLs = dictionary
        .filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .map { DirectR2SignedURL(relativePath: $0.key, url: $0.value, headers: [:]) }
      return
    }

    signedURLs = []
  }
}

private struct DirectR2SignedURLEntry: Decodable {
  let relativePath: String
  let url: String
  let headers: [String: String]?
}

private struct DirectR2SignedURL: Equatable {
  let relativePath: String
  let url: String
  let headers: [String: String]
}

private struct DirectR2SignedURLRequest: Encodable {
  let relative_path: String
  let size_bytes: Int
}

private struct DirectR2SignedURLResponse: Decodable {
  let url: String?
  let signedUrl: String?
  let uploadUrl: String?
  let presignedUrl: String?
  let headers: [String: String]?

  func toSignedURL() -> DirectR2SignedURL? {
    let candidate = (url ?? signedUrl ?? uploadUrl ?? presignedUrl)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let candidate, !candidate.isEmpty else {
      return nil
    }
    return DirectR2SignedURL(relativePath: "", url: candidate, headers: headers ?? [:])
  }
}

private struct DirectR2MarkUploadedRequest: Encodable {
  let relative_path: String
  let size_bytes: Int
  let sha256: String?
  let etag: String?
}

private struct UploadSessionCreateResponse: Decodable {
  let sessionId: String
  let expectedFiles: Int?
  let totalBytesExpected: Int?
  let warnings: [String]?
  let manifestSidecarPath: String?
  let filesToUpload: [UploadSessionCreateFileToUpload]?
  let files: [UploadSessionCreateFileInfo]?
}

private struct UploadSessionCreateFileInfo: Decodable {
  let itemId: String
  let fileId: String?
}

private struct UploadSessionCreateFileToUpload: Decodable {
  let itemId: String
  let originalFilename: String?
}

private struct MobileWebConnectHandshakeRequest: Encodable {
  let schema: String
  let web_session_id: String
  let project_id: String?
  let job_id: String
  let cust3: String?
  let job5: String?
  let naming_version: String
  let client_type: String
  let app_version: String
  let capabilities: MobileWebConnectHandshakeCapabilities
  let manifest_summary: MobileWebConnectHandshakeManifestSummary
  let manifest: UploadSessionManifestPayload
}

private struct MobileWebConnectHandshakeCapabilities: Encodable {
  let supports_capture_v2: Bool
  let supports_floor_id: Bool
  let supports_view_id: Bool
  let supports_raw_brackets: Bool
}

private struct MobileWebConnectHandshakeManifestSummary: Encodable {
  let capture_count: Int
  let file_count: Int
  let total_bytes: Int
}

private struct MobileWebConnectResolvedIdentity: Decodable {
  let jobId: String
  let cust3: String?
  let job5: String?
  let namingVersion: String?
  let taxonomyVersion: String?
}

private struct MobileWebConnectRequirements: Decodable {
  let viewIdRequired: Bool?
  let acceptedMode: String?
}

private struct MobileWebConnectHandshakeResponse: Decodable {
  let schema: String?
  let status: String?
  let command: String?
  let webSessionId: String?
  let uploadSessionId: String?
  let expectedFiles: Int?
  let totalBytesExpected: Int?
  let manifestSidecarPath: String?
  let filesToUpload: [UploadSessionCreateFileToUpload]?
  let files: [UploadSessionCreateFileInfo]?
  let resolved: MobileWebConnectResolvedIdentity?
  let requirements: MobileWebConnectRequirements?
  let warnings: [String]?
}

private struct MobileWebConnectCommandResponse: Decodable {
  let status: String?
  let command: String?
  let webSessionId: String?
  let uploadSessionId: String?
  let stylePreset: String?
  let tasks: [String]?
  let requirements: MobileWebConnectRequirements?
  let warnings: [String]?
}

private struct PixcapturePackageKeyRequest: Encodable {
  let client_type: String
  let app_version: String
}

private struct PixcapturePackageKeyResponse: Decodable {
  let schema: String
  let packageId: String
  let keyId: String
  let encryption: PixcapturePackageKeyEncryption
  let expiresAt: String?
}

private struct PixcapturePackageKeyEncryption: Decodable {
  let algorithm: String
  let keyBase64: String
}

private struct PixcapturePackagePrepareRequest: Encodable {
  let job_id: String
  let project_id: String?
  let cust3: String?
  let job5: String?
  let client_type: String
  let app_version: String
  let package: PixcapturePackagePrepareInfo
  let manifest: UploadSessionManifestPayload
}

private struct PixcapturePackagePrepareInfo: Encodable {
  let package_id: String
  let key_id: String
  let filename: String
  let size_bytes: Int
  let sha256: String
  let motif_count: Int
  let technical_file_count: Int
  let source_total_bytes: Int
}

private struct PixcapturePackagePrepareResponse: Decodable {
  let schema: String?
  let success: Bool?
  let sessionId: String
  let status: String?
  let expiresAt: String?
  let expectedFiles: Int?
  let totalBytesExpected: Int?
  let package: PixcapturePackagePrepareResponsePackage
  let filesToUpload: [UploadSessionCreateFileToUpload]?
  let files: [UploadSessionCreateFileInfo]?
  let warnings: [String]?
}

private struct PixcapturePackagePrepareResponsePackage: Decodable {
  let packageId: String
  let keyId: String
  let fileId: String
  let itemId: String
  let filename: String
  let objectKey: String?
}

private struct PixcapturePackageEnvelope: Encodable {
  let schema: String
  let package_id: String
  let key_id: String
  let encryption_algorithm: String
  let app_version: String
  let created_at: String
  let source_file_count: Int
  let source_total_bytes: Int
  let manifest: UploadSessionManifestPayload
  let files: [PixcapturePackageSourceFile]
  let previews: [PixcapturePackagePreview]
}

private struct PixcapturePackageSourceFile: Encodable {
  let file_id: String
  let filename: String
  let relative_path: String?
  let mime_type: String
  let size_bytes: Int
  let checksum_sha256: String?
  let capture_id: String
  let capture_type: String
  let room_id: String
  let room_name: String
  let floor_id: String
  let motif_index: Int?
  let exposure_index: Int?
}

private struct PixcapturePackagePreview: Encodable {
  let capture_id: String
  let filename: String
  let mime_type: String
  let size_bytes: Int
  let data_base64: String
  let room_name: String
  let floor_id: String
  let motif_index: Int?
}

private struct PixcapturePackageEntryHeader: Encodable {
  let file_id: String
  let filename: String
  let relative_path: String?
  let mime_type: String
  let size_bytes: Int
  let checksum_sha256: String
}

nonisolated struct CompanionPackageReceiveResponse: Decodable, Sendable {
  let accepted: Bool?
  let packageId: String?
  let filename: String?
  let sizeBytes: Int?
  let sha256: String?
  let storedPath: String?
  let warnings: [String]?
}

nonisolated enum CompanionPackageReceiptValidationError: Error, Equatable, Sendable {
  case notAccepted
  case wrongPackageId
  case wrongSize(received: Int?, expected: Int)
  case wrongChecksum
  case warnings([String])
}

nonisolated enum CompanionPackageReceiptValidator {
  static func validate(
    _ receipt: CompanionPackageReceiveResponse,
    expectedPackageId: String,
    expectedSizeBytes: Int,
    expectedSHA256: String
  ) throws {
    guard receipt.accepted == true else {
      throw CompanionPackageReceiptValidationError.notAccepted
    }
    guard receipt.packageId == expectedPackageId else {
      throw CompanionPackageReceiptValidationError.wrongPackageId
    }
    guard receipt.sizeBytes == expectedSizeBytes else {
      throw CompanionPackageReceiptValidationError.wrongSize(
        received: receipt.sizeBytes,
        expected: expectedSizeBytes
      )
    }
    guard let receivedSHA256 = receipt.sha256,
          receivedSHA256.caseInsensitiveCompare(expectedSHA256) == .orderedSame else {
      throw CompanionPackageReceiptValidationError.wrongChecksum
    }
    guard receipt.warnings?.isEmpty != false else {
      throw CompanionPackageReceiptValidationError.warnings(receipt.warnings ?? [])
    }
  }
}

private struct UploadSessionPresignRequest: Encodable {
  let parts: Int?
}

private struct UploadSessionPresignResponse: Decodable {
  let uploadType: String
  let uploadUrl: String?
  let uploadId: String?
  let parts: [UploadSessionPresignPart]?
}

private struct UploadSessionPresignPart: Decodable {
  let partNumber: Int
  let uploadUrl: String
}

private struct UploadSessionMultipartPart: Encodable {
  let part_number: Int
  let etag: String
}

private struct UploadSessionMultipartCompletePayload: Encodable {
  let upload_id: String
  let parts: [UploadSessionMultipartPart]
}

private struct UploadSessionCompleteRequest: Encodable {
  let checksum_sha256: String?
  let size_bytes: Int
  let multipart: UploadSessionMultipartCompletePayload?
}

private struct UploadSessionCompleteResponse: Decodable {
  let status: String?
  let warnings: [String]?
}

private struct UploadSessionFinalizeMetrics: Encodable {
  let total: Int
  let verified: Int
  let failed: Int
}

private struct UploadSessionFinalizeRequest: Encodable {
  let apply_renaming: Bool
  let total_size_tolerance_percent: Int
  let metrics: UploadSessionFinalizeMetrics?
}

private struct UploadSessionFinalizeResponse: Decodable {
  let status: String?
  let phase: String?
  let message: String?
  let files: [UploadSessionFinalizeFile]?
  let warnings: [String]?
  let receiptPath: String?
  let filesDetailed: [UploadProtocolReceiptFile]?
  let actualTotalSizeBytes: Int?
  let serverTotal: Int?
  let serverVerified: Int?
  let metricsMatch: Bool?
}

private struct UploadSessionFinalizeFile: Decodable {
  let itemId: String
  let canonicalName: String?
  let finalR2Url: String?
}


private struct APIError: Decodable {
  let error: String
}
