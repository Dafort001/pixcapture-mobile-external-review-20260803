import SwiftUI
import UIKit

#if canImport(RoomPlan)
import RoomPlan
#endif

struct FloorplanWorkflowView: View {
  var onNavigate: (AppScreen) -> Void

  private enum FloorplanTheme {
    static let primary = Color(red: 42.0 / 255.0, green: 63.0 / 255.0, blue: 104.0 / 255.0)
    static let secondary = Color(red: 108.0 / 255.0, green: 168.0 / 255.0, blue: 200.0 / 255.0)
    static let accent = Color(red: 209.0 / 255.0, green: 94.0 / 255.0, blue: 64.0 / 255.0)
    static let neutral = Color(red: 95.0 / 255.0, green: 100.0 / 255.0, blue: 106.0 / 255.0)
    static let canvas = PixBrand.background
    static let headerTitle = PixBrand.textOnDark
    static let headerBody = PixBrand.textOnDarkSecondary
    static let headerPanel = PixBrand.panel
    static let headerBorder = PixBrand.borderOnDark
    static let blueCard = Color(red: 0.82, green: 0.91, blue: 0.98)
    static let pinkCard = Color(red: 0.97, green: 0.88, blue: 0.92)
    static let warmCard = Color(red: 0.98, green: 0.92, blue: 0.84)
  }

  @EnvironmentObject private var settings: AppSettings
  @EnvironmentObject private var authService: AuthService

  @State private var project: FloorplanProject? = nil
  @State private var isRoomPickerPresented = false
  @State private var isJobPickerPresented = false
  @State private var isRoomPlanCapturePresented = false
  @State private var isComposerPresented = false
  @State private var isFloorScanPresented = false
  @State private var isMeasurePresented = false
  @State private var pendingScanId: UUID? = nil
  @State private var pendingScanRoomId: String = RoomTaxonomy.defaultRoomId
  @State private var pendingScanFloorId: String = FloorTaxonomy.defaultFloorId
  @State private var pendingRoomPlanTrackingSessionId: String? = nil
  @State private var isScanSetupPresented = false
  @State private var scanSetupRoomId: String = RoomTaxonomy.defaultRoomId
  @State private var scanSetupFloorId: String = FloorTaxonomy.defaultFloorId
  @State private var isScanTipsPresented = false
  @State private var isEditScanPresented = false
  @State private var editScanId: UUID? = nil
  @State private var editRoomId: String = RoomTaxonomy.defaultRoomId
  @State private var editFloorId: String = FloorTaxonomy.defaultFloorId
  @State private var exportMessage: String = ""
  @State private var showExportAlert = false
  @State private var showContinueScanAlert = false
  @State private var lastSavedScanLabel = ""
  @State private var shareItems: [Any] = []
  @State private var shareExcludedActivityTypes: [UIActivity.ActivityType]? = nil
  @State private var showShareSheet = false
  @State private var pendingMail: PendingMailDraft? = nil
  @State private var stagedShareDirectoryURL: URL? = nil
  @State private var roomSemanticSummaryByScanId: [UUID: RoomSemanticSummary] = [:]
  @State private var hasFinalizedExportArtifacts = false
  @State private var roomSequenceTrackingProjectKey: String? = nil
  @State private var roomSequenceTrackingFloorId: String? = nil
  @State private var roomSequenceTrackingSessionId: String? = nil

  private var projectKey: String? {
    let trimmed = settings.selectedJobId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
  }

  private var hasProjectContext: Bool {
    projectKey != nil
  }

  private var hasExistingScans: Bool {
    !(project?.roomScans.isEmpty ?? true)
  }

  private var shouldShowOverviewCanvas: Bool {
    hasExistingScans && !isRoomPlanCapturePresented && !isFloorScanPresented && !isComposerPresented
  }

  private var exportDisplayName: String {
    let label = settings.jobLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    if !label.isEmpty {
      return label
    }
    return projectKey ?? l10n("floorplan.noJob")
  }

  private var projectOverview: ProjectOverview {
    guard let project else {
      return ProjectOverview(
        roomCount: 0,
        floorCount: 0,
        totalAreaSqmApprox: 0,
        totalDoorCount: 0,
        totalOpeningCount: 0,
        totalWindowCount: 0
      )
    }

    let floorCount = Set(project.roomScans.map(\.floorId)).count
    let totalArea = project.roomScans.reduce(0.0) { $0 + max(0, $1.metrics.areaSqmApprox) }
    let totals = project.roomScans.reduce(into: (doors: 0, openings: 0, windows: 0)) { partial, scan in
      let summary = roomSemanticSummaryByScanId[scan.id]
      partial.doors += summary?.doorCount ?? 0
      partial.openings += summary?.openingCount ?? 0
      partial.windows += summary?.windowCount ?? 0
    }

    return ProjectOverview(
      roomCount: project.roomScans.count,
      floorCount: floorCount,
      totalAreaSqmApprox: totalArea,
      totalDoorCount: totals.doors,
      totalOpeningCount: totals.openings,
      totalWindowCount: totals.windows
    )
  }

  var body: some View {
    ZStack {
      FloorplanTheme.canvas
        .ignoresSafeArea()

      if let project, let projectKey, shouldShowOverviewCanvas {
        FloorplanOverviewCanvasView(projectKey: projectKey, project: project, showsEmptyHint: false)
          .ignoresSafeArea()
          .allowsHitTesting(false)
      }

      VStack(spacing: 14) {
        header

        ScrollView {
          VStack(spacing: 12) {
            if hasProjectContext {
              projectCard
              if hasExistingScans {
                roomsCard
                exportCard
              } else {
                if hasFinalizedExportArtifacts {
                  finalizedExportCard
                }
                actionsCard
              }
            } else {
              missingJobCard
            }
          }
          .padding(.horizontal, 18)
          .padding(.bottom, 18)
        }
        .blur(radius: showContinueScanAlert ? 5 : 0)
        .allowsHitTesting(!showContinueScanAlert)

        BottomNavBar(selected: .panorama) { tab in
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
      }

      if showContinueScanAlert {
        continueScanOverlay
      }
    }
    .sheet(isPresented: $isRoomPickerPresented) {
      RoomPickerView(
        selectedRoomId: $pendingScanRoomId,
        selectedFloorId: $pendingScanFloorId,
        onDone: {
          pendingScanRoomId = RoomTaxonomy.normalizedRoomId(pendingScanRoomId)
          pendingScanFloorId = FloorTaxonomy.normalizedFloorId(pendingScanFloorId)
          settings.selectedRoomId = pendingScanRoomId
          settings.selectedFloorId = pendingScanFloorId
        }
      )
    }
    .sheet(isPresented: $isJobPickerPresented) {
      JobSelectionSheet(
        title: l10n("floorplan.jobSheet.title"),
        subtitle: l10n("floorplan.jobSheet.subtitle"),
        allowsClear: false,
        clearLabel: "",
        requiresSelection: true,
        onSelect: { job in
          applySelectedJob(job)
          loadProject()
        },
        onClear: {}
      )
      .environmentObject(authService)
      .environmentObject(settings)
    }
    .sheet(isPresented: $isScanSetupPresented) {
      RoomPickerView(
        selectedRoomId: $scanSetupRoomId,
        selectedFloorId: $scanSetupFloorId,
        onDone: {
          handleScanSetupDone()
        }
      )
    }
    .fullScreenCover(isPresented: $isScanTipsPresented) {
      RoomPlanScanTipsView(
        roomName: RoomTaxonomy.room(id: pendingScanRoomId).displayName,
        floorName: FloorTaxonomy.floor(id: pendingScanFloorId).shortDisplayName,
        onCancel: {
          isScanTipsPresented = false
        },
        onStart: {
          markScanTipsSeenForProject()
          isScanTipsPresented = false
          let roomId = pendingScanRoomId
          let floorId = pendingScanFloorId
          scheduleNextPresentation {
            startNewScanNow(roomId: roomId, floorId: floorId)
          }
        }
      )
      .interactiveDismissDisabled(true)
    }
    .sheet(isPresented: $isEditScanPresented) {
      RoomPickerView(
        selectedRoomId: $editRoomId,
        selectedFloorId: $editFloorId,
        onDone: {
          applyScanMetadataEdit()
        }
      )
    }
    .fullScreenCover(isPresented: $isRoomPlanCapturePresented) {
      if let scanId = pendingScanId,
         let projectKey,
         let outputPaths = try? FloorplanProjectStore.roomScanOutputPaths(projectKey: projectKey, scanId: scanId) {
        RoomPlanCaptureScreen(
          outputPaths: outputPaths,
          roomId: pendingScanRoomId,
          floorId: pendingScanFloorId,
          trackingSessionId: pendingRoomPlanTrackingSessionId,
          referenceOverlayImageURL: referenceOverlayFloorplanURL(),
          referenceOverlaySegmentsURL: referenceOverlaySegmentsURL(),
          onCancel: {
            pendingScanId = nil
            pendingRoomPlanTrackingSessionId = nil
            isRoomPlanCapturePresented = false
          },
          onFinished: { _ in
            let finishedRoomId = pendingScanRoomId
            let finishedFloorId = pendingScanFloorId
            pendingScanId = nil
            pendingRoomPlanTrackingSessionId = nil
            isRoomPlanCapturePresented = false
            lastSavedScanLabel = "\(RoomTaxonomy.room(id: finishedRoomId).displayName) · \(FloorTaxonomy.floor(id: finishedFloorId).shortDisplayName)"
            Task { @MainActor in
              await addScanToProject(scanId: scanId, roomId: finishedRoomId, floorId: finishedFloorId)
              scheduleNextPresentation {
                showContinueScanAlert = true
              }
            }
          }
        )
      } else {
        Text(l10n("floorplan.error.projectPaths"))
      }
    }
    .fullScreenCover(isPresented: $isComposerPresented) {
      if let binding = bindingForProject(), let projectKey {
        FloorplanComposerView(
          projectKey: projectKey,
          project: binding,
          onDone: { isComposerPresented = false }
        )
      } else {
        Text(l10n("floorplan.error.projectLoad"))
      }
    }
    .fullScreenCover(isPresented: $isFloorScanPresented) {
      if let projectKey {
        FloorScanScreen(
          projectKey: projectKey,
          floorId: pendingScanFloorId,
          initialRoomId: pendingScanRoomId,
          onDone: {
            isFloorScanPresented = false
            loadProject()
          }
        )
        .interactiveDismissDisabled(true)
      } else {
        Text(l10n("floorplan.error.chooseJobFirst"))
      }
    }
    .fullScreenCover(isPresented: $isMeasurePresented) {
      FloorplanMeasureView(projectKey: projectKey) {
        isMeasurePresented = false
      }
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
          exportMessage = "Mail-Export fehlgeschlagen: \(error.localizedDescription)"
          showExportAlert = true
        }
        pendingMail = nil
      }
    }
    .alert(l10n("floorplan.export.alert.title"), isPresented: $showExportAlert) {
      Button(l10n("common.ok"), role: .cancel) {}
    } message: {
      Text(exportMessage)
    }
    .onAppear {
      syncScanDefaultsFromSettings()
      loadProject()
    }
    .onDisappear {
      resetRoomSequenceTrackingSession()
    }
    .onChange(of: settings.selectedJobId) { _, _ in
      syncScanDefaultsFromSettings()
      loadProject()
    }
    .onChange(of: settings.selectedRoomId) { _, _ in
      syncScanDefaultsFromSettings()
    }
    .onChange(of: settings.selectedFloorId) { _, _ in
      syncScanDefaultsFromSettings()
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      Button(action: { onNavigate(.start) }) {
        Image(systemName: "chevron.left")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(FloorplanTheme.headerTitle)
          .frame(width: 36, height: 36)
          .background(FloorplanTheme.headerPanel)
          .clipShape(PixBrand.tileShape())
          .overlay(PixBrand.tileShape().stroke(FloorplanTheme.headerBorder, lineWidth: 1))
          .frame(width: 44, height: 44)
      }
      .accessibilityLabel(l10n("common.back"))

      VStack(alignment: .leading, spacing: 2) {
        Text(l10n("floorplan.title"))
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(FloorplanTheme.headerTitle)
        Text(settings.jobLabel.isEmpty ? l10n("floorplan.header.noJob") : settings.jobLabel)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(FloorplanTheme.headerBody)
          .lineLimit(1)
      }

      Spacer()

      Button(action: {
        isJobPickerPresented = true
      }) {
        Image(systemName: "briefcase")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(FloorplanTheme.primary.opacity(0.88))
          .frame(width: 36, height: 36)
          .background(FloorplanTheme.blueCard)
          .clipShape(PixBrand.tileShape())
          .overlay(PixBrand.tileShape().stroke(FloorplanTheme.primary.opacity(0.18), lineWidth: 1))
          .frame(width: 44, height: 44)
      }
      .accessibilityLabel(l10n("floorplan.accessibility.chooseJob"))

      Button(action: {
        if hasProjectContext {
          isRoomPickerPresented = true
        } else {
          isJobPickerPresented = true
        }
      }) {
        Image(systemName: "tag")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(FloorplanTheme.headerTitle)
          .frame(width: 36, height: 36)
          .background(FloorplanTheme.headerPanel)
          .clipShape(PixBrand.tileShape())
          .overlay(PixBrand.tileShape().stroke(FloorplanTheme.headerBorder, lineWidth: 1))
          .frame(width: 44, height: 44)
      }
      .accessibilityLabel(hasProjectContext ? l10n("floorplan.accessibility.chooseRoom") : l10n("floorplan.accessibility.chooseJob"))
    }
    .padding(.horizontal, 18)
    .padding(.top, 16)
  }

  private var projectCard: some View {
    let address = settings.jobAddress.trimmingCharacters(in: .whitespacesAndNewlines)

    return VStack(alignment: .leading, spacing: 8) {
      Text(hasExistingScans ? l10n("floorplan.project.overview") : l10n("floorplan.project.step"))
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Color.black.opacity(0.8))

      HStack(spacing: 10) {
        VStack(alignment: .leading, spacing: 4) {
          Text(settings.jobLabel.isEmpty ? l10n("floorplan.noJob") : settings.jobLabel)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.8))
          Text(l10nFormat("floorplan.project.default.format", RoomTaxonomy.room(id: pendingScanRoomId).displayName, FloorTaxonomy.floor(id: pendingScanFloorId).shortDisplayName))
            .font(.system(size: 12))
            .foregroundStyle(Color.black.opacity(0.6))
        }
        Spacer()
        Text(projectKey ?? l10n("floorplan.noJob"))
          .foregroundStyle(Color.black.opacity(0.45))
          .font(.system(size: 11, weight: .medium, design: .monospaced))
          .lineLimit(1)
      }

      if !address.isEmpty {
        Text(address)
          .font(.system(size: 12))
          .foregroundStyle(Color.black.opacity(0.58))
          .fixedSize(horizontal: false, vertical: true)
      }

      HStack(spacing: 8) {
        summaryPill(title: l10nFormat("floorplan.summary.rooms.format", projectOverview.roomCount))
        summaryPill(title: l10nFormat("floorplan.summary.floors.format", projectOverview.floorCount))
        summaryPill(title: l10nFormat("floorplan.summary.area.format", formattedMetric(projectOverview.totalAreaSqmApprox)))
      }

      HStack(spacing: 8) {
        summaryPill(title: l10nFormat("floorplan.summary.doors.format", projectOverview.totalDoorCount))
        summaryPill(title: l10nFormat("floorplan.summary.openings.format", projectOverview.totalOpeningCount))
        summaryPill(title: l10nFormat("floorplan.summary.windows.format", projectOverview.totalWindowCount))
      }

      Button {
        isJobPickerPresented = true
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "briefcase")
            .font(.system(size: 14, weight: .semibold))
          Text(l10n("floorplan.project.changeJob"))
            .font(.system(size: 13, weight: .semibold))
          Spacer()
          Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(FloorplanTheme.primary)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(FloorplanTheme.primary.opacity(0.08))
        .clipShape(PixBrand.tileShape())
        .overlay(
          PixBrand.tileShape()
            .stroke(FloorplanTheme.primary.opacity(0.14), lineWidth: 1)
        )
      }

      if !hasExistingScans {
        Text(l10n("floorplan.project.explainer"))
          .font(.system(size: 12))
          .foregroundStyle(Color.black.opacity(0.58))
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(14)
    .background(FloorplanTheme.blueCard)
    .clipShape(PixBrand.tileShape())
    .overlay(PixBrand.tileShape().stroke(Color.black.opacity(0.06), lineWidth: 1))
  }

  private var missingJobCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(l10n("floorplan.missingJob.title"))
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(Color.black.opacity(0.82))

      Text(l10n("floorplan.missingJob.body"))
        .font(.system(size: 12))
        .foregroundStyle(Color.black.opacity(0.62))
        .fixedSize(horizontal: false, vertical: true)

      Button {
        isJobPickerPresented = true
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "briefcase")
            .font(.system(size: 15, weight: .semibold))
          Text(l10n("floorplan.missingJob.chooseJob"))
            .font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(FloorplanTheme.primary)
        .clipShape(PixBrand.tileShape())
      }

      Button {
        onNavigate(.start)
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "chevron.left")
            .font(.system(size: 14, weight: .semibold))
          Text(l10n("floorplan.missingJob.backToStart"))
            .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(FloorplanTheme.primary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(FloorplanTheme.primary.opacity(0.08))
        .clipShape(PixBrand.tileShape())
      }
    }
    .padding(14)
    .background(FloorplanTheme.warmCard)
    .clipShape(PixBrand.tileShape())
    .overlay(PixBrand.tileShape().stroke(Color.black.opacity(0.06), lineWidth: 1))
  }

  private var actionsCard: some View {
    return VStack(alignment: .leading, spacing: 10) {
      Text(l10n("floorplan.actions.firstScan.title"))
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Color.black.opacity(0.82))

      Text(l10n("floorplan.actions.firstScan.body"))
        .font(.system(size: 12))
        .foregroundStyle(Color.black.opacity(0.6))
        .fixedSize(horizontal: false, vertical: true)

      Button {
        beginNewScan()
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "cube.transparent.fill")
            .font(.system(size: 16, weight: .semibold))
          Text(l10n("floorplan.actions.startRoomScan"))
            .font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(FloorplanTheme.primary)
        .clipShape(PixBrand.tileShape())
      }

      Menu {
        Button {
          isMeasurePresented = true
        } label: {
          Label("Messen", systemImage: "ruler")
        }
        Button(l10n("floorplan.actions.floorScanBeta")) {
          beginFloorScan()
        }
        Button(l10n("floorplan.actions.directStart")) {
          startNewScanNow(roomId: pendingScanRoomId, floorId: pendingScanFloorId)
        }
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "ellipsis.circle")
            .font(.system(size: 14, weight: .semibold))
          Text(l10n("floorplan.actions.moreOptions"))
            .font(.system(size: 13, weight: .semibold))
          Spacer()
          Image(systemName: "chevron.down")
            .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(Color.black.opacity(0.65))
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(FloorplanTheme.secondary.opacity(0.10))
        .clipShape(PixBrand.tileShape())
      }
    }
    .padding(14)
    .background(FloorplanTheme.pinkCard)
    .clipShape(PixBrand.tileShape())
    .overlay(PixBrand.tileShape().stroke(Color.black.opacity(0.06), lineWidth: 1))
  }

  private var finalizedExportCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Finaler Export bereits vorhanden")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Color.black.opacity(0.82))

      Text("Für diesen Job liegen schon exportierte Grundriss-Dateien vor. Die Raumscan-Arbeitsdaten wurden danach geleert, deshalb wirkt das Projekt hier leer, obwohl die Exporte weiter vorhanden sind.")
        .font(.system(size: 12))
        .foregroundStyle(Color.black.opacity(0.62))
        .fixedSize(horizontal: false, vertical: true)

      Button {
        shareExistingFinalExport()
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "square.and.arrow.up")
            .font(.system(size: 15, weight: .semibold))
          Text("Export erneut teilen")
            .font(.system(size: 14, weight: .semibold))
          Spacer()
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(FloorplanTheme.primary)
        .clipShape(PixBrand.tileShape())
      }

      ViewThatFits(in: .horizontal) {
        HStack(spacing: 10) {
          finalizedExportActionButton(title: "Per Mail senden", systemImage: "envelope") {
            prepareCombinedMailExport(existingOnly: true)
          }
          finalizedExportActionButton(title: "In Dateien sichern", systemImage: "folder") {
            copyExistingFinalExportToFiles()
          }
        }
        VStack(spacing: 10) {
          finalizedExportActionButton(title: "Per Mail senden", systemImage: "envelope") {
            prepareCombinedMailExport(existingOnly: true)
          }
          finalizedExportActionButton(title: "In Dateien sichern", systemImage: "folder") {
            copyExistingFinalExportToFiles()
          }
        }
      }
    }
    .padding(14)
    .background(FloorplanTheme.warmCard)
    .clipShape(PixBrand.tileShape())
    .overlay(PixBrand.tileShape().stroke(Color.black.opacity(0.06), lineWidth: 1))
  }

  private func finalizedExportActionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: systemImage)
          .font(.system(size: 13, weight: .semibold))
        Text(title)
          .font(.system(size: 13, weight: .semibold))
        Spacer(minLength: 0)
      }
      .foregroundStyle(FloorplanTheme.primary)
      .frame(maxWidth: .infinity)
      .padding(.horizontal, 12)
      .padding(.vertical, 11)
      .background(FloorplanTheme.primary.opacity(0.08))
      .clipShape(PixBrand.tileShape())
    }
    .buttonStyle(.plain)
  }

  private var roomsCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("2. Räume im Projekt")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Color.black.opacity(0.82))
        Spacer()
        Text("\(project?.roomScans.count ?? 0) Räume")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Color.black.opacity(0.5))
      }

      if let project, project.roomScans.isEmpty {
        Text("Noch keine Scans. Füge zuerst Räume hinzu.")
          .font(.system(size: 12))
          .foregroundStyle(Color.black.opacity(0.6))
      } else if let project {
        Button {
          beginNewScan()
        } label: {
          HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
              .font(.system(size: 14, weight: .semibold))
            Text("Weiteren Raum scannen")
              .font(.system(size: 13, weight: .semibold))
            Spacer()
          }
        .foregroundStyle(FloorplanTheme.primary)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(FloorplanTheme.primary.opacity(0.08))
        .clipShape(PixBrand.tileShape())
      }

        ForEach(project.roomScans) { scan in
          roomRow(scan)
        }
      }

      Button {
        isComposerPresented = true
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "checkmark.seal.fill")
            .font(.system(size: 16, weight: .semibold))
          Text("Grundriss bearbeiten")
            .font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(Color.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(FloorplanTheme.primary.opacity(0.96))
        .clipShape(PixBrand.tileShape())
        .overlay(PixBrand.tileShape().stroke(Color.black.opacity(0.04), lineWidth: 1))
      }
      .disabled((project?.roomScans.isEmpty ?? true))
      .opacity((project?.roomScans.isEmpty ?? true) ? 0.55 : 1.0)

      Menu {
        Button {
          isMeasurePresented = true
        } label: {
          Label("Messen", systemImage: "ruler")
        }
        Button("Etage scannen") {
          beginFloorScan()
        }
        Button("Direkt ohne Anleitung starten") {
          startNewScanNow(roomId: pendingScanRoomId, floorId: pendingScanFloorId)
        }
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "ellipsis.circle")
            .font(.system(size: 14, weight: .semibold))
          Text("Weitere Scan-Optionen")
            .font(.system(size: 13, weight: .semibold))
          Spacer()
          Image(systemName: "chevron.down")
            .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(Color.black.opacity(0.65))
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(FloorplanTheme.secondary.opacity(0.10))
        .clipShape(PixBrand.tileShape())
      }
    }
    .padding(14)
    .background(FloorplanTheme.blueCard)
    .clipShape(PixBrand.tileShape())
    .overlay(PixBrand.tileShape().stroke(Color.black.opacity(0.06), lineWidth: 1))
  }

  private func roomRow(_ scan: FloorplanRoomScan) -> some View {
    let roomName = RoomTaxonomy.room(id: scan.roomId).displayName
    let floorName = FloorTaxonomy.floor(id: scan.floorId).shortDisplayName
    let metrics = scan.metrics
    let summary = roomSemanticSummaryByScanId[scan.id]
    let area = String(format: "%.1f", metrics.areaSqmApprox)
    let perim = String(format: "%.1f", metrics.perimeterMeters)
    let width = String(format: "%.1f", metrics.widthMeters)
    let depth = String(format: "%.1f", metrics.depthMeters)

    return HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text("\(roomName) · \(floorName)")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Color.black.opacity(0.82))
        Text("Fläche ca.: \(area) m² · Umfang: \(perim) m")
          .font(.system(size: 11))
          .foregroundStyle(Color.black.opacity(0.55))
        Text("Breite: \(width) m · Tiefe: \(depth) m")
          .font(.system(size: 11))
          .foregroundStyle(Color.black.opacity(0.55))
        if let summary {
          Text("Türen: \(summary.doorCount) · Durchgänge: \(summary.openingCount) · Fenster: \(summary.windowCount)")
            .font(.system(size: 11))
            .foregroundStyle(Color.black.opacity(0.55))
        }
      }
      Spacer()
      Button {
        beginEditMetadata(scanId: scan.id)
      } label: {
        Image(systemName: "pencil")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Color.black.opacity(0.65))
          .frame(width: 32, height: 32)
          .background(Color.black.opacity(0.06))
          .clipShape(PixBrand.tileShape())
          .frame(width: 44, height: 44)
      }
      .accessibilityLabel("Raumdaten bearbeiten")
      Button(role: .destructive) {
        deleteScan(scan.id)
      } label: {
        Image(systemName: "trash")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Color.red.opacity(0.85))
          .frame(width: 32, height: 32)
          .background(Color.red.opacity(0.08))
          .clipShape(PixBrand.tileShape())
          .frame(width: 44, height: 44)
      }
      .accessibilityLabel("Raumscan löschen")
    }
    .padding(.vertical, 6)
  }

  private var exportCard: some View {
    let exportDisabled = project?.roomScans.isEmpty ?? true

    return VStack(alignment: .leading, spacing: 10) {
      Text("3. Export (PNG / PDF / CSV)")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Color.black.opacity(0.82))

      Text("Erzeugt ein gemeinsames Exportpaket mit Plan, Datenblatt, OpenImmo, CSV-Listen und PNG. Beim naechsten Uploadlauf fuer diesen Job werden die Grundriss-Artefakte als Job-Dateien mit vorbereitet.")
        .font(.system(size: 12))
        .foregroundStyle(Color.black.opacity(0.6))
        .fixedSize(horizontal: false, vertical: true)

      Button {
        exportCombined()
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "square.and.arrow.up")
            .font(.system(size: 16, weight: .semibold))
          Text("Export erzeugen & teilen")
            .font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(FloorplanTheme.primary)
        .clipShape(PixBrand.tileShape())
      }
      .disabled(exportDisabled)
      .opacity(exportDisabled ? 0.55 : 1.0)

      ViewThatFits(in: .horizontal) {
        HStack(spacing: 10) {
          secondaryExportButton(title: "Per Mail senden", systemImage: "envelope") {
            prepareCombinedMailExport(existingOnly: false)
          }
          secondaryExportButton(title: "In Dateien sichern", systemImage: "folder") {
            copyCurrentExportToFiles()
          }
        }
        VStack(spacing: 10) {
          secondaryExportButton(title: "Per Mail senden", systemImage: "envelope") {
            prepareCombinedMailExport(existingOnly: false)
          }
          secondaryExportButton(title: "In Dateien sichern", systemImage: "folder") {
            copyCurrentExportToFiles()
          }
        }
      }
      .disabled(exportDisabled)
      .opacity(exportDisabled ? 0.55 : 1.0)
    }
    .padding(14)
    .background(FloorplanTheme.warmCard)
    .clipShape(PixBrand.tileShape())
    .overlay(PixBrand.tileShape().stroke(Color.black.opacity(0.06), lineWidth: 1))
  }

  private func secondaryExportButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: systemImage)
          .font(.system(size: 13, weight: .semibold))
        Text(title)
          .font(.system(size: 12, weight: .semibold))
          .lineLimit(1)
          .minimumScaleFactor(0.85)
      }
      .foregroundStyle(Color.black.opacity(0.78))
      .frame(maxWidth: .infinity)
      .padding(.vertical, 11)
      .background(Color.black.opacity(0.06))
      .clipShape(PixBrand.tileShape())
      .overlay(
        PixBrand.tileShape()
          .stroke(Color.black.opacity(0.08), lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
  }

  private var continueScanOverlay: some View {
    ZStack {
      Color.black.opacity(0.18)
        .ignoresSafeArea()
        .onTapGesture {
          withAnimation(.easeInOut(duration: 0.18)) {
            showContinueScanAlert = false
          }
        }

      VStack(alignment: .leading, spacing: 14) {
        Text("Raum gespeichert")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(PixBrand.textOnDark)

        Text("\(lastSavedScanLabel) wurde übernommen. Möchtest du direkt den nächsten Raum scannen oder erst im Projekt weiterarbeiten?")
          .font(.system(size: 14))
          .foregroundStyle(PixBrand.textOnDarkSecondary)
          .fixedSize(horizontal: false, vertical: true)

        VStack(spacing: 10) {
          Button {
            withAnimation(.easeInOut(duration: 0.18)) {
              showContinueScanAlert = false
            }
            scheduleNextPresentation {
              beginNewScan()
            }
          } label: {
              Text("Weiteren Raum scannen")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(FloorplanTheme.primary)
                .clipShape(PixBrand.tileShape())
          }

          Button {
            withAnimation(.easeInOut(duration: 0.18)) {
              showContinueScanAlert = false
            }
          } label: {
              Text("Zum Projekt")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PixBrand.textOnDark)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(PixBrand.panelSecondary)
                .clipShape(PixBrand.tileShape())
          }
        }
      }
      .padding(18)
      .frame(maxWidth: 340)
      .background(PixBrand.panel)
      .clipShape(PixBrand.tileShape())
      .overlay(
        PixBrand.tileShape()
          .stroke(PixBrand.borderOnDark, lineWidth: 1)
      )
      .shadow(color: Color.black.opacity(0.12), radius: 24, y: 14)
      .padding(.horizontal, 20)
      .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
    .zIndex(10)
  }

  private func loadProject() {
    guard let projectKey else {
      project = nil
      roomSemanticSummaryByScanId = [:]
      hasFinalizedExportArtifacts = false
      resetRoomSequenceTrackingSession()
      return
    }

    if roomSequenceTrackingProjectKey != projectKey {
      resetRoomSequenceTrackingSession()
    }
    do {
      let loadedProject = try FloorplanProjectStore.loadOrCreate(projectKey: projectKey)
      let normalizedProject = FloorplanProjectStore.normalizedLayout(project: loadedProject)
      if normalizedProject != loadedProject {
        try? FloorplanProjectStore.save(project: normalizedProject)
      }
      project = normalizedProject
      roomSemanticSummaryByScanId = loadRoomSemanticSummaries(projectKey: projectKey, scans: normalizedProject.roomScans)
      refreshFinalizedExportState(projectKey: projectKey, project: normalizedProject)
    } catch {
      exportMessage = error.localizedDescription
      showExportAlert = true
      project = nil
      roomSemanticSummaryByScanId = [:]
      hasFinalizedExportArtifacts = false
    }
  }

  private func resetRoomSequenceTrackingSession() {
    if #available(iOS 17.0, *) {
      RoomPlanCaptureUIView.releaseSharedARSession(for: roomSequenceTrackingSessionId)
    }
    roomSequenceTrackingProjectKey = nil
    roomSequenceTrackingFloorId = nil
    roomSequenceTrackingSessionId = nil
    pendingRoomPlanTrackingSessionId = nil
  }

  private func ensureRoomSequenceTrackingSessionId(projectKey: String, floorId: String) -> String {
    let normalizedFloorId = FloorTaxonomy.normalizedFloorId(floorId)
    let existingFloorScanCount = project?.roomScans.filter { $0.floorId == normalizedFloorId }.count ?? 0

    if let sessionId = roomSequenceTrackingSessionId,
       roomSequenceTrackingProjectKey == projectKey,
       roomSequenceTrackingFloorId == normalizedFloorId,
       existingFloorScanCount > 0 {
      return sessionId
    }

    let sessionId = UUID().uuidString
    roomSequenceTrackingProjectKey = projectKey
    roomSequenceTrackingFloorId = normalizedFloorId
    roomSequenceTrackingSessionId = sessionId
    return sessionId
  }

  private func loadSegmentsFile(projectKey: String, relativePath: String) -> FloorplanSegmentsFile? {
    guard let url = try? FloorplanProjectStore.resolve(projectKey: projectKey, relativePath: relativePath),
          let data = try? Data(contentsOf: url),
          let decoded = try? JSONDecoder().decode(FloorplanSegmentsFile.self, from: data) else {
      return nil
    }
    return decoded
  }

  private func syncScanDefaultsFromSettings() {
    pendingScanRoomId = RoomTaxonomy.normalizedRoomId(settings.selectedRoomId)
    pendingScanFloorId = FloorTaxonomy.normalizedFloorId(settings.selectedFloorId)
  }

  private func bindingForProject() -> Binding<FloorplanProject>? {
    guard project != nil else { return nil }
    return Binding(
      get: { project! },
      set: { newValue in
        project = newValue
        try? FloorplanProjectStore.save(project: newValue)
      }
    )
  }

  private func beginNewScan() {
    guard hasProjectContext else {
      presentJobPickerIfNeeded()
      return
    }
    scanSetupRoomId = RoomTaxonomy.normalizedRoomId(pendingScanRoomId)
    scanSetupFloorId = FloorTaxonomy.normalizedFloorId(pendingScanFloorId)
    isScanSetupPresented = true
  }

  private func beginFloorScan() {
    guard hasProjectContext else {
      presentJobPickerIfNeeded()
      return
    }
    pendingScanRoomId = RoomTaxonomy.normalizedRoomId(settings.selectedRoomId)
    pendingScanFloorId = FloorTaxonomy.normalizedFloorId(settings.selectedFloorId)
    isFloorScanPresented = true
  }

  private func handleScanSetupDone() {
    // Remember the selection for this scan. Kept separate from the photo camera selection.
    pendingScanRoomId = RoomTaxonomy.normalizedRoomId(scanSetupRoomId)
    pendingScanFloorId = FloorTaxonomy.normalizedFloorId(scanSetupFloorId)
    settings.selectedRoomId = pendingScanRoomId
    settings.selectedFloorId = pendingScanFloorId
    if shouldShowScanTipsForProject() {
      scheduleNextPresentation {
        isScanTipsPresented = true
      }
    } else {
      let roomId = pendingScanRoomId
      let floorId = pendingScanFloorId
      scheduleNextPresentation {
        startNewScanNow(roomId: roomId, floorId: floorId)
      }
    }
  }

  private func scheduleNextPresentation(_ action: @escaping () -> Void) {
    // Wait one run-loop + a small delay so the previous sheet can dismiss cleanly.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
      action()
    }
  }

  private var scanTipsSeenDefaultsKey: String {
    "floorplan.scanTipsSeen.\(projectKey ?? "unassigned")"
  }

  private func shouldShowScanTipsForProject() -> Bool {
    !UserDefaults.standard.bool(forKey: scanTipsSeenDefaultsKey)
  }

  private func markScanTipsSeenForProject() {
    UserDefaults.standard.set(true, forKey: scanTipsSeenDefaultsKey)
  }

  private func referenceOverlayFloorplanURL() -> URL? {
    guard let projectKey else { return nil }
    guard let previous = previousRoomScanForOverlay() else { return nil }
    return try? FloorplanProjectStore.resolve(projectKey: projectKey, relativePath: previous.floorplanPNGPath)
  }

  private func referenceOverlaySegmentsURL() -> URL? {
    guard let projectKey else { return nil }
    guard let previous = previousRoomScanForOverlay() else { return nil }
    return try? FloorplanProjectStore.resolve(projectKey: projectKey, relativePath: previous.segmentsJSONPath)
  }

  private func previousRoomScanForOverlay() -> FloorplanRoomScan? {
    guard let project else { return nil }
    return project.roomScans
      .filter { $0.floorId == pendingScanFloorId }
      .sorted(by: { $0.createdAt < $1.createdAt })
      .last
  }

  private func startNewScanNow(roomId: String, floorId: String) {
    guard let projectKey else {
      presentJobPickerIfNeeded()
      return
    }
    do {
      if project == nil {
        project = try FloorplanProjectStore.loadOrCreate(projectKey: projectKey)
      }
      let scanId = UUID()
      pendingScanId = scanId
      pendingScanRoomId = RoomTaxonomy.normalizedRoomId(roomId)
      pendingScanFloorId = FloorTaxonomy.normalizedFloorId(floorId)
      pendingRoomPlanTrackingSessionId = ensureRoomSequenceTrackingSessionId(
        projectKey: projectKey,
        floorId: pendingScanFloorId
      )
      settings.selectedRoomId = pendingScanRoomId
      settings.selectedFloorId = pendingScanFloorId
      isRoomPlanCapturePresented = true
    } catch {
      exportMessage = error.localizedDescription
      showExportAlert = true
    }
  }

  private func addScanToProject(scanId: UUID, roomId: String, floorId: String) async {
    guard let projectKey else { return }
    guard var project else { return }

    // Load metrics from segments.json
    let normalizedFloorId = FloorTaxonomy.normalizedFloorId(floorId)
    let segmentsRel = "rooms/\(scanId.uuidString)/segments.json"
    let usdzRel = "rooms/\(scanId.uuidString)/scan.usdz"
    let pngRel = "rooms/\(scanId.uuidString)/floorplan.png"
    let capturedRoomDataRel = persistedCapturedRoomRelativePathIfExists(
      projectKey: projectKey,
      relativePath: "rooms/\(scanId.uuidString)/captured_room_data.json"
    )
    let capturedRoomRel = persistedCapturedRoomRelativePathIfExists(
      projectKey: projectKey,
      relativePath: "rooms/\(scanId.uuidString)/captured_room.json"
    )
    var metrics = FloorplanMetrics(perimeterMeters: 0, widthMeters: 0, depthMeters: 0, areaSqmApprox: 0)
    var rawGeo: FloorplanSegmentsFile? = nil
    var newGeo: FloorplanSegmentsFile? = nil
    if let decoded = loadSegmentsFile(projectKey: projectKey, relativePath: segmentsRel) {
      rawGeo = decoded
      let normalized = decoded.normalizedForDisplay()
      metrics = normalized.metrics
      newGeo = normalized
    }

    // Initial placement: append to the right of existing rooms (simple but predictable).
    let gap = 1.0
    let offsetX = project.roomScans.reduce(0.0) { partial, scan in
      partial + scan.metrics.widthMeters + gap
    }
    var transform = FloorplanRoomTransform(translationX: offsetX, translationY: 0, rotationRadians: 0)
    var trackedTransform: FloorplanRoomTransform? = nil
    var dockResult: FloorplanAutoDockService.Result? = nil
    var trackedSnapResult: FloorplanAutoDockService.Result? = nil
    var trackedConnection: FloorplanRoomConnection? = nil

    let loadGeo: (UUID) -> FloorplanSegmentsFile? = { existingScanId in
      let rel = "rooms/\(existingScanId.uuidString)/segments.json"
      return loadSegmentsFile(projectKey: projectKey, relativePath: rel)
    }

    if let rawGeo {
      trackedTransform = FloorplanTrackedPlacementService.trackedTransform(
        project: project,
        newGeo: rawGeo,
        floorId: normalizedFloorId,
        loadGeo: loadGeo
      )
    }

    // Let passage geometry produce the final snapped transform.
    // Shared-world tracking only acts as a soft prior so rooms still end up flush on the wall.
    let requiresTrackedAgreement =
      rawGeo?.trackingSource == .roomSequenceSharedWorld &&
      trackedTransform != nil
    if let newGeo {
      dockResult = FloorplanAutoDockService.bestAutoDock(
        project: project,
        newScanId: scanId,
        newGeo: newGeo,
        floorId: normalizedFloorId,
        loadGeo: loadGeo,
        preferredTransform: trackedTransform,
        requiresTrackedAgreement: requiresTrackedAgreement
      )
    }

    if dockResult == nil,
       let newGeo,
       let trackedTransform,
       rawGeo?.trackingSource == .roomSequenceSharedWorld {
      trackedSnapResult = FloorplanAutoDockService.refinedTrackedPlacement(
        project: project,
        newScanId: scanId,
        newGeo: newGeo,
        trackedTransform: trackedTransform,
        floorId: normalizedFloorId,
        loadGeo: loadGeo
      )
    }

    if let dockResult {
      transform = dockResult.transform
    } else if let trackedSnapResult {
      transform = trackedSnapResult.transform
    } else if let trackedTransform {
      let previousSameFloor = project.roomScans
        .filter { $0.floorId == normalizedFloorId }
        .sorted(by: { $0.createdAt < $1.createdAt })
        .last
      let plausible: Bool
      if let previousSameFloor {
        let distance = FloorplanAutoDockService.transformDistanceMeters(a: previousSameFloor.transform, b: trackedTransform)
        plausible = distance <= 18.0
      } else {
        plausible = true
      }

      let collides = newGeo.map {
        FloorplanAutoDockService.placementHasSevereOverlap(
          project: project,
          newGeo: $0,
          newTransform: trackedTransform,
          floorId: normalizedFloorId,
          loadGeo: loadGeo
        )
      } ?? false

      if plausible && !collides {
        transform = trackedTransform
        if let newGeo {
          trackedConnection = FloorplanAutoDockService.bestConnectionForPlacedRoom(
            project: project,
            newScanId: scanId,
            newGeo: newGeo,
            newTransform: trackedTransform,
            floorId: normalizedFloorId,
            loadGeo: loadGeo
          )
        }
      }
    }

    if let connection = dockResult?.connection ?? trackedSnapResult?.connection ?? trackedConnection {
      project.connections.append(connection)
    }

    let capturedRoomIdentifier = capturedRoomRel.flatMap {
      loadCapturedRoomIdentifier(projectKey: projectKey, relativePath: $0)
    }

    let scan = FloorplanRoomScan(
      id: scanId,
      roomId: RoomTaxonomy.normalizedRoomId(roomId),
      floorId: normalizedFloorId,
      createdAt: Date(),
      usdzPath: usdzRel,
      floorplanPNGPath: pngRel,
      segmentsJSONPath: segmentsRel,
      capturedRoomDataPath: capturedRoomDataRel,
      capturedRoomJSONPath: capturedRoomRel,
      capturedRoomIdentifier: capturedRoomIdentifier,
      metrics: metrics,
      transform: transform
    )
    project.roomScans.append(scan)
    project = FloorplanProjectStore.normalizedLayout(project: project)

    do {
      try FloorplanProjectStore.save(project: project)
      self.project = project
      roomSemanticSummaryByScanId = loadRoomSemanticSummaries(projectKey: projectKey, scans: project.roomScans)
      refreshFinalizedExportState(projectKey: projectKey, project: project)
    } catch {
      exportMessage = error.localizedDescription
      showExportAlert = true
      self.project = project
      roomSemanticSummaryByScanId = loadRoomSemanticSummaries(projectKey: projectKey, scans: project.roomScans)
      refreshFinalizedExportState(projectKey: projectKey, project: project)
    }

    do {
      let mergedProject = try await RoomPlanStructureMergeService.reconcileProject(
        projectKey: projectKey,
        project: project
      )
      guard mergedProject != project else { return }
      try FloorplanProjectStore.save(project: mergedProject)
      self.project = mergedProject
      roomSemanticSummaryByScanId = loadRoomSemanticSummaries(projectKey: projectKey, scans: mergedProject.roomScans)
      refreshFinalizedExportState(projectKey: projectKey, project: mergedProject)
    } catch {
      exportMessage = "RoomPlan-Mehrraum-Merge fehlgeschlagen: \(error.localizedDescription)"
      showExportAlert = true
    }
  }

  private func loadCapturedRoomIdentifier(projectKey: String, relativePath: String) -> String? {
    guard let url = try? FloorplanProjectStore.resolve(projectKey: projectKey, relativePath: relativePath),
          let capturedRoom = try? RoomPlanStructureMergeService.loadCapturedRoom(from: url) else {
      return nil
    }
    return capturedRoom.identifier.uuidString
  }

  private func persistedCapturedRoomRelativePathIfExists(
    projectKey: String,
    relativePath: String
  ) -> String? {
    guard let url = try? FloorplanProjectStore.resolve(projectKey: projectKey, relativePath: relativePath),
          FileManager.default.fileExists(atPath: url.path) else {
      return nil
    }
    return relativePath
  }

  private func beginEditMetadata(scanId: UUID) {
    guard let project, let scan = project.roomScans.first(where: { $0.id == scanId }) else { return }
    editScanId = scanId
    editRoomId = RoomTaxonomy.normalizedRoomId(scan.roomId)
    editFloorId = FloorTaxonomy.normalizedFloorId(scan.floorId)
    isEditScanPresented = true
  }

  private func applyScanMetadataEdit() {
    guard let scanId = editScanId else { return }
    guard var project else { return }
    guard let index = project.roomScans.firstIndex(where: { $0.id == scanId }) else { return }

    project.roomScans[index].roomId = RoomTaxonomy.normalizedRoomId(editRoomId)
    project.roomScans[index].floorId = FloorTaxonomy.normalizedFloorId(editFloorId)
    self.project = project
    try? FloorplanProjectStore.save(project: project)
    if let projectKey {
      roomSemanticSummaryByScanId = loadRoomSemanticSummaries(projectKey: projectKey, scans: project.roomScans)
    }
  }

  private func deleteScan(_ scanId: UUID) {
    guard let projectKey else { return }
    guard var project else { return }
    project.roomScans.removeAll { $0.id == scanId }
    project.connections.removeAll { $0.a.scanId == scanId || $0.b.scanId == scanId }
    self.project = project
    try? FloorplanProjectStore.save(project: project)
    roomSemanticSummaryByScanId.removeValue(forKey: scanId)

    // Best-effort cleanup of room folder.
    if let dir = try? FloorplanProjectStore.roomScanDirectory(projectKey: projectKey, scanId: scanId) {
      try? FileManager.default.removeItem(at: dir)
    }
  }

  private func presentJobPickerIfNeeded() {
    guard !hasProjectContext else { return }
    DispatchQueue.main.async {
      guard !isJobPickerPresented else { return }
      isJobPickerPresented = true
    }
  }

  private func refreshFinalizedExportState(projectKey: String, project: FloorplanProject) {
    let isWorkingProjectEmpty = project.roomScans.isEmpty
    guard isWorkingProjectEmpty,
          let paths = try? FloorplanProjectStore.projectPaths(projectKey: projectKey) else {
      hasFinalizedExportArtifacts = false
      return
    }

    let fm = FileManager.default
    hasFinalizedExportArtifacts =
      fm.fileExists(atPath: paths.visualPDF.path) ||
      fm.fileExists(atPath: paths.combinedPDF.path) ||
      fm.fileExists(atPath: paths.combinedPNG.path)
  }

  private func applySelectedJob(_ job: JobInfo) {
    settings.setCurrentJob(job, userScope: authService.recentJobScope)
  }

  private func loadRoomSemanticSummaries(projectKey: String, scans: [FloorplanRoomScan]) -> [UUID: RoomSemanticSummary] {
    Dictionary(uniqueKeysWithValues: scans.compactMap { scan in
      guard let url = try? FloorplanProjectStore.resolve(projectKey: projectKey, relativePath: scan.segmentsJSONPath),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(FloorplanSegmentsFile.self, from: data) else {
        return (scan.id, RoomSemanticSummary(doorCount: 0, openingCount: 0, windowCount: 0))
      }

      let normalized = decoded.normalizedForDisplay()
      return (
        scan.id,
        RoomSemanticSummary(
          doorCount: normalized.doors?.count ?? 0,
          openingCount: normalized.openings?.count ?? 0,
          windowCount: normalized.windows?.count ?? 0
        )
      )
    })
  }

  private func formattedMetric(_ value: Double) -> String {
    String(format: "%.1f", value)
  }

  private func summaryPill(title: String) -> some View {
    Text(title)
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(Color.black.opacity(0.68))
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .background(Color.black.opacity(0.05))
      .clipShape(PixBrand.tileShape())
  }

  private struct AutoDockResult {
    let transform: FloorplanRoomTransform
    let connection: FloorplanRoomConnection
  }

  private struct PassageCandidate {
    let kind: FloorplanPassageKind
    let index: Int
    let seg: FloorplanSegment
  }

  private func bestAutoDock(
    project: FloorplanProject,
    newScanId: UUID,
    newGeo: FloorplanSegmentsFile,
    floorId: String
  ) -> AutoDockResult? {
    guard let projectKey else { return nil }
    // Prefer docking to the last scanned room on the same floor.
    let previous = project.roomScans
      .filter { $0.floorId == floorId }
      .sorted(by: { $0.createdAt < $1.createdAt })
      .last
    guard let previous else { return nil }

    guard let prevURL = try? FloorplanProjectStore.resolve(projectKey: projectKey, relativePath: previous.segmentsJSONPath),
          let prevData = try? Data(contentsOf: prevURL),
          let prevDecoded = try? JSONDecoder().decode(FloorplanSegmentsFile.self, from: prevData) else { return nil }
    let prevGeo = prevDecoded.normalizedForDisplay()

    let prevPassages = passageCandidates(from: prevGeo)
    var newPassages = passageCandidates(from: newGeo)
    if let hint = newGeo.entryPassageHint {
      let hintedKind: FloorplanPassageKind? = {
        switch hint.kind {
        case "door": return .door
        case "opening": return .opening
        default: return nil
        }
      }()
      if let hintedKind {
        let filtered = newPassages.filter { $0.kind == hintedKind && $0.index == hint.index }
        if !filtered.isEmpty {
          newPassages = filtered
        }
      }
    }
    guard !prevPassages.isEmpty, !newPassages.isEmpty else { return nil }

    guard let prevCentroidLocal = centroidLocal(from: prevGeo.segments),
          let newCentroidLocal = centroidLocal(from: newGeo.segments) else { return nil }

    // Precompute old room world centroid and bounds.
    let prevCentroidWorld = mapLocalPointToWorld(prevCentroidLocal, t: previous.transform)
    let prevBoundsWorld = boundsWorld(segmentsLocal: prevGeo.segments, t: previous.transform)

    var best: (score: Double, t: FloorplanRoomTransform, a: PassageCandidate, b: PassageCandidate)? = nil

    for a in prevPassages {
      let aWorld = transformSegment(segLocal: a.seg, t: previous.transform)
      let aMidWorld = midpoint(aWorld)
      let aDirWorld = normalized(direction(aWorld))

      for b in newPassages {
        // Candidate transform aligning passage b to passage a.
        let (candidateT, rotDeltaAbs) = dockTransform(
          sourceDirWorld: aDirWorld,
          sourceMidWorld: aMidWorld,
          targetSegLocal: b.seg
        )

        // Centroid side check: room centroids should lie on opposite sides of the door line.
        let newCentroidWorld = mapLocalPointToWorld(newCentroidLocal, t: candidateT)
        let vOld = DPoint(x: prevCentroidWorld.x - aMidWorld.x, y: prevCentroidWorld.y - aMidWorld.y)
        let vNew = DPoint(x: newCentroidWorld.x - aMidWorld.x, y: newCentroidWorld.y - aMidWorld.y)
        let crossOld = cross(aDirWorld, vOld)
        let crossNew = cross(aDirWorld, vNew)
        let oppositeSides = (crossOld == 0 || crossNew == 0) ? false : (crossOld * crossNew) < 0

        // Overlap penalty (bbox intersection ratio).
        let newBoundsWorld = boundsWorld(segmentsLocal: newGeo.segments, t: candidateT)
        let overlapRatio = boundsOverlapRatio(a: prevBoundsWorld, b: newBoundsWorld)

        let lenA = lengthMeters(aWorld)
        let lenB = lengthMeters(transformSegment(segLocal: b.seg, t: candidateT))
        let lenPenalty = abs(lenA - lenB) * 4.0

        var score = 0.0
        score += oppositeSides ? 0.0 : 35.0
        score += overlapRatio * 24.0
        score += lenPenalty
        score += rotDeltaAbs * 0.8

        if best == nil || score < best!.score {
          best = (score, candidateT, a, b)
        }
      }
    }

    guard let best else { return nil }
    // Require at least "somewhat plausible" placement.
    guard best.score <= 55 else { return nil }

    let connection = FloorplanRoomConnection(
      id: UUID(),
      createdAt: Date(),
      a: FloorplanPassageRef(scanId: previous.id, kind: best.a.kind, index: best.a.index),
      b: FloorplanPassageRef(scanId: newScanId, kind: best.b.kind, index: best.b.index)
    )
    return AutoDockResult(transform: best.t, connection: connection)
  }

  private func passageCandidates(from geo: FloorplanSegmentsFile) -> [PassageCandidate] {
    var out: [PassageCandidate] = []
    if let doors = geo.doors {
      for (idx, seg) in doors.enumerated() {
        out.append(PassageCandidate(kind: .door, index: idx, seg: seg))
      }
    }
    if let openings = geo.openings {
      for (idx, seg) in openings.enumerated() {
        out.append(PassageCandidate(kind: .opening, index: idx, seg: seg))
      }
    }
    return out
  }

  private func centroidLocal(from segments: [FloorplanSegment]) -> DPoint? {
    guard !segments.isEmpty else { return nil }
    var sumX = 0.0
    var sumY = 0.0
    var count = 0.0
    for s in segments {
      sumX += s.ax + s.bx
      sumY += s.ay + s.by
      count += 2.0
    }
    guard count > 0 else { return nil }
    return DPoint(x: sumX / count, y: sumY / count)
  }

  private func boundsWorld(segmentsLocal: [FloorplanSegment], t: FloorplanRoomTransform) -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
    var minX = Double.greatestFiniteMagnitude
    var minY = Double.greatestFiniteMagnitude
    var maxX = -Double.greatestFiniteMagnitude
    var maxY = -Double.greatestFiniteMagnitude
    for s in segmentsLocal {
      let w = transformSegment(segLocal: s, t: t)
      minX = min(minX, w.ax, w.bx)
      minY = min(minY, w.ay, w.by)
      maxX = max(maxX, w.ax, w.bx)
      maxY = max(maxY, w.ay, w.by)
    }
    if !minX.isFinite || !minY.isFinite || !maxX.isFinite || !maxY.isFinite {
      return (0, 0, 0, 0)
    }
    return (minX, minY, maxX, maxY)
  }

  private func boundsOverlapRatio(
    a: (minX: Double, minY: Double, maxX: Double, maxY: Double),
    b: (minX: Double, minY: Double, maxX: Double, maxY: Double)
  ) -> Double {
    let ix = max(0.0, min(a.maxX, b.maxX) - max(a.minX, b.minX))
    let iy = max(0.0, min(a.maxY, b.maxY) - max(a.minY, b.minY))
    let inter = ix * iy
    let areaA = max(0.0, (a.maxX - a.minX) * (a.maxY - a.minY))
    let areaB = max(0.0, (b.maxX - b.minX) * (b.maxY - b.minY))
    let denom = max(0.001, min(areaA, areaB))
    return inter / denom
  }

  private func dockTransform(
    sourceDirWorld: DPoint,
    sourceMidWorld: DPoint,
    targetSegLocal: FloorplanSegment
  ) -> (FloorplanRoomTransform, Double) {
    let sourceTheta = atan2(sourceDirWorld.y, sourceDirWorld.x)

    let targetDirLocal = direction(targetSegLocal)
    let targetThetaLocal = atan2(targetDirLocal.y, targetDirLocal.x)

    let diffA = normalizeAngle(sourceTheta - targetThetaLocal)
    let diffB = normalizeAngle((sourceTheta + Double.pi) - targetThetaLocal)
    let rotation = abs(diffA) <= abs(diffB) ? diffA : diffB

    let targetMidLocal = midpoint(targetSegLocal)
    let rotatedMid = rotatePoint(targetMidLocal, radians: rotation)
    let tx = sourceMidWorld.x - rotatedMid.x
    let ty = sourceMidWorld.y - rotatedMid.y
    return (FloorplanRoomTransform(translationX: tx, translationY: ty, rotationRadians: rotation), abs(rotation))
  }

  private func transformSegment(segLocal: FloorplanSegment, t: FloorplanRoomTransform) -> FloorplanSegment {
    let cosR = cos(t.rotationRadians)
    let sinR = sin(t.rotationRadians)
    func apply(x: Double, y: Double) -> (Double, Double) {
      let rx = x * cosR - y * sinR
      let ry = x * sinR + y * cosR
      return (rx + t.translationX, ry + t.translationY)
    }
    let (ax, ay) = apply(x: segLocal.ax, y: segLocal.ay)
    let (bx, by) = apply(x: segLocal.bx, y: segLocal.by)
    return FloorplanSegment(ax: ax, ay: ay, bx: bx, by: by)
  }

  private func mapLocalPointToWorld(_ p: DPoint, t: FloorplanRoomTransform) -> DPoint {
    let rotated = rotatePoint(p, radians: t.rotationRadians)
    return DPoint(x: rotated.x + t.translationX, y: rotated.y + t.translationY)
  }

  private func rotatePoint(_ p: DPoint, radians: Double) -> DPoint {
    let cosR = cos(radians)
    let sinR = sin(radians)
    return DPoint(x: p.x * cosR - p.y * sinR, y: p.x * sinR + p.y * cosR)
  }

  private func normalizeAngle(_ value: Double) -> Double {
    var v = value
    while v > Double.pi { v -= 2 * Double.pi }
    while v < -Double.pi { v += 2 * Double.pi }
    return v
  }

  private func midpoint(_ seg: FloorplanSegment) -> DPoint {
    DPoint(x: (seg.ax + seg.bx) * 0.5, y: (seg.ay + seg.by) * 0.5)
  }

  private func direction(_ seg: FloorplanSegment) -> DPoint {
    let vx = seg.bx - seg.ax
    let vy = seg.by - seg.ay
    return normalized(DPoint(x: vx, y: vy))
  }

  private func lengthMeters(_ seg: FloorplanSegment) -> Double {
    let dx = seg.bx - seg.ax
    let dy = seg.by - seg.ay
    return (dx * dx + dy * dy).squareRoot()
  }

  private func normalized(_ v: DPoint) -> DPoint {
    let len = (v.x * v.x + v.y * v.y).squareRoot()
    guard len > 1e-9 else { return DPoint(x: 1, y: 0) }
    return DPoint(x: v.x / len, y: v.y / len)
  }

  private func cross(_ a: DPoint, _ b: DPoint) -> Double {
    a.x * b.y - a.y * b.x
  }

  private struct DPoint: Hashable {
    var x: Double
    var y: Double
  }

  private struct PendingMailDraft: Identifiable {
    let id = UUID()
    let subject: String
    let message: String
    let attachments: [MailAttachmentData]
  }

  private struct GeneratedExportArtifacts {
    let paths: FloorplanProjectPaths
    let result: FloorplanComposerRenderer.CombinedResult
  }

  private struct RoomSemanticSummary: Hashable {
    let doorCount: Int
    let openingCount: Int
    let windowCount: Int
  }

  private struct ProjectOverview {
    let roomCount: Int
    let floorCount: Int
    let totalAreaSqmApprox: Double
    let totalDoorCount: Int
    let totalOpeningCount: Int
    let totalWindowCount: Int
  }

  private func combinedExportSubject(projectName: String) -> String {
    "PIXCAPTURE Grundriss \(projectName)"
  }

  private func combinedExportMessage(projectName: String) -> String {
    "Im Anhang befinden sich der Grundriss, das Datenblatt, OpenImmo und die CSV-/CRM-Dateien fuer \(projectName)."
  }

  private func combinedExportAttachmentURLs(from paths: FloorplanProjectPaths) -> [URL] {
    FloorplanProjectStore.finalExportURLs(paths: paths)
  }

  private func exportCombined() {
    do {
      let artifacts = try ensureExportArtifacts()
      _ = try? FloorplanProjectStore.copyFinalExportsToUserVisibleDirectory(
        projectKey: artifacts.paths.root.lastPathComponent,
        paths: artifacts.paths
      )
      try presentShareSheet(
        fileURLs: FloorplanProjectStore.existingFiles(from: combinedExportAttachmentURLs(from: artifacts.paths)),
        excludedActivityTypes: nil,
        subject: combinedExportSubject(projectName: exportDisplayName),
        message: combinedExportMessage(projectName: exportDisplayName)
      )
    } catch {
      exportMessage = error.localizedDescription
      showExportAlert = true
    }
  }

  private func prepareCombinedMailExport(existingOnly: Bool) {
    do {
      let paths = existingOnly ? try existingFinalExportPaths() : try ensureExportArtifacts().paths
      let attachmentURLs = FloorplanProjectStore.existingFiles(from: combinedExportAttachmentURLs(from: paths))
      guard !attachmentURLs.isEmpty else {
        throw NSError(
          domain: "FloorplanWorkflowView",
          code: 6,
          userInfo: [NSLocalizedDescriptionKey: "Keine fertigen Grundriss-Dateien gefunden."]
        )
      }
      let subject = combinedExportSubject(projectName: exportDisplayName)
      let message = combinedExportMessage(projectName: exportDisplayName)

      if MailComposerSheet.canSendMail() {
        let attachments = try attachmentURLs.map { try MailAttachmentData(fileURL: $0) }
        pendingMail = PendingMailDraft(subject: subject, message: message, attachments: attachments)
      } else {
        try presentShareSheet(
          fileURLs: attachmentURLs,
          excludedActivityTypes: nil,
          subject: subject,
          message: message
        )
      }
    } catch {
      exportMessage = error.localizedDescription
      showExportAlert = true
    }
  }

  private func copyCurrentExportToFiles() {
    do {
      let paths = try ensureExportArtifacts().paths
      guard let projectKey else {
        throw NSError(
          domain: "FloorplanWorkflowView",
          code: 5,
          userInfo: [NSLocalizedDescriptionKey: "Bitte zuerst einen Job waehlen."]
        )
      }
      let copy = try FloorplanProjectStore.copyFinalExportsToUserVisibleDirectory(projectKey: projectKey, paths: paths)
      exportMessage = "Grundriss-Dateien wurden sichtbar abgelegt:\nDateien > Auf meinem iPhone > PixCapture > FloorplanExports > \(copy.directory.lastPathComponent)\n\n\(copy.files.count) Dateien kopiert. Die Raumscan-Arbeitsdaten bleiben im Projekt erhalten."
      showExportAlert = true
    } catch {
      exportMessage = error.localizedDescription
      showExportAlert = true
    }
  }

  private func shareExistingFinalExport() {
    do {
      let paths = try existingFinalExportPaths()
      let urls = FloorplanProjectStore.existingFiles(from: combinedExportAttachmentURLs(from: paths))
      guard !urls.isEmpty else {
        throw NSError(
          domain: "FloorplanWorkflowView",
          code: 4,
          userInfo: [NSLocalizedDescriptionKey: "Keine fertigen Grundriss-Dateien gefunden."]
        )
      }
      try presentShareSheet(
        fileURLs: urls,
        excludedActivityTypes: nil,
        subject: combinedExportSubject(projectName: exportDisplayName),
        message: combinedExportMessage(projectName: exportDisplayName)
      )
    } catch {
      exportMessage = error.localizedDescription
      showExportAlert = true
    }
  }

  private func copyExistingFinalExportToFiles() {
    do {
      let paths = try existingFinalExportPaths()
      guard let projectKey else {
        throw NSError(
          domain: "FloorplanWorkflowView",
          code: 5,
          userInfo: [NSLocalizedDescriptionKey: "Bitte zuerst einen Job waehlen."]
        )
      }
      let copy = try FloorplanProjectStore.copyFinalExportsToUserVisibleDirectory(projectKey: projectKey, paths: paths)
      exportMessage = "Grundriss-Dateien wurden sichtbar abgelegt:\nDateien > Auf meinem iPhone > PixCapture > FloorplanExports > \(copy.directory.lastPathComponent)\n\n\(copy.files.count) Dateien kopiert."
      showExportAlert = true
    } catch {
      exportMessage = error.localizedDescription
      showExportAlert = true
    }
  }

  private func existingFinalExportPaths() throws -> FloorplanProjectPaths {
    guard let projectKey else {
      throw NSError(
        domain: "FloorplanWorkflowView",
        code: 3,
        userInfo: [NSLocalizedDescriptionKey: "Bitte zuerst einen Job waehlen."]
      )
    }
    return try FloorplanProjectStore.projectPaths(projectKey: projectKey)
  }

  private func ensureExportArtifacts() throws -> GeneratedExportArtifacts {
    guard let project, !project.roomScans.isEmpty else {
      throw NSError(
        domain: "FloorplanWorkflowView",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Keine Raumscans im Projekt vorhanden."]
      )
    }
    guard let projectKey else {
      throw NSError(
        domain: "FloorplanWorkflowView",
        code: 3,
        userInfo: [NSLocalizedDescriptionKey: "Bitte zuerst einen Job waehlen."]
      )
    }

    let paths = try FloorplanProjectStore.projectPaths(projectKey: projectKey)
    let exportMetadata = FloorplanComposerRenderer.ExportMetadata(
      projectKey: project.projectKey,
      projectName: exportDisplayName,
      jobId: settings.selectedJobId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
      jobAddress: settings.jobAddress.trimmingCharacters(in: .whitespacesAndNewlines),
      projectCreatedAt: project.createdAt,
      generatedAt: Date()
    )
    let result = try FloorplanComposerRenderer.exportCombinedFloorplan(
      project: project,
      outputPNG: paths.combinedPNG,
      outputPDF: paths.combinedPDF,
      outputVisualPDF: paths.visualPDF,
      outputDataPDF: paths.dataPDF,
      outputDataCSV: paths.dataCSV,
      outputSummaryCSV: paths.summaryCSV,
      outputRoomsCSV: paths.roomsCSV,
      outputCRMPropertyCSV: paths.crmPropertyCSV,
      outputCRMRoomsCSV: paths.crmRoomsCSV,
      outputOpenImmoXML: paths.openImmoXML,
      exportTitle: exportDisplayName,
      exportMetadata: exportMetadata,
      resolveURL: { rel in try FloorplanProjectStore.resolve(projectKey: projectKey, relativePath: rel) }
    )
    return GeneratedExportArtifacts(paths: paths, result: result)
  }

  private func presentShareSheet(
    fileURLs: [URL],
    excludedActivityTypes: [UIActivity.ActivityType]?,
    subject: String? = nil,
    message: String? = nil
  ) throws {
    let stagedURLs = try stageFilesForShare(fileURLs)
    guard !stagedURLs.isEmpty else {
      throw NSError(
        domain: "FloorplanWorkflowView",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Keine exportierbaren Dateien gefunden."]
      )
    }

    var items: [Any] = []
    if let subject, let message {
      items.append(MailShareMessageItemSource(subject: subject, message: message))
    }
    items.append(contentsOf: stagedURLs)

    shareExcludedActivityTypes = excludedActivityTypes
    shareItems = items
    showShareSheet = true
  }

  private func stageFilesForShare(_ fileURLs: [URL]) throws -> [URL] {
    let fm = FileManager.default
    cleanupShareStagingDirectory()

    let stagingDir = fm.temporaryDirectory.appendingPathComponent(
      "pixcapture-floorplan-share-\(UUID().uuidString)",
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

  private func l10n(_ key: String) -> String {
    settings.localized(key)
  }

  private func l10nFormat(_ key: String, _ arguments: CVarArg...) -> String {
    AppLocalizer.localizedFormat(key, language: settings.appLanguage, arguments: arguments)
  }
}
