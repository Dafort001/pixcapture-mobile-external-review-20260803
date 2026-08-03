import SwiftUI

struct ExpertModeView: View {
  @EnvironmentObject var settings: AppSettings
  @EnvironmentObject var camera: CameraManager
  @EnvironmentObject var authService: AuthService
  @EnvironmentObject var uploadQueue: UploadQueue
  @Environment(\.dismiss) private var dismiss
  @AppStorage("pixcapture.supportToolsUnlocked") private var supportToolsUnlocked = false
  @State private var whiteBalanceExpanded: Bool = false
  @State private var baseExposureExpanded: Bool = false
  @State private var showPairingScanner = false
  @State private var pairingInput = ""
  @State private var pairingMessage: String?
  @State private var isRecoveryDocumentExportPresented = false
  @State private var recoveryExportURLs: [URL] = []
  @State private var recoveryStagingDirectoryURL: URL?
  @State private var recoveryMessage: String?
  @State private var recoveryErrorMessage: String?
  @State private var isRecoveryPreparing = false
  @State private var recoveryPreparationTitle = "Recovery wird vorbereitet"
  @State private var recoveryPreparationDetail = "Lokale Dateien werden gesammelt."
  @State private var showRecoveryResetConfirmation = false
  @State private var showOrphanCleanupConfirmation = false
  @State private var orphanCleanupSummary: LocalCaptureCleanupSummary?
  var onDone: (() -> Void)? = nil
  var onOpenHelp: (() -> Void)? = nil

  var body: some View {
    NavigationStack {
      ZStack {
        PixBrand.background.ignoresSafeArea()

        Form {
        Section {
          Picker("expert.captureMode", selection: $settings.photoCaptureMode) {
            Text("expert.captureMode.standard").tag(PhotoCaptureMode.standardBracket)
            Text("Einzelbild").tag(PhotoCaptureMode.singleShot)
            Text("expert.captureMode.darkRoom").tag(PhotoCaptureMode.darkRoom)
          }

          if settings.photoCaptureMode == .standardBracket {
            Picker("expert.bracketCount", selection: $settings.bracketCount) {
              Text("1").tag(1)
              Text("3").tag(3)
              Text("5").tag(5)
              Text("7").tag(7)
            }

            Picker("expert.step", selection: $settings.exposureStepEV) {
              Text("1.0 EV").tag(1.0)
              Text("1.5 EV").tag(1.5)
            }

            Picker("expert.bracketMetering", selection: $settings.bracketMeteringMode) {
              Text("expert.bracketMetering.previewBalanced").tag(BracketMeteringMode.previewBalanced)
              Text("expert.bracketMetering.highlightAnchor").tag(BracketMeteringMode.highlightAnchor)
            }

            Text("expert.bracketMetering.help")
              .font(.footnote)
              .foregroundStyle(.secondary)

            if settings.bracketCount >= 5 {
              Text("expert.bracketing.rawHelp")
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
          } else {
            Picker("expert.maxExposureSeconds", selection: $settings.maxExposureSeconds) {
              Text("5s").tag(5.0)
              Text("10s").tag(10.0)
              Text("15s").tag(15.0)
              Text("20s").tag(20.0)
              Text("30s").tag(30.0)
            }

            Text("expert.darkRoom.help")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        } header: {
          Text("expert.bracketing")
        } footer: {
          Text("expert.bracketing.help")
        }

        Section {
          Picker("expert.photoFormat", selection: $settings.photoFormat) {
            Text("JPEG").tag(PhotoFormat.jpeg)
            Text(camera.hasResolvedProRAWCaptureAvailability && !camera.isProRAWCaptureAvailable
              ? LocalizedStringKey("expert.proRaw.disabledOption")
              : LocalizedStringKey("expert.proRaw.option")
            )
            .tag(PhotoFormat.proRaw)
            .disabled(camera.hasResolvedProRAWCaptureAvailability && !camera.isProRAWCaptureAvailable)
          }
        } header: {
          Text("expert.format")
        } footer: {
          VStack(alignment: .leading, spacing: 6) {
            Text("expert.format.help")
            if camera.hasResolvedProRAWCaptureAvailability && !camera.isProRAWCaptureAvailable {
              Text("expert.proRaw.unavailable")
            }
          }
        }

        Section {
          Toggle("expert.focusLock", isOn: $settings.focusLockEnabled)

          DisclosureGroup("expert.whiteBalancePanel", isExpanded: $whiteBalanceExpanded) {
            Toggle("expert.whiteBalanceLock", isOn: $settings.whiteBalanceLocked)
            HStack {
              Text("expert.whiteBalance.kelvin")
              Slider(value: $settings.whiteBalanceKelvin, in: 2000...6000, step: 50)
              Text("\(Int(settings.whiteBalanceKelvin))K")
                .monospacedDigit()
                .frame(width: 68, alignment: .trailing)
            }
            Text(settings.whiteBalanceLocked ? "expert.whiteBalance.status.locked" : "expert.whiteBalance.status.auto")
              .font(.footnote)
              .foregroundStyle(.secondary)
            Text("expert.whiteBalance.help")
              .font(.footnote)
              .foregroundStyle(.secondary)
            Text("expert.whiteBalance.kelvinHelp")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        } header: {
          Text("expert.locks")
        } footer: {
          Text("expert.locks.help")
        }

        Section {
          HStack {
            Text("expert.isoValue")
            Slider(
              value: isoSliderValue,
              in: 0...Double(max(isoPresetValues.count - 1, 1)),
              step: 1
            )
            .disabled(isoPresetValues.count <= 1)
            Text(String(format: "%.0f", nearestISOPreset(to: settings.manualISOValue)))
              .monospacedDigit()
              .frame(width: 56, alignment: .trailing)
          }

          Text("ISO rastet auf feste Halbblenden-Stufen ein.")
            .font(.footnote)
            .foregroundStyle(.secondary)

          if settings.manualISOValue > 400 {
            Text("expert.isoWarning")
              .font(.footnote)
              .foregroundStyle(Color.orange)
          }

          DisclosureGroup("expert.shutterPanel", isExpanded: $baseExposureExpanded) {
            Picker("expert.shutter", selection: $settings.manualShutterSeconds) {
              ForEach(shutterOptions, id: \.self) { value in
                Text(shutterLabel(value)).tag(value)
              }
            }
            Text("expert.shutter.help")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        } header: {
          Text("expert.exposure")
        } footer: {
          Text("expert.exposure.help")
        }

        Section {
          Toggle("expert.grid", isOn: $settings.gridEnabled)
          Toggle("expert.level", isOn: $settings.levelEnabled)
          Toggle("expert.histogram", isOn: $settings.histogramEnabled)
          Picker("expert.galleryOrientationMode", selection: $settings.galleryOrientationMode) {
            Text("expert.galleryOrientation.auto").tag(AppSettings.GalleryOrientationMode.autoExif)
            Text("expert.galleryOrientation.manual").tag(AppSettings.GalleryOrientationMode.manualFixed)
          }
        } header: {
          Text("expert.overlays")
        } footer: {
          Text("expert.overlays.help")
        }

        Section {
          Toggle("expert.volumeShutter", isOn: $settings.volumeShutterEnabled)
          if settings.volumeShutterEnabled {
            Toggle("expert.volumeShutter.stableVolume", isOn: $settings.volumeShutterKeepVolumeStable)
          }
        } header: {
          Text("expert.remote")
        } footer: {
          VStack(alignment: .leading, spacing: 6) {
            Text("expert.volumeShutter.help")
            if settings.volumeShutterEnabled {
              Text("expert.volumeShutter.stableVolume.help")
            }
          }
        }

        Section {
          Toggle("expert.allowCellular", isOn: $settings.allowCellularUpload)
        } header: {
          Text("expert.upload")
        } footer: {
          Text("expert.upload.help")
        }

        if AppFeatureFlags.supportToolsUnlockEnabled && supportToolsUnlocked {
          Section {
            Label(recoverySummaryText, systemImage: "externaldrive.badge.checkmark")

            Label("Support-ZIP lokal deaktiviert - Portal-Upload folgt", systemImage: "externaldrive.badge.exclamationmark")
              .foregroundStyle(.secondary)

            Button {
              presentRecoveryFileListExport()
            } label: {
              Label("Dateiliste ins Kundenportal sichern", systemImage: "list.bullet.rectangle")
            }
            .disabled(uploadQueue.localRecoveryFileCount == 0 || isRecoveryPreparing)

            if isRecoveryPreparing {
              HStack(spacing: 10) {
                ProgressView()
                Text("Bitte warten. Die App sammelt lokale Dateien und erstellt Recovery-ZIPs.")
                  .font(.footnote)
                  .foregroundStyle(Color.secondary)
              }
            }

            Button(role: .destructive) {
              showRecoveryResetConfirmation = true
            } label: {
              Label("Lokale Dateien erneut uploadbar machen", systemImage: "arrow.clockwise")
            }
            .disabled(uploadQueue.isUploading || uploadQueue.records.isEmpty || isRecoveryPreparing)

            Button(role: .destructive) {
              prepareOrphanCleanupConfirmation()
            } label: {
              Label("Verwaiste lokale Dateien löschen", systemImage: "trash")
            }
            .disabled(uploadQueue.isUploading || uploadQueue.localRecoveryFileCount == 0 || isRecoveryPreparing)

            if let recoveryMessage {
              Text(recoveryMessage)
                .font(.footnote)
                .foregroundStyle(Color.secondary)
            }
          } header: {
            Text("Recovery")
          } footer: {
            Text("Support-ZIP nur nach Absprache verwenden: Es enthaelt lokal erreichbare Originale, Previews, XMP-, Depth- und EXIF-Dateien. Fuer normale Tests zuerst nur die Dateiliste sichern.")
          }
        }

        Section {
          Button {
            pairingMessage = nil
            showPairingScanner = true
          } label: {
            Label("Anmelde-QR scannen", systemImage: "qrcode.viewfinder")
          }

          TextField("pixcapture://connect?token=...", text: $pairingInput)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .onSubmit {
              savePairingFromInput()
              hideSystemKeyboard()
            }
            .font(.callout.monospaced())

          Button("Link/Token speichern") {
            savePairingFromInput()
          }
          .disabled(parsedPairingToken == nil)

          if authService.mobileConnectToken != nil {
            Label("QR-Anmeldung gespeichert", systemImage: "checkmark.seal.fill")
              .foregroundStyle(Color.green)
          } else {
            Label("Nicht eingerichtet – bei Passwort-Anmeldung nicht nötig", systemImage: "info.circle")
              .foregroundStyle(Color.secondary)
          }

          if let pairingMessage {
            Text(pairingMessage)
              .font(.footnote)
              .foregroundStyle(Color.secondary)
          }

          if authService.mobileConnectToken != nil {
            Button("Anderes Konto per QR anmelden") {
              authService.clearMobileConnectToken()
              pairingInput = ""
              pairingMessage = "Vorhandene QR-Anmeldung entfernt. Bitte den Anmelde-QR des anderen Kontos scannen."
              showPairingScanner = true
            }

            Button("QR-Anmeldung entfernen", role: .destructive) {
              authService.clearMobileConnectToken()
              pairingInput = ""
              pairingMessage = "QR-Anmeldung wurde entfernt."
            }
          }
        } header: {
          Text("Alternative Anmeldung per QR")
        } footer: {
          VStack(alignment: .leading, spacing: 6) {
            Text("Nur als Alternative zur Anmeldung mit E-Mail und Passwort. Der Upload-QR unter „Aufnahmen übertragen“ ist ein anderer QR-Code und gilt nur für die jeweilige Übertragung.")
            if AppFeatureFlags.supportToolsUnlockEnabled && supportToolsUnlocked {
              Text("Support-Werkzeuge auf diesem Geraet aktiv.")
                .foregroundStyle(PixBrand.orange)
            }
          }
          .onTapGesture(count: 5) {
            guard AppFeatureFlags.supportToolsUnlockEnabled else { return }
            supportToolsUnlocked.toggle()
            pairingMessage = supportToolsUnlocked
              ? "Support-Werkzeuge wurden auf diesem Geraet aktiviert."
              : "Support-Werkzeuge wurden auf diesem Geraet deaktiviert."
          }
        }
      }

        if isRecoveryPreparing {
          recoveryPreparationOverlay
            .transition(.opacity)
            .zIndex(10)
        }
      }
      .scrollContentBackground(.hidden)
      .background(PixBrand.background)
      .tint(PixBrand.orange)
      .scrollDismissesKeyboard(.interactively)
      .navigationTitle(Text("expert.title"))
      .toolbarBackground(PixBrand.background, for: .navigationBar)
      .toolbarColorScheme(.dark, for: .navigationBar)
      .toolbar {
        if let onOpenHelp {
          ToolbarItem(placement: .topBarLeading) {
            Button {
              onOpenHelp()
            } label: {
              Image(systemName: "questionmark.circle")
            }
            .accessibilityLabel("Hilfe öffnen")
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("common.done") {
            guard !isRecoveryPreparing else { return }
            if let onDone {
              onDone()
            } else {
              dismiss()
            }
          }
        }
      }
      .keyboardDoneToolbar()
    }
    .preferredColorScheme(.dark)
    .sheet(isPresented: $showPairingScanner) {
      ZStack(alignment: .topTrailing) {
        MobileConnectQRScannerView { rawCode in
          applyScannedPairingCode(rawCode)
        } onError: { message in
          pairingMessage = message
          showPairingScanner = false
        }

        Button {
          showPairingScanner = false
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.title2)
            .foregroundStyle(.white)
            .padding(12)
        }
      }
      .ignoresSafeArea()
    }
    .sheet(isPresented: $isRecoveryDocumentExportPresented, onDismiss: cleanupRecoveryStagingDirectory) {
      DocumentExportSheet(
        exportURLs: recoveryExportURLs,
        onComplete: { completed in
          isRecoveryDocumentExportPresented = false
          recoveryMessage = completed
            ? "Recovery-Paket wurde an Dateien uebergeben."
            : "Recovery-Export wurde abgebrochen."
          cleanupRecoveryStagingDirectory()
        }
      )
    }
    .confirmationDialog(
      "Upload-Status zuruecksetzen?",
      isPresented: $showRecoveryResetConfirmation,
      titleVisibility: .visible
    ) {
      Button("Alle lokalen Dateien erneut uploadbar machen", role: .destructive) {
        let updatedCount = uploadQueue.resetLocalRecordsForRecovery()
        recoveryMessage = updatedCount > 0
          ? "\(updatedCount) Dateien sind wieder uploadbar. Das kann bei bereits angekommenen Serverdateien Duplikate erzeugen."
          : "Keine lokalen Dateien mussten geaendert werden."
      }
      Button("Abbrechen", role: .cancel) {}
    } message: {
      Text("Das loescht keine Bilder. Es setzt nur den lokalen Upload-Status fuer vorhandene Dateien zurueck.")
    }
    .confirmationDialog(
      "Verwaiste lokale Dateien löschen?",
      isPresented: $showOrphanCleanupConfirmation,
      titleVisibility: .visible
    ) {
      Button("Verwaiste Dateien endgültig löschen", role: .destructive) {
        deleteOrphanedLocalCaptureFiles()
      }
      Button("Abbrechen", role: .cancel) {}
    } message: {
      Text(orphanCleanupConfirmationText)
    }
    .alert("Recovery fehlgeschlagen", isPresented: Binding(
      get: { recoveryErrorMessage != nil },
      set: { if !$0 { recoveryErrorMessage = nil } }
    )) {
      Button("OK", role: .cancel) {
        recoveryErrorMessage = nil
      }
    } message: {
      Text(recoveryErrorMessage ?? "")
    }
    .onAppear {
      let allowedSteps: Set<Double> = [1.0, BracketStepPolicy.denseBracketStepEV]
      if !allowedSteps.contains(settings.exposureStepEV) {
        settings.exposureStepEV = BracketStepPolicy.denseBracketStepEV
      }
      syncPhotoFormatAvailability()
      snapManualISOToPreset()
      if pairingInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        pairingInput = authService.mobileConnectToken ?? ""
      }
    }
    .onChange(of: camera.isProRAWCaptureAvailable) { _, _ in
      syncPhotoFormatAvailability()
    }
    .onChange(of: camera.hasResolvedProRAWCaptureAvailability) { _, isResolved in
      guard isResolved else { return }
      syncPhotoFormatAvailability()
    }
    .onChange(of: camera.isoRange) { _, _ in
      snapManualISOToPreset()
    }
  }

  private var parsedPairingToken: String? {
    AuthService.parseMobileConnectToken(from: pairingInput)
  }

  private var recoverySummaryText: String {
    let records = uploadQueue.records
    let seriesCount = Set(records.map(\.seriesId)).count
    let pending = records.filter { $0.status == .pending }.count
    let uploading = records.filter { $0.status == .uploading }.count
    let uploaded = records.filter { $0.status == .uploaded }.count
    let failed = records.filter { $0.status == .failed }.count
    return "\(records.count) Queue-Dateien, \(uploadQueue.localRecoveryFileCount) lokale Dateien, \(seriesCount) Motive - pending \(pending), uploading \(uploading), uploaded \(uploaded), failed \(failed)"
  }

  private var recoveryPreparationOverlay: some View {
    ZStack {
      Color.black.opacity(0.58)
        .ignoresSafeArea()

      VStack(alignment: .leading, spacing: 16) {
        HStack(spacing: 12) {
          ProgressView()
            .tint(.white)
          Text(recoveryPreparationTitle)
            .font(.headline)
            .foregroundStyle(.white)
        }

        Text(recoveryPreparationDetail)
          .font(.callout)
          .foregroundStyle(Color.white.opacity(0.88))

        Text("Das kann bei vielen Bildern einige Minuten dauern. Danach öffnet sich automatisch der Dateien-Dialog.")
          .font(.footnote)
          .foregroundStyle(Color.white.opacity(0.72))
      }
      .padding(22)
      .frame(maxWidth: 360, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .fill(Color(white: 0.08))
          .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
              .stroke(Color.white.opacity(0.14), lineWidth: 1)
          )
      )
      .padding(24)
    }
    .allowsHitTesting(true)
  }

  private var orphanCleanupConfirmationText: String {
    guard let orphanCleanupSummary else {
      return "Die App prueft lokale Dateien, die keinem Upload-Eintrag mehr zugeordnet sind."
    }
    return "\(orphanCleanupSummary.orphanFiles) verwaiste lokale Dateien mit \(formatFileSize(orphanCleanupSummary.orphanBytes)) werden geloescht. Queue-Dateien und Upload-Protokolle bleiben erhalten."
  }

  private func presentRecoveryDocumentExport() {
    guard !isRecoveryPreparing else { return }
    cleanupRecoveryStagingDirectory()
    uploadQueue.refreshLocalRecoveryFileCount()
    recoveryErrorMessage = nil
    recoveryMessage = "Recovery wird vorbereitet..."
    recoveryPreparationTitle = "Recovery wird vorbereitet"
    recoveryPreparationDetail = "\(uploadQueue.localRecoveryFileCount) lokale Dateien werden gesammelt und in Recovery-ZIPs geschrieben."
    isRecoveryPreparing = true
    let records = uploadQueue.records

    Task {
      let result = await Task.detached(priority: .userInitiated) {
        Result {
          try FileStore.prepareRecoveryJobExport(records: records)
        }
      }.value

      isRecoveryPreparing = false
      switch result {
      case .success(let preparedExport):
        recoveryStagingDirectoryURL = preparedExport.directoryURL
        recoveryExportURLs = preparedExport.itemURLs
        recoveryMessage = "\(preparedExport.itemURLs.count) Recovery-Dateien vorbereitet."
        isRecoveryDocumentExportPresented = true
      case .failure(let error):
        recoveryErrorMessage = error.localizedDescription
        recoveryMessage = nil
      }
    }
  }

  private func presentRecoveryFileListExport() {
    guard !isRecoveryPreparing else { return }
    cleanupRecoveryStagingDirectory()
    uploadQueue.refreshLocalRecoveryFileCount()
    recoveryErrorMessage = nil
    recoveryMessage = "Dateiliste wird vorbereitet..."
    recoveryPreparationTitle = "Dateiliste wird vorbereitet"
    recoveryPreparationDetail = "Es werden nur Dateinamen, Groessen, Datum und Queue-Zuordnung geschrieben. Danach wird die Liste ins Kundenportal gesichert."
    isRecoveryPreparing = true
    let records = uploadQueue.records
    let localFileCount = uploadQueue.localRecoveryFileCount

    Task {
      let result = await Task.detached(priority: .userInitiated) {
        Result {
          try FileStore.prepareRecoveryFileListExport(records: records)
        }
      }.value

      switch result {
      case .success(let preparedExport):
        recoveryStagingDirectoryURL = preparedExport.directoryURL
        recoveryExportURLs = preparedExport.itemURLs
        recoveryPreparationDetail = "Support-Dateiliste wird ins Kundenportal hochgeladen."
        let uploaded = await authService.uploadSupportFileList(
          itemURLs: preparedExport.itemURLs,
          localFileCount: localFileCount,
          queueRecordCount: records.count
        )
        isRecoveryPreparing = false
        if uploaded {
          recoveryMessage = authService.lastInfoMessage ?? "Support-Dateiliste wurde im Kundenportal gesichert."
        } else {
          recoveryErrorMessage = authService.lastError ?? "Support-Dateiliste konnte nicht ins Kundenportal gesichert werden."
          recoveryMessage = nil
        }
        cleanupRecoveryStagingDirectory()
      case .failure(let error):
        isRecoveryPreparing = false
        recoveryErrorMessage = error.localizedDescription
        recoveryMessage = nil
      }
    }
  }

  private func prepareOrphanCleanupConfirmation() {
    guard !isRecoveryPreparing else { return }
    uploadQueue.refreshLocalRecoveryFileCount()
    recoveryErrorMessage = nil
    recoveryMessage = nil
    recoveryPreparationTitle = "Lokale Dateien werden geprueft"
    recoveryPreparationDetail = "Die App sucht Dateien im lokalen Capture-Speicher, die keinem Queue-Eintrag mehr gehoeren."
    isRecoveryPreparing = true
    let records = uploadQueue.records

    Task {
      let result = await Task.detached(priority: .userInitiated) {
        Result {
          try FileStore.orphanedLocalCaptureCleanupSummary(records: records)
        }
      }.value

      isRecoveryPreparing = false
      switch result {
      case .success(let summary):
        orphanCleanupSummary = summary
        if summary.orphanFiles > 0 {
          showOrphanCleanupConfirmation = true
        } else {
          recoveryMessage = "Keine verwaisten lokalen Capture-Dateien gefunden."
        }
      case .failure(let error):
        recoveryErrorMessage = error.localizedDescription
      }
    }
  }

  private func deleteOrphanedLocalCaptureFiles() {
    guard !isRecoveryPreparing else { return }
    recoveryErrorMessage = nil
    recoveryMessage = nil
    recoveryPreparationTitle = "Verwaiste Dateien werden geloescht"
    recoveryPreparationDetail = "Die App loescht nur lokale Dateien, die keinem Queue-Eintrag mehr zugeordnet sind."
    isRecoveryPreparing = true
    let records = uploadQueue.records

    Task {
      let result = await Task.detached(priority: .userInitiated) {
        Result {
          try FileStore.deleteOrphanedLocalCaptureFiles(records: records)
        }
      }.value

      isRecoveryPreparing = false
      uploadQueue.refreshLocalRecoveryFileCount()
      switch result {
      case .success(let summary):
        orphanCleanupSummary = summary
        if summary.failedFiles > 0 {
          recoveryMessage = "\(summary.deletedFiles) Dateien geloescht, \(summary.failedFiles) konnten nicht geloescht werden."
        } else {
          recoveryMessage = "\(summary.deletedFiles) verwaiste Dateien mit \(formatFileSize(summary.deletedBytes)) geloescht."
        }
      case .failure(let error):
        recoveryErrorMessage = error.localizedDescription
      }
    }
  }

  private func cleanupRecoveryStagingDirectory() {
    if let recoveryStagingDirectoryURL {
      try? FileManager.default.removeItem(at: recoveryStagingDirectoryURL)
      self.recoveryStagingDirectoryURL = nil
    }
    recoveryExportURLs = []
  }

  private func formatFileSize(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }

  private func savePairingFromInput() {
    guard let token = parsedPairingToken else {
      pairingMessage = "Ungültiger Anmelde-Link oder Token."
      return
    }
    authService.setMobileConnectToken(token)
    pairingMessage = "QR-Anmeldung erfolgreich gespeichert."
  }

  private func applyScannedPairingCode(_ rawCode: String) {
    guard let token = AuthService.parseMobileConnectToken(from: rawCode) else {
      pairingMessage = "QR-Code enthält keinen gültigen Anmelde-Token."
      return
    }
    authService.setMobileConnectToken(token)
    pairingInput = rawCode
    pairingMessage = "QR-Anmeldung erfolgreich."
    showPairingScanner = false
  }

  private func syncPhotoFormatAvailability() {
    guard camera.hasResolvedProRAWCaptureAvailability else { return }
    _ = settings.syncPhotoFormatAvailability(isProRAWAvailable: camera.isProRAWCaptureAvailable)
  }

  private var shutterOptions: [Double] {
    [
      1.0 / 4000.0,
      1.0 / 2000.0,
      1.0 / 1000.0,
      1.0 / 500.0,
      1.0 / 250.0,
      1.0 / 125.0,
      1.0 / 60.0,
      1.0 / 30.0,
      1.0 / 15.0,
      1.0 / 8.0,
      1.0 / 4.0,
      1.0 / 2.0,
      1.0
    ]
  }

  private func shutterLabel(_ seconds: Double) -> String {
    if seconds >= 1.0 {
      return String(format: "%.0fs", seconds)
    }
    let denom = Int(round(1.0 / seconds))
    return "1/\(denom)"
  }

  private var isoPresetValues: [Double] {
    let lower = Double(camera.isoRange.lowerBound)
    let upper = Double(camera.isoRange.upperBound)
    let allPresets: [Double] = [50, 70, 100, 140, 200, 280, 400, 560, 800]
    let filtered = allPresets.filter { $0 >= lower && $0 <= upper }
    if !filtered.isEmpty {
      return filtered
    }
    return [min(max(100.0, lower), upper)]
  }

  private var isoSliderValue: Binding<Double> {
    Binding(
      get: {
        Double(nearestISOPresetIndex(for: settings.manualISOValue))
      },
      set: { newValue in
        guard !isoPresetValues.isEmpty else { return }
        let index = min(max(Int(newValue.rounded()), 0), isoPresetValues.count - 1)
        settings.manualISOValue = isoPresetValues[index]
      }
    )
  }

  private func nearestISOPreset(to value: Double) -> Double {
    let presets = isoPresetValues
    guard let best = presets.min(by: { abs($0 - value) < abs($1 - value) }) else {
      let lower = Double(camera.isoRange.lowerBound)
      let upper = Double(camera.isoRange.upperBound)
      return min(max(value, lower), upper)
    }
    return best
  }

  private func nearestISOPresetIndex(for value: Double) -> Int {
    let snapped = nearestISOPreset(to: value)
    return isoPresetValues.firstIndex(of: snapped) ?? 0
  }

  private func snapManualISOToPreset() {
    let snapped = nearestISOPreset(to: settings.manualISOValue)
    if abs(settings.manualISOValue - snapped) > 0.5 {
      settings.manualISOValue = snapped
    }
  }
}
