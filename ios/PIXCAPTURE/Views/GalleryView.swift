import SwiftUI
import ImageIO

struct GalleryView: View {
  private enum Palette {
    static let background = PixBrand.background
    static let panel = PixBrand.panel
    static let panelSecondary = PixBrand.panelSecondary
    static let title = PixBrand.textOnDark
    static let body = PixBrand.textOnDarkSecondary
    static let accent = PixBrand.orange
    static let primary = PixBrand.darkBlue
    static let lightBlue = PixBrand.lightBlue
    static let pink = PixBrand.pink
    static let border = PixBrand.borderOnDark
  }

  @EnvironmentObject var settings: AppSettings
  @EnvironmentObject var uploadQueue: UploadQueue
  @EnvironmentObject var camera: CameraManager
  @EnvironmentObject var authService: AuthService
  @AppStorage("pixcapture.supportToolsUnlocked") private var supportToolsUnlocked = false
  @Binding var pendingExternalConnectURL: String?
  var onNavigate: (AppScreen) -> Void

  @State private var selectedSeries: GallerySeries?
  @State private var filter: GalleryFilter = .all
  @State private var isUploadPresented = false
  @State private var uploadInitialConnectURL: String?
  @State private var pendingDeleteSeries: GallerySeries?
  @State private var pendingDeleteSeriesIds: Set<UUID> = []
  @State private var isMultiSelectEnabled = false
  @State private var selectedSeriesIds: Set<UUID> = []
  @State private var isAssignJobPresented = false
  @State private var isCurrentJobPickerPresented = false
  @State private var isAssignRoomPresented = false
  @State private var collapsedJobGroupKeys: Set<String> = []
  @State private var photoSaveStatusMessage: String?
  @State private var isRecoveryDocumentExportPresented = false
  @State private var recoveryExportURLs: [URL] = []
  @State private var recoveryStagingDirectoryURL: URL?
  @State private var recoveryMessage: String?
  @State private var recoveryErrorMessage: String?
  @State private var isRecoveryPreparing = false
  @State private var isOrphanCleanupPromptPresented = false
  @State private var recoveryPreparationTitle = "Recovery wird vorbereitet"
  @State private var recoveryPreparationDetail = "Lokale Dateien werden gesammelt."
  @State private var pendingRoomSeriesIds: Set<UUID> = []
  @State private var pendingRoomId: String = RoomTaxonomy.defaultRoomId
  @State private var pendingFloorId: String = FloorTaxonomy.defaultFloorId

  private let columns: [GridItem] = [
    GridItem(.flexible(), spacing: 8),
    GridItem(.flexible(), spacing: 8),
    GridItem(.flexible(), spacing: 8)
  ]

  private var showsPhotoLibrarySaveAction: Bool {
    AppFeatureFlags.visiblePhotoLibrarySaveEnabled
      || (AppFeatureFlags.supportToolsUnlockEnabled && supportToolsUnlocked)
  }

  private var uploadButtonTitle: String {
    if selectedSeriesIds.isEmpty {
      return uploadableSeriesCount > 0
        ? l10nFormat("gallery.upload.prepare.count.format", uploadableSeriesCount)
        : l10n("gallery.upload.prepare")
    }
    if selectedSeriesIds.count < uploadableSeriesCount {
      return "Vorbereiten (\(selectedSeriesIds.count) von \(uploadableSeriesCount))"
    }
    return l10nFormat("gallery.upload.prepare.count.format", selectedSeriesIds.count)
  }

  private var selectedUploadScopeSeriesIds: Set<UUID>? {
    selectedSeriesIds.isEmpty ? nil : selectedSeriesIds
  }

  var body: some View {
    galleryRoot
      .onAppear(perform: handleAppear)
      .onChange(of: pendingExternalConnectURL) { _, _ in
        consumePendingExternalConnectURL()
      }
      .sheet(item: $selectedSeries) { series in
        GallerySeriesView(series: series)
      }
      .sheet(isPresented: $isUploadPresented, onDismiss: {
        uploadInitialConnectURL = nil
      }) {
        UploadQueueView(
          uploadScopeSeriesIds: selectedUploadScopeSeriesIds,
          initialConnectURL: uploadInitialConnectURL
        )
      }
      .sheet(isPresented: $isAssignJobPresented) {
        JobSelectionSheet(
          title: l10n("gallery.assignJob.title"),
          subtitle: l10nFormat("gallery.assignJob.subtitle.format", selectedSeriesIds.count),
          allowsClear: true,
          clearLabel: l10n("gallery.assignJob.clear"),
          requiresSelection: false,
          onSelect: { job in assignSelectedSeries(to: job) },
          onClear: { assignSelectedSeries(to: nil) }
        )
        .environmentObject(authService)
        .environmentObject(settings)
      }
      .sheet(isPresented: $isCurrentJobPickerPresented) {
        JobSelectionSheet(
          title: l10n("start.jobs.sheet.title"),
          subtitle: l10n("gallery.currentJob.subtitle"),
          allowsClear: true,
          clearLabel: l10n("gallery.currentJob.clear"),
          requiresSelection: false,
          onSelect: { job in applyCurrentJob(job) },
          onClear: { settings.clearCurrentJobSelection() }
        )
        .environmentObject(authService)
        .environmentObject(settings)
      }
      .sheet(isPresented: $isAssignRoomPresented) {
        RoomPickerView(
          selectedRoomId: $pendingRoomId,
          selectedFloorId: $pendingFloorId,
          onDone: applyRoomFloorAssignment
        )
      }
      .sheet(isPresented: $isRecoveryDocumentExportPresented, onDismiss: cleanupRecoveryStagingDirectory) {
        DocumentExportSheet(
          exportURLs: recoveryExportURLs,
          onComplete: { completed in
            isRecoveryDocumentExportPresented = false
            recoveryMessage = completed
              ? l10n("gallery.recovery.exportComplete")
              : l10n("gallery.recovery.exportCancelled")
            cleanupRecoveryStagingDirectory()
          }
        )
      }
      .alert(l10n("gallery.delete.title"), isPresented: Binding(
        get: { pendingDeleteSeries != nil },
        set: { if !$0 { pendingDeleteSeries = nil } }
      )) {
        Button(l10n("common.delete"), role: .destructive) {
          guard !uploadQueue.isUploading else { return }
          guard let series = pendingDeleteSeries else { return }
          for record in series.records {
            uploadQueue.deleteRecord(record.id, deleteFile: true)
          }
          pendingDeleteSeries = nil
        }
        Button(l10n("common.cancel"), role: .cancel) {
          pendingDeleteSeries = nil
        }
      } message: {
        Text(l10n("gallery.delete.message"))
      }
      .alert(l10n("gallery.discardSelected.title"), isPresented: Binding(
        get: { !pendingDeleteSeriesIds.isEmpty },
        set: { if !$0 { pendingDeleteSeriesIds.removeAll() } }
      )) {
        Button(l10n("gallery.discard.confirm"), role: .destructive) {
          deleteSeries(withIds: pendingDeleteSeriesIds)
          pendingDeleteSeriesIds.removeAll()
        }
        Button(l10n("common.cancel"), role: .cancel) {
          pendingDeleteSeriesIds.removeAll()
        }
      } message: {
        Text(l10nFormat("gallery.discardSelected.message.format", pendingDeleteSeriesIds.count))
      }
      .alert(l10n("gallery.savePhotos"), isPresented: Binding(
        get: { photoSaveStatusMessage != nil },
        set: { if !$0 { photoSaveStatusMessage = nil } }
      )) {
        Button(l10n("common.ok"), role: .cancel) {
          photoSaveStatusMessage = nil
        }
      } message: {
        Text(photoSaveStatusMessage ?? "")
      }
      .alert(l10n("gallery.recovery.failed"), isPresented: Binding(
        get: { recoveryErrorMessage != nil },
        set: { if !$0 { recoveryErrorMessage = nil } }
      )) {
        Button(l10n("common.ok"), role: .cancel) {
          recoveryErrorMessage = nil
        }
      } message: {
        Text(recoveryErrorMessage ?? "")
      }
      .alert("Lokale Altdateien löschen?", isPresented: $isOrphanCleanupPromptPresented) {
        Button(l10n("common.cancel"), role: .cancel) {}
        Button(l10n("common.delete"), role: .destructive) {
          cleanupOrphanedLocalCaptureFiles()
        }
      } message: {
        Text("\(uploadQueue.localRecoveryFileCount) lokale Dateien ohne Upload-Liste werden vom Telefon entfernt. Bereits uploadbare Galerie-Einträge bleiben geschützt.")
      }
      .keyboardDoneToolbar()
      .dismissKeyboardOnTap()
  }

  private var galleryRoot: some View {
    ZStack {
      Palette.background.ignoresSafeArea()
      VStack(spacing: 0) {
        header
        galleryScroll
      }

      if isRecoveryPreparing {
        recoveryPreparationOverlay
          .transition(.opacity)
          .zIndex(10)
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      galleryBottomNav
    }
  }

  private var galleryScroll: some View {
    ScrollView {
      if groupedSeries.isEmpty {
        emptyGalleryState
      } else {
        gallerySeriesList
      }
    }
    .scrollDismissesKeyboard(.interactively)
    .dismissKeyboardOnTap()
  }

  private var emptyGalleryState: some View {
    let hasRecoveryFiles = uploadQueue.localRecoveryFileCount > 0
    let noticeAlreadyShowsRecoveryActions = hasRecoveryFiles && uploadQueue.latestNotice != nil

    return VStack(spacing: 8) {
      Image(systemName: hasRecoveryFiles ? "externaldrive.badge.exclamationmark" : "photo.on.rectangle.angled")
        .font(.system(size: 28))
        .foregroundStyle(Palette.body)
      Text(hasRecoveryFiles ? l10n("gallery.empty.localFiles.title") : l10n("gallery.empty.noCaptures.title"))
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(Palette.title)
      Text(
        hasRecoveryFiles
          ? l10n("gallery.empty.localFiles.body")
          : l10n("gallery.empty.noCaptures.body")
      )
        .font(.system(size: 12))
        .foregroundStyle(Palette.body)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
      if hasRecoveryFiles && !noticeAlreadyShowsRecoveryActions {
        Text("Lokale Aufnahmen wurden gefunden. Bitte im Upload-Bereich fortfahren oder den Support kontaktieren, falls Motive fehlen.")
          .font(.system(size: 12))
          .foregroundStyle(Palette.body)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 24)

        localRecoveryKindSummary
          .padding(.horizontal, 24)

        HStack(spacing: 10) {
          Button {
            presentRecoveryFileListExport()
          } label: {
            Label("Dateiliste sichern", systemImage: "doc.text")
              .font(.system(size: 12, weight: .semibold))
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
          .disabled(isRecoveryPreparing)

          Button(role: .destructive) {
            isOrphanCleanupPromptPresented = true
          } label: {
            Label("Altdateien löschen", systemImage: "trash")
              .font(.system(size: 12, weight: .semibold))
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .disabled(isRecoveryPreparing)
        }
        .padding(.horizontal, 24)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 280)
    .padding(.top, 40)
  }

  private var gallerySeriesList: some View {
    VStack(alignment: .leading, spacing: 18) {
      ForEach(groupedSeries, id: \.key) { group in
        VStack(alignment: .leading, spacing: 10) {
          galleryJobHeader(for: group)

          if !collapsedJobGroupKeys.contains(group.key) {
            LazyVGrid(columns: columns, spacing: 8) {
              ForEach(group.series) { series in
                galleryTile(for: series)
              }
            }
            .padding(.horizontal, 12)
          }
        }
      }
    }
    .padding(.bottom, 24)
  }

  private func galleryJobHeader(for group: GallerySeriesGroup) -> some View {
    let isCollapsed = collapsedJobGroupKeys.contains(group.key)
    return VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 10) {
          Button {
            toggleJobGroup(group.key)
          } label: {
            HStack(spacing: 10) {
              Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Palette.lightBlue)
                .frame(width: 18)

              VStack(alignment: .leading, spacing: 4) {
                Text(group.title)
                  .font(.pixInter(size: 14, weight: .semibold))
                  .foregroundStyle(Palette.title)
                  .lineLimit(1)

                Text(galleryJobSummary(for: group))
                  .font(.system(size: 11, weight: .medium))
                  .foregroundStyle(Palette.body)
                  .lineLimit(1)
              }
            }
          }
          .buttonStyle(.plain)

          Spacer(minLength: 8)

          if group.needsJobAssignment {
            Button {
              presentJobAssignment(for: group)
            } label: {
              Label("Job zuweisen", systemImage: "briefcase.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.primary)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(Palette.lightBlue)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("gallery.assignUnassignedGroup")
          }
        }

        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            if group.isOlder {
              galleryStatusPill(
                title: l10n("gallery.job.old"),
                tint: Palette.body
              )
            }
            if group.openMotifCount > 0 {
              galleryStatusPill(
                title: l10nFormat("gallery.job.open.count.format", group.openMotifCount),
                tint: Palette.accent
              )
            }
            if group.uploadedMotifCount > 0 {
              galleryStatusPill(
                title: l10nFormat("gallery.job.uploaded.count.format", group.uploadedMotifCount),
                tint: Color.green.opacity(0.86)
              )
            }
            if group.canDeleteLocalCopies {
              galleryStatusPill(
                title: l10n("gallery.job.canDeleteLocal"),
                tint: Palette.lightBlue
              )
            }
            if group.failedMotifCount > 0 {
              galleryStatusPill(
                title: l10nFormat("gallery.job.failed.count.format", group.failedMotifCount),
                tint: Color.red.opacity(0.86)
              )
            }
            if isMultiSelectEnabled {
              galleryJobSelectionButton(for: group)
            }
          }
        }
        .padding(.leading, 28)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 11)
      .background(Palette.panelSecondary)
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(Palette.border, lineWidth: 1)
      )
      .padding(.horizontal, 12)
  }

  private func galleryStatusPill(title: String, tint: Color) -> some View {
    Text(title)
      .font(.system(size: 10, weight: .semibold))
      .foregroundStyle(tint)
      .padding(.horizontal, 7)
      .padding(.vertical, 4)
      .background(tint.opacity(0.14))
      .clipShape(Capsule())
  }

  private func galleryJobSelectionButton(for group: GallerySeriesGroup) -> some View {
    let isFullySelected = isJobGroupFullySelected(group)
    return Button {
      toggleSelection(for: group)
    } label: {
      Label(
        isFullySelected ? l10n("gallery.selection.clearJob") : l10n("gallery.selection.selectJob"),
        systemImage: isFullySelected ? "minus.circle.fill" : "checkmark.circle.fill"
      )
      .font(.system(size: 13, weight: .semibold))
      .foregroundStyle(isFullySelected ? Palette.body : Palette.lightBlue)
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .frame(minHeight: 44)
      .background((isFullySelected ? Palette.body : Palette.lightBlue).opacity(0.14))
      .clipShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("gallery.selection.toggleJob.\(group.accessibilityKey)")
  }

  private var galleryBottomNav: some View {
    BottomNavBar(selected: .gallery) { tab in
      switch tab {
      case .start: onNavigate(.start)
      case .help: onNavigate(.help)
      case .sunPlan: onNavigate(.sunPlan)
      case .camera: onNavigate(.camera)
      case .panorama: onNavigate(AppFeatureFlags.secondaryCaptureScreen)
      case .gallery: onNavigate(.gallery)
      case .manual: onNavigate(.settings)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
  }

  private func handleAppear() {
    consumePendingExternalConnectURL()
    uploadQueue.refreshLocalRecoveryFileCount()
    if settings.selectedJobId != nil {
      settings.touchCurrentJobActivity(userScope: authService.recentJobScope)
    }
  }

  private func consumePendingExternalConnectURL() {
    guard let rawURL = pendingExternalConnectURL?.trimmingCharacters(in: .whitespacesAndNewlines),
          !rawURL.isEmpty else {
      return
    }
    uploadInitialConnectURL = rawURL
    pendingExternalConnectURL = nil
    isUploadPresented = true
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .center, spacing: 12) {
        Text(l10n("bottom.gallery"))
          .font(.pixInter(size: 24, weight: .light))
          .tracking(0.8)
          .foregroundStyle(Palette.title)
          .lineLimit(1)
          .minimumScaleFactor(0.85)
        Spacer()
        Button(isMultiSelectEnabled ? l10n("common.done") : l10n("gallery.select")) {
          toggleMultiSelect()
        }
        .accessibilityIdentifier("gallery.select.toggle")
        .font(.pixInter(size: 12, weight: .regular))
        .foregroundStyle(Palette.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Palette.pink)
        .clipShape(Capsule())
      }
      if isMultiSelectEnabled {
        selectionActionBar
      } else {
        HStack(spacing: 8) {
          Button(uploadQueue.isUploading ? l10n("gallery.upload.running") : uploadButtonTitle) {
            isUploadPresented = true
          }
          .accessibilityIdentifier("gallery.upload.prepare")
          .font(.pixInter(size: 12, weight: .regular))
          .foregroundStyle(Color.black.opacity(0.82))
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(uploadQueue.isUploading ? Palette.lightBlue : Palette.accent)
          .clipShape(Capsule())
          if showsPhotoLibrarySaveAction {
            Button(NSLocalizedString("gallery.savePhotos", comment: "Save to Photos")) {
              saveSeriesToPhotos()
            }
            .disabled(selectedSeriesIds.isEmpty)
            .font(.pixInter(size: 12, weight: .regular))
            .foregroundStyle(selectedSeriesIds.isEmpty ? Palette.body : Palette.title)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(selectedSeriesIds.isEmpty ? Palette.panel : Palette.panelSecondary)
            .clipShape(Capsule())
          }
          Spacer(minLength: 0)
        }
      }
      selectedUploadScopeNotice
      if uploadQueue.isUploading, let progress = uploadQueue.uploadProgress {
        liveUploadStatusCard(progress)
      }
      if let notice = uploadQueue.latestNotice {
        HStack(alignment: .top, spacing: 10) {
          Image(systemName: noticeIcon(for: notice.kind))
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(noticeColor(for: notice.kind))
            .padding(.top, 2)

          VStack(alignment: .leading, spacing: 4) {
            Text(noticeTitle(for: notice))
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(Palette.title)
            Text(notice.message)
              .font(.system(size: 12))
              .foregroundStyle(Palette.body)
              .fixedSize(horizontal: false, vertical: true)
          }

          Spacer(minLength: 8)

          Button {
            uploadQueue.clearLatestNotice()
          } label: {
            Image(systemName: "xmark")
              .font(.system(size: 11, weight: .bold))
              .foregroundStyle(Palette.body)
              .padding(8)
              .background(Palette.panel.opacity(0.9))
              .clipShape(Circle())
          }
        }
        .padding(12)
        .background(
          RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Palette.panelSecondary)
        )
      }
      HStack(spacing: 10) {
        filterChip(title: l10n("gallery.filter.all"), isSelected: filter == .all) { filter = .all }
        filterChip(title: l10n("gallery.filter.open"), isSelected: filter == .open) { filter = .open }
        filterChip(title: l10n("gallery.filter.uploaded"), isSelected: filter == .uploaded) { filter = .uploaded }
        Spacer(minLength: 0)
      }
      HStack(spacing: 10) {
        currentJobButton()
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }

  private var selectionActionBar: some View {
    let disabled = selectedSeriesIds.isEmpty
    let columns = [
      GridItem(.flexible(), spacing: 8),
      GridItem(.flexible(), spacing: 8)
    ]

    return LazyVGrid(columns: columns, spacing: 8) {
      selectionActionButton(
        title: selectedSeriesIds.isEmpty ? l10n("gallery.upload.prepare.short") : l10nFormat("gallery.upload.prepare.count.format", selectedSeriesIds.count),
        systemImage: "arrow.up.circle.fill",
        foreground: Color.black.opacity(0.82),
        background: disabled ? Palette.panelSecondary : Palette.accent,
        disabled: disabled || uploadQueue.isUploading
      ) {
        isUploadPresented = true
      }
      .accessibilityIdentifier("gallery.selection.prepareUpload")

      selectionActionButton(
        title: l10n("gallery.assignJob.title"),
        systemImage: "briefcase.fill",
        foreground: Palette.primary,
        background: disabled ? Palette.panelSecondary : Palette.lightBlue,
        disabled: disabled
      ) {
        isAssignJobPresented = true
      }

      selectionActionButton(
        title: l10n("gallery.assignRoom.title"),
        systemImage: "rectangle.3.group.fill",
        foreground: Color.black.opacity(0.8),
        background: disabled ? Palette.panelSecondary : Palette.accent,
        disabled: disabled
      ) {
        presentRoomFloorPicker(for: selectedSeriesIds)
      }

      selectionActionButton(
        title: selectedSeriesIds.isEmpty ? l10n("gallery.discard.short") : l10nFormat("gallery.discard.count.format", selectedSeriesIds.count),
        systemImage: "trash.fill",
        foreground: Color.black.opacity(0.8),
        background: disabled ? Palette.panelSecondary : PixBrand.danger,
        disabled: disabled
      ) {
        deleteSelectedSeries()
      }

      if showsPhotoLibrarySaveAction {
        selectionActionButton(
          title: NSLocalizedString("gallery.savePhotos", comment: "Save to Photos"),
          systemImage: "square.and.arrow.down.fill",
          foreground: disabled ? Palette.body : Palette.title,
          background: disabled ? Palette.panel : Palette.panelSecondary,
          disabled: disabled
        ) {
          saveSeriesToPhotos()
        }
      }
    }
  }

  private func selectionActionButton(
    title: String,
    systemImage: String,
    foreground: Color,
    background: Color,
    disabled: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: systemImage)
          .font(.system(size: 13, weight: .semibold))
        Text(title)
          .font(.pixInter(size: 12, weight: .regular))
          .lineLimit(1)
          .minimumScaleFactor(0.72)
        Spacer(minLength: 0)
      }
      .foregroundStyle(disabled ? Palette.body : foreground)
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity, minHeight: 42)
      .background(background)
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .buttonStyle(.plain)
    .disabled(disabled)
    .opacity(disabled ? 0.62 : 1.0)
  }

  @ViewBuilder
  private var selectedUploadScopeNotice: some View {
    if !isMultiSelectEnabled, !selectedSeriesIds.isEmpty {
      let selectedUploadableCount = selectedSeriesIds.intersection(uploadableSeriesIds).count
      let selectionText = selectedUploadableCount < uploadableSeriesCount
        ? "\(selectedUploadableCount) von \(uploadableSeriesCount) Motiven für den nächsten Upload ausgewählt"
        : l10nFormat("gallery.selection.notice.format", selectedUploadableCount)
      HStack(alignment: .top, spacing: 8) {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Palette.lightBlue)
          .padding(.top, 1)
        VStack(alignment: .leading, spacing: 6) {
          Text(selectionText)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Palette.body)
            .lineLimit(2)
          HStack(spacing: 12) {
            if selectedUploadableCount < uploadableSeriesCount {
              Button("Alle \(uploadableSeriesCount) wählen") {
                selectedSeriesIds = uploadableSeriesIds
              }
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(Palette.lightBlue)
            }
            Button(l10n("gallery.selection.clear")) {
              selectedSeriesIds.removeAll()
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Palette.pink)
          }
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(Palette.panelSecondary)
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
  }

  private func liveUploadStatusCard(_ progress: PixcaptureUploadProgress) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        ProgressView()
          .tint(liveUploadTint(for: progress.phase))
        VStack(alignment: .leading, spacing: 2) {
          Text(liveUploadTitle(for: progress.phase))
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Palette.title)
          Text(liveUploadUserDetail(for: progress))
            .font(.system(size: 12))
            .foregroundStyle(Palette.body)
            .lineLimit(2)
        }
        Spacer(minLength: 8)
        Text(progress.mode.displayName)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(liveUploadTint(for: progress.phase))
          .padding(.horizontal, 9)
          .padding(.vertical, 5)
          .background(liveUploadTint(for: progress.phase).opacity(0.14))
          .clipShape(Capsule())
      }

      if progress.phase == .waitingForApproval {
        ProgressView()
          .tint(liveUploadTint(for: progress.phase))
      } else {
        ProgressView(value: progress.fractionCompleted)
          .tint(liveUploadTint(for: progress.phase))
      }

      HStack {
        Text(liveUploadMotifText(for: progress))
        Spacer()
        Text("\(formatUploadBytes(progress.bytesSent)) / \(formatUploadBytes(max(progress.bytesTotal, progress.bytesSent)))")
      }
      .font(.system(size: 11))
      .foregroundStyle(Palette.body)
    }
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(Palette.panelSecondary)
        .overlay(
          RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(liveUploadTint(for: progress.phase).opacity(0.35), lineWidth: 1)
        )
    )
  }

  private var liveUploadMotifCount: Int {
    let records = uploadQueue.records.filter { record in
      record.status == .pending || record.status == .failed || record.status == .uploading
    }
    return Set(records.map(\.seriesId)).count
  }

  private func liveUploadMotifText(for progress: PixcaptureUploadProgress) -> String {
    let count = liveUploadMotifCount
    let label = count == 1 ? "Motiv" : "Motive"
    switch progress.phase {
    case .completed:
      return count > 0 ? "\(count) \(label) uebertragen" : "Upload abgeschlossen"
    case .failed:
      return count > 0 ? "\(count) \(label) betroffen" : "Upload pruefen"
    default:
      return count > 0 ? "\(count) \(label)" : "Motive werden uebertragen"
    }
  }

  private func liveUploadUserDetail(for progress: PixcaptureUploadProgress) -> String {
    switch progress.phase {
    case .preparing, .connecting, .waitingForApproval:
      return progress.detail ?? "Upload wird vorbereitet."
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
      return progress.detail ?? "Upload-Status wird aktualisiert."
    }
  }

  private func liveUploadTitle(for phase: PixcaptureUploadPhase) -> String {
    switch phase {
    case .preparing:
      return "Upload wird vorbereitet"
    case .connecting:
      return "Verbindung wird aufgebaut"
    case .waitingForApproval:
      return "Warte auf Startsignal"
    case .uploading:
      return "Daten werden übertragen"
    case .finalizing:
      return "Server prüft Upload"
    case .completed:
      return "Upload abgeschlossen"
    case .failed:
      return "Upload fehlgeschlagen"
    }
  }

  private func liveUploadTint(for phase: PixcaptureUploadPhase) -> Color {
    switch phase {
    case .preparing, .connecting:
      return Palette.lightBlue
    case .waitingForApproval:
      return Color.orange.opacity(0.9)
    case .uploading:
      return Palette.pink
    case .finalizing, .completed:
      return Color.green.opacity(0.85)
    case .failed:
      return Color.red.opacity(0.85)
    }
  }

  private func formatUploadBytes(_ bytes: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
  }

  private func noticeTitle(for notice: UploadQueueNotice) -> String {
    if notice.message.hasPrefix("Kabel-Option bereit")
      || notice.message.hasPrefix("WLAN-Option bereit") {
      return "Lokaler Eingang wartet"
    }
    switch notice.kind {
    case .success:
      return "Upload abgeschlossen"
    case .warning:
      return "Upload mit Hinweisen"
    case .error:
      return "Upload fehlgeschlagen"
    }
  }

  private func noticeIcon(for kind: UploadQueueNotice.Kind) -> String {
    switch kind {
    case .success:
      return "checkmark.circle.fill"
    case .warning:
      return "exclamationmark.triangle.fill"
    case .error:
      return "xmark.octagon.fill"
    }
  }

  private func noticeColor(for kind: UploadQueueNotice.Kind) -> Color {
    switch kind {
    case .success:
      return Color.green.opacity(0.85)
    case .warning:
      return Color.orange.opacity(0.9)
    case .error:
      return Color.red.opacity(0.85)
    }
  }

  @ViewBuilder
  private var localRecoveryKindSummary: some View {
    let diagnostics = uploadQueue.localStorageDiagnostics()
    let pills = localRecoveryKindPills(for: diagnostics)

    if diagnostics.localFileCount > 0 && !pills.isEmpty {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(pills, id: \.self) { text in
            Text(text)
              .font(.caption2.monospacedDigit())
              .foregroundStyle(Palette.body)
              .padding(.horizontal, 8)
              .padding(.vertical, 5)
              .background(Palette.panel.opacity(0.9))
              .clipShape(Capsule())
              .overlay(
                Capsule().stroke(Palette.border, lineWidth: 1)
              )
          }
        }
        .padding(.horizontal, 2)
      }
    }
  }

  private func localRecoveryKindPills(for diagnostics: LocalCaptureStorageDiagnostics) -> [String] {
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

        Text("Danach oeffnet sich automatisch der Dateien-Dialog. Dort kannst du das Paket sichern oder teilen.")
          .font(.footnote)
          .foregroundStyle(Color.white.opacity(0.72))

        if let recoveryMessage {
          Text(recoveryMessage)
            .font(.footnote)
            .foregroundStyle(Color.white.opacity(0.72))
        }
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
    recoveryMessage = l10n("gallery.recovery.fileListPreparing")
    recoveryPreparationTitle = l10n("gallery.recovery.fileListPreparing")
    recoveryPreparationDetail = l10n("gallery.recovery.portalDetail")
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
        recoveryPreparationDetail = l10n("gallery.recovery.portalUploading")
        let uploaded = await authService.uploadSupportFileList(
          itemURLs: preparedExport.itemURLs,
          localFileCount: localFileCount,
          queueRecordCount: records.count
        )
        isRecoveryPreparing = false
        if uploaded {
          recoveryMessage = authService.lastInfoMessage ?? l10n("gallery.recovery.portalComplete")
        } else {
          recoveryErrorMessage = authService.lastError ?? l10n("gallery.recovery.portalFailed")
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

  private func cleanupRecoveryStagingDirectory() {
    if let recoveryStagingDirectoryURL {
      try? FileManager.default.removeItem(at: recoveryStagingDirectoryURL)
      self.recoveryStagingDirectoryURL = nil
    }
    recoveryExportURLs = []
  }

  private func cleanupOrphanedLocalCaptureFiles() {
    _ = uploadQueue.deleteOrphanedLocalCaptureFiles()
  }

  private func restoreLocalCaptureRecords() {
    let jobLabel = settings.jobLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    let fallbackLabel = jobLabel.isEmpty ? "Recovery" : jobLabel
    _ = uploadQueue.recoverLocalCaptureRecords(
      jobLabel: fallbackLabel,
      jobId: settings.selectedJobId
    )
  }

  private func currentJobButton() -> some View {
    let hasJob = !settings.jobLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let jobTitle = hasJob ? settings.jobLabel : l10n("gallery.currentJob.choose")
    return Button {
      isCurrentJobPickerPresented = true
    } label: {
      HStack(spacing: 8) {
        Image(systemName: "briefcase.fill")
          .font(.system(size: 11, weight: .semibold))
        VStack(alignment: .leading, spacing: 2) {
          Text(hasJob ? l10n("gallery.currentJob.active") : l10n("gallery.currentJob.label"))
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Palette.body)
          Text(jobTitle)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(hasJob ? Palette.pink : Palette.title)
            .lineLimit(1)
        }
        Spacer(minLength: 8)
        Image(systemName: "plus.circle")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Palette.lightBlue)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 9)
      .background(Palette.panel)
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(Palette.border, lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
  }

  private var seriesGroups: [GallerySeries] {
    let existing = uploadQueue.records.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
    let grouped = Dictionary(grouping: existing) { $0.seriesId }
    return grouped
      .map { key, records in
        GallerySeries(id: key, records: records.sorted(by: { $0.createdAt > $1.createdAt }))
      }
      .sorted(by: { $0.latestDate > $1.latestDate })
  }

  private var uploadableSeriesIds: Set<UUID> {
    Set(seriesGroups.filter { $0.aggregateStatus != .uploaded }.map(\.id))
  }

  private var uploadableSeriesCount: Int {
    uploadableSeriesIds.count
  }

  private var filteredSeries: [GallerySeries] {
    switch filter {
    case .all:
      return seriesGroups
    case .open:
      return seriesGroups.filter { $0.aggregateStatus != .uploaded }
    case .uploaded:
      return seriesGroups.filter { $0.aggregateStatus == .uploaded }
    }
  }

  private var groupedSeries: [GallerySeriesGroup] {
    let grouped = Dictionary(grouping: filteredSeries) { series in
      let label = series.jobLabel.trimmingCharacters(in: .whitespacesAndNewlines)
      return label.isEmpty ? "Ohne Job" : label
    }

    let groups = grouped.map { key, series in
      GallerySeriesGroup(jobLabel: key, series: series.sorted(by: { $0.latestDate > $1.latestDate }))
    }

    return groups.sorted(by: { $0.latestDate > $1.latestDate })
  }

  private func galleryTile(for series: GallerySeries) -> some View {
    let record = series.displayRecord
    let isSelected = selectedSeriesIds.contains(series.id)
    let statusColor: Color = {
      if !series.metadataReady { return .orange }
      switch series.aggregateStatus {
      case .pending: return .yellow
      case .uploading: return .blue
      case .uploaded: return .green
      case .failed: return .red
      }
    }()

    return VStack(spacing: 6) {
      ZStack {
        Group {
          if let record {
            thumbnail(for: record)
          } else {
            Rectangle()
              .fill(Color.gray.opacity(0.1))
          }
        }
          .aspectRatio(1, contentMode: .fit)
          .clipShape(RoundedRectangle(cornerRadius: 10))
          .overlay(
            RoundedRectangle(cornerRadius: 10)
              .stroke(Palette.border, lineWidth: 1)
          )
          .overlay(
            RoundedRectangle(cornerRadius: 10)
              .stroke(isSelected ? Palette.lightBlue : Color.clear, lineWidth: 2)
          )
      }
      .overlay(alignment: .topTrailing) {
        Circle()
          .fill(statusColor)
          .frame(width: 8, height: 8)
          .padding(8)
      }
      .overlay(alignment: .topLeading) {
        if series.captureMode == .darkRoom {
          HStack(spacing: 4) {
            Image(systemName: "moon.stars.fill")
              .font(.system(size: 9, weight: .semibold))
            Text(NSLocalizedString("gallery.captureMode.darkRoom.short", comment: "Dark room short label"))
              .font(.system(size: 10, weight: .bold))
          }
          .foregroundStyle(.white)
          .padding(.horizontal, 6)
          .padding(.vertical, 4)
          .background(Color.black.opacity(0.6))
          .clipShape(Capsule())
          .padding(6)
        } else if series.records.count > 1 {
          HStack(spacing: 4) {
            Image(systemName: "square.stack.3d.up")
              .font(.system(size: 9, weight: .semibold))
            Text("\(series.records.count)x")
              .font(.system(size: 10, weight: .bold))
          }
          .foregroundStyle(.white)
          .padding(.horizontal, 6)
          .padding(.vertical, 4)
          .background(Color.black.opacity(0.6))
          .clipShape(Capsule())
          .padding(6)
        }
      }
      .overlay(alignment: .bottomTrailing) {
        if !isMultiSelectEnabled && !uploadQueue.isUploading {
          Button {
            pendingDeleteSeries = series
          } label: {
            Image(systemName: "trash")
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(.white)
              .padding(6)
              .background(Color.black.opacity(0.6))
              .clipShape(Circle())
          }
          .padding(6)
        }
      }
      .overlay(alignment: .bottomLeading) {
        if isMultiSelectEnabled {
          Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isSelected ? AppTheme.primary : Color.white.opacity(0.9))
            .padding(6)
        }
      }
      if let record {
        Text("\(RoomTaxonomy.room(id: record.roomId).displayName(language: settings.appLanguage)) · \(FloorTaxonomy.floor(id: record.floorId).shortDisplayName(language: settings.appLanguage))")
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(Palette.title)
          .lineLimit(1)
        Text(String(format: NSLocalizedString("motif.format", comment: "Motif label"), record.seriesIndex))
          .font(.system(size: 9))
          .foregroundStyle(Palette.body)
        if series.captureMode == .darkRoom {
          Text(NSLocalizedString("gallery.captureMode.darkRoom.detail", comment: "Dark room detail label"))
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Palette.lightBlue)
        }
        if !series.metadataReady {
          Text("Metadaten laufen")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Palette.accent)
        }
        if series.aggregateStatus == .uploaded {
          Text("Auf Server vorhanden")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Color.green.opacity(0.9))
        }
        Text(String(format: "EV %.1f", record.exposureEV))
          .font(.system(size: 9))
          .foregroundStyle(Palette.body)
      }
    }
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("gallery.series.\(series.id.uuidString)")
    .onTapGesture {
      if isMultiSelectEnabled {
        toggleSelection(for: series.id)
      } else {
        selectedSeries = series
      }
    }
    .contextMenu {
      if !isMultiSelectEnabled {
        Button {
          presentRoomFloorPicker(for: [series.id])
        } label: {
          Text("Raum/Etage ändern")
        }

        Button(role: .destructive) {
          guard !uploadQueue.isUploading else { return }
          for record in series.records {
            uploadQueue.deleteRecord(record.id, deleteFile: true)
          }
        } label: {
          Text("Serie löschen")
        }
      }
    }
  }

  @ViewBuilder
  private func thumbnail(for record: UploadRecord) -> some View {
    if let image = downsampledThumbnail(for: record, maxPixel: 420) {
      Image(uiImage: image)
        .resizable()
        .scaledToFit()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.12))
    } else {
      Rectangle()
        .fill(Color.gray.opacity(0.1))
        .overlay(
          Image(systemName: "photo")
            .foregroundStyle(Color.gray.opacity(0.6))
        )
    }
  }

  private func downsampledThumbnail(for record: UploadRecord, maxPixel: CGFloat) -> UIImage? {
    let url = FileStore.ensurePreviewExists(
      for: record.fileURL,
      captureOrientation: record.captureOrientation,
      sensorRollDegrees: record.sensorRollDegrees
    ) ?? record.fileURL
    let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
    guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
      return nil
    }
    let autoOrientation = settings.galleryOrientationMode == .autoExif
    let thumbOptions: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceThumbnailMaxPixelSize: Int(maxPixel),
      kCGImageSourceCreateThumbnailWithTransform: autoOrientation,
      kCGImageSourceShouldCacheImmediately: false
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
      return nil
    }
    if autoOrientation {
      return UIImage(cgImage: cgImage)
    }
    let properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
    let metadataOrientation = properties[kCGImagePropertyOrientation] as? Int
    let pixelWidth = (properties[kCGImagePropertyPixelWidth] as? Int) ?? cgImage.width
    let pixelHeight = (properties[kCGImagePropertyPixelHeight] as? Int) ?? cgImage.height
    let uiOrientation = manualGalleryOrientation(
      captureOrientation: record.captureOrientation,
      sensorRollDegrees: record.sensorRollDegrees,
      metadataOrientation: metadataOrientation,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight
    )
    return UIImage(cgImage: cgImage, scale: 1.0, orientation: uiOrientation)
  }

  private func deleteUploaded() {
    guard !uploadQueue.isUploading else { return }
    let uploaded = uploadQueue.records.filter { $0.status == .uploaded }
    for record in uploaded {
      uploadQueue.deleteRecord(record.id, deleteFile: true)
    }
  }

  private func toggleMultiSelect() {
    isMultiSelectEnabled.toggle()
  }

  private func toggleJobGroup(_ key: String) {
    if collapsedJobGroupKeys.contains(key) {
      collapsedJobGroupKeys.remove(key)
    } else {
      collapsedJobGroupKeys.insert(key)
    }
  }

  private func presentJobAssignment(for group: GallerySeriesGroup) {
    selectedSeriesIds = Set(group.series.map(\.id))
    isMultiSelectEnabled = true
    isAssignJobPresented = true
  }

  private func galleryJobSummary(for group: GallerySeriesGroup) -> String {
    l10nFormat(
      "gallery.job.summary.format",
      group.motifCount,
      group.fileCount
    )
  }

  private func toggleSelection(for id: UUID) {
    if selectedSeriesIds.contains(id) {
      selectedSeriesIds.remove(id)
    } else {
      selectedSeriesIds.insert(id)
    }
  }

  private func isJobGroupFullySelected(_ group: GallerySeriesGroup) -> Bool {
    let ids = Set(group.series.map(\.id))
    return !ids.isEmpty && ids.isSubset(of: selectedSeriesIds)
  }

  private func toggleSelection(for group: GallerySeriesGroup) {
    let ids = Set(group.series.map(\.id))
    guard !ids.isEmpty else { return }
    if ids.isSubset(of: selectedSeriesIds) {
      selectedSeriesIds.subtract(ids)
    } else {
      selectedSeriesIds.formUnion(ids)
    }
  }

  private func deleteSelectedSeries() {
    guard !uploadQueue.isUploading else { return }
    guard !selectedSeriesIds.isEmpty else { return }
    pendingDeleteSeriesIds = selectedSeriesIds
  }

  private func deleteSeries(withIds idsToDelete: Set<UUID>) {
    guard !uploadQueue.isUploading else { return }
    guard !idsToDelete.isEmpty else { return }
    for series in seriesGroups where idsToDelete.contains(series.id) {
      for record in series.records {
        uploadQueue.deleteRecord(record.id, deleteFile: true)
      }
    }
    selectedSeriesIds.removeAll()
    isMultiSelectEnabled = false
  }

  private func assignSelectedSeries(to job: JobInfo?) {
    guard !selectedSeriesIds.isEmpty else { return }
    uploadQueue.assignJob(
      forSeriesIds: selectedSeriesIds,
      jobLabel: job?.name ?? "",
      jobId: job?.id
    )
    selectedSeriesIds.removeAll()
    isMultiSelectEnabled = false
    isAssignJobPresented = false
  }

  private func applyCurrentJob(_ job: JobInfo) {
    settings.setCurrentJob(job, userScope: authService.recentJobScope)
  }

  private func presentRoomFloorPicker(for seriesIds: Set<UUID>) {
    guard !seriesIds.isEmpty else { return }
    pendingRoomSeriesIds = seriesIds
    if let seed = seedRecord(for: seriesIds) {
      pendingRoomId = seed.roomId
      pendingFloorId = seed.floorId
    } else {
      pendingRoomId = RoomTaxonomy.defaultRoomId
      pendingFloorId = FloorTaxonomy.defaultFloorId
    }
    isAssignRoomPresented = true
  }

  private func seedRecord(for seriesIds: Set<UUID>) -> UploadRecord? {
    for series in seriesGroups where seriesIds.contains(series.id) {
      if let first = series.records.first {
        return first
      }
    }
    return nil
  }

  private func applyRoomFloorAssignment() {
    guard !pendingRoomSeriesIds.isEmpty else { return }
    uploadQueue.assignRoomFloor(
      forSeriesIds: pendingRoomSeriesIds,
      roomId: pendingRoomId,
      floorId: pendingFloorId
    )
    if isMultiSelectEnabled {
      selectedSeriesIds.removeAll()
      isMultiSelectEnabled = false
    }
    pendingRoomSeriesIds.removeAll()
  }

  private func saveSeriesToPhotos() {
    guard isMultiSelectEnabled, !selectedSeriesIds.isEmpty else { return }
    let targetSeries = seriesGroups.filter { selectedSeriesIds.contains($0.id) }
    let targetRecords = targetSeries.flatMap(\.records)
    let urls = targetRecords
      .map(\.fileURL)
      .filter { FileManager.default.fileExists(atPath: $0.path) }
    guard !urls.isEmpty else { return }
    Task {
      let saved = await camera.saveSeriesToPhotoLibrary(urls: urls)
      await MainActor.run {
        if saved {
          uploadQueue.markSavedToPhotos(targetRecords.map(\.id))
          photoSaveStatusMessage = NSLocalizedString("save.photos.success", comment: "")
        } else {
          photoSaveStatusMessage = camera.warningMessage ?? NSLocalizedString("save.photos.failed", comment: "")
          camera.warningMessage = nil
        }
      }
    }
  }

  private func l10n(_ key: String) -> String {
    settings.localized(key)
  }

  private func l10nFormat(_ key: String, _ arguments: CVarArg...) -> String {
    AppLocalizer.localizedFormat(key, language: settings.appLanguage, arguments: arguments)
  }
}

private enum GalleryFilter {
  case all
  case open
  case uploaded
}

private extension GalleryView {
  func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .font(.pixInter(size: 12, weight: .regular))
        .foregroundStyle(isSelected ? Palette.primary : Palette.body)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Palette.lightBlue : Palette.panel)
        .clipShape(Capsule())
        .overlay(
          Capsule().stroke(Palette.border, lineWidth: 1)
        )
    }
  }
}

struct GallerySeriesView: View {
  let series: GallerySeries
  @EnvironmentObject var settings: AppSettings
  @EnvironmentObject var uploadQueue: UploadQueue
  @Environment(\.dismiss) private var dismiss
  @AppStorage("pixcapture.supportToolsUnlocked") private var supportToolsUnlocked = false
  @State private var shareItems: [Any] = []
  @State private var isSharePresented = false
  @State private var shareErrorMessage: String?
  @State private var stagedShareDirectoryURL: URL?
  @State private var pendingMail: PendingMailDraft?
  @State private var documentExportURLs: [URL] = []
  @State private var isDocumentExportPresented = false
  @State private var isRoomPickerPresented = false
  @State private var pendingRoomId: String = RoomTaxonomy.defaultRoomId
  @State private var pendingFloorId: String = FloorTaxonomy.defaultFloorId
  @State private var zoomedRecordId: UUID?
  @State private var imageZoom: CGFloat = 1
  @State private var committedImageZoom: CGFloat = 1
  @State private var imagePan: CGSize = .zero
  @State private var committedImagePan: CGSize = .zero
  @State private var isDiscardConfirmationPresented = false

  private var showsInternalExportTools: Bool {
    AppFeatureFlags.visibleInternalExportEnabled
      || (AppFeatureFlags.supportToolsUnlockEnabled && supportToolsUnlocked)
  }

  private var reviewRecords: [UploadRecord] {
    liveSeries.records.sorted {
      if $0.exposureEV == $1.exposureEV {
        return $0.createdAt < $1.createdAt
      }
      return $0.exposureEV < $1.exposureEV
    }
  }

  private var liveSeries: GallerySeries {
    let records = uploadQueue.records
      .filter { $0.seriesId == series.id && FileManager.default.fileExists(atPath: $0.fileURL.path) }
      .sorted(by: { $0.createdAt > $1.createdAt })
    guard !records.isEmpty else { return series }
    return GallerySeries(id: series.id, records: records)
  }

  private var roomDisplayName: String {
    RoomTaxonomy.room(id: currentRoomId).displayName(language: settings.appLanguage)
  }

  private var floorDisplayName: String {
    FloorTaxonomy.floor(id: currentFloorId).shortDisplayName(language: settings.appLanguage)
  }

  private var currentRoomId: String {
    pendingRoomId
  }

  private var currentFloorId: String {
    pendingFloorId
  }

  var body: some View {
    NavigationStack {
      ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 12) {
          seriesReviewHeader
            .padding(.horizontal, 16)
            .padding(.top, 12)

          GeometryReader { proxy in
            horizontalStackReview(size: proxy.size)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .navigationTitle(liveSeries.title)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          if liveSeries.exifLogURL != nil && showsInternalExportTools {
            Menu {
              Button("JSON teilen") {
                presentJSONShare()
              }

              Button("JSON per Mail") {
                presentJSONMail()
              }

              Button("Interne ZIP teilen") {
                presentInternalDatasetShare()
              }

              Button("Interne ZIP per Mail") {
                presentInternalDatasetMail()
              }

              Button("ZIP in Cloud sichern") {
                presentInternalDatasetCloudExport()
              }
            } label: {
              Label("Export", systemImage: "square.and.arrow.up")
            }
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Fertig") { dismiss() }
        }
      }
    }
    .onAppear {
      syncRoomSeed()
    }
    .sheet(isPresented: $isRoomPickerPresented) {
      RoomPickerView(
        selectedRoomId: $pendingRoomId,
        selectedFloorId: $pendingFloorId,
        onDone: applyRoomFloorAssignment
      )
    }
    .sheet(isPresented: $isSharePresented, onDismiss: cleanupShareStagingDirectory) {
      ShareSheet(
        activityItems: shareItems,
        onComplete: { _ in
          cleanupShareStagingDirectory()
        }
      )
    }
    .sheet(isPresented: $isDocumentExportPresented, onDismiss: cleanupShareStagingDirectory) {
      DocumentExportSheet(
        exportURLs: documentExportURLs,
        onComplete: { _ in
          isDocumentExportPresented = false
          cleanupShareStagingDirectory()
        }
      )
    }
    .sheet(item: $pendingMail, onDismiss: cleanupShareStagingDirectory) { draft in
      MailComposerSheet(
        subject: draft.subject,
        body: draft.message,
        attachments: draft.attachments,
        onComplete: { _, error in
          if let error {
            shareErrorMessage = "Mail-Export fehlgeschlagen: \(error.localizedDescription)"
          }
          pendingMail = nil
          cleanupShareStagingDirectory()
        }
      )
    }
    .alert("Export fehlgeschlagen", isPresented: Binding(
      get: { shareErrorMessage != nil },
      set: { if !$0 { shareErrorMessage = nil } }
    )) {
      Button("OK", role: .cancel) {
        shareErrorMessage = nil
      }
    } message: {
      Text(shareErrorMessage ?? "")
    }
    .alert(l10n("gallery.discardSeries.title"), isPresented: $isDiscardConfirmationPresented) {
      Button(l10n("gallery.discard.confirm"), role: .destructive) {
        discardCurrentSeries()
      }
      Button(l10n("common.cancel"), role: .cancel) {}
    } message: {
      Text(l10nFormat("gallery.discardSeries.message.format", reviewRecords.count))
    }
  }

  private var seriesReviewHeader: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Stack pruefen")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Color.white.opacity(0.92))
        Text("\(reviewRecords.count) Bilder · \(roomDisplayName) · \(floorDisplayName)")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(Color.white.opacity(0.62))
          .lineLimit(1)
      }

      Spacer(minLength: 8)

      Button {
        isRoomPickerPresented = true
      } label: {
        Label("Raum ändern", systemImage: "mappin.and.ellipse")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Color.black.opacity(0.82))
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(PixBrand.orange)
          .clipShape(Capsule())
      }
      .accessibilityIdentifier("gallery.review.room.change")

      Button(role: .destructive) {
        isDiscardConfirmationPresented = true
      } label: {
        Label(l10n("gallery.discard.short"), systemImage: "trash")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(Color.red.opacity(0.72))
          .clipShape(Capsule())
      }
      .disabled(uploadQueue.isUploading)
    }
    .padding(12)
    .background(Color.white.opacity(0.06))
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(Color.white.opacity(0.12), lineWidth: 1)
    )
  }

  private func horizontalStackReview(size: CGSize) -> some View {
    let safeWidth = max(size.width, 1)
    let safeHeight = max(size.height, 1)
    let availableWidth = max(safeWidth - 44, 1)
    let primaryCardSize = reviewCardSize(
      for: reviewRecords.first,
      availableWidth: availableWidth,
      availableHeight: max(safeHeight - 22, 1),
      containerWidth: safeWidth
    )
    let overlapSpacing = -min(primaryCardSize.width * 0.08, 28)

    return ScrollView(.horizontal) {
      LazyHStack(spacing: overlapSpacing) {
        ForEach(Array(reviewRecords.enumerated()), id: \.element.id) { index, record in
          reviewCard(
            record: record,
            index: index,
            total: reviewRecords.count,
            size: reviewCardSize(
              for: record,
              availableWidth: availableWidth,
              availableHeight: max(safeHeight - 22, 1),
              containerWidth: safeWidth
            )
          )
          .scrollTransition(.interactive, axis: .horizontal) { content, phase in
            content
              .scaleEffect(phase.isIdentity ? 1.0 : 0.92)
              .opacity(phase.isIdentity ? 1.0 : 0.72)
              .rotationEffect(.degrees(phase.value * -1.5))
          }
        }
      }
      .scrollTargetLayout()
      .padding(.horizontal, max((safeWidth - primaryCardSize.width) / 2, 16))
      .padding(.vertical, 10)
      .frame(minHeight: safeHeight, alignment: .center)
    }
    .scrollIndicators(.hidden)
    .scrollTargetBehavior(.viewAligned)
  }

  private func reviewCardSize(
    for record: UploadRecord?,
    availableWidth: CGFloat,
    availableHeight: CGFloat,
    containerWidth: CGFloat
  ) -> CGSize {
    let aspect = record.map(imageAspectRatio(for:)) ?? 1
    let isLandscape = aspect >= 1.08
    let widthFraction: CGFloat = isLandscape ? 0.88 : 0.76
    let minWidth: CGFloat = isLandscape ? 300 : 250
    let targetWidth = min(max(containerWidth * widthFraction, minWidth), availableWidth)
    let targetHeight = min(max(targetWidth / max(aspect, 0.1), 180), availableHeight)
    return CGSize(width: targetWidth, height: targetHeight)
  }

  private func reviewCard(
    record: UploadRecord,
    index: Int,
    total: Int,
    size: CGSize
  ) -> some View {
    let isZoomedRecord = zoomedRecordId == record.id
    let zoomScale = isZoomedRecord ? imageZoom : 1
    let panOffset = isZoomedRecord ? imagePan : .zero

    return ZStack(alignment: .topLeading) {
      if let image = displayImage(for: record, maxPixel: 2400) {
        reviewImage(
          image,
          recordId: record.id,
          size: size,
          isZoomedRecord: isZoomedRecord,
          zoomScale: zoomScale,
          panOffset: panOffset
        )
      } else {
        Rectangle()
          .fill(Color.white.opacity(0.08))
          .frame(width: size.width, height: size.height)
          .overlay(
            Image(systemName: "photo")
              .font(.system(size: 32))
              .foregroundStyle(Color.white.opacity(0.45))
          )
      }

      HStack(spacing: 8) {
        Text("\(index + 1)/\(total)")
        Text(String(format: "EV %.1f", record.exposureEV))
      }
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(.white)
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .background(Color.black.opacity(0.58))
      .clipShape(Capsule())
      .padding(12)

      if isZoomedRecord && zoomScale > 1.01 {
        Text("\(Int(zoomScale * 100))%")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 9)
          .padding(.vertical, 6)
          .background(Color.black.opacity(0.55))
          .clipShape(Capsule())
          .padding(12)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
      }
    }
    .frame(width: size.width, height: size.height)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(Color.white.opacity(0.16), lineWidth: 1)
    )
    .shadow(color: .black.opacity(0.32), radius: 18, x: 0, y: 10)
  }

  @ViewBuilder
  private func reviewImage(
    _ image: UIImage,
    recordId: UUID,
    size: CGSize,
    isZoomedRecord: Bool,
    zoomScale: CGFloat,
    panOffset: CGSize
  ) -> some View {
    let imageAspect = displayAspectRatio(for: image)
    let clampedPan = clampReviewPan(panOffset, zoom: zoomScale, cardSize: size, imageAspect: imageAspect)
    let imageView = Image(uiImage: image)
      .resizable()
      .scaledToFit()
      .scaleEffect(zoomScale)
      .offset(clampedPan)
      .frame(width: size.width, height: size.height)
      .background(Color.white.opacity(0.04))
      .clipShape(Rectangle())
      .contentShape(Rectangle())
      .gesture(zoomGesture(for: recordId, cardSize: size, imageAspect: imageAspect))
      .onTapGesture(count: 2) {
        toggleReviewZoom(for: recordId)
      }

    if isZoomedRecord && zoomScale > 1.01 {
      imageView.simultaneousGesture(panGesture(for: recordId, cardSize: size, imageAspect: imageAspect))
    } else {
      imageView
    }
  }

  private func syncRoomSeed() {
    pendingRoomId = liveSeries.records.first?.roomId ?? RoomTaxonomy.defaultRoomId
    pendingFloorId = liveSeries.records.first?.floorId ?? FloorTaxonomy.defaultFloorId
  }

  private func discardCurrentSeries() {
    guard !uploadQueue.isUploading else { return }
    for record in liveSeries.records {
      uploadQueue.deleteRecord(record.id, deleteFile: true)
    }
    dismiss()
  }

  private func l10n(_ key: String) -> String {
    settings.localized(key)
  }

  private func l10nFormat(_ key: String, _ arguments: CVarArg...) -> String {
    AppLocalizer.localizedFormat(key, language: settings.appLanguage, arguments: arguments)
  }

  private func imageAspectRatio(for record: UploadRecord) -> CGFloat {
    let url = FileStore.ensurePreviewExists(
      for: record.fileURL,
      captureOrientation: record.captureOrientation,
      sensorRollDegrees: record.sensorRollDegrees
    ) ?? record.fileURL
    let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
    guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
      return 1
    }
    let properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
    let metadataOrientation = properties[kCGImagePropertyOrientation] as? Int
    let pixelWidth = CGFloat((properties[kCGImagePropertyPixelWidth] as? Int) ?? 1)
    let pixelHeight = CGFloat((properties[kCGImagePropertyPixelHeight] as? Int) ?? 1)
    let autoOrientation = settings.galleryOrientationMode == .autoExif
    let shouldSwapAxes: Bool

    if autoOrientation {
      shouldSwapAxes = metadataOrientation == 6 || metadataOrientation == 8
    } else {
      let uiOrientation = manualGalleryOrientation(
        captureOrientation: record.captureOrientation,
        sensorRollDegrees: record.sensorRollDegrees,
        metadataOrientation: metadataOrientation,
        pixelWidth: Int(pixelWidth),
        pixelHeight: Int(pixelHeight)
      )
      shouldSwapAxes = uiOrientation == .left || uiOrientation == .right
    }

    let displayWidth = shouldSwapAxes ? pixelHeight : pixelWidth
    let displayHeight = shouldSwapAxes ? pixelWidth : pixelHeight
    return max(displayWidth, 1) / max(displayHeight, 1)
  }

  private func displayAspectRatio(for image: UIImage) -> CGFloat {
    let width = max(image.size.width, 1)
    let height = max(image.size.height, 1)
    return width / height
  }

  private func fittedImageSize(imageAspect: CGFloat, in cardSize: CGSize) -> CGSize {
    let safeAspect = max(imageAspect, 0.1)
    let cardAspect = max(cardSize.width, 1) / max(cardSize.height, 1)

    if safeAspect > cardAspect {
      let width = cardSize.width
      return CGSize(width: width, height: width / safeAspect)
    }

    let height = cardSize.height
    return CGSize(width: height * safeAspect, height: height)
  }

  private func clampReviewPan(
    _ pan: CGSize,
    zoom: CGFloat,
    cardSize: CGSize,
    imageAspect: CGFloat
  ) -> CGSize {
    guard zoom > 1.01 else { return .zero }

    let fitSize = fittedImageSize(imageAspect: imageAspect, in: cardSize)
    let scaledWidth = fitSize.width * zoom
    let scaledHeight = fitSize.height * zoom
    let maxX = max((scaledWidth - cardSize.width) / 2, 0)
    let maxY = max((scaledHeight - cardSize.height) / 2, 0)

    return CGSize(
      width: min(max(pan.width, -maxX), maxX),
      height: min(max(pan.height, -maxY), maxY)
    )
  }

  private func zoomGesture(for recordId: UUID, cardSize: CGSize, imageAspect: CGFloat) -> some Gesture {
    MagnificationGesture()
      .onChanged { value in
        if zoomedRecordId != recordId {
          zoomedRecordId = recordId
          committedImageZoom = 1
          committedImagePan = .zero
          imagePan = .zero
        }
        imageZoom = reviewZoomScale(from: value)
        if imageZoom <= 1.01 {
          imagePan = .zero
        } else {
          imagePan = clampReviewPan(imagePan, zoom: imageZoom, cardSize: cardSize, imageAspect: imageAspect)
        }
      }
      .onEnded { _ in
        imageZoom = min(max(imageZoom, 1), 4)
        committedImageZoom = imageZoom
        if imageZoom <= 1.01 {
          resetReviewZoom()
        } else {
          imagePan = clampReviewPan(imagePan, zoom: imageZoom, cardSize: cardSize, imageAspect: imageAspect)
          committedImagePan = imagePan
        }
      }
  }

  private func reviewZoomScale(from magnification: CGFloat) -> CGFloat {
    let zoomGain: CGFloat = 4.0
    let adjustedMagnification = 1 + ((magnification - 1) * zoomGain)
    return min(max(committedImageZoom * adjustedMagnification, 1), 4)
  }

  private func panGesture(for recordId: UUID, cardSize: CGSize, imageAspect: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 4)
      .onChanged { value in
        guard zoomedRecordId == recordId, imageZoom > 1.01 else { return }
        let nextPan = CGSize(
          width: committedImagePan.width + value.translation.width,
          height: committedImagePan.height + value.translation.height
        )
        imagePan = clampReviewPan(nextPan, zoom: imageZoom, cardSize: cardSize, imageAspect: imageAspect)
      }
      .onEnded { _ in
        guard zoomedRecordId == recordId else { return }
        imagePan = clampReviewPan(imagePan, zoom: imageZoom, cardSize: cardSize, imageAspect: imageAspect)
        committedImagePan = imagePan
      }
  }

  private func toggleReviewZoom(for recordId: UUID) {
    if zoomedRecordId == recordId, imageZoom > 1.01 {
      resetReviewZoom()
    } else {
      zoomedRecordId = recordId
      imageZoom = 2
      committedImageZoom = 2
      imagePan = .zero
      committedImagePan = .zero
    }
  }

  private func resetReviewZoom() {
    zoomedRecordId = nil
    imageZoom = 1
    committedImageZoom = 1
    imagePan = .zero
    committedImagePan = .zero
  }

  private func applyRoomFloorAssignment() {
    uploadQueue.assignRoomFloor(
      forSeriesIds: [series.id],
      roomId: pendingRoomId,
      floorId: pendingFloorId
    )
  }

  private func presentJSONShare() {
    cleanupShareStagingDirectory()
    guard let exifLogURL = liveSeries.exifLogURL else { return }
    shareItems = [exifLogURL]
    isSharePresented = true
  }

  private func presentJSONMail() {
    cleanupShareStagingDirectory()
    guard let exifLogURL = liveSeries.exifLogURL else { return }

    do {
      let attachments = [try MailAttachmentData(fileURL: exifLogURL)]
      if MailComposerSheet.canSendMail() {
        pendingMail = PendingMailDraft(
          subject: jsonExportSubject,
          message: jsonExportMessage,
          attachments: attachments
        )
      } else {
        shareItems = [exifLogURL]
        isSharePresented = true
      }
    } catch {
      shareErrorMessage = error.localizedDescription
    }
  }

  private func presentInternalDatasetShare() {
    cleanupShareStagingDirectory()

    do {
      let preparedExport = try FileStore.prepareInternalSeriesZipExport(
        records: liveSeries.records,
        exifLogURL: liveSeries.exifLogURL
      )
      stagedShareDirectoryURL = preparedExport.directoryURL
      shareItems = preparedExport.itemURLs
      isSharePresented = true
    } catch {
      shareErrorMessage = error.localizedDescription
    }
  }

  private func presentInternalDatasetMail() {
    cleanupShareStagingDirectory()

    do {
      let preparedExport = try FileStore.prepareInternalSeriesZipExport(
        records: liveSeries.records,
        exifLogURL: liveSeries.exifLogURL
      )
      stagedShareDirectoryURL = preparedExport.directoryURL

      if MailComposerSheet.canSendMail() {
        let attachments = try preparedExport.itemURLs.map { try MailAttachmentData(fileURL: $0) }
        pendingMail = PendingMailDraft(
          subject: internalExportSubject,
          message: internalExportMessage,
          attachments: attachments
        )
      } else {
        shareItems = preparedExport.itemURLs
        isSharePresented = true
      }
    } catch {
      shareErrorMessage = error.localizedDescription
    }
  }

  private func presentInternalDatasetCloudExport() {
    cleanupShareStagingDirectory()

    do {
      let preparedExport = try FileStore.prepareInternalSeriesZipExport(
        records: liveSeries.records,
        exifLogURL: liveSeries.exifLogURL
      )
      stagedShareDirectoryURL = preparedExport.directoryURL
      documentExportURLs = preparedExport.itemURLs
      isDocumentExportPresented = true
    } catch {
      shareErrorMessage = error.localizedDescription
    }
  }

  private func cleanupShareStagingDirectory() {
    if let stagedShareDirectoryURL {
      try? FileManager.default.removeItem(at: stagedShareDirectoryURL)
      self.stagedShareDirectoryURL = nil
    }
    shareItems = []
    documentExportURLs = []
  }

  private func displayImage(for record: UploadRecord, maxPixel: CGFloat) -> UIImage? {
    let url = FileStore.ensurePreviewExists(
      for: record.fileURL,
      captureOrientation: record.captureOrientation,
      sensorRollDegrees: record.sensorRollDegrees
    ) ?? record.fileURL
    let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
    guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
      return nil
    }
    let autoOrientation = settings.galleryOrientationMode == .autoExif
    let thumbOptions: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceThumbnailMaxPixelSize: Int(maxPixel),
      kCGImageSourceCreateThumbnailWithTransform: autoOrientation,
      kCGImageSourceShouldCacheImmediately: false
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
      return nil
    }
    if autoOrientation {
      return UIImage(cgImage: cgImage)
    }
    let properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
    let metadataOrientation = properties[kCGImagePropertyOrientation] as? Int
    let pixelWidth = (properties[kCGImagePropertyPixelWidth] as? Int) ?? cgImage.width
    let pixelHeight = (properties[kCGImagePropertyPixelHeight] as? Int) ?? cgImage.height
    let uiOrientation = manualGalleryOrientation(
      captureOrientation: record.captureOrientation,
      sensorRollDegrees: record.sensorRollDegrees,
      metadataOrientation: metadataOrientation,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight
    )
    return UIImage(cgImage: cgImage, scale: 1.0, orientation: uiOrientation)
  }

  private var jsonExportSubject: String {
    "PIXCAPTURE JSON \(liveSeries.title)"
  }

  private var jsonExportMessage: String {
    "Im Anhang befinden sich die JSON-Metadaten zu \(liveSeries.title)."
  }

  private var internalExportSubject: String {
    "PIXCAPTURE Export \(liveSeries.title)"
  }

  private var internalExportMessage: String {
    "Im Anhang befindet sich die ZIP-Datei mit Originaldateien und JSON-Metadaten zu \(liveSeries.title)."
  }

  private struct PendingMailDraft: Identifiable {
    let id = UUID()
    let subject: String
    let message: String
    let attachments: [MailAttachmentData]
  }
}

struct GallerySeries: Identifiable {
  let id: UUID
  let records: [UploadRecord]

  var displayRecord: UploadRecord? {
    records.min {
      let left = abs($0.exposureEV)
      let right = abs($1.exposureEV)
      if left == right {
        return $0.createdAt > $1.createdAt
      }
      return left < right
    }
  }

  var latestDate: Date {
    records.map(\.createdAt).max() ?? .distantPast
  }

  var aggregateStatus: UploadRecord.Status {
    if records.contains(where: { $0.status == .failed }) { return .failed }
    if records.contains(where: { $0.status == .uploading }) { return .uploading }
    if records.contains(where: { $0.status == .pending }) { return .pending }
    return .uploaded
  }

  var title: String {
    guard let first = records.first else { return "Serie" }
    let room = RoomTaxonomy.room(id: first.roomId).displayName
    let floor = FloorTaxonomy.floor(id: first.floorId).displayName
    let motif = String(format: NSLocalizedString("motif.format", comment: "Motif label"), first.seriesIndex)
    return "\(room) · \(floor) – \(motif)"
  }

  var jobLabel: String {
    records.first?.jobLabel ?? ""
  }

  var exifLogURL: URL? {
    records.first(where: { $0.exifLogURL != nil })?.exifLogURL
  }

  var metadataReady: Bool {
    records.allSatisfy { $0.metadataReady }
  }

  var captureMode: PhotoCaptureMode {
    records.first?.captureMode ?? .standardBracket
  }

  var hasAssignedJob: Bool {
    records.contains { record in
      if let jobId = record.jobId?.trimmingCharacters(in: .whitespacesAndNewlines),
         !jobId.isEmpty {
        return true
      }

      let label = record.jobLabel.trimmingCharacters(in: .whitespacesAndNewlines)
      if label.isEmpty {
        return false
      }
      return label.compare("Ohne Job", options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame
    }
  }
}

private struct GallerySeriesGroup {
  let jobLabel: String
  let series: [GallerySeries]

  var key: String {
    let trimmed = jobLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "__pixcapture_no_job__" : trimmed.lowercased()
  }

  var accessibilityKey: String {
    key
      .unicodeScalars
      .map { scalar in
        CharacterSet.alphanumerics.contains(scalar) ? Character(scalar).description : "-"
      }
      .joined()
  }

  var title: String {
    let trimmed = jobLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "Ohne Job / Sammelcontainer" : trimmed
  }

  var needsJobAssignment: Bool {
    !series.isEmpty
      && series.allSatisfy {
        !CaptureJobPolicy.hasExplicitAssignment(
          jobId: $0.records.first?.jobId,
          jobLabel: $0.jobLabel
        )
      }
  }

  var latestDate: Date {
    series.map(\.latestDate).max() ?? .distantPast
  }

  var motifCount: Int {
    series.count
  }

  var fileCount: Int {
    series.reduce(0) { $0 + $1.records.count }
  }

  var openMotifCount: Int {
    series.filter { $0.aggregateStatus != .uploaded }.count
  }

  var uploadedMotifCount: Int {
    series.filter { $0.aggregateStatus == .uploaded }.count
  }

  var failedMotifCount: Int {
    series.filter { $0.aggregateStatus == .failed }.count
  }

  var isOlder: Bool {
    Date().timeIntervalSince(latestDate) >= TimeInterval(UploadQueue.uploadedRetentionDays * 24 * 60 * 60)
  }

  var canDeleteLocalCopies: Bool {
    guard !series.isEmpty else { return false }
    guard openMotifCount == 0 else { return false }
    return series.flatMap(\.records).allSatisfy { record in
      guard record.status == .uploaded else { return false }
      let referenceDate = record.uploadedAt ?? record.createdAt
      return Date().timeIntervalSince(referenceDate) >= TimeInterval(UploadQueue.uploadedRetentionDays * 24 * 60 * 60)
    }
  }
}

func manualGalleryOrientation(
  captureOrientation: String?,
  sensorRollDegrees: Double? = nil,
  metadataOrientation: Int? = nil,
  pixelWidth: Int,
  pixelHeight: Int
) -> UIImage.Orientation {
  // Prefer explicit EXIF orientation when available and meaningful.
  if let metadataOrientation, metadataOrientation != 1 {
    switch metadataOrientation {
    case 3:
      return .down
    case 6:
      return .right
    case 8:
      return .left
    default:
      break
    }
  }

  let isPixelPortrait = pixelHeight > pixelWidth
  if let inferredOrientation = FileStore.inferredPreviewOrientation(
    captureOrientation: captureOrientation,
    sensorRollDegrees: sensorRollDegrees
  ) {
    switch inferredOrientation {
    case .portrait:
      return isPixelPortrait ? .up : .right
    case .portraitUpsideDown:
      return isPixelPortrait ? .up : .left
    case .landscapeRight:
      return isPixelPortrait ? .right : .up
    case .landscapeLeft:
      return isPixelPortrait ? .left : .up
    }
  }

  return .up
}
