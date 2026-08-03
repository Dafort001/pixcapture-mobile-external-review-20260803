import Foundation
import SwiftUI
import AVFoundation
import UIKit

struct UploadQueueView: View {
  private static let unassignedInboxMotifLimit = AuthService.mobileInboxMotifLimit

  let uploadScopeSeriesIds: Set<UUID>?
  let initialConnectURL: String?

  init(uploadScopeSeriesIds: Set<UUID>? = nil, initialConnectURL: String? = nil) {
    self.uploadScopeSeriesIds = uploadScopeSeriesIds
    self.initialConnectURL = initialConnectURL
  }

  private static let cablePackageDisabledMessage = "Die Kabel-Option ist in dieser App-Version deaktiviert. Bitte nutze Direkt in die Cloud oder die WLAN-Option. Ein Kabel-Paket ist nur noch ein Support-Notfallweg und kein normaler Upload."

  private enum UploadStartMode: String, CaseIterable, Identifiable, Hashable {
    case localWifi
    case directR2
    case companionWifi
    case cablePackage

    var id: String { rawValue }

    static var customerVisibleCases: [UploadStartMode] {
      [.companionWifi, .localWifi]
    }

    var title: String {
      switch self {
      case .localWifi:
        return "Direkt in Cloud"
      case .directR2:
        return "Direkt ohne Portal-QR"
      case .companionWifi:
        return "Über Rechner"
      case .cablePackage:
        return "Kabel-Option deaktiviert"
      }
    }

    var compactTitle: String {
      switch self {
      case .localWifi:
        return "Direkt in Cloud"
      case .directR2:
        return "Direkt"
      case .companionWifi:
        return "Über Rechner"
      case .cablePackage:
        return "Kabel"
      }
    }

    var subtitle: String {
      switch self {
      case .localWifi:
        return "Nur als Ersatzweg: Das iPhone lädt selbst in den PixCapture-Speicher."
      case .directR2:
        return "Ohne Portal-QR mit deinem App-Login direkt hochladen."
      case .companionWifi:
        return "Telefon sendet die ausgewählten Motive zuerst lokal an diesen Rechner."
      case .cablePackage:
        return UploadQueueView.cablePackageDisabledMessage
      }
    }

    var systemImage: String {
      switch self {
      case .localWifi:
        return "qrcode.viewfinder"
      case .directR2:
        return "icloud.and.arrow.up.fill"
      case .companionWifi:
        return "desktopcomputer.and.arrow.down"
      case .cablePackage:
        return "cable.connector"
      }
    }

    var isAvailable: Bool {
      switch self {
      case .localWifi, .directR2, .companionWifi, .cablePackage:
        return self != .cablePackage
      }
    }

    var accessibilityIdentifier: String {
      switch self {
      case .localWifi:
        return "upload.mode.localWifi"
      case .directR2:
        return "upload.mode.direct"
      case .companionWifi:
        return "upload.mode.companionWifi"
      case .cablePackage:
        return "upload.mode.cablePackage"
      }
    }
  }

  @EnvironmentObject var uploadQueue: UploadQueue
  @EnvironmentObject var authService: AuthService
  @EnvironmentObject var settings: AppSettings
  @EnvironmentObject var companionTransfer: CompanionTransferService
  @Environment(\.dismiss) private var dismiss
  @AppStorage("pixcapture.supportToolsUnlocked") private var supportToolsUnlocked = false
  @State private var protocolShareURL: URL?
  @State private var packageExportURL: URL?
  @State private var showWebConnectSheet = false
  @State private var showQRScanner = false
  @State private var webConnectInput = ""
  @State private var webConnectError: String?
  @State private var uploadModeSelection: UploadStartMode = .companionWifi
  @State private var showUploadMethodDetails = false
  @State private var didAutoPresentConnectSheet = false
  @State private var expandedSeriesIds: Set<UUID> = []
  @State private var expandedProtocolLogIds: Set<UUID> = []
  @State private var showRetentionPrompt = false
  @State private var retentionPromptRecordIds: [UUID] = []
  @State private var showUploadedCleanupPrompt = false
  @State private var uploadedCleanupPromptRecordIds: [UUID] = []
  @State private var showPackageDeletePrompt = false
  @State private var supportCopyMessage: String?

  private var showsProtocolExportTools: Bool {
    AppFeatureFlags.visibleInternalExportEnabled
      || (AppFeatureFlags.supportToolsUnlockEnabled && supportToolsUnlocked)
  }

  private var isUploading: Bool {
    uploadQueue.isUploading
  }

  private var uploadMessage: String? {
    uploadQueue.uploadMessage
  }

  private var uploadProgress: PixcaptureUploadProgress? {
    uploadQueue.uploadProgress
  }

  private var shouldShowUploadStatusCard: Bool {
    if let uploadProgress {
      return uploadProgress.phase != .completed
    }
    return uploadMessage != nil
  }

  private var uploadFileErrors: [UploadFileError] {
    uploadQueue.uploadFileErrors
  }

  private var uploadedCleanupRecords: [UploadRecord] {
    uploadQueue.records.filter { $0.status == .uploaded }
  }

  private var hasReadyCablePackage: Bool {
    uploadQueue.latestPackageExportURL != nil
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 12) {
        if let uploadScopeSeriesIds, !uploadScopeSeriesIds.isEmpty {
          Text(uploadScopeNoticeText(count: uploadScopeSeriesIds.count))
            .font(.caption)
            .foregroundStyle(Color.blue.opacity(0.9))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
        }
        let unassignedCount = uploadCandidates.filter { !hasAssignedJob($0) }.count
        let unassignedStackCount = stackCount(for: uploadCandidates.filter { !hasAssignedJob($0) })
        let metadataPendingCount = uploadCandidates.filter { !$0.metadataReady }.count
        if unassignedCount > 0 {
          Text(unassignedStackCount > Self.unassignedInboxMotifLimit
            ? l10nFormat("upload.inbox.full.format", unassignedStackCount)
            : l10nFormat("upload.inbox.notice.format", unassignedStackCount, unassignedCount))
            .font(.caption)
            .foregroundStyle(unassignedStackCount > Self.unassignedInboxMotifLimit ? Color.red.opacity(0.9) : Color.orange.opacity(0.9))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
        }
        if metadataPendingCount > 0 {
          Text(l10nFormat("upload.metadataPending.format", metadataPendingCount))
            .font(.caption)
            .foregroundStyle(Color.orange.opacity(0.9))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
        }
        if shouldShowUploadStatusCard {
          uploadStatusCard
            .padding(.horizontal, 16)
        }
        if hasReadyCablePackage {
          cablePackageReadyCard
            .padding(.horizontal, 16)
        } else {
          localSafetyCard
            .padding(.horizontal, 16)
          localPackageInventoryCard
            .padding(.horizontal, 16)
          uploadStartButton
            .padding(.horizontal, 16)
        }
        List {
          if !uploadFileErrors.isEmpty {
            Section(l10n("upload.section.fileErrors")) {
              ForEach(uploadFileErrors) { entry in
                VStack(alignment: .leading, spacing: 4) {
                  Text(entry.relativePath)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                  Text(entry.message)
                    .font(.caption)
                    .foregroundStyle(Color.red.opacity(0.9))
                }
                .padding(.vertical, 2)
              }
              Button(l10n("upload.clearFileErrors"), role: .destructive) {
                clearTransientUploadFeedback()
              }
              .font(.caption)
            }
          }

          if !uploadQueue.protocolLogs.isEmpty {
            Section(l10n("upload.section.protocols")) {
              ForEach(uploadQueue.protocolLogs) { log in
                DisclosureGroup(
                  isExpanded: bindingForProtocolExpansion(of: log.id),
                  content: {
                    VStack(alignment: .leading, spacing: 10) {
                      payloadStatusCard(
                        title: protocolReceiptTitle(for: log),
                        subtitle: protocolReceiptSubtitle(for: log),
                        lines: protocolReceiptLines(for: log),
                        tint: protocolReceiptTint(for: log)
                      )

                      if let files = log.filesDetailed, !files.isEmpty {
                        ForEach(files) { file in
                          protocolReceiptFileRow(file)
                        }
                      } else {
                        Text(l10n("upload.protocol.noReceipt"))
                          .font(.caption)
                          .foregroundStyle(.secondary)
                      }

                      if showsProtocolExportTools {
                        Button(l10n("upload.protocol.shareJSON")) {
                          protocolShareURL = makeProtocolExportURL(log)
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                      }
                    }
                    .padding(.vertical, 4)
                  },
                  label: {
                    protocolLogRow(log)
                  }
                )
                .padding(.vertical, 2)
              }

              Button(l10n("upload.protocol.clear"), role: .destructive) {
                uploadQueue.clearProtocolLogs()
                expandedProtocolLogIds.removeAll()
              }
              .font(.caption)
            }
          }

          Section(uploadScopeSeriesIds == nil ? l10n("upload.section.stacks") : l10n("upload.section.selectedStacks")) {
            if queueSeries.isEmpty {
              Text(l10n("upload.emptyStacks"))
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
              ForEach(queueSeries) { series in
                DisclosureGroup(
                  isExpanded: bindingForExpansion(of: series.id),
                  content: {
                    ForEach(series.records.sorted(by: uploadRecordSort)) { record in
                      HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(record.fileURL.lastPathComponent)
                          .font(.caption2.monospaced())
                          .lineLimit(1)
                          .truncationMode(.middle)
                        Spacer()
                        Text(String(format: "EV %.1f", record.exposureEV))
                          .font(.caption2)
                          .foregroundStyle(.secondary)
                        statusBadge(for: record.status)
                      }
                      .padding(.vertical, 2)
                    }
                  },
                  label: {
                    stackRow(for: series)
                  }
                )
                .swipeActions(edge: .trailing) {
                  Button(role: .destructive) {
                    deleteSeries(series.id)
                  } label: {
                    Label("Stack löschen", systemImage: "trash")
                  }
                }
              }
            }
          }
        }
      }
      .navigationTitle(Text("upload.title"))
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            if uploadProgress != nil || uploadMessage != nil || !uploadFileErrors.isEmpty {
              Button(l10n("upload.clearStatus"), role: .destructive) {
                clearTransientUploadFeedback()
              }
            }

            if !uploadQueue.protocolLogs.isEmpty {
              Button(l10n("upload.protocol.clear"), role: .destructive) {
                uploadQueue.clearProtocolLogs()
                expandedProtocolLogIds.removeAll()
              }
            }

            Button {
              copySupportDiagnostics()
            } label: {
              Label("Support-Diagnose kopieren", systemImage: "doc.on.doc")
            }

            if uploadQueue.records.contains(where: { $0.status == .failed }) {
              Button(l10n("upload.retryFailed")) {
                uploadQueue.resetFailed()
                trimExpandedSeriesState()
              }
            }

            if !uploadedCleanupRecords.isEmpty {
              Button(l10n("upload.cleanupUploaded"), role: .destructive) {
                uploadedCleanupPromptRecordIds = uploadedCleanupRecords.map(\.id)
                showUploadedCleanupPrompt = true
              }
            }
          } label: {
            Label(l10n("upload.cleanup"), systemImage: "trash")
          }
          .disabled(
            isUploading
              || (uploadQueue.records.isEmpty
              && uploadQueue.protocolLogs.isEmpty
              && uploadFileErrors.isEmpty
              && uploadProgress == nil
              && uploadMessage == nil)
          )
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(l10n("common.done")) { dismiss() }
        }
      }
      .sheet(
        isPresented: Binding(
          get: { protocolShareURL != nil },
          set: { isPresented in
            if !isPresented {
              protocolShareURL = nil
            }
          }
        )
      ) {
        if let shareURL = protocolShareURL {
          ShareSheet(
            activityItems: [shareURL],
            onComplete: { _ in
              protocolShareURL = nil
            }
          )
        }
      }
      .sheet(
        isPresented: Binding(
          get: { packageExportURL != nil },
          set: { isPresented in
            if !isPresented {
              packageExportURL = nil
            }
          }
        )
      ) {
        if let exportURL = packageExportURL {
          DocumentExportSheet(
            exportURLs: [exportURL],
            onComplete: { _ in
              packageExportURL = nil
            }
          )
        }
      }
      .onAppear {
        uploadQueue.refreshLocalPackageInventory()
      }
      .alert(l10n("upload.retention.title"), isPresented: $showRetentionPrompt) {
        Button(l10n("upload.retention.keep"), role: .cancel) {
          retentionPromptRecordIds = []
        }
        Button(l10n("common.delete"), role: .destructive) {
          uploadQueue.deleteRecords(retentionPromptRecordIds, deleteFile: true)
          retentionPromptRecordIds = []
        }
      } message: {
        Text(l10nFormat("upload.retention.message.format", retentionPromptRecordIds.count, UploadQueue.uploadedRetentionDays))
      }
      .alert(l10n("upload.cleanupUploaded.title"), isPresented: $showUploadedCleanupPrompt) {
        Button(l10n("common.cancel"), role: .cancel) {
          uploadedCleanupPromptRecordIds = []
        }
        Button(l10n("common.delete"), role: .destructive) {
          uploadQueue.deleteRecords(uploadedCleanupPromptRecordIds, deleteFile: true)
          uploadedCleanupPromptRecordIds = []
        }
      } message: {
        Text(l10nFormat("upload.cleanupUploaded.message.format", uploadedCleanupPromptRecordIds.count))
      }
      .alert("Temporäre lokale Eingangsdaten aufräumen?", isPresented: $showPackageDeletePrompt) {
        Button(l10n("common.cancel"), role: .cancel) {}
        Button(l10n("common.delete"), role: .destructive) {
          uploadQueue.deleteLocalPackageExports()
        }
      } message: {
        Text("Temporäre lokale Eingangsdaten werden vom iPhone entfernt. Bereits in der Cloud vorhandene Aufnahmen bleiben im PixCapture-Speicher.")
      }
      .alert(
        "Support-Diagnose kopiert",
        isPresented: Binding(
          get: { supportCopyMessage != nil },
          set: { isPresented in
            if !isPresented {
              supportCopyMessage = nil
            }
          }
        )
      ) {
        Button("OK", role: .cancel) {
          supportCopyMessage = nil
        }
      } message: {
        Text(supportCopyMessage ?? "")
      }
      .sheet(isPresented: $showWebConnectSheet) {
        NavigationStack {
          ScrollView {
            VStack(alignment: .leading, spacing: 12) {
              uploadMethodSelector

              if uploadModeSelection == .companionWifi {
                Button {
                  webConnectError = nil
                  showQRScanner = true
                } label: {
                  Label("Upload-QR auf der Webseite scannen", systemImage: "qrcode.viewfinder")
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("upload.connect.scanQR.companion")

                Text("Auf der PixCapture-Webseite „Über Rechner“ wählen und den dort angezeigten Upload-QR scannen.")
                  .font(.caption)
                  .foregroundStyle(.secondary)

                if let payload = parsedWebConnectPayload {
                  payloadStatusCard(
                    title: payload.companionTransport == "browser_webrtc" ? "Mit dem Rechner verbunden" : "Falscher QR-Code",
                    subtitle: payload.companionTransport == "browser_webrtc"
                      ? "Die Übertragung ist bereit. Tippe unten auf „An Rechner übertragen“."
                      : "Bitte am Rechner die WLAN-Übertragung öffnen und den dort angezeigten QR-Code scannen.",
                    lines: [
                      "Session: \(payload.webSessionId)",
                      "Transport: \(payload.companionTransport ?? "-")"
                    ],
                    tint: payload.companionTransport == "browser_webrtc" ? Color.green : Color.orange
                  )
                }
              }

              if uploadModeSelection == .localWifi {
                Button {
                  webConnectError = nil
                  showQRScanner = true
                } label: {
                  Label("Upload-QR auf der Webseite scannen", systemImage: "qrcode.viewfinder")
                }
                .buttonStyle(.borderedProminent)

                TextField(l10n("upload.connect.qrPlaceholder"), text: $webConnectInput)
                  .textInputAutocapitalization(.never)
                  .autocorrectionDisabled()
                  .submitLabel(.done)
                  .onSubmit {
                    hideSystemKeyboard()
                  }
                  .font(.callout.monospaced())
                  .textFieldStyle(.roundedBorder)
                  .accessibilityIdentifier("upload.connect.localWifi.input")

                Text("Auf der PixCapture-Webseite „Direkt in Cloud“ wählen und den dort angezeigten Upload-QR scannen.")
                  .font(.caption)
                  .foregroundStyle(.secondary)

                if let payload = parsedWebConnectPayload {
                  let authReady = authService.effectiveAccessToken != nil
                  payloadStatusCard(
                    title: "Web-Connect erkannt",
                    subtitle: authReady
                      ? (payload.requiresViewId == true
                          ? "CONNECT-QR erkannt, aber diese Session verlangt view_id. Bitte erst die App aktualisieren."
                          : "Session verbunden. Der Button unten startet den Upload und wartet danach auf die Serverbestätigung.")
                      : "CONNECT-QR erkannt. Fuer Web-Connect bitte zusaetzlich anmelden oder einen Pairing-Token setzen.",
                    lines: [
                      "Session: \(payload.webSessionId)",
                      "Endpoint: \(payload.endpoint.absoluteString)",
                      "QR-Hinweis Job: \(payload.jobId.flatMap { $0.isEmpty ? nil : $0 } ?? "-")",
                      "QR-Hinweis cust3/job5: \(payload.customerCode.isEmpty ? "-" : payload.customerCode)/\(payload.jobCode.isEmpty ? "-" : payload.jobCode)",
                      "Naming: \(payload.namingVersion.flatMap { $0.isEmpty ? nil : $0 } ?? "-")",
                      "view_id erforderlich: \(payload.requiresViewId == true ? "ja" : "nein")",
                      "Ablauf: \(payload.expiresAt.flatMap { $0.isEmpty ? nil : $0 } ?? "-")"
                    ],
                    tint: (authReady && payload.requiresViewId != true) ? Color.green : Color.orange
                  )
                } else if let payload = parsedLocalWiFiPayload {
                  payloadStatusCard(
                    title: "LOCAL_WIFI erkannt",
                    subtitle: "Die lokale Transfer-Session ist bereit. Kein Login oder Pairing-Token noetig.",
                    lines: [
                      "Session: \(payload.sessionId)",
                      "Ablauf: \(payload.expiresAt)",
                      "Ziel: \(localWiFiDestinationDescription(for: payload))"
                    ],
                    tint: Color.green
                  )
                } else if !webConnectInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                  payloadStatusCard(
                    title: l10n("upload.connect.invalidQR.title"),
                    subtitle: l10n("upload.connect.invalidQR.subtitle"),
                    lines: [],
                    tint: Color.orange
                  )
                }
              } else if uploadModeSelection == .directR2 {
                Button {
                  webConnectError = nil
                  showQRScanner = true
                } label: {
                  Label(l10n("upload.connect.scanQR"), systemImage: "qrcode.viewfinder")
                }
                .buttonStyle(.bordered)

                  Text("Direkt ohne Portal-QR nutzt deine Anmeldung. Ein Pairing-Link ist nur noetig, wenn du nicht eingeloggt bist.")
                  .font(.caption)
                  .foregroundStyle(.secondary)
                TextField("Pairing-Link oder Token", text: $webConnectInput)
                  .textInputAutocapitalization(.never)
                  .autocorrectionDisabled()
                  .submitLabel(.done)
                  .onSubmit {
                    hideSystemKeyboard()
                  }
                  .font(.callout.monospaced())
                  .textFieldStyle(.roundedBorder)
                if authService.mobileConnectToken != nil {
                  payloadStatusCard(
                    title: "Pairing aktiv",
                    subtitle: "Der Mobile-Direct-Token ist gespeichert und kann sofort verwendet werden.",
                    lines: [],
                    tint: Color.green
                  )
                } else if parsedMobileConnectToken != nil {
                  payloadStatusCard(
                    title: "Pairing-Token erkannt",
                    subtitle: "Der Token wird beim Start des direkten Uploads gespeichert.",
                    lines: [],
                    tint: Color.green
                  )
                } else {
                  payloadStatusCard(
                    title: "Noch kein Pairing erkannt",
                    subtitle: "Wenn du eingeloggt bist, kannst du direkt starten. Sonst Token oder Pairing-Link einfuegen.",
                    lines: [],
                    tint: authService.effectiveAccessToken != nil ? Color.green : Color.orange
                  )
                }
              } else if uploadModeSelection == .cablePackage {
                payloadStatusCard(
                  title: "Kabel-Option deaktiviert",
                  subtitle: Self.cablePackageDisabledMessage,
                  lines: parsedWebConnectPayload.map {
                    [
                      "Session: \($0.webSessionId)",
                      "Transport: \($0.companionTransport ?? "-")"
                    ]
                  } ?? [],
                  tint: Color.orange
                )
              } else {
                uploadMethodDetails
              }

              if let webConnectError {
                Text(webConnectError)
                  .font(.caption)
                  .foregroundStyle(Color.red)
              }
            }
            .padding(16)
          }
          .dismissKeyboardOnTap()
          .navigationTitle(l10n("upload.connect.navigationTitle"))
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button(l10n("common.cancel")) {
                showWebConnectSheet = false
              }
            }
          }
          .safeAreaInset(edge: .bottom) {
            uploadConnectStartButton
              .padding(.horizontal, 16)
              .padding(.top, 10)
              .padding(.bottom, 12)
              .background(.regularMaterial)
          }
          .sheet(isPresented: $showQRScanner) {
            NavigationStack {
              VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                  Text(l10n("upload.connect.scanQR"))
                    .font(.headline)
                  Text(l10n("upload.connect.scanQRHelp"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                ZStack {
                  RoundedRectangle(cornerRadius: 28)
                    .fill(Color.black)

                  WebConnectQRScannerView { rawCode in
                    let token = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let payload = UploadConnectionParser.extractWebConnectPayload(from: token) {
                      UploadDebugLog.write("[PIXUPLOAD] qrScan webConnect session=\(payload.webSessionId) transport=\(payload.companionTransport ?? "-")")
                      uploadModeSelection = modeForWebConnectPayload(payload)
                      webConnectInput = token
                      webConnectError = nil
                      showQRScanner = false
                    } else if UploadConnectionParser.extractLocalWiFiPayload(from: token) != nil {
                      UploadDebugLog.write("[PIXUPLOAD] qrScan localWiFi")
                      uploadModeSelection = .localWifi
                      webConnectInput = token
                      webConnectError = nil
                      showQRScanner = false
                    } else if let parsedToken = AuthService.parseMobileConnectToken(from: token) {
                      UploadDebugLog.write("[PIXUPLOAD] qrScan mobileConnectToken")
                      uploadModeSelection = .directR2
                      authService.setMobileConnectToken(parsedToken)
                      webConnectInput = token
                      webConnectError = nil
                      showQRScanner = false
                    } else {
                      UploadDebugLog.write("[PIXUPLOAD] qrScan invalid tokenPrefix=\(String(token.prefix(48)))")
                      webConnectError = AuthService.looksLikeWebConnectQR(token)
                        ? l10n("upload.connect.error.invalidConnectQR")
                        : l10n("upload.connect.error.invalidPairingQR")
                      showQRScanner = false
                    }
                  } onError: { message in
                    UploadDebugLog.write("[PIXUPLOAD] qrScan error=\(message)")
                    webConnectError = message
                    showQRScanner = false
                  }
                  .clipShape(RoundedRectangle(cornerRadius: 28))

                  RoundedRectangle(cornerRadius: 28)
                    .stroke(Color.white.opacity(0.9), lineWidth: 3)

                  RoundedRectangle(cornerRadius: 20)
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [8, 8]))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .padding(34)
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)

                payloadStatusCard(
                  title: "Was hier erkannt wird",
                  subtitle: "Upload-QR, lokaler Transfer-QR oder Session-Link. Nach dem Scan erscheint die Verbindungsbestaetigung direkt im vorherigen Fenster.",
                  lines: [],
                  tint: Color.blue
                )

                Spacer(minLength: 0)
              }
              .padding(20)
              .navigationTitle("QR-Scanner")
              .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                  Button(l10n("common.close")) {
                    showQRScanner = false
                  }
                }
              }
            }
          }
          .keyboardDoneToolbar()
        }
      }
      .onOpenURL { url in
        let rawURL = url.absoluteString
        webConnectInput = rawURL
        let isUploadQR = UploadConnectionParser.extractWebConnectPayload(from: rawURL) != nil
          || UploadConnectionParser.extractLocalWiFiPayload(from: rawURL) != nil
        if !isUploadQR,
           let token = AuthService.parseMobileConnectToken(from: rawURL) {
          authService.setMobileConnectToken(token)
        }
        webConnectError = nil
        if !isUploading {
          showWebConnectSheet = true
        }
      }
      .onAppear {
        maybeAutoPresentConnectSheet()
        maybePromptUploadedRetentionCleanup()
      }
    }
  }

  private var uploadStartButton: some View {
    Button {
      if isUploading {
        uploadQueue.cancelActiveUpload()
      } else {
        openUploadStart()
      }
    } label: {
      HStack(spacing: 10) {
        Image(systemName: isUploading ? "pause.fill" : "arrow.up.circle.fill")
          .font(.system(size: 17, weight: .semibold))
        Text(isUploading ? l10n("upload.pause") : l10n("upload.chooseMethod"))
          .font(.system(size: 15, weight: .semibold))
        Spacer(minLength: 0)
        if !isUploading {
          Text(l10nFormat("upload.readyMotifs.format", stackCount(for: uploadReadyCandidates)))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.78))
        }
      }
      .foregroundStyle(.white)
      .padding(.horizontal, 14)
      .padding(.vertical, 13)
      .frame(maxWidth: .infinity)
      .background(isUploading ? Color.orange : Color.blue)
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("upload.chooseMethod.main")
  }

  private var uploadMethodSelector: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Wie möchtest du übertragen?")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)

      HStack(spacing: 8) {
        ForEach(UploadStartMode.customerVisibleCases) { mode in
          uploadModeCard(mode)
        }
      }

      Text(selectedUploadModeExplanation)
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
  }

  private var selectedUploadModeExplanation: String {
    switch uploadModeSelection {
    case .companionWifi:
      return "iPhone → per WLAN zum Rechner → anschließend vom Rechner in die Cloud."
    case .localWifi:
      return settings.allowCellularUpload
        ? "iPhone → direkt in die Cloud. WLAN wird bevorzugt; ohne WLAN dürfen mobile Daten verwendet werden."
        : "iPhone → direkt in die Cloud. Nur über WLAN; mobile Daten sind ausgeschaltet."
    case .directR2:
      return "iPhone → direkt in die Cloud."
    case .cablePackage:
      return Self.cablePackageDisabledMessage
    }
  }

  private var uploadConnectStartButton: some View {
    Button {
      confirmUploadStartFromConnectSheet()
    } label: {
      HStack(spacing: 10) {
        Image(systemName: canConfirmUploadConnection ? "arrow.up.circle.fill" : "qrcode.viewfinder")
          .font(.system(size: 17, weight: .semibold))
        Text(uploadConnectPrimaryTitle)
          .font(.system(size: 15, weight: .semibold))
        Spacer(minLength: 0)
      }
      .foregroundStyle(.white)
      .padding(.horizontal, 14)
      .padding(.vertical, 13)
      .frame(maxWidth: .infinity)
      .background(canConfirmUploadConnection ? Color.blue : Color.gray)
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("upload.connect.start.primary")
    .disabled(isUploading || !canConfirmUploadConnection)
    .opacity(isUploading ? 0.6 : 1.0)
  }

  private var uploadConnectPrimaryTitle: String {
    switch uploadModeSelection {
    case .cablePackage:
      return "Kabel-Option deaktiviert"
    case .companionWifi:
      return canConfirmUploadConnection ? "An Rechner übertragen" : "Zuerst Upload-QR scannen"
    case .localWifi:
      return canConfirmUploadConnection ? "Direkt-Upload starten" : "Zuerst Upload-QR scannen"
    case .directR2:
      return l10n("upload.start")
    }
  }

  private var canConfirmUploadConnection: Bool {
    switch uploadModeSelection {
    case .companionWifi:
      return parsedWebConnectPayload?.companionTransport == "browser_webrtc"
    case .localWifi:
      return parsedWebConnectPayload != nil || parsedLocalWiFiPayload != nil
    case .directR2:
      return true
    case .cablePackage:
      return false
    }
  }

  private var uploadMethodDetails: some View {
    let preflight = companionPackagePreflight
    let title = "Übertragung über den Rechner"
    let subtitle = preflight.hasFiles
      ? "Das iPhone sendet die ausgewählten Motive an den lokalen Eingang dieses Rechners. Danach überträgt der Browser sie in den PixCapture-Speicher."
      : "Noch keine paketfähigen lokalen Dateien gefunden."
    let lines = companionPackageSummaryLines(preflight) + [
      "1. PixCapture am Rechner öffnen.",
      "2. „Über Rechner“ wählen und QR-Code anzeigen.",
      "3. QR-Code mit dem iPhone scannen.",
      "4. Auf „An Rechner übertragen“ tippen.",
      "5. Browser geöffnet lassen, bis der Upload abgeschlossen ist."
    ]

    return DisclosureGroup(isExpanded: $showUploadMethodDetails) {
      payloadStatusCard(
        title: title,
        subtitle: subtitle,
        lines: lines,
        tint: Color.orange
      )
      .padding(.top, 8)
    } label: {
      Label("So funktioniert die Übertragung", systemImage: "info.circle")
        .font(.caption.weight(.semibold))
    }
    .tint(Color.secondary)
  }

  private func uploadModeCard(_ mode: UploadStartMode) -> some View {
    let isSelected = uploadModeSelection == mode
    return Button {
      uploadModeSelection = mode
      webConnectError = nil
    } label: {
      VStack(spacing: 7) {
        Image(systemName: mode.systemImage)
          .font(.system(size: 18, weight: .semibold))
          .frame(height: 20)
          .foregroundStyle(isSelected ? Color.blue : Color.secondary)

        Text(mode.compactTitle)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Color.primary)
          .lineLimit(1)
          .minimumScaleFactor(0.78)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity)
      .frame(height: 64)
      .background(isSelected ? Color.blue.opacity(0.10) : Color(.secondarySystemBackground))
      .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(isSelected ? Color.blue.opacity(0.45) : Color.clear, lineWidth: 1)
      )
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(mode.accessibilityIdentifier)
    .accessibilityLabel(mode.title)
  }

  private var parsedLocalWiFiPayload: LocalWiFiUploadHandshake? {
    UploadConnectionParser.extractLocalWiFiPayload(from: webConnectInput)
  }

  private func uploadScopeNoticeText(count: Int) -> String {
    if count == 1 {
      return l10n("upload.scope.notice.one")
    }
    return l10nFormat("upload.scope.notice.format", count)
  }

  private var localSafetyCard: some View {
    let diagnostics = localDiagnostics
    let sizeText = ByteCountFormatter.string(fromByteCount: diagnostics.localBytes, countStyle: .file)
    let orphanSizeText = ByteCountFormatter.string(fromByteCount: diagnostics.orphanBytes, countStyle: .file)
    let hasIssue = diagnostics.failedRecords > 0 || diagnostics.orphanFiles > 0

    return VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Image(systemName: hasIssue ? "externaldrive.badge.exclamationmark" : "checkmark.shield.fill")
          .foregroundStyle(hasIssue ? Color.orange : Color.green)
        Text("Lokale Sicherung")
          .font(.system(size: 14, weight: .semibold))
        Spacer(minLength: 0)
        Text(sizeText)
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }

      Text(localSafetyMessage(for: diagnostics))
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          diagnosticPill("\(diagnostics.seriesCount) Motive")
          diagnosticPill("\(stackCount(for: uploadQueue.records.filter { $0.status == .pending })) Motive offen")
          diagnosticPill("\(stackCount(for: uploadQueue.records.filter { $0.status == .failed })) Motive fehlerhaft")
          if diagnostics.orphanFiles > 0 {
            diagnosticPill("\(diagnostics.orphanFiles) Altdateien / \(orphanSizeText)")
          }
        }
      }

      if diagnostics.localFileCount > 0 {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(localFileKindPills(for: diagnostics), id: \.self) { text in
              diagnosticPill(text)
            }
          }
        }
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(.secondarySystemBackground))
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  @ViewBuilder
  private var localPackageInventoryCard: some View {
    if uploadQueue.localPackageFileCount > 0 {
      let size = ByteCountFormatter.string(
        fromByteCount: Int64(uploadQueue.localPackageTotalBytes),
        countStyle: .file
      )

      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Image(systemName: "externaldrive.badge.exclamationmark")
            .foregroundStyle(Color.orange)
          Text("Lokaler Eingang wartet")
            .font(.system(size: 14, weight: .semibold))
          Spacer(minLength: 0)
          Text(size)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }

        Text("Auf diesem iPhone liegen noch temporäre lokale Eingangsdaten. Nach lokalem Empfang überträgt der Rechner die auf dem Telefon ausgewählten Motive in den PixCapture-Speicher.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        HStack(spacing: 8) {
          Button {
            uploadQueue.refreshLocalPackageInventory()
          } label: {
            Label("Status prüfen", systemImage: "arrow.clockwise")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)

          Button(role: .destructive) {
            showPackageDeletePrompt = true
          } label: {
            Label("Aufräumen", systemImage: "trash")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
          .disabled(isUploading)
        }
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.orange.opacity(0.10))
      .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(Color.orange.opacity(0.28), lineWidth: 1)
      )
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
  }

  @ViewBuilder
  private var cablePackageReadyCard: some View {
    if let packageURL = uploadQueue.latestPackageExportURL {
      let size = (try? packageURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map {
        ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)
      } ?? "Groesse unbekannt"

      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Image(systemName: "arrow.up.doc.fill")
            .foregroundStyle(Color.blue)
          Text("Lokaler Eingang bereit")
            .font(.system(size: 14, weight: .semibold))
          Spacer(minLength: 0)
          Text(size)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }

        Text("Die ausgewählten Motive sind für den lokalen Eingang dieses Rechners vorbereitet. Sobald der Empfänger sie lokal gespeichert hat, überträgt der Rechner diese Daten in den PixCapture-Speicher.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        Label("Status: lokaler Eingang / Speicherupload", systemImage: "display")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(Color.blue)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.blue.opacity(0.10))
      .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(Color.blue.opacity(0.28), lineWidth: 1)
      )
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
  }

  private func diagnosticPill(_ text: String) -> some View {
    Text(text)
      .font(.caption2.monospacedDigit())
      .foregroundStyle(.secondary)
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .background(Color(.tertiarySystemBackground))
      .clipShape(Capsule())
  }

  private func localSafetyMessage(for diagnostics: LocalCaptureStorageDiagnostics) -> String {
    if diagnostics.queueRecordCount == 0 && diagnostics.localFileCount == 0 {
      return "Keine lokalen Aufnahmen in der App."
    }
    if diagnostics.queueRecordCount == 0 && diagnostics.localFileCount > 0 {
      return "Die Upload-Liste ist leer, aber im lokalen Capture-Speicher liegen noch technische Dateien. Die Dateitypen unten zeigen, ob es Originale, Previews, XMP- oder JSON-Dateien sind. Die Support-Dateiliste benennt jede Datei einzeln."
    }
    if diagnostics.orphanFiles > 0 {
      return "Aufnahmen bleiben lokal gesichert. Einige Altdateien sind keiner Galerie-Liste zugeordnet und koennen bei Bedarf als Support-Dateiliste gesichert werden."
    }
    if diagnostics.failedRecords > 0 {
      return "Aufnahmen bleiben lokal gesichert. Fehlgeschlagene Uploads koennen erneut gestartet werden."
    }
    if diagnostics.pendingRecords > 0 {
      return "Aufnahmen sind lokal gesichert und warten auf den Upload."
    }
    return "Alle bekannten Aufnahmen sind serverseitig bestaetigt. Lokale Kopien bleiben erhalten, bis sie bewusst geloescht werden."
  }

  private func localFileKindPills(for diagnostics: LocalCaptureStorageDiagnostics) -> [String] {
    let counts = diagnostics.orphanFiles > 0 ? diagnostics.orphanKindCounts : diagnostics.kindCounts
    let labels: [(String, String)] = [
      ("original", "Originale"),
      ("preview", "Previews"),
      ("xmp", "XMP"),
      ("json", "JSON"),
      ("depth", "Depth"),
      ("diagnostic", "Diagnose"),
      ("file", "Dateien")
    ]

    return labels.compactMap { key, label in
      guard let count = counts[key], count > 0 else { return nil }
      return "\(label) \(count)"
    }
  }

  private var parsedWebConnectPayload: WebConnectUploadHandshake? {
    UploadConnectionParser.extractWebConnectPayload(from: webConnectInput)
  }

  private var parsedMobileConnectToken: String? {
    AuthService.parseMobileConnectToken(from: webConnectInput)
  }

  private var uploadCandidates: [UploadRecord] {
    uploadQueue.records.filter { record in
      (record.status == .pending || record.status == .failed) && isInUploadScope(record)
    }
  }

  private var uploadReadyCandidates: [UploadRecord] {
    uploadCandidates.filter(\.metadataReady)
  }

  private var localDiagnostics: LocalCaptureStorageDiagnostics {
    uploadQueue.localStorageDiagnostics()
  }

  private var companionPackagePreflight: CompanionPackagePreflight {
    companionTransfer.packagePreflight(records: uploadCandidates)
  }

  private func companionPackageSummaryLines(_ preflight: CompanionPackagePreflight) -> [String] {
    var lines = [
      "Motive: \(preflight.motifCount)",
      "Technische Dateien: \(preflight.technicalFileCount)",
      "Groesse: \(ByteCountFormatter.string(fromByteCount: preflight.totalBytes, countStyle: .file))"
    ]
    if preflight.missingFileCount > 0 {
      lines.append("Fehlende lokale Dateien: \(preflight.missingFileCount)")
    }
    lines.append("Paket: verschluesselt (.pixcapturepkg)")
    return lines
  }

  private var companionConnectionFields: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Companion-Ziel")
        .font(.subheadline.weight(.semibold))

      TextField("Host oder IP, z. B. 192.168.178.25", text: $settings.companionHost)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .font(.callout.monospaced())
        .textFieldStyle(.roundedBorder)

      HStack(spacing: 10) {
        TextField("Port", text: companionPortBinding)
          .keyboardType(.numberPad)
          .font(.callout.monospaced())
          .textFieldStyle(.roundedBorder)
          .frame(maxWidth: 110)

        Toggle("HTTPS", isOn: $settings.companionUseHTTPS)
          .font(.caption)
      }

      SecureField("Pairing-Code (optional)", text: $settings.companionPairingCode)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .font(.callout.monospaced())
        .textFieldStyle(.roundedBorder)

      HStack(spacing: 10) {
        Button {
          Task {
            await companionTransfer.testConnection(using: settings)
          }
        } label: {
          Label("Verbindung testen", systemImage: "network")
        }
        .buttonStyle(.bordered)

        if companionTransfer.isConnected {
          Label("bereit", systemImage: "checkmark.circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.green)
        }
      }

      if let message = companionTransfer.statusMessage,
         !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Text(message)
          .font(.caption)
          .foregroundStyle(companionTransfer.isConnected ? Color.green : Color.orange)
      }
    }
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(Color.black.opacity(0.04))
    )
  }

  private var companionPortBinding: Binding<String> {
    Binding(
      get: { String(settings.companionPort) },
      set: { value in
        let digits = value.filter(\.isNumber)
        if let port = Int(digits), (1...65535).contains(port) {
          settings.companionPort = port
        }
      }
    )
  }

  private func companionWiFiHandshakeFromSettings() -> CompanionWiFiUploadHandshake? {
    let host = settings.companionHost.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !host.isEmpty else { return nil }
    return CompanionWiFiUploadHandshake(
      host: host,
      port: settings.companionPort,
      useHTTPS: settings.companionUseHTTPS,
      pairingCode: settings.companionPairingCode
    )
  }

  private var queueSeries: [UploadSeries] {
    let grouped = Dictionary(grouping: uploadQueue.records.filter(isInUploadScope)) { $0.seriesId }
    return grouped
      .map { key, records in
        UploadSeries(id: key, records: records)
      }
      .sorted(by: { $0.latestDate > $1.latestDate })
  }

  private func isInUploadScope(_ record: UploadRecord) -> Bool {
    guard let uploadScopeSeriesIds, !uploadScopeSeriesIds.isEmpty else {
      return true
    }
    return uploadScopeSeriesIds.contains(record.seriesId)
  }

  private func hasAssignedJob(_ record: UploadRecord) -> Bool {
    CaptureJobPolicy.hasExplicitAssignment(jobId: record.jobId, jobLabel: record.jobLabel)
  }

  private func allowsUnassignedUpload(connection: PixcaptureUploadConnection) -> Bool {
    switch connection {
    case .companionWiFi, .browserCompanion, .webConnect:
      return true
    case .cablePackage, .directR2, .localWiFi:
      return false
    }
  }

  private func modeForWebConnectPayload(_ payload: WebConnectUploadHandshake) -> UploadStartMode {
    switch payload.companionTransport {
    case "browser_webrtc":
      return .companionWifi
    case "cable_package":
      return .cablePackage
    default:
      return .localWifi
    }
  }

  private func openUploadStart() {
    guard !isUploading else { return }
    UploadDebugLog.reset()
    guard !uploadCandidates.isEmpty else {
      if uploadQueue.localRecoveryFileCount > 0 {
        uploadQueue.setUploadMessage("\(uploadQueue.localRecoveryFileCount) lokale Altdateien gefunden, aber keine Upload-Liste geladen. Bitte in der Galerie die Dateiliste sichern oder Altdateien löschen.")
      } else {
        uploadQueue.setUploadMessage("Keine ausstehenden Uploads.")
      }
      return
    }
    guard !uploadReadyCandidates.isEmpty else {
      uploadQueue.setUploadMessage("Aufnahmen sind schon in der Galerie, aber noch nicht uploadbereit. Pflicht-Metadaten werden noch erstellt.")
      return
    }

    var didResolveConnectPayload = false
    let explicitConnectURL = initialConnectURL?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let explicitConnectURL, !explicitConnectURL.isEmpty,
      let payload = UploadConnectionParser.extractWebConnectPayload(from: explicitConnectURL) {
      uploadModeSelection = modeForWebConnectPayload(payload)
      webConnectInput = explicitConnectURL
      didResolveConnectPayload = true
    } else if let explicitConnectURL, !explicitConnectURL.isEmpty,
              UploadConnectionParser.extractLocalWiFiPayload(from: explicitConnectURL) != nil {
      uploadModeSelection = .localWifi
      webConnectInput = explicitConnectURL
      didResolveConnectPayload = true
    } else if let clipboard = UIPasteboard.general.string {
      if let payload = UploadConnectionParser.extractWebConnectPayload(from: clipboard) {
        uploadModeSelection = modeForWebConnectPayload(payload)
        webConnectInput = clipboard
        didResolveConnectPayload = true
      } else if UploadConnectionParser.extractLocalWiFiPayload(from: clipboard) != nil {
        uploadModeSelection = .localWifi
        webConnectInput = clipboard
        didResolveConnectPayload = true
      } else if AuthService.parseMobileConnectToken(from: clipboard) != nil {
        uploadModeSelection = .directR2
        webConnectInput = clipboard
        didResolveConnectPayload = true
      }
    }
    if !didResolveConnectPayload,
       authService.validEffectiveAccessToken() != nil,
       uploadModeSelection == .directR2 {
      uploadModeSelection = .localWifi
      webConnectInput = ""
    }
    UploadDebugLog.write("[PIXUPLOAD] openUploadStart mode=\(uploadModeSelection.rawValue) candidates=\(uploadCandidates.count) ready=\(uploadReadyCandidates.count) connectPayloadResolved=\(didResolveConnectPayload)")
    webConnectError = nil
    showWebConnectSheet = true
  }

  private func startUpload(connection: PixcaptureUploadConnection) {
    UploadDebugLog.write("[PIXUPLOAD] startUpload connection=\(connection.mode.rawValue)")
    Task {
      await startUploadAsync(connection: connection)
    }
  }

  private func confirmUploadStartFromConnectSheet() {
    UploadDebugLog.write("[PIXUPLOAD] confirmUploadStart selected=\(uploadModeSelection.rawValue) hasWebPayload=\(parsedWebConnectPayload != nil) hasLocalPayload=\(parsedLocalWiFiPayload != nil)")

    switch uploadModeSelection {
    case .localWifi:
      if let payload = parsedWebConnectPayload {
        UploadDebugLog.write("[PIXUPLOAD] parsedWebConnect session=\(payload.webSessionId) transport=\(payload.companionTransport ?? "-") endpoint=\(payload.endpoint.absoluteString)")
        guard canStartUpload(connection: .webConnect(payload)) else {
          webConnectError = missingUploadAuthMessage(for: .webConnect(payload))
          return
        }
        showWebConnectSheet = false
        startUpload(connection: .webConnect(payload))
        return
      }
      if let payload = parsedLocalWiFiPayload {
        showWebConnectSheet = false
        startUpload(connection: .localWiFi(payload))
        return
      }
      webConnectError = l10n("upload.connect.error.invalidConnectQR")
    case .directR2:
      guard canStartUpload(connection: .directR2) else {
        webConnectError = missingUploadAuthMessage(for: .directR2)
        return
      }
      showWebConnectSheet = false
      startUpload(connection: .directR2)
    case .cablePackage:
      UploadDebugLog.write("[PIXUPLOAD] reject cablePackage: customer mode disabled")
      webConnectError = Self.cablePackageDisabledMessage
      return
    case .companionWifi:
      guard let payload = parsedWebConnectPayload else {
        webConnectError = "Bitte die WLAN-Option auf der Webseite starten und den QR scannen."
        return
      }
      UploadDebugLog.write("[PIXUPLOAD] parsedWebConnect session=\(payload.webSessionId) transport=\(payload.companionTransport ?? "-") endpoint=\(payload.endpoint.absoluteString)")
      guard payload.companionTransport == "browser_webrtc" else {
        UploadDebugLog.write("[PIXUPLOAD] reject companion: wrong transport=\(payload.companionTransport ?? "-")")
        webConnectError = "Bitte auf der Webseite die WLAN-Option starten und diesen QR scannen."
        return
      }
      guard canStartUpload(connection: .browserCompanion(payload)) else {
        webConnectError = missingUploadAuthMessage(for: .browserCompanion(payload))
        return
      }
      showWebConnectSheet = false
      startUpload(connection: .browserCompanion(payload))
    }
  }

  private func startUploadAsync(connection: PixcaptureUploadConnection) async {
    guard !isUploading else {
      UploadDebugLog.write("[PIXUPLOAD] startUploadAsync rejected: already uploading")
      return
    }
    if case .directR2 = connection, let tokenFromInput = parsedMobileConnectToken {
      authService.setMobileConnectToken(tokenFromInput)
    }
    guard let authContext = uploadAuthContext(for: connection) else {
      UploadDebugLog.write("[PIXUPLOAD] startUploadAsync rejected: missing auth mode=\(connection.mode.rawValue)")
      uploadQueue.setUploadMessage(missingUploadAuthMessage(for: connection))
      return
    }
    let token = authContext.token
    let userId = authContext.userId
    var candidates = uploadCandidates
    guard !candidates.isEmpty else {
      UploadDebugLog.write("[PIXUPLOAD] startUploadAsync rejected: no candidates mode=\(connection.mode.rawValue) queue=\(uploadQueue.records.count)")
      uploadQueue.setUploadMessage(l10n("upload.noPending"))
      return
    }

    let allowsUnassigned = allowsUnassignedUpload(connection: connection)
    let unassignedCandidates = candidates.filter { !hasAssignedJob($0) }
    if !unassignedCandidates.isEmpty && !allowsUnassigned {
      let unassignedMotifCount = stackCount(for: unassignedCandidates)
      UploadDebugLog.write("[PIXUPLOAD] startUploadAsync unassigned candidates=\(unassignedCandidates.count) motifs=\(unassignedMotifCount)")
      guard unassignedMotifCount <= Self.unassignedInboxMotifLimit else {
        UploadDebugLog.write("[PIXUPLOAD] startUploadAsync rejected: inbox limit motifs=\(unassignedMotifCount)")
        uploadQueue.setUploadMessage(
          l10nFormat("upload.inbox.fullAction.format", unassignedMotifCount)
        )
        return
      }

      if let fallbackAssignment = currentUploadAssignment() {
        UploadDebugLog.write("[PIXUPLOAD] startUploadAsync assigning fallback jobId=\(fallbackAssignment.jobId ?? "-")")
        uploadQueue.assignJob(
          forSeriesIds: Set(unassignedCandidates.map(\.seriesId)),
          jobLabel: fallbackAssignment.jobLabel,
          jobId: fallbackAssignment.jobId
        )
        candidates = uploadCandidates
      } else {
        UploadDebugLog.write("[PIXUPLOAD] startUploadAsync preparing mobile inbox")
        guard let inboxJob = await authService.ensureMobileInboxJob(incomingMotifCount: unassignedMotifCount) else {
          UploadDebugLog.write("[PIXUPLOAD] startUploadAsync rejected: inbox unavailable message=\(authService.lastError ?? "-")")
          uploadQueue.setUploadMessage(
            authService.lastError
              ?? "Sammelcontainer konnte nicht vorbereitet werden. Bitte Jobs aufraeumen oder spaeter erneut versuchen."
          )
          return
        }
        UploadDebugLog.write("[PIXUPLOAD] startUploadAsync assigning inbox jobId=\(inboxJob.id)")
        uploadQueue.assignJob(
          forSeriesIds: Set(unassignedCandidates.map(\.seriesId)),
          jobLabel: inboxJob.name,
          jobId: inboxJob.id
        )
        candidates = uploadCandidates
      }
    } else if !unassignedCandidates.isEmpty {
      UploadDebugLog.write("[PIXUPLOAD] startUploadAsync preserving unassigned candidates=\(unassignedCandidates.count) mode=\(connection.mode.rawValue)")
    }

    let pending = candidates.filter { (hasAssignedJob($0) || allowsUnassigned) && $0.metadataReady }
    let skippedRecords = candidates.filter { !hasAssignedJob($0) && !allowsUnassigned }
    let skippedCount = skippedRecords.count
    let skippedStackCount = stackCount(for: skippedRecords)
    let metadataPendingRecords = candidates.filter { !$0.metadataReady }
    let metadataPendingCount = metadataPendingRecords.count
    let metadataPendingStackCount = stackCount(for: metadataPendingRecords)
    UploadDebugLog.write("[PIXUPLOAD] startUploadAsync pending=\(pending.count) skipped=\(skippedCount) metadataPending=\(metadataPendingCount) mode=\(connection.mode.rawValue)")
    guard !pending.isEmpty else {
      if metadataPendingCount > 0 {
        uploadQueue.setUploadMessage("Keine uploadfähigen Motive: Pflicht-Metadaten werden noch erstellt oder fehlen.")
      } else {
        uploadQueue.setUploadMessage(
          allowsUnassigned
            ? "Keine uploadfähigen Motive gefunden."
            : "Keine uploadfähigen Motive: Bitte zuerst in der Galerie einen Job zuweisen."
        )
      }
      return
    }

    uploadQueue.startManagedUpload(
      records: pending,
      token: token,
      userId: userId,
      connection: connection,
      identityHintsByJobId: uploadIdentityHintsByJobId(for: connection),
      allowsCellularAccess: allowsCellularAccess(for: connection),
      skipSummary: UploadRunSkipSummary(
        skippedCount: skippedCount,
        skippedStackCount: skippedStackCount,
        metadataPendingCount: metadataPendingCount,
        metadataPendingStackCount: metadataPendingStackCount
      ),
      initialDetail: initialProgressDetail(for: connection)
    )
  }

  private func allowsCellularAccess(for connection: PixcaptureUploadConnection) -> Bool {
    switch connection {
    case .cablePackage, .browserCompanion, .companionWiFi:
      return true
    case .directR2, .webConnect, .localWiFi:
      return settings.allowCellularUpload
    }
  }

  private func canStartUpload(connection: PixcaptureUploadConnection) -> Bool {
    if case .cablePackage = connection {
      return false
    }
    return uploadAuthContext(for: connection) != nil
  }

  private func uploadIdentityHintsByJobId(
    for connection: PixcaptureUploadConnection
  ) -> [String: PixcaptureUploadIdentityHint] {
    var hints: [String: PixcaptureUploadIdentityHint] = [:]

    for job in authService.availableJobs {
      let jobId = job.id.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !jobId.isEmpty else { continue }
      hints[jobId.lowercased()] = PixcaptureUploadIdentityHint(
        cust3: job.customerCode,
        job5: jobId
      )
    }

    let webHandshake: WebConnectUploadHandshake?
    switch connection {
    case .webConnect(let handshake), .browserCompanion(let handshake), .cablePackage(let handshake):
      webHandshake = handshake
    case .localWiFi, .directR2, .companionWiFi:
      webHandshake = nil
    }

    if let webHandshake {
      let jobIds = uploadCandidates.compactMap { record -> String? in
        let value = record.jobId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value.lowercased()
      }
      for jobId in jobIds {
        if hints[jobId] != nil {
          continue
        }
        hints[jobId] = PixcaptureUploadIdentityHint(
          cust3: webHandshake.customerCode,
          job5: webHandshake.jobCode
        )
      }
    }

    return hints
  }

  private func uploadAuthContext(for connection: PixcaptureUploadConnection) -> (token: String, userId: String)? {
    switch connection {
    case .localWiFi(let handshake):
      let sessionId = handshake.sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
      let transferToken = handshake.transferToken.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !sessionId.isEmpty, !transferToken.isEmpty else {
        return nil
      }
      let resolvedUserId = authService.effectiveUserId ?? "local-\(sessionId)"
      return (transferToken, resolvedUserId)
    case .cablePackage(let handshake):
      let sessionId = handshake.webSessionId.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !sessionId.isEmpty else {
        return nil
      }
      let resolvedUserId = authService.effectiveUserId ?? "cable-\(sessionId)"
      return ("cable-local-receipt", resolvedUserId)
    case .webConnect, .directR2, .companionWiFi, .browserCompanion:
      guard let token = authService.validEffectiveAccessToken() else {
        return nil
      }
      let userId = authService.effectiveUserId ?? "mobile"
      return (token, userId)
    }
  }

  private func missingUploadAuthMessage(for connection: PixcaptureUploadConnection) -> String {
    switch connection {
    case .webConnect:
      return "CONNECT-QR erkannt, aber Web-Connect braucht zusaetzlich Anmeldung oder einen Pairing-Token."
    case .directR2:
      return "Bitte zuerst mit E-Mail und Passwort oder mit einem Anmelde-QR anmelden."
    case .cablePackage:
      return Self.cablePackageDisabledMessage
    case .companionWiFi:
      return "Bitte zuerst anmelden. Die WLAN-Option braucht einen Paket-Schluessel vom Backend."
    case .browserCompanion:
      return "Bitte zuerst anmelden. Die WLAN-Option braucht einen Paket-Schluessel vom Backend."
    case .localWiFi:
      return "LOCAL_WIFI-QR ist unvollstaendig oder abgelaufen."
    }
  }

  private func currentUploadAssignment() -> (jobLabel: String, jobId: String?)? {
    let normalizedJobId = settings.selectedJobId?.trimmingCharacters(in: .whitespacesAndNewlines)
    var normalizedJobLabel = settings.jobLabel.trimmingCharacters(in: .whitespacesAndNewlines)

    if let normalizedJobId, !normalizedJobId.isEmpty {
      if normalizedJobLabel.isEmpty {
        normalizedJobLabel = authService.availableJobs
          .first(where: { $0.id == normalizedJobId })?
          .name
          .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      }
      return (normalizedJobLabel, normalizedJobId)
    }

    guard !normalizedJobLabel.isEmpty else {
      return nil
    }
    guard CaptureJobPolicy.hasExplicitAssignment(jobId: nil, jobLabel: normalizedJobLabel) else {
      return nil
    }
    return (normalizedJobLabel, nil)
  }

  private func maybeAutoPresentConnectSheet() {
    guard !didAutoPresentConnectSheet else { return }
    didAutoPresentConnectSheet = true
    guard !uploadCandidates.isEmpty else { return }
    guard !isUploading, !showWebConnectSheet else { return }
    openUploadStart()
  }

  private func maybePromptUploadedRetentionCleanup() {
    guard !isUploading else { return }
    guard uploadCandidates.isEmpty else { return }
    guard !showWebConnectSheet, !showQRScanner, protocolShareURL == nil else { return }
    guard retentionPromptRecordIds.isEmpty, !showRetentionPrompt else { return }
    let candidates = uploadQueue.uploadedRecordsEligibleForDeletion()
    guard !candidates.isEmpty else { return }
    retentionPromptRecordIds = candidates.map(\.id)
    showRetentionPrompt = true
  }

  private func stackCount(for records: [UploadRecord]) -> Int {
    Set(records.map(\.seriesId)).count
  }

  private func summarizeStackUpload(
    pendingRecords: [UploadRecord],
    uploadedRecordIds: [UUID],
    failedRecordIds: [UUID],
    pendingRecordIds: [UUID]
  ) -> StackUploadSummary {
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

    return StackUploadSummary(
      totalStacks: totalBySeries.count,
      completedStacks: completedStacks,
      failedStacks: failedStacks,
      pendingStacks: pendingStacks
    )
  }

  private func bindingForExpansion(of seriesId: UUID) -> Binding<Bool> {
    Binding(
      get: { expandedSeriesIds.contains(seriesId) },
      set: { expanded in
        if expanded {
          expandedSeriesIds.insert(seriesId)
        } else {
          expandedSeriesIds.remove(seriesId)
        }
      }
    )
  }

  private func bindingForProtocolExpansion(of logId: UUID) -> Binding<Bool> {
    Binding(
      get: { expandedProtocolLogIds.contains(logId) },
      set: { expanded in
        if expanded {
          expandedProtocolLogIds.insert(logId)
        } else {
          expandedProtocolLogIds.remove(logId)
        }
      }
    )
  }

  private func stackRow(for series: UploadSeries) -> some View {
    let summary = series.summaryRecord
    return HStack(alignment: .center, spacing: 10) {
      VStack(alignment: .leading, spacing: 4) {
        if let summary {
          let jobTitle = summary.jobLabel.trimmingCharacters(in: .whitespacesAndNewlines)
          let motif = String(
            format: NSLocalizedString("motif.format", comment: "Motif label"),
            summary.seriesIndex
          )
          Text(jobTitle.isEmpty ? "Ohne Job" : jobTitle)
            .font(.subheadline)
            .foregroundStyle(Color.black.opacity(0.75))
          Text("\(RoomTaxonomy.room(id: summary.roomId).displayName) · \(FloorTaxonomy.floor(id: summary.floorId).displayName) – \(motif)")
            .font(.headline)
          Text("\(series.records.count) technische Dateien")
            .font(.caption)
            .foregroundStyle(.secondary)
          if !series.metadataReady {
            Text("Pflicht-Metadaten werden noch erstellt")
              .font(.caption2)
              .foregroundStyle(Color.orange.opacity(0.85))
          }
        } else {
          Text("Stack")
            .font(.subheadline)
          Text("\(series.records.count) technische Dateien")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Spacer()
      statusBadge(for: series.aggregateStatus)
    }
    .padding(.vertical, 2)
  }

  private func statusBadge(for status: UploadRecord.Status) -> some View {
    Text(status.rawValue)
      .font(.caption)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(Color.black.opacity(0.1))
      .clipShape(Capsule())
  }

  private func uploadRecordSort(_ lhs: UploadRecord, _ rhs: UploadRecord) -> Bool {
    if lhs.exposureEV == rhs.exposureEV {
      return lhs.createdAt < rhs.createdAt
    }
    return lhs.exposureEV < rhs.exposureEV
  }

  private func deleteSeries(_ seriesId: UUID) {
    guard !isUploading else { return }
    let ids = uploadQueue.records
      .filter { $0.seriesId == seriesId }
      .map(\.id)
    for id in ids {
      uploadQueue.deleteRecord(id, deleteFile: true)
    }
    expandedSeriesIds.remove(seriesId)
  }

  private func clearTransientUploadFeedback() {
    uploadQueue.clearTransientUploadFeedback()
  }

  private func copySupportDiagnostics() {
    let accountLabel = authService.effectiveUserId ?? (authService.isAuthenticated ? "angemeldet" : "nicht angemeldet")
    let selectedJobLabel = settings.jobLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    let text = uploadQueue.supportDiagnosticsText(
      accountLabel: accountLabel,
      selectedJobLabel: selectedJobLabel,
      selectedJobId: settings.selectedJobId
    )
    UIPasteboard.general.string = text
    supportCopyMessage = "Die Diagnose wurde in die Zwischenablage kopiert. Du kannst sie direkt an den Support senden."
  }

  private func trimExpandedSeriesState() {
    let existingSeriesIds = Set(uploadQueue.records.map(\.seriesId))
    expandedSeriesIds = expandedSeriesIds.intersection(existingSeriesIds)
  }

  private func formatBytes(_ bytes: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
  }

  private func makeProtocolExportURL(_ log: UploadProtocolLog) -> URL? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(log) else { return nil }
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("upload-protocol-\(log.uploadId).json")
    do {
      try data.write(to: url, options: .atomic)
      return url
    } catch {
      return nil
    }
  }

  private func protocolLogRow(_ log: UploadProtocolLog) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(protocolStatusTitle(for: log))
          .font(.caption)
          .foregroundStyle(protocolStatusColor(for: log))
        Spacer()
        Text(log.createdAt.formatted(date: .abbreviated, time: .shortened))
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      Text("Upload-ID: \(log.uploadId)")
        .font(.caption2)
        .foregroundStyle(.secondary)
      Text("Job: \(log.jobId)")
        .font(.caption2)
        .foregroundStyle(.secondary)
      Text("Dateien \(log.receivedFileCount)/\(max(log.expectedFileCount, 1)) • \(formatBytes(log.receivedTotalBytes))/\(formatBytes(max(log.expectedTotalBytes, log.receivedTotalBytes)))")
        .font(.caption)

      let summary = protocolMetadataSummary(for: log)
      if summary.receiptFiles > 0 {
        Text("Receipt \(summary.receiptFiles) • Kamera \(summary.cameraMetadataFiles) • Sensor \(summary.sensorDataFiles) • EXIF-Logs \(summary.exifSidecarFiles) • XMP \(summary.xmpSidecarFiles)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      if !log.mismatches.isEmpty {
        Text("Hinweise: \(log.mismatches.count)")
          .font(.caption)
          .foregroundStyle(summary.criticalIssues > 0 ? Color.red.opacity(0.85) : Color.orange.opacity(0.85))
      }
    }
    .padding(.vertical, 4)
  }

  private func protocolReceiptTitle(for log: UploadProtocolLog) -> String {
    let summary = protocolMetadataSummary(for: log)
    if summary.criticalIssues > 0 {
      return "Server-Quittung unvollstaendig"
    }
    if !log.mismatches.isEmpty {
      return "Server-Quittung mit Hinweisen"
    }
    return "Server-Quittung"
  }

  private func protocolReceiptSubtitle(for log: UploadProtocolLog) -> String {
    let summary = protocolMetadataSummary(for: log)
    if summary.receiptFiles == 0 {
      return "Der Upload wurde protokolliert, aber es liegt noch keine detaillierte Receipt-Datei in der App vor."
    }
    if summary.criticalIssues > 0 {
      return "Die Receipt-Datei ist vorhanden, aber Pflicht-Metadaten fuer die Weiterverarbeitung fehlen oder konnten nicht verifiziert werden."
    }
    if !log.mismatches.isEmpty {
      return "Alle Bilddaten sind angekommen. Einige technische Zusatzdateien wurden nur ohne vollstaendige kanonische Benennung oder Zusatzklassifizierung gespeichert."
    }
    return "Die Receipt-Datei ist vorhanden und die wichtigsten Aufnahme-Metadaten wurden fuer die Weiterverarbeitung verifiziert."
  }

  private func protocolReceiptTint(for log: UploadProtocolLog) -> Color {
    let summary = protocolMetadataSummary(for: log)
    if summary.criticalIssues > 0 {
      return .orange
    }
    return summary.receiptFiles > 0 ? .green : .blue
  }

  private func protocolReceiptLines(for log: UploadProtocolLog) -> [String] {
    let summary = protocolMetadataSummary(for: log)
    var lines: [String] = []
    if let manifestPath = log.manifestPath {
      lines.append("Manifest: \(manifestPath)")
    }
    if let receiptPath = log.receiptPath {
      lines.append("Receipt: \(receiptPath)")
    }
    if summary.receiptFiles > 0 {
      lines.append("Receipt-Dateien: \(summary.receiptFiles)")
      lines.append("camera_metadata: \(summary.cameraMetadataFiles)")
      lines.append("sensor_data: \(summary.sensorDataFiles)")
      lines.append("exif_series_log: \(summary.exifSidecarFiles)")
      if summary.xmpSidecarFiles > 0 {
        lines.append("xmp_sidecar: \(summary.xmpSidecarFiles)")
      }
      if summary.videoMetadataFiles > 0 {
        lines.append("video_metadata: \(summary.videoMetadataFiles)")
      }
      if summary.motionMetadataFiles > 0 {
        lines.append("motion_metadata: \(summary.motionMetadataFiles)")
      }
      if summary.intrinsicsMetadataFiles > 0 {
        lines.append("intrinsics_metadata: \(summary.intrinsicsMetadataFiles)")
      }
      if summary.trackingMetadataFiles > 0 {
        lines.append("tracking_metadata: \(summary.trackingMetadataFiles)")
      }
      if summary.floorplanMetadataFiles > 0 {
        lines.append("floorplan_metadata: \(summary.floorplanMetadataFiles)")
      }
    }
    if summary.criticalIssues > 0 {
      lines.append("Pflichtdaten-Fehler: \(summary.criticalIssues)")
    } else if !log.mismatches.isEmpty {
      lines.append("Technische Hinweise: \(log.mismatches.count)")
    }
    return lines
  }

  private func protocolReceiptFileRow(_ file: UploadProtocolReceiptFile) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(file.canonicalFilename.isEmpty ? file.originalFilename : file.canonicalFilename)
        .font(.caption.monospaced())
        .lineLimit(1)
        .truncationMode(.middle)
      Text(protocolReceiptFileSubtitle(for: file))
        .font(.caption2)
        .foregroundStyle(.secondary)
      Text(file.canonicalObjectKey.isEmpty ? file.relativePath : file.canonicalObjectKey)
        .font(.caption2.monospaced())
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .truncationMode(.middle)
      let badges = protocolReceiptBadges(for: file)
      if !badges.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 6) {
            ForEach(badges, id: \.self) { badge in
              Text(badge)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.black.opacity(0.75))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.08))
                .clipShape(Capsule())
            }
          }
        }
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color.black.opacity(0.03))
    )
  }

  private var uploadStatusCard: some View {
    let progress = uploadProgress
    let title = progress.map(progressTitle(for:)) ?? "Upload-Status"
    let tint = progress.map(progressTint(for:)) ?? Color.blue

    return VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .center, spacing: 10) {
        Image(systemName: progress.map(progressIcon(for:)) ?? "info.circle.fill")
          .foregroundStyle(tint)
        Text(title)
          .font(.headline)
        Spacer()
        if let progress {
          Text(progress.mode.displayName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
        }
      }

      if let detail = uploadStatusDetail(for: progress) {
        Text(detail)
          .font(.subheadline)
          .foregroundStyle(Color.black.opacity(0.75))
      }

      if let progress, showsLiveActivity(for: progress) {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
          HStack(spacing: 8) {
            ProgressView()
              .controlSize(.small)
              .tint(tint)
            Text(liveActivityText(for: progress, at: timeline.date))
              .font(.caption.weight(.medium))
              .foregroundStyle(tint)
              .contentTransition(.numericText())
          }
          .accessibilityIdentifier("upload.progress.liveActivity")
        }
      }

      if let progress {
        if progress.phase == .waitingForApproval || shouldUseIndeterminateProgress(for: progress) {
          ProgressView()
            .tint(tint)
        } else {
          ProgressView(value: progress.fractionCompleted)
            .tint(tint)
        }

        HStack {
          Text(uploadMotifProgressText(for: progress))
          Spacer()
          Text("\(formatBytes(progress.bytesSent)) / \(formatBytes(max(progress.bytesTotal, progress.bytesSent)))")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      if progress?.phase == .completed, !uploadedCleanupRecords.isEmpty {
        Button(role: .destructive) {
          uploadedCleanupPromptRecordIds = uploadedCleanupRecords.map(\.id)
          showUploadedCleanupPrompt = true
        } label: {
          Label(l10n("upload.cleanupUploaded"), systemImage: "trash")
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(.bordered)
        .tint(.red)
      }
    }
    .padding(14)
    .background(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(Color.white)
        .shadow(color: Color.black.opacity(0.06), radius: 12, y: 4)
    )
  }

  private func payloadStatusCard(
    title: String,
    subtitle: String,
    lines: [String],
    tint: Color
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(tint)
      Text(subtitle)
        .font(.caption)
        .foregroundStyle(Color.black.opacity(0.7))
      ForEach(lines.filter { !$0.isEmpty }, id: \.self) { line in
        Text(line)
          .font(.caption2.monospaced())
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(tint.opacity(0.08))
    )
  }

  private func progressTitle(for progress: PixcaptureUploadProgress) -> String {
    switch progress.phase {
    case .preparing:
      return l10n("upload.progress.preparing")
    case .connecting:
      return l10n("upload.progress.connecting")
    case .waitingForApproval:
      return l10n("upload.progress.waitingForApproval")
    case .uploading:
      return l10n("upload.progress.uploading")
    case .finalizing:
      return l10n("upload.progress.finalizing")
    case .completed:
      return l10n("upload.progress.completed")
    case .failed:
      return l10n("upload.progress.failed")
    }
  }

  private func progressIcon(for progress: PixcaptureUploadProgress) -> String {
    switch progress.phase {
    case .preparing:
      return "gearshape.2.fill"
    case .connecting:
      return "link.circle.fill"
    case .waitingForApproval:
      return "hourglass.circle.fill"
    case .uploading:
      return "arrow.up.circle.fill"
    case .finalizing:
      return "checkmark.seal.fill"
    case .completed:
      return "checkmark.circle.fill"
    case .failed:
      return "exclamationmark.triangle.fill"
    }
  }

  private func progressTint(for progress: PixcaptureUploadProgress) -> Color {
    switch progress.phase {
    case .preparing, .connecting:
      return .blue
    case .waitingForApproval:
      return .orange
    case .uploading:
      return .indigo
    case .finalizing, .completed:
      return .green
    case .failed:
      return .red
    }
  }

  private func showsLiveActivity(for progress: PixcaptureUploadProgress) -> Bool {
    switch progress.phase {
    case .preparing, .connecting, .waitingForApproval, .uploading, .finalizing:
      return true
    case .completed, .failed:
      return false
    }
  }

  private func shouldUseIndeterminateProgress(for progress: PixcaptureUploadProgress) -> Bool {
    (progress.mode == .cablePackage || progress.mode == .companionWifi)
      && progress.phase != .completed
      && progress.phase != .failed
      && (progress.bytesSent == 0 || progress.phase == .finalizing)
  }

  private func liveActivityText(for progress: PixcaptureUploadProgress, at date: Date) -> String {
    let dots = String(repeating: ".", count: Int(date.timeIntervalSinceReferenceDate) % 4)
    switch progress.mode {
    case .cablePackage, .companionWifi:
      switch progress.phase {
      case .preparing:
        return progress.mode == .companionWifi
          ? "WLAN-Eingang wird lokal verschlüsselt\(dots)"
          : "Kabel-Eingang wird lokal verschlüsselt\(dots)"
      case .connecting:
        return "Backend wird kontaktiert\(dots)"
      case .uploading:
        return progress.mode == .companionWifi
          ? "WLAN-Transfer läuft weiter\(dots)"
          : "Kabeldaten werden für den lokalen Eingang vorbereitet\(dots)"
      case .finalizing:
        return progress.mode == .companionWifi
          ? "Lokaler Eingang bestätigt Empfang\(dots)"
          : "Warte auf lokalen Eingang\(dots)"
      case .waitingForApproval:
        return "Warte auf Speicherupload\(dots)"
      case .completed, .failed:
        return ""
      }
    default:
      switch progress.phase {
      case .preparing:
        return "Upload wird vorbereitet\(dots)"
      case .connecting:
        return "Verbindung wird aufgebaut\(dots)"
      case .waitingForApproval:
        return "Warte auf Serverbestätigung\(dots)"
      case .uploading:
        return "Upload läuft\(dots)"
      case .finalizing:
        return "Server finalisiert\(dots)"
      case .completed, .failed:
        return ""
      }
    }
  }

  private var uploadStatusMotifCount: Int {
    let readyCount = stackCount(for: uploadReadyCandidates)
    if readyCount > 0 {
      return readyCount
    }
    let activeRecords = uploadQueue.records.filter { record in
      isInUploadScope(record)
        && (record.status == .pending || record.status == .failed || record.status == .uploading)
    }
    return stackCount(for: activeRecords)
  }

  private func uploadMotifProgressText(for progress: PixcaptureUploadProgress) -> String {
    let motifCount = uploadStatusMotifCount
    let motifLabel = motifCount == 1 ? "Motiv" : "Motive"
    switch progress.phase {
    case .completed:
      return motifCount > 0 ? "\(motifCount) \(motifLabel) uebertragen" : "Upload abgeschlossen"
    case .failed:
      return motifCount > 0 ? "\(motifCount) \(motifLabel) betroffen" : "Upload pruefen"
    default:
      return motifCount > 0 ? "\(motifCount) \(motifLabel)" : "Motive werden uebertragen"
    }
  }

  private func uploadStatusDetail(for progress: PixcaptureUploadProgress?) -> String? {
    guard let progress else {
      return uploadMessage
    }
    switch progress.phase {
    case .preparing, .connecting, .waitingForApproval:
      return progress.detail ?? uploadMessage
    case .uploading:
      switch progress.mode {
      case .cablePackage, .companionWifi:
        return "Motive und technische Begleitdaten werden fuer den lokalen Eingang vorbereitet."
      default:
        return "Motive und technische Begleitdaten werden uebertragen."
      }
    case .finalizing:
      return "Der Server prueft den Upload und ordnet die Motive dem Auftrag zu."
    case .completed, .failed:
      return progress.detail ?? uploadMessage
    }
  }

  private func initialProgressDetail(for connection: PixcaptureUploadConnection) -> String {
    switch connection {
    case .webConnect:
      return "QR-Code erkannt. Verbinde App und Browser-Session."
    case .localWiFi:
      return "QR-Code erkannt. Pruefe lokale Transfer-Verbindung."
    case .directR2:
      return "Pairing erkannt. Bereite Direct-Upload vor."
    case .cablePackage:
      return "Bereite verschluesselte Daten fuer den lokalen Eingang vor."
    case .companionWiFi:
      return "Bereite verschluesselte Daten fuer den lokalen Eingang vor."
    case .browserCompanion:
      return "Bereite Verbindung zum lokalen Eingang dieses Rechners vor."
    }
  }

  private func localWiFiDestinationDescription(for payload: LocalWiFiUploadHandshake) -> String {
    if let baseURL = payload.baseURL,
       !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return baseURL
    }

    let host = payload.ip?.trimmingCharacters(in: .whitespacesAndNewlines)
    let port = payload.port.map(String.init)
    if let host, !host.isEmpty, let port, !port.isEmpty {
      return "\(host):\(port)"
    }
    if let host, !host.isEmpty {
      return host
    }
    return "nicht angegeben"
  }

  private func protocolStatusTitle(for log: UploadProtocolLog) -> String {
    let criticalIssues = log.mismatches.filter(isCriticalMetadataMismatch).count
    if criticalIssues > 0 {
      return "Server-Quittung unvollstaendig"
    }
    if log.receiptPath?.hasSuffix(".pixcapturepkg") == true {
      return "Paket lokal vorbereitet"
    }
    if !log.complete && !log.mismatches.isEmpty && log.receiptPath != nil && log.receivedFileCount >= log.expectedFileCount {
      return "Empfang bestaetigt, mit Hinweisen"
    }
    return log.complete ? "Empfang bestaetigt" : "Unvollstaendig"
  }

  private func protocolStatusColor(for log: UploadProtocolLog) -> Color {
    let criticalIssues = log.mismatches.filter(isCriticalMetadataMismatch).count
    if criticalIssues > 0 {
      return .red
    }
    return log.complete ? .green : .orange
  }

  private func isCriticalMetadataMismatch(_ mismatch: UploadProtocolMismatch) -> Bool {
    mismatch.isCriticalForUploadCompletion
  }

  private func protocolMetadataSummary(for log: UploadProtocolLog) -> ProtocolMetadataSummary {
    let files = log.filesDetailed ?? []
    return ProtocolMetadataSummary(
      receiptFiles: files.count,
      cameraMetadataFiles: files.filter { $0.cameraMetadata != nil }.count,
      sensorDataFiles: files.filter { $0.sensorData != nil }.count,
      exifSidecarFiles: files.filter { protocolMetadataRole(for: $0) == "exif_series_log" }.count,
      xmpSidecarFiles: files.filter { protocolMetadataRole(for: $0) == "xmp_sidecar" }.count,
      videoMetadataFiles: files.filter { $0.videoMetadata != nil }.count,
      motionMetadataFiles: files.filter { $0.motionMetadata != nil }.count,
      intrinsicsMetadataFiles: files.filter { $0.intrinsicsMetadata != nil }.count,
      trackingMetadataFiles: files.filter { $0.trackingMetadata != nil }.count,
      floorplanMetadataFiles: files.filter { $0.floorplanMetadata != nil }.count,
      criticalIssues: log.mismatches.filter(isCriticalMetadataMismatch).count
    )
  }

  private func protocolMetadataRole(for file: UploadProtocolReceiptFile) -> String? {
    file.fileMetadata?.objectValue?["metadata_role"]?.stringValue
  }

  private func protocolReceiptFileSubtitle(for file: UploadProtocolReceiptFile) -> String {
    var components: [String] = [file.captureType]
    if let roomLabel = protocolReceiptRoomLabel(for: file) {
      components.append(roomLabel)
    }
    if let mappingLabel = protocolReceiptMappingLabel(for: file) {
      components.append(mappingLabel)
    }
    if let captureSubtype = file.captureSubtype,
       !captureSubtype.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      components.append(captureSubtype)
    }
    if let mimeType = file.mimeType,
       !mimeType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      components.append(mimeType)
    }
    if let sizeBytes = file.sizeBytes, sizeBytes > 0 {
      components.append(formatBytes(sizeBytes))
    }
    return components.joined(separator: " • ")
  }

  private func protocolReceiptRoomLabel(for file: UploadProtocolReceiptFile) -> String? {
    let roomName = file.roomName?.trimmingCharacters(in: .whitespacesAndNewlines)
    let roomType = file.roomType?.trimmingCharacters(in: .whitespacesAndNewlines)
    let base = (roomName?.isEmpty == false ? roomName : roomType) ?? nil
    guard var label = base, !label.isEmpty else {
      return nil
    }
    if let roomVariant = file.roomVariant, roomVariant > 1 {
      label += " #\(roomVariant)"
    }
    return label
  }

  private func protocolReceiptMappingLabel(for file: UploadProtocolReceiptFile) -> String? {
    var parts: [String] = []
    if let motifIndex = file.motifIndex, motifIndex > 0 {
      parts.append(String(format: "m%02d", motifIndex))
    }
    if let exposureIndex = file.exposureIndex, exposureIndex > 0 {
      parts.append(String(format: "e%02d", exposureIndex))
    }
    guard !parts.isEmpty else {
      return nil
    }
    return parts.joined(separator: " ")
  }

  private func protocolReceiptBadges(for file: UploadProtocolReceiptFile) -> [String] {
    var badges: [String] = []
    if file.cameraMetadata != nil { badges.append("camera") }
    if file.sensorData != nil { badges.append("sensor") }
    if let metadataRole = protocolMetadataRole(for: file) {
      badges.append(metadataRole)
    } else if file.fileMetadata != nil {
      badges.append("file-meta")
    }
    if file.videoMetadata != nil { badges.append("video") }
    if file.motionMetadata != nil { badges.append("motion") }
    if file.intrinsicsMetadata != nil { badges.append("intrinsics") }
    if file.trackingMetadata != nil { badges.append("tracking") }
    if file.floorplanMetadata != nil { badges.append("floorplan") }
    return badges
  }

  private func l10n(_ key: String) -> String {
    settings.localized(key)
  }

  private func l10nFormat(_ key: String, _ arguments: CVarArg...) -> String {
    AppLocalizer.localizedFormat(key, language: settings.appLanguage, arguments: arguments)
  }
}

private struct UploadSeries: Identifiable {
  let id: UUID
  let records: [UploadRecord]

  var latestDate: Date {
    records.map(\.createdAt).max() ?? .distantPast
  }

  var summaryRecord: UploadRecord? {
    records.min {
      let left = abs($0.exposureEV)
      let right = abs($1.exposureEV)
      if left == right {
        return $0.createdAt > $1.createdAt
      }
      return left < right
    }
  }

  var aggregateStatus: UploadRecord.Status {
    if records.contains(where: { $0.status == .failed }) { return .failed }
    if records.contains(where: { $0.status == .uploading }) { return .uploading }
    if records.contains(where: { $0.status == .pending }) { return .pending }
    return .uploaded
  }

  var metadataReady: Bool {
    records.allSatisfy { $0.metadataReady }
  }
}

private struct StackUploadSummary {
  let totalStacks: Int
  let completedStacks: Int
  let failedStacks: Int
  let pendingStacks: Int
}

private struct ProtocolMetadataSummary {
  let receiptFiles: Int
  let cameraMetadataFiles: Int
  let sensorDataFiles: Int
  let exifSidecarFiles: Int
  let xmpSidecarFiles: Int
  let videoMetadataFiles: Int
  let motionMetadataFiles: Int
  let intrinsicsMetadataFiles: Int
  let trackingMetadataFiles: Int
  let floorplanMetadataFiles: Int
  let criticalIssues: Int
}

private enum UploadConnectionParser {
  private struct LocalWiFiQRPayload: Decodable {
    let sessionId: String
    let transferToken: String
    let expiresAt: String
    let uploadMode: String
    let ip: String?
    let port: Int?
    let baseURL: String?
  }

  private static let payloadQueryNames: Set<String> = ["payload", "qr", "data"]
  private static let webSessionQueryNames: Set<String> = [
    "session", "sessionid", "web_session_id", "websessionid", "id"
  ]
  private static let legacyWebSessionQueryNames: Set<String> = ["token"]
  private static let endpointQueryNames: Set<String> = [
    "endpoint", "api", "api_base_url", "apibaseurl"
  ]
  private static let schemaQueryNames: Set<String> = ["schema"]
  private static let jobIdQueryNames: Set<String> = ["job_id", "jobid"]
  private static let namingVersionQueryNames: Set<String> = ["naming_version", "namingversion"]
  private static let taxonomyVersionQueryNames: Set<String> = ["taxonomy_version", "taxonomyversion"]
  private static let requiresViewIdQueryNames: Set<String> = ["requires_view_id", "requiresviewid"]
  private static let expiresAtQueryNames: Set<String> = ["expires_at", "expiresat"]
  private static let customerCodeQueryNames: Set<String> = [
    "cust3", "customer_code", "customercode"
  ]
  private static let jobCodeQueryNames: Set<String> = [
    "job5", "job_code", "jobcode"
  ]
  private static let packageIdQueryNames: Set<String> = ["package_id", "packageid"]
  private static let packageKeyIdQueryNames: Set<String> = ["key_id", "keyid"]
  private static let packageKeyBase64QueryNames: Set<String> = [
    "package_key_base64", "packagekeybase64", "key_base64", "keybase64"
  ]
  private static let connectPathPrefixes: Set<String> = ["up", "connect", "web-connect"]
  private static let defaultWebConnectEndpoint = URL(string: "https://api.pixcapture.app")!

  static func extractLocalWiFiPayload(from raw: String) -> LocalWiFiUploadHandshake? {
    let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !token.isEmpty else { return nil }

    for candidate in candidatePayloadStrings(from: token) {
      if let payload = decodeLocalWiFiPayload(jsonString: candidate) {
        return payload
      }
      if let decodedString = decodeBase64PayloadString(candidate),
         let payload = decodeLocalWiFiPayload(jsonString: decodedString) {
        return payload
      }
    }

    return nil
  }

  static func extractWebConnectPayload(from raw: String) -> WebConnectUploadHandshake? {
    let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !token.isEmpty else { return nil }

    for candidate in candidatePayloadStrings(from: token) {
      if let payload = decodeWebConnectPayload(jsonString: candidate)
          ?? decodeWebConnectURLPayload(candidate)
          ?? decodeRawWebConnectPayload(candidate) {
        return payload
      }
      if let decodedString = decodeBase64PayloadString(candidate),
         let payload = decodeWebConnectPayload(jsonString: decodedString)
          ?? decodeWebConnectURLPayload(decodedString)
          ?? decodeRawWebConnectPayload(decodedString) {
        return payload
      }
    }

    return nil
  }

  private static func candidatePayloadStrings(from raw: String) -> [String] {
    var candidates: [String] = []
    var seen = Set<String>()

    func appendCandidate(_ value: String?) {
      guard let value else { return }
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return }
      if seen.insert(trimmed).inserted {
        candidates.append(trimmed)
      }
    }

    appendCandidate(raw)

    if let url = URL(string: raw),
       let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
       let queryItems = components.queryItems {
      for item in queryItems where payloadQueryNames.contains(item.name.lowercased()) {
        appendCandidate(item.value)
      }
    }

    return candidates
  }

  private static func decodeLocalWiFiPayload(jsonString: String) -> LocalWiFiUploadHandshake? {
    guard let data = jsonString.data(using: .utf8) else { return nil }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    guard let payload = try? decoder.decode(LocalWiFiQRPayload.self, from: data) else {
      return nil
    }
    guard payload.uploadMode.uppercased() == PixcaptureUploadMode.localWifi.rawValue else {
      return nil
    }
    let sessionId = payload.sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
    let transferToken = payload.transferToken.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sessionId.isEmpty, !transferToken.isEmpty else {
      return nil
    }
    return LocalWiFiUploadHandshake(
      sessionId: sessionId,
      transferToken: transferToken,
      expiresAt: payload.expiresAt,
      uploadMode: .localWifi,
      ip: payload.ip,
      port: payload.port,
      baseURL: payload.baseURL
    )
  }

  private static func decodeWebConnectPayload(jsonString: String) -> WebConnectUploadHandshake? {
    guard let data = jsonString.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return nil
    }

    let action = normalizedString(value(in: object, keys: ["action"]))?.lowercased() ?? "connect"
    guard action == "connect" else {
      return nil
    }

    guard let webSessionId = normalizedWebSessionId(
      value(in: object, keys: ["web_session_id", "webSessionId", "session", "sessionId"])
    ) ?? normalizedLegacyWebSessionId(
      value(in: object, keys: ["token"])
    ) else {
      return nil
    }

    return WebConnectUploadHandshake(
      action: action,
      customerCode: normalizedIdentityCode(
        value(in: object, keys: ["cust3", "customer_code", "customerCode"]),
        expectedLength: 3
      ) ?? "",
      jobCode: normalizedIdentityCode(
        value(in: object, keys: ["job5", "job_code", "jobCode"]),
        expectedLength: 5
      ) ?? "",
      webSessionId: webSessionId,
      endpoint: normalizedEndpointURL(
        value(in: object, keys: ["endpoint", "api_base_url", "apiBaseURL"])
      ) ?? defaultWebConnectEndpoint,
      schema: normalizedString(value(in: object, keys: ["schema"])),
      jobId: normalizedString(value(in: object, keys: ["job_id", "jobId"])),
      namingVersion: normalizedNamingVersion(
        value(in: object, keys: ["naming_version", "namingVersion"])
      ),
      taxonomyVersion: normalizedString(
        value(in: object, keys: ["taxonomy_version", "taxonomyVersion"])
      ),
      requiresViewId: boolValue(in: object, keys: ["requires_view_id", "requiresViewId"]),
      companionTransport: normalizedString(
        value(in: object, keys: ["companion_transport", "companionTransport"])
      ),
      expiresAt: normalizedString(value(in: object, keys: ["expires_at", "expiresAt"])),
      packageKey: packageKeyMaterial(in: object),
      cableReceiverToken: cableReceiverToken(in: object)
    )
  }

  private static func decodeWebConnectURLPayload(_ raw: String) -> WebConnectUploadHandshake? {
    guard let url = URL(string: raw),
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return nil
    }

    let queryItems = components.queryItems ?? []
    let action = normalizedString(
      firstQueryValue(in: queryItems, names: ["action"])
    )?.lowercased() ?? "connect"
    guard action == "connect" else {
      return nil
    }

    let sessionId = normalizedWebSessionId(
      firstQueryValue(in: queryItems, names: webSessionQueryNames)
        ?? sessionIdFromURLPath(components.path)
    ) ?? normalizedLegacyWebSessionId(
      firstQueryValue(in: queryItems, names: legacyWebSessionQueryNames)
    )
    guard let sessionId else { return nil }

    let endpoint = normalizedEndpointURL(
      firstQueryValue(in: queryItems, names: endpointQueryNames)
    ) ?? defaultWebConnectEndpoint

    return WebConnectUploadHandshake(
      action: action,
      customerCode: normalizedIdentityCode(
        firstQueryValue(in: queryItems, names: customerCodeQueryNames),
        expectedLength: 3
      ) ?? "",
      jobCode: normalizedIdentityCode(
        firstQueryValue(in: queryItems, names: jobCodeQueryNames),
        expectedLength: 5
      ) ?? "",
      webSessionId: sessionId,
      endpoint: endpoint,
      schema: normalizedString(firstQueryValue(in: queryItems, names: schemaQueryNames)),
      jobId: normalizedString(firstQueryValue(in: queryItems, names: jobIdQueryNames)),
      namingVersion: normalizedNamingVersion(
        firstQueryValue(in: queryItems, names: namingVersionQueryNames)
      ),
      taxonomyVersion: normalizedString(
        firstQueryValue(in: queryItems, names: taxonomyVersionQueryNames)
      ),
      requiresViewId: normalizedBoolean(
        firstQueryValue(in: queryItems, names: requiresViewIdQueryNames)
      ),
      companionTransport: normalizedString(
        firstQueryValue(in: queryItems, names: ["companion_transport", "companiontransport"])
      ),
      expiresAt: normalizedString(firstQueryValue(in: queryItems, names: expiresAtQueryNames)),
      packageKey: packageKeyMaterial(in: queryItems),
      cableReceiverToken: firstQueryValue(in: queryItems, names: ["cable_receiver_token", "cablereceivertoken", "receiver_token", "receivertoken"])
    )
  }

  private static func decodeRawWebConnectPayload(_ raw: String) -> WebConnectUploadHandshake? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.lowercased().hasPrefix("sess"),
          let sessionId = normalizedWebSessionId(trimmed) else {
      return nil
    }

    return WebConnectUploadHandshake(
      action: "connect",
      customerCode: "",
      jobCode: "",
      webSessionId: sessionId,
      endpoint: defaultWebConnectEndpoint
    )
  }

  private static func cableReceiverToken(in object: [String: Any]) -> String? {
    if let direct = normalizedString(
      value(in: object, keys: ["cable_receiver_token", "cableReceiverToken", "receiver_token", "receiverToken"])
    ) {
      return direct
    }
    if let nested = object["cable_receiver"] as? [String: Any]
      ?? object["cableReceiver"] as? [String: Any] {
      return normalizedString(value(in: nested, keys: ["token", "receiver_token", "receiverToken"]))
    }
    return nil
  }

  private static func packageKeyMaterial(in object: [String: Any]) -> PixcapturePackageKeyMaterial? {
    let nested = object["package_key"] as? [String: Any]
      ?? object["packageKey"] as? [String: Any]
      ?? object
    let encryption = nested["encryption"] as? [String: Any] ?? nested

    guard let packageId = normalizedPackageId(
      value(in: nested, keys: ["package_id", "packageId"])
    ),
          let keyId = normalizedPackageKeyId(
            value(in: nested, keys: ["key_id", "keyId"])
          ),
          let keyBase64 = normalizedString(
            value(in: encryption, keys: ["key_base64", "keyBase64", "package_key_base64", "packageKeyBase64"])
          ) else {
      return nil
    }

    return PixcapturePackageKeyMaterial(
      schema: normalizedString(value(in: nested, keys: ["schema"])),
      packageId: packageId,
      keyId: keyId,
      algorithm: normalizedString(value(in: encryption, keys: ["algorithm"])) ?? "AES-256-GCM",
      keyBase64: keyBase64,
      expiresAt: normalizedString(value(in: nested, keys: ["expires_at", "expiresAt"]))
    )
  }

  private static func packageKeyMaterial(in queryItems: [URLQueryItem]) -> PixcapturePackageKeyMaterial? {
    guard let packageId = normalizedPackageId(
      firstQueryValue(in: queryItems, names: packageIdQueryNames)
    ),
          let keyId = normalizedPackageKeyId(
            firstQueryValue(in: queryItems, names: packageKeyIdQueryNames)
          ),
          let keyBase64 = normalizedString(
            firstQueryValue(in: queryItems, names: packageKeyBase64QueryNames)
          ) else {
      return nil
    }

    return PixcapturePackageKeyMaterial(
      schema: normalizedString(firstQueryValue(in: queryItems, names: schemaQueryNames)),
      packageId: packageId,
      keyId: keyId,
      algorithm: "AES-256-GCM",
      keyBase64: keyBase64,
      expiresAt: normalizedString(firstQueryValue(in: queryItems, names: expiresAtQueryNames))
    )
  }

  private static func value(in object: [String: Any], keys: [String]) -> String? {
    for key in keys {
      if let raw = object[key] {
        if let value = raw as? String {
          return value
        }
        if let number = raw as? NSNumber {
          return number.stringValue
        }
      }
    }
    return nil
  }

  private static func firstQueryValue(in items: [URLQueryItem], names: Set<String>) -> String? {
    items.first {
      names.contains($0.name.lowercased())
    }?.value
  }

  private static func boolValue(in object: [String: Any], keys: [String]) -> Bool? {
    for key in keys {
      if let raw = object[key] as? Bool {
        return raw
      }
      if let raw = object[key] as? NSNumber {
        return raw.boolValue
      }
      if let raw = object[key] as? String,
         let normalized = normalizedBoolean(raw) {
        return normalized
      }
    }
    return nil
  }

  private static func sessionIdFromURLPath(_ path: String) -> String? {
    let components = path
      .split(separator: "/")
      .map(String.init)
      .filter { !$0.isEmpty }

    guard !components.isEmpty else { return nil }

    if components.count >= 2,
       connectPathPrefixes.contains(components[0].lowercased()) {
      return components[1]
    }
    if components.count == 1, components[0].lowercased().hasPrefix("sess") {
      return components[0]
    }
    return nil
  }

  private static func normalizedWebSessionId(_ value: String?) -> String? {
    guard let trimmed = normalizedString(value),
          let regex = try? NSRegularExpression(pattern: "^[A-Za-z0-9_-]{6,128}$") else {
      return nil
    }
    let range = NSRange(location: 0, length: trimmed.utf16.count)
    guard regex.firstMatch(in: trimmed, options: [], range: range) != nil else {
      return nil
    }
    return trimmed
  }

  private static func normalizedLegacyWebSessionId(_ value: String?) -> String? {
    guard let sessionId = normalizedWebSessionId(value),
          sessionId.lowercased().hasPrefix("sess") else {
      return nil
    }
    return sessionId
  }

  private static func normalizedEndpointURL(_ value: String?) -> URL? {
    guard let endpointString = normalizedString(value),
          let endpointURL = URL(string: endpointString),
          let scheme = endpointURL.scheme?.lowercased(),
          (scheme == "https" || scheme == "http"),
          endpointURL.host?.isEmpty == false else {
      return nil
    }
    return endpointURL
  }

  private static func normalizedIdentityCode(_ value: String?, expectedLength: Int) -> String? {
    guard let trimmed = normalizedString(value)?.lowercased() else { return nil }
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789")
    let scalars = trimmed.unicodeScalars.filter { allowed.contains($0) }
    let normalized = String(String.UnicodeScalarView(scalars))
    guard normalized.count == expectedLength else {
      return nil
    }
    return normalized
  }

  private static func normalizedNamingVersion(_ value: String?) -> String? {
    guard let trimmed = normalizedString(value)?.lowercased() else { return nil }
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-_.")
    let scalars = trimmed.unicodeScalars.filter { allowed.contains($0) }
    let normalized = String(String.UnicodeScalarView(scalars))
    guard !normalized.isEmpty else {
      return nil
    }
    return normalized
  }

  private static func normalizedBoolean(_ value: String?) -> Bool? {
    guard let trimmed = normalizedString(value)?.lowercased() else { return nil }
    switch trimmed {
    case "1", "true", "yes", "y":
      return true
    case "0", "false", "no", "n":
      return false
    default:
      return nil
    }
  }

  private static func normalizedString(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
          !trimmed.isEmpty else {
      return nil
    }
    return trimmed
  }

  private static func normalizedPackageId(_ value: String?) -> String? {
    guard let trimmed = normalizedString(value),
          trimmed.range(of: #"^pkg_[A-Za-z0-9_-]{12,80}$"#, options: .regularExpression) != nil else {
      return nil
    }
    return trimmed
  }

  private static func normalizedPackageKeyId(_ value: String?) -> String? {
    guard let trimmed = normalizedString(value),
          trimmed.range(of: #"^pkgkey_[A-Za-z0-9_-]{12,80}$"#, options: .regularExpression) != nil else {
      return nil
    }
    return trimmed
  }

  private static func decodeBase64PayloadString(_ value: String) -> String? {
    guard let data = decodeBase64PayloadData(value) else { return nil }
    return String(data: data, encoding: .utf8)
  }

  private static func decodeBase64PayloadData(_ value: String) -> Data? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if let standard = Data(base64Encoded: trimmed) {
      return standard
    }
    var normalized = trimmed
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    let remainder = normalized.count % 4
    if remainder != 0 {
      normalized += String(repeating: "=", count: 4 - remainder)
    }
    return Data(base64Encoded: normalized)
  }
}

private struct WebConnectQRScannerView: UIViewControllerRepresentable {
  let onCode: (String) -> Void
  let onError: (String) -> Void

  func makeUIViewController(context: Context) -> WebConnectQRScannerController {
    WebConnectQRScannerController(onCode: onCode, onError: onError)
  }

  func updateUIViewController(_ uiViewController: WebConnectQRScannerController, context: Context) {}
}

private final class WebConnectQRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
  private let onCode: (String) -> Void
  private let onError: (String) -> Void
  private let session = AVCaptureSession()
  private var previewLayer: AVCaptureVideoPreviewLayer?
  private var didEmitResult = false

  init(onCode: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
    self.onCode = onCode
    self.onError = onError
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    return nil
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    configureCaptureSession()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    previewLayer?.frame = view.bounds
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    if session.isRunning {
      session.stopRunning()
    }
  }

  private func configureCaptureSession() {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      setupSession()
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        DispatchQueue.main.async {
          guard let self else { return }
          if granted {
            self.setupSession()
          } else {
            self.emitError("Kamerazugriff wurde nicht erlaubt.")
          }
        }
      }
    case .denied, .restricted:
      emitError("Kein Kamerazugriff. Bitte in den iOS-Einstellungen aktivieren.")
    @unknown default:
      emitError("Kamera konnte nicht initialisiert werden.")
    }
  }

  private func setupSession() {
    guard let videoDevice = AVCaptureDevice.default(for: .video) else {
      emitError("Keine Kamera gefunden.")
      return
    }

    do {
      let input = try AVCaptureDeviceInput(device: videoDevice)
      guard session.canAddInput(input) else {
        emitError("Kamera-Input konnte nicht hinzugefügt werden.")
        return
      }
      session.addInput(input)
    } catch {
      emitError("Kamera-Input fehlgeschlagen.")
      return
    }

    let output = AVCaptureMetadataOutput()
    guard session.canAddOutput(output) else {
      emitError("Scanner-Output konnte nicht hinzugefügt werden.")
      return
    }
    session.addOutput(output)
    output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
    output.metadataObjectTypes = [.qr]

    let preview = AVCaptureVideoPreviewLayer(session: session)
    preview.videoGravity = .resizeAspectFill
    preview.frame = view.bounds
    view.layer.addSublayer(preview)
    previewLayer = preview

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      self?.session.startRunning()
    }
  }

  func metadataOutput(
    _ output: AVCaptureMetadataOutput,
    didOutput metadataObjects: [AVMetadataObject],
    from connection: AVCaptureConnection
  ) {
    guard !didEmitResult else { return }
    guard let first = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
          first.type == .qr,
          let code = first.stringValue else {
      return
    }

    didEmitResult = true
    session.stopRunning()
    onCode(code)
  }

  private func emitError(_ message: String) {
    guard !didEmitResult else { return }
    didEmitResult = true
    onError(message)
  }
}
