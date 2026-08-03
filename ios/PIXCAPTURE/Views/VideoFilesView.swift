import SwiftUI
import UIKit

struct VideoFilesView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var entries: [VideoProjectEntry] = []
  @State private var errorText: String? = nil
  @State private var shareItems: [Any] = []
  @State private var shareExcludedActivityTypes: [UIActivity.ActivityType]? = [.mail]
  @State private var showShareSheet = false
  @State private var pendingDeletion: VideoProjectEntry? = nil
  @State private var showDeleteAllConfirmation = false
  @State private var pendingMail: PendingMailDraft? = nil
  @State private var stagedShareDirectoryURL: URL? = nil

  var body: some View {
    NavigationStack {
      ZStack {
        Color(.systemGray6).ignoresSafeArea()

        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            infoCard

            if let errorText {
              Text(errorText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.red.opacity(0.9))
                .padding(.horizontal, 18)
            }

            if entries.isEmpty {
              emptyState
                .padding(.horizontal, 18)
            } else {
              VStack(spacing: 10) {
                ForEach(entries) { entry in
                  entryCard(entry)
                }
              }
              .padding(.horizontal, 18)
            }
          }
          .padding(.vertical, 14)
          .padding(.bottom, 30)
        }
      }
      .navigationTitle("Video-Dateien")
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Alle löschen", role: .destructive) {
            showDeleteAllConfirmation = true
          }
          .disabled(entries.isEmpty)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Fertig") { dismiss() }
        }
      }
      .onAppear {
        reload()
      }
      .sheet(isPresented: $showShareSheet, onDismiss: cleanupShareStagingDirectory) {
        ShareSheet(
          activityItems: shareItems,
          excludedActivityTypes: shareExcludedActivityTypes
        ) { _ in
          cleanupShareStagingDirectory()
        }
      }
      .sheet(item: $pendingMail) { draft in
        MailComposerSheet(
          subject: draft.subject,
          body: draft.message,
          attachments: draft.attachments
        ) { _, error in
          if let error {
            errorText = "Mail-Export fehlgeschlagen: \(error.localizedDescription)"
          }
          pendingMail = nil
        }
      }
      .confirmationDialog(
        "Alle Video-Daten löschen?",
        isPresented: $showDeleteAllConfirmation,
        titleVisibility: .visible
      ) {
        Button("Alles endgültig löschen", role: .destructive) {
          deleteAllEntries()
        }
        Button("Abbrechen", role: .cancel) {}
      } message: {
        Text("Alle Video-Projekte und zugehörigen Dateien werden dauerhaft aus dem App-Speicher entfernt.")
      }
      .alert(
        "Projekt löschen?",
        isPresented: Binding(
          get: { pendingDeletion != nil },
          set: { isPresented in
            if !isPresented { pendingDeletion = nil }
          }
        ),
        presenting: pendingDeletion
      ) { entry in
        Button("Abbrechen", role: .cancel) {}
        Button("Löschen", role: .destructive) {
          deleteEntry(entry)
        }
      } message: { entry in
        Text("Projekt \(entry.idString) und alle enthaltenen Dateien werden endgültig gelöscht.")
      }
    }
  }

  private var infoCard: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Speicherort (Dateien-App)")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Color.black.opacity(0.82))

      Text("Du findest die Projekte in der Dateien-App unter:\nAuf meinem iPhone → PixCapture → VideoProjects")
        .font(.system(size: 12))
        .foregroundStyle(Color.black.opacity(0.6))
        .fixedSize(horizontal: false, vertical: true)

      Text("Neue Clips liegen pro Aufnahme in einem eigenen Unterordner unter video/<take_id>/ (mit Video + Tracking + Sensoren + Intrinsics).")
        .font(.system(size: 12))
        .foregroundStyle(Color.black.opacity(0.6))
        .fixedSize(horizontal: false, vertical: true)

      Text("Tipp: „Per Mail“ und „Teilen“ senden den kompletten Datensatz als Datei-Anhänge (keine Ordner-URLs).")
        .font(.system(size: 12))
        .foregroundStyle(Color.black.opacity(0.6))
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(14)
    .background(Color.white)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.06), lineWidth: 1))
    .padding(.horizontal, 18)
  }

  private var emptyState: some View {
    VStack(spacing: 10) {
      Image(systemName: "video.slash")
        .font(.system(size: 26, weight: .semibold))
        .foregroundStyle(Color.gray.opacity(0.7))
      Text("Noch keine Video-Projekte")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(Color.black.opacity(0.75))
      Text("Erstelle ein 3D Video, dann erscheint es hier und in der Dateien-App.")
        .font(.system(size: 12))
        .foregroundStyle(Color.black.opacity(0.55))
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, minHeight: 220)
    .padding(.vertical, 24)
    .background(Color.white)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.06), lineWidth: 1))
  }

  private func entryCard(_ entry: VideoProjectEntry) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Projekt \(entry.idString)")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.82))
          Text(entry.subtitle)
            .font(.system(size: 12))
            .foregroundStyle(Color.black.opacity(0.6))
        }
        Spacer()
        HStack(spacing: 8) {
          Button {
            prepareMailShare(for: entry)
          } label: {
            Text("Per Mail")
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(.white)
              .padding(.horizontal, 12)
              .padding(.vertical, 8)
              .background(Color.blue.opacity(0.82))
              .clipShape(Capsule())
          }
          .disabled(!entry.hasExportableFiles)
          .opacity(entry.hasExportableFiles ? 1.0 : 0.5)

          Button {
            prepareGeneralShare(for: entry)
          } label: {
            Text("Teilen")
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(.white)
              .padding(.horizontal, 12)
              .padding(.vertical, 8)
              .background(Color.black.opacity(0.75))
              .clipShape(Capsule())
          }
          .disabled(!entry.hasExportableFiles)
          .opacity(entry.hasExportableFiles ? 1.0 : 0.5)

          Button(role: .destructive) {
            pendingDeletion = entry
          } label: {
            Text("Löschen")
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(.white)
              .padding(.horizontal, 12)
              .padding(.vertical, 8)
              .background(Color.red.opacity(0.85))
              .clipShape(Capsule())
          }
        }
      }

      HStack(spacing: 10) {
        badge(title: entry.hasVideo ? "Video" : "Video fehlt", ok: entry.hasVideo)
        badge(title: entry.hasLidar ? "LiDAR" : "LiDAR fehlt", ok: entry.hasLidar)
        badge(title: entry.hasManifest ? "manifest" : "manifest fehlt", ok: entry.hasManifest)
      }
    }
    .padding(14)
    .background(Color.white)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.06), lineWidth: 1))
  }

  private func badge(title: String, ok: Bool) -> some View {
    Text(title)
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(ok ? Color.black.opacity(0.75) : Color.black.opacity(0.4))
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(ok ? Color(red: 0.29, green: 0.35, blue: 0.29).opacity(0.15) : Color.black.opacity(0.05))
      .clipShape(Capsule())
      .overlay(
        Capsule().stroke(ok ? Color(red: 0.29, green: 0.35, blue: 0.29).opacity(0.35) : Color.black.opacity(0.06), lineWidth: 1)
      )
  }

  private func reload() {
    errorText = nil
    do {
      let base = try FileStore.ensureUserFilesDirectory()
      let projectsDir = base.appendingPathComponent("VideoProjects", isDirectory: true)
      let fm = FileManager.default
      guard fm.fileExists(atPath: projectsDir.path) else {
        entries = []
        return
      }

      let urls = try fm.contentsOfDirectory(
        at: projectsDir,
        includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
        options: [.skipsHiddenFiles]
      )

      var found: [VideoProjectEntry] = []
      for url in urls {
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
        guard let uuid = UUID(uuidString: url.lastPathComponent) else { continue }
        found.append(VideoProjectEntry(projectId: uuid, root: url))
      }

      entries = found.sorted(by: { $0.modifiedAt > $1.modifiedAt })
    } catch {
      errorText = error.localizedDescription
      entries = []
    }
  }

  private func prepareGeneralShare(for entry: VideoProjectEntry) {
    errorText = nil
    let attachmentURLs = entry.shareURLs
    guard !attachmentURLs.isEmpty else {
      errorText = "Keine exportierbaren Dateien gefunden."
      return
    }
    do {
      shareExcludedActivityTypes = [.mail]
      shareItems = try makeShareItems(
        for: attachmentURLs
      )
      showShareSheet = true
    } catch {
      errorText = "Teilen fehlgeschlagen: \(error.localizedDescription)"
      cleanupShareStagingDirectory()
    }
  }

  private func prepareMailShare(for entry: VideoProjectEntry) {
    errorText = nil
    let subject = "PIXCAPTURE Datensatz \(entry.idString)"
    let message = "Kompletter Datensatz als Dateianhänge."
    let attachmentURLs = entry.mailAttachmentURLs
    guard !attachmentURLs.isEmpty else {
      errorText = "Keine exportierbaren Dateien gefunden."
      return
    }

    if MailComposerSheet.canSendMail() {
      do {
        let attachments = try attachmentURLs.map { try MailAttachmentData(fileURL: $0) }
        pendingMail = PendingMailDraft(subject: subject, message: message, attachments: attachments)
      } catch {
        errorText = "Mail-Anhänge konnten nicht vorbereitet werden: \(error.localizedDescription)"
      }
      return
    }

    // Fallback for devices without Apple Mail account: open generic share sheet with file URLs.
    errorText = "Mail ist auf diesem Gerät nicht eingerichtet. Anhänge werden über „Teilen“ bereitgestellt."
    do {
      shareExcludedActivityTypes = nil
      shareItems = try makeShareItems(for: attachmentURLs)
      showShareSheet = true
    } catch {
      errorText = "Teilen fehlgeschlagen: \(error.localizedDescription)"
      cleanupShareStagingDirectory()
    }
  }

  private func makeShareItems(for fileURLs: [URL]) throws -> [Any] {
    let stagedURLs = try stageFilesForShare(fileURLs)
    guard !stagedURLs.isEmpty else {
      throw CocoaError(.fileNoSuchFile)
    }
    return stagedURLs
  }

  private func stageFilesForShare(_ fileURLs: [URL]) throws -> [URL] {
    let fm = FileManager.default
    cleanupShareStagingDirectory()

    let stagingDir = fm.temporaryDirectory.appendingPathComponent(
      "pixcapture-share-\(UUID().uuidString)",
      isDirectory: true
    )
    try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)

    var stagedURLs: [URL] = []
    for sourceURL in fileURLs {
      var isDirectory: ObjCBool = false
      guard fm.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
        continue
      }

      let candidate = stagingDir.appendingPathComponent(sourceURL.lastPathComponent)
      let targetURL: URL
      if fm.fileExists(atPath: candidate.path) {
        targetURL = stagingDir.appendingPathComponent("\(UUID().uuidString)_\(sourceURL.lastPathComponent)")
      } else {
        targetURL = candidate
      }

      try fm.copyItem(at: sourceURL, to: targetURL)
      stagedURLs.append(targetURL)
    }
    stagedShareDirectoryURL = stagingDir
    return stagedURLs
  }

  private func cleanupShareStagingDirectory() {
    guard let stagedShareDirectoryURL else { return }
    try? FileManager.default.removeItem(at: stagedShareDirectoryURL)
    self.stagedShareDirectoryURL = nil
  }

  private func deleteEntry(_ entry: VideoProjectEntry) {
    errorText = nil
    do {
      try VideoProjectStore.deleteProjectCompletely(projectId: entry.id)
      reload()
    } catch {
      errorText = "Löschen fehlgeschlagen: \(error.localizedDescription)"
    }
  }

  private func deleteAllEntries() {
    errorText = nil
    do {
      try VideoProjectStore.deleteAllProjectsCompletely()
      reload()
    } catch {
      errorText = "Löschen aller Video-Daten fehlgeschlagen: \(error.localizedDescription)"
    }
  }

  private struct PendingMailDraft: Identifiable {
    let id = UUID()
    let subject: String
    let message: String
    let attachments: [MailAttachmentData]
  }

  private struct VideoProjectEntry: Identifiable, Hashable {
    let id: UUID
    let root: URL
    let modifiedAt: Date

    let videoDirURL: URL
    let videoURLs: [URL]
    let perTakeSensorURLs: [URL]
    let perTakeIntrinsicsURLs: [URL]
    let perTakeTrackingURLs: [URL]

    let mainVideoURLLegacy: URL
    let lidarURL: URL
    let sensorsURLLegacy: URL
    let intrinsicsURLLegacy: URL
    let trackingURLLegacy: URL
    let manifestURL: URL
    let floorplanPNGURL: URL
    let segmentsJSONURL: URL

    init(projectId: UUID, root: URL) {
      id = projectId
      self.root = root

      let fm = FileManager.default
      let attrs = (try? fm.attributesOfItem(atPath: root.path)) ?? [:]
      modifiedAt = (attrs[.modificationDate] as? Date) ?? Date.distantPast

      videoDirURL = root.appendingPathComponent("video", isDirectory: true)
      let videoFiles = Self.recursiveFiles(in: videoDirURL)
      videoURLs = videoFiles.filter { $0.pathExtension.lowercased() == "mov" }
      perTakeSensorURLs = videoFiles.filter {
        $0.pathExtension.lowercased() == "csv" || $0.lastPathComponent.lowercased().contains("sensor")
      }
      perTakeIntrinsicsURLs = videoFiles.filter {
        $0.pathExtension.lowercased() == "json" && $0.lastPathComponent.lowercased().contains("intrinsics")
      }
      perTakeTrackingURLs = videoFiles.filter {
        $0.pathExtension.lowercased() == "json" && $0.lastPathComponent.lowercased().contains("tracking")
      }

      mainVideoURLLegacy = videoDirURL.appendingPathComponent("main_scan.mov")
      lidarURL = root.appendingPathComponent("scan.usdz")
      sensorsURLLegacy = root.appendingPathComponent("sensors.csv")
      intrinsicsURLLegacy = root.appendingPathComponent("intrinsics.json")
      trackingURLLegacy = root.appendingPathComponent("tracking.json")
      manifestURL = root.appendingPathComponent("manifest.upj")
      floorplanPNGURL = root.appendingPathComponent("floorplan.png")
      segmentsJSONURL = root.appendingPathComponent("segments.json")
    }

    var idString: String {
      String(id.uuidString.prefix(8))
    }

    var hasVideo: Bool {
      !videoURLs.isEmpty || FileManager.default.fileExists(atPath: mainVideoURLLegacy.path)
    }
    var hasLidar: Bool { FileManager.default.fileExists(atPath: lidarURL.path) }
    var hasManifest: Bool { FileManager.default.fileExists(atPath: manifestURL.path) }
    var hasExportableFiles: Bool { !allFileURLs.isEmpty }

    private var allFileURLs: [URL] {
      var seen = Set<String>()
      return Self.recursiveFiles(in: root)
        .filter { url in
        guard Self.isExistingFile(url) else { return false }
        if seen.contains(url.path) { return false }
        seen.insert(url.path)
        return true
      }
        .sorted(by: { $0.path < $1.path })
    }

    var subtitle: String {
      let date = DateFormatter.localizedString(from: modifiedAt, dateStyle: .medium, timeStyle: .short)
      let takeCount = hasVideo ? max(videoURLs.count, 1) : 0
      return "Zuletzt geändert: \(date) · \(takeCount) Video(s)"
    }

    var shareURLs: [URL] {
      allFileURLs
    }

    var mailAttachmentURLs: [URL] {
      allFileURLs
    }

    private static func recursiveFiles(in directory: URL) -> [URL] {
      let fm = FileManager.default
      guard fm.fileExists(atPath: directory.path) else { return [] }
      guard let enumerator = fm.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      ) else {
        return []
      }

      var files: [URL] = []
      for case let url as URL in enumerator {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if !isDirectory {
          files.append(url)
        }
      }
      return files
    }

    private static func isExistingFile(_ url: URL) -> Bool {
      var isDirectory: ObjCBool = false
      let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
      return exists && !isDirectory.boolValue
    }
  }
}
