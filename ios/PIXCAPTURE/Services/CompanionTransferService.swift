import Foundation
import Combine

nonisolated struct CompanionPackagePreflight {
  let motifCount: Int
  let technicalFileCount: Int
  let totalBytes: Int64
  let missingFileCount: Int

  var hasFiles: Bool {
    technicalFileCount > 0
  }
}

@MainActor
final class CompanionTransferService: ObservableObject {
  @Published private(set) var isConnected: Bool = false
  @Published private(set) var isTransferring: Bool = false
  @Published private(set) var statusMessage: String?

  func testConnection(using settings: AppSettings) async {
    let host = settings.companionHost.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !host.isEmpty else {
      isConnected = false
      statusMessage = "Bitte Host/IP eintragen."
      return
    }
    guard let baseURL = buildBaseURL(settings: settings) else {
      isConnected = false
      statusMessage = "Ungültige Host-Konfiguration."
      return
    }

    var request = URLRequest(url: baseURL.appendingPathComponent("health"))
    request.httpMethod = "GET"
    request.timeoutInterval = 4.0

    do {
      let (_, response) = try await URLSession.shared.data(for: request)
      if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
        isConnected = true
        statusMessage = "WLAN-Verbindung erfolgreich."
      } else {
        isConnected = false
        statusMessage = "Rechner erreichbar, aber Companion-Endpunkt antwortet nicht wie erwartet."
      }
    } catch {
      isConnected = false
      statusMessage = "Verbindung fehlgeschlagen: \(error.localizedDescription)"
    }
  }

  func send(records: [UploadRecord], settings: AppSettings) async -> (sent: Int, failed: Int) {
    guard !isTransferring else { return (0, records.count) }
    guard !records.isEmpty else {
      statusMessage = "Keine markierten Bilder."
      return (0, 0)
    }
    let preflight = packagePreflight(records: records)
    let byteText = ByteCountFormatter.string(fromByteCount: preflight.totalBytes, countStyle: .file)
    statusMessage = "Paket-Vorpruefung: \(preflight.motifCount) Motive, \(preflight.technicalFileCount) technische Dateien, \(byteText). Companion/Kabel bleibt bis zur verschluesselten .pixcapturepkg-Backend-Freigabe gesperrt."
    return (0, records.count)
  }

  func packagePreflight(records: [UploadRecord]) -> CompanionPackagePreflight {
    var seenPaths = Set<String>()
    var technicalFileCount = 0
    var totalBytes: Int64 = 0
    var missingFileCount = 0

    func register(_ url: URL?) {
      guard let url else { return }
      let path = url.standardizedFileURL.path
      guard seenPaths.insert(path).inserted else { return }
      guard FileManager.default.fileExists(atPath: path) else {
        missingFileCount += 1
        return
      }
      technicalFileCount += 1
      let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
      let bytes = values?.fileSize ?? values?.totalFileAllocatedSize ?? 0
      totalBytes += Int64(max(0, bytes))
    }

    for record in records {
      register(record.fileURL)
      register(record.originalFileURL)
      register(FileStore.existingCompanionPreviewURL(for: record.fileURL))
      register(FileStore.existingCompanionXMPURL(for: record.fileURL))
      register(FileStore.existingCompanionDepthURL(for: record.fileURL))
      register(record.exifLogURL)
    }

    return CompanionPackagePreflight(
      motifCount: Set(records.map(\.seriesId)).count,
      technicalFileCount: technicalFileCount,
      totalBytes: totalBytes,
      missingFileCount: missingFileCount
    )
  }

  private func buildBaseURL(settings: AppSettings) -> URL? {
    let host = settings.companionHost.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !host.isEmpty else { return nil }
    let scheme = settings.companionUseHTTPS ? "https" : "http"
    var components = URLComponents()
    components.scheme = scheme
    components.host = host
    components.port = settings.companionPort
    return components.url
  }
}
