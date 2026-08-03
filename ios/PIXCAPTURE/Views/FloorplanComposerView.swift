import SwiftUI

struct FloorplanComposerView: View {
  let projectKey: String
  @Binding var project: FloorplanProject
  let onDone: () -> Void
  @EnvironmentObject private var settings: AppSettings

  private enum FloorplanTheme {
    static let primary = Color(red: 42.0 / 255.0, green: 63.0 / 255.0, blue: 104.0 / 255.0)
    static let secondary = Color(red: 108.0 / 255.0, green: 168.0 / 255.0, blue: 200.0 / 255.0)
    static let accent = Color(red: 209.0 / 255.0, green: 94.0 / 255.0, blue: 64.0 / 255.0)
    static let neutral = Color(red: 95.0 / 255.0, green: 100.0 / 255.0, blue: 106.0 / 255.0)
    static let canvas = Color(red: 0.97, green: 0.98, blue: 0.99)
  }

  private enum ToolMode: String {
    case move
    case doors
    case connect
    case drawRoom
  }

  private enum PassageEditMode: String {
    case addDoor
    case addOpening
    case addWindow
    case rotateDoor
    case remove
  }

  private enum RouteOverlayMode: String, CaseIterable {
    case manual
    case suggested

    var displayName: String {
      switch self {
      case .manual:
        return "Manuell"
      case .suggested:
        return "Auto-Vorschlag"
      }
    }
  }

  private struct QuickAction: Identifiable {
    let title: String
    let systemImage: String
    let tint: Color
    let isEnabled: Bool
    let action: () -> Void

    var id: String { "\(title)-\(systemImage)" }
  }

  @State private var geometryByScanId: [UUID: FloorplanSegmentsFile] = [:]
  @State private var selectedScanId: UUID? = nil
  @State private var toolMode: ToolMode = .move
  @State private var passageEditMode: PassageEditMode = .addDoor

  @State private var showRouteOverlay: Bool = false
  @State private var routeMode: RouteOverlayMode = .manual
  @State private var routePointsWorld: [DPoint] = []
  @State private var routeMessage: String? = nil
  @State private var handlesVisibleUntil: Date? = nil
  @State private var handlesVisibilityToken: UUID = UUID()

  @State private var zoom: CGFloat = 1.0
  @State private var pan: CGSize = .zero
  @State private var lastPan: CGSize = .zero
  @State private var lastZoom: CGFloat = 1.0
  @State private var baseFitScale: CGFloat = 60
  @State private var baseFitCenterWorld: DPoint = DPoint(x: 0, y: 0)
  @State private var lastCanvasSize: CGSize = .zero
  @State private var hasBaseFit: Bool = false
  @State private var activeRoomDragStart: FloorplanRoomTransform? = nil
  @State private var activePanStart: CGSize? = nil
  @State private var activeRoomRotation: ActiveRoomRotationState? = nil
  @State private var activeDragKind: DragKind? = nil
  @State private var activeWallSelection: WallSelection? = nil
  @State private var activeWallDragStartGeometry: FloorplanSegmentsFile? = nil
  @State private var pendingRotationSnapId: UUID? = nil
  @State private var doorDockPreview: DoorDockPreview? = nil
  @State private var connectSourceDoor: DoorSelection? = nil
  @State private var activePassageSelection: DoorSelection? = nil
  @State private var showAllWallMeasurements: Bool = false
  @State private var isToolPaletteExpanded: Bool = false
  @State private var manualRoomDraftPoints: [DPoint] = []
  @State private var isFourCornerManualRoomMode: Bool = false
  @State private var isManualRoomPickerPresented = false
  @State private var manualRoomRoomId: String = RoomTaxonomy.defaultRoomId
  @State private var manualRoomFloorId: String = FloorTaxonomy.defaultFloorId
  @State private var isStairPickerPresented = false
  @State private var stairFromFloorId: String = FloorTaxonomy.defaultFloorId
  @State private var stairToFloorId: String = FloorTaxonomy.defaultFloorId
  @State private var isPlacingStairConnection = false
  @State private var toolPaletteOffset: CGSize = .zero
  @State private var lastToolPaletteOffset: CGSize = .zero

  private enum DragKind: Hashable {
    case roomMove
    case roomRotate
    case wallMove
    case pan
  }

  private let handleMoveRadiusPx: CGFloat = 38
  private let handleRotateRadiusPx: CGFloat = 38
  private let handleRotateOffsetXPx: CGFloat = 140
  private let wallMeasureMinLengthMeters: Double = 0.55
  private let interiorWallLineWidthPx: CGFloat = 4.2
  private let exteriorWallLineWidthPx: CGFloat = 8.2
  private let selectedWallHighlightWidthPx: CGFloat = 6.0

  private let snapThresholdMeters: Double = 0.35
  private let doorDefaultHalfWidthMeters: Double = 0.45
  private let openingDefaultHalfWidthMeters: Double = 0.82
  private let tapHitThresholdMeters: Double = 0.24
  private let doorDockThresholdMeters: Double = 0.75
  private let doorDockMaxRotationRadians: Double = Double.pi * 0.75 // avoid crazy flips
  private let connectHitThresholdMeters: Double = 0.26
  private let manualDraftCloseHitMeters: Double = 0.38

  private enum PassageKind: String, Hashable {
    case door
    case opening
    case window
  }

  private struct DoorSelection: Hashable {
    let scanId: UUID
    let kind: PassageKind
    let index: Int
  }

  private struct WallSelection: Hashable {
    let scanId: UUID
    let index: Int
  }

  private struct DoorDockPreview: Hashable {
    let movingScanId: UUID
    let otherScanId: UUID
    let movingDoorWorld: FloorplanSegment
    let otherDoorWorld: FloorplanSegment
    let targetTransform: FloorplanRoomTransform
  }

  private struct PassageEditResult {
    let message: String
    let selection: DoorSelection?
    let changed: Bool
  }

  private enum DetectedPassageRemoval {
    case door(index: Int)
    case opening(index: Int)
    case window(index: Int)

    var label: String {
      switch self {
      case .door:
        return "Tür"
      case .opening:
        return "Durchgang"
      case .window:
        return "Fenster"
      }
    }
  }

  private struct ActiveRoomRotationState {
    let scanId: UUID
    let startTransform: FloorplanRoomTransform
    let pivotLocal: DPoint
    let pivotWorld: DPoint
    let pivotScreen: DPoint
    let startAngleScreenRadians: Double
  }

  var body: some View {
    ZStack {
      FloorplanTheme.canvas.ignoresSafeArea()

      GeometryReader { geo in
        Canvas { context, size in
          draw(context: &context, size: size)
        }
        .gesture(canvasGestures(viewSize: geo.size))
        .contentShape(Rectangle())
        .simultaneousGesture(
          SpatialTapGesture()
            .onEnded { value in
              handleTap(at: value.location, viewSize: geo.size)
            }
        )
        .onAppear {
          ensureBaseFit(viewSize: geo.size)
        }
        .onChange(of: geo.size) { _, newSize in
          ensureBaseFit(viewSize: newSize, force: true)
        }
      }
      .ignoresSafeArea()

      VStack(spacing: 8) {
        topBar
        if isToolPaletteExpanded {
          quickActionsBar
            .transition(.move(edge: .top).combined(with: .opacity))
        }
      }
      .padding(.horizontal, 14)
      .padding(.top, 12)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

      roomChips
        .padding(.horizontal, 14)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

      if let routeMessage {
        Text(routeMessage)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 12)
          .padding(.vertical, 10)
          .background(Color.black.opacity(0.75))
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          .padding(.horizontal, 18)
          .padding(.bottom, 22)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
          .transition(.opacity)
      }
    }
    .onAppear {
      loadSegments()
      pruneInvalidConnectionsIfNeeded(persist: false)
      if selectedScanId == nil {
        selectedScanId = project.roomScans.first?.id
      }
      if lastCanvasSize.width > 1, lastCanvasSize.height > 1 {
        ensureBaseFit(viewSize: lastCanvasSize, force: true)
      }
    }
    .onDisappear {
      try? FloorplanProjectStore.save(project: project)
    }
    .sheet(isPresented: $isManualRoomPickerPresented) {
      RoomPickerView(
        selectedRoomId: $manualRoomRoomId,
        selectedFloorId: $manualRoomFloorId,
        onDone: {
          finalizeManualRoomDrawing()
        }
      )
    }
    .sheet(isPresented: $isStairPickerPresented) {
      StairConnectionPickerSheet(
        fromFloorId: $stairFromFloorId,
        toFloorId: $stairToFloorId,
        onCancel: {
          isPlacingStairConnection = false
          isStairPickerPresented = false
        },
        onStartPlacement: {
          guard stairFromFloorId != stairToFloorId else {
            showToast("Start- und Ziel-Etage müssen unterschiedlich sein.")
            return
          }
          isStairPickerPresented = false
          isPlacingStairConnection = true
          toolMode = .move
          showToast("Tippe auf die Position der Treppe im Grundriss.")
        }
      )
    }
  }

  private var topBar: some View {
    HStack(spacing: 10) {
      Button(action: onDone) {
        HStack(spacing: 6) {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 14, weight: .semibold))
          Text("Fertig")
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
        }
        .foregroundStyle(FloorplanTheme.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.96))
        .clipShape(Capsule())
        .overlay(
          Capsule()
            .stroke(FloorplanTheme.primary.opacity(0.18), lineWidth: 1)
        )
      }
      .accessibilityLabel("Grundriss fertigstellen")

      // Minimal mode controls (avoid many tiny buttons). Room handles appear contextually on tap/drag.
      HStack(spacing: 8) {
        modeButton(mode: .move, systemImage: "arrow.up.and.down.and.arrow.left.and.right", tint: FloorplanTheme.primary)
        modeButton(mode: .doors, systemImage: "door.left.hand.open", tint: FloorplanTheme.neutral)
        modeButton(mode: .connect, systemImage: "link", tint: FloorplanTheme.secondary)
        modeButton(mode: .drawRoom, systemImage: "pencil.line", tint: FloorplanTheme.accent)
      }

      Spacer()

      Button {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
          isToolPaletteExpanded.toggle()
        }
      } label: {
        HStack(spacing: 6) {
          Image(systemName: isToolPaletteExpanded ? "wrench.and.screwdriver.fill" : "wrench.and.screwdriver")
            .font(.system(size: 13, weight: .semibold))
          Text("Werkzeuge")
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
        }
        .foregroundStyle(isToolPaletteExpanded ? FloorplanTheme.primary : FloorplanTheme.primary.opacity(0.88))
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(isToolPaletteExpanded ? FloorplanTheme.primary.opacity(0.12) : Color.white.opacity(0.96))
        .clipShape(Capsule())
        .overlay(
          Capsule()
            .stroke(isToolPaletteExpanded ? FloorplanTheme.primary.opacity(0.35) : FloorplanTheme.primary.opacity(0.14), lineWidth: 1)
        )
      }
      .accessibilityLabel("Werkzeuge")

      Menu {
        Button(showRouteOverlay ? "Route ausblenden" : "Route anzeigen") { toggleRouteOverlay() }
        Menu("Route-Modus: \(routeMode.displayName)") {
          Button("Manuell") { setRouteMode(.manual) }
          Button("Auto-Vorschlag") { setRouteMode(.suggested) }
        }
        if routeMode == .manual {
          Button("Letzten Wegpunkt löschen") { removeLastManualRoutePoint() }
            .disabled(project.routePoints.isEmpty)
          Button("Route leeren", role: .destructive) { clearManualRoutePoints() }
            .disabled(project.routePoints.isEmpty)
        }
        Divider()
        Button(showAllWallMeasurements ? "Bemaßung: nur ausgewählter Raum" : "Bemaßung: alle Räume") {
          showAllWallMeasurements.toggle()
        }
        if !project.connections.isEmpty {
          Divider()
          Button("Verbindungen löschen", role: .destructive) {
            project.connections.removeAll()
            try? FloorplanProjectStore.save(project: project)
            if showRouteOverlay { recomputeRouteOverlay() }
          }
        }
        if !project.stairConnections.isEmpty {
          Divider()
          Button("Treppen-Verbindungen löschen", role: .destructive) {
            project.stairConnections.removeAll()
            isPlacingStairConnection = false
            try? FloorplanProjectStore.save(project: project)
            showToast("Treppen-Verbindungen gelöscht.")
          }
        }
      } label: {
        Image(systemName: "ellipsis")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(FloorplanTheme.primary.opacity(0.82))
          .frame(width: 36, height: 36)
          .background(Color.white)
          .clipShape(Circle())
          .overlay(Circle().stroke(FloorplanTheme.primary.opacity(0.16), lineWidth: 1))
          .frame(width: 44, height: 44)
      }
      .accessibilityLabel("Menü")
    }
  }

  private var quickActionsBar: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(toolMode == .move ? "Schnellaktionen" : "Werkzeuge")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Color.black.opacity(0.45))
        .padding(.horizontal, 2)

      ForEach(chunkedQuickActions(currentQuickActions, size: 3).indices, id: \.self) { rowIndex in
        HStack(spacing: 6) {
          ForEach(chunkedQuickActions(currentQuickActions, size: 3)[rowIndex]) { action in
            quickActionButton(
              title: action.title,
              systemImage: action.systemImage,
              tint: action.tint,
              isEnabled: action.isEnabled,
              action: action.action
            )
          }
        }
      }
    }
    .padding(7)
    .background(.ultraThinMaterial)
    .background(Color.white.opacity(0.54))
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(Color.black.opacity(0.07), lineWidth: 1)
    )
    .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
    .frame(maxWidth: 218, alignment: .trailing)
    .frame(maxWidth: .infinity, alignment: .trailing)
    .offset(toolPaletteOffset)
    .gesture(
      DragGesture()
        .onChanged { value in
          toolPaletteOffset = CGSize(
            width: lastToolPaletteOffset.width + value.translation.width,
            height: lastToolPaletteOffset.height + value.translation.height
          )
        }
        .onEnded { _ in
          lastToolPaletteOffset = toolPaletteOffset
        }
    )
  }

  private func quickActionButton(
    title: String,
    systemImage: String,
    tint: Color,
    isEnabled: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      VStack(spacing: 3) {
        Image(systemName: systemImage)
          .font(.system(size: 11, weight: .semibold))
        Text(title)
          .font(.system(size: 8.5, weight: .semibold))
          .lineLimit(2)
          .minimumScaleFactor(0.70)
          .multilineTextAlignment(.center)
      }
      .foregroundStyle(isEnabled ? tint.opacity(0.95) : Color.black.opacity(0.35))
      .frame(maxWidth: .infinity, minHeight: 34)
      .padding(.horizontal, 5)
      .padding(.vertical, 5)
      .background(isEnabled ? tint.opacity(0.09) : Color.white.opacity(0.52))
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(isEnabled ? tint.opacity(0.38) : Color.black.opacity(0.08), lineWidth: 1)
      )
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    .disabled(!isEnabled)
    .buttonStyle(.plain)
  }

  private var currentQuickActions: [QuickAction] {
    if toolMode == .drawRoom {
      return [
        QuickAction(
          title: isFourCornerManualRoomMode ? "4 Ecken aktiv" : "4 Ecken",
          systemImage: "square",
          tint: isFourCornerManualRoomMode ? FloorplanTheme.primary : FloorplanTheme.neutral,
          isEnabled: true,
          action: toggleFourCornerManualRoomMode
        ),
        QuickAction(
          title: "Punkt zurück",
          systemImage: "arrow.uturn.backward",
          tint: FloorplanTheme.neutral,
          isEnabled: !manualRoomDraftPoints.isEmpty,
          action: removeLastManualDraftPoint
        ),
        QuickAction(
          title: isFourCornerManualRoomMode ? "\(manualRoomDraftPoints.count)/4 speichern" : "Raum speichern",
          systemImage: "checkmark.circle",
          tint: FloorplanTheme.primary,
          isEnabled: isFourCornerManualRoomMode ? manualRoomDraftPoints.count == 4 : manualRoomDraftPoints.count >= 3,
          action: beginManualRoomMetadataSelection
        ),
        QuickAction(
          title: "Zeichnen beenden",
          systemImage: "xmark.circle",
          tint: FloorplanTheme.accent,
          isEnabled: true,
          action: cancelManualRoomDrawing
        )
      ]
    }

    if toolMode == .doors {
      return [
        QuickAction(
          title: passageEditMode == .addDoor ? "Tür aktiv" : "Tür",
          systemImage: "door.left.hand.open",
          tint: passageEditMode == .addDoor ? FloorplanTheme.primary : FloorplanTheme.neutral,
          isEnabled: true,
          action: { applyPassagePaletteMode(.addDoor) }
        ),
        QuickAction(
          title: passageEditMode == .addOpening ? "Durchgang aktiv" : "Durchgang",
          systemImage: "arrow.left.and.right",
          tint: passageEditMode == .addOpening ? FloorplanTheme.secondary : FloorplanTheme.neutral,
          isEnabled: true,
          action: { applyPassagePaletteMode(.addOpening) }
        ),
        QuickAction(
          title: passageEditMode == .addWindow ? "Fenster aktiv" : "Fenster",
          systemImage: "rectangle.split.3x1",
          tint: passageEditMode == .addWindow ? FloorplanTheme.secondary : FloorplanTheme.neutral,
          isEnabled: true,
          action: { applyPassagePaletteMode(.addWindow) }
        ),
        QuickAction(
          title: passageEditMode == .rotateDoor ? "Drehen aktiv" : "Tür drehen",
          systemImage: "rotate.3d",
          tint: passageEditMode == .rotateDoor ? FloorplanTheme.primary : FloorplanTheme.neutral,
          isEnabled: true,
          action: { applyPassagePaletteMode(.rotateDoor) }
        ),
        QuickAction(
          title: passageEditMode == .remove ? "Entfernen aktiv" : "Entfernen",
          systemImage: "trash",
          tint: passageEditMode == .remove ? FloorplanTheme.accent : FloorplanTheme.neutral,
          isEnabled: true,
          action: { applyPassagePaletteMode(.remove) }
        ),
        QuickAction(
          title: "Ansicht zentrieren",
          systemImage: "scope",
          tint: FloorplanTheme.neutral,
          isEnabled: true,
          action: resetView
        )
      ]
    }

    return [
      QuickAction(
        title: l10n("floorplan.composer.action.drawRoom"),
        systemImage: "plus.rectangle.on.rectangle",
        tint: FloorplanTheme.primary,
        isEnabled: true,
        action: { setToolMode(.drawRoom) }
      ),
      QuickAction(
        title: "Andocken",
        systemImage: "square.on.square",
        tint: FloorplanTheme.primary,
        isEnabled: selectedScanId != nil,
        action: autoDockAndConnectSelectedRoom
      ),
      QuickAction(
        title: activeWallSelection == nil ? "Wand wählen" : "Wand aktiv",
        systemImage: "line.diagonal",
        tint: activeWallSelection == nil ? FloorplanTheme.neutral : FloorplanTheme.accent,
        isEnabled: true,
        action: { showToast(activeWallSelection == nil ? "Tippe auf eine Wand, um sie zu bearbeiten." : "Ziehe die markierte Wand oder entferne sie.") }
      ),
      QuickAction(
        title: "Wand löschen",
        systemImage: "trash",
        tint: FloorplanTheme.accent,
        isEnabled: activeWallSelection != nil,
        action: removeActiveWall
      ),
      QuickAction(
        title: "Auto verbinden",
        systemImage: "link.badge.plus",
        tint: FloorplanTheme.secondary,
        isEnabled: project.roomScans.count >= 2,
        action: autoConnectNearbyPassages
      ),
      QuickAction(
        title: "Auto anordnen",
        systemImage: "square.grid.3x2",
        tint: FloorplanTheme.accent,
        isEnabled: !project.roomScans.isEmpty,
        action: autoLayout
      ),
      QuickAction(
        title: isPlacingStairConnection ? "Treppe platzieren" : "Treppe",
        systemImage: "stairs",
        tint: FloorplanTheme.primary,
        isEnabled: true,
        action: toggleStairPlacementFlow
      ),
      QuickAction(
        title: "Ansicht zentrieren",
        systemImage: "scope",
        tint: FloorplanTheme.neutral,
        isEnabled: true,
        action: resetView
      ),
      QuickAction(
        title: "Verbindung lösen",
        systemImage: "xmark.circle",
        tint: FloorplanTheme.accent,
        isEnabled: hasConnectionForSelectedRoom(),
        action: removeConnectionForSelectedRoom
      )
    ]
  }

  private func chunkedQuickActions(_ actions: [QuickAction], size: Int) -> [[QuickAction]] {
    guard size > 0, !actions.isEmpty else { return [] }
    return stride(from: 0, to: actions.count, by: size).map { start in
      let end = min(start + size, actions.count)
      return Array(actions[start..<end])
    }
  }

  private func modeButton(mode: ToolMode, systemImage: String, tint: Color) -> some View {
    Button {
      setToolMode(mode)
    } label: {
      Image(systemName: systemImage)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(Color.black.opacity(0.65))
        .frame(width: 36, height: 36)
        .background(toolMode == mode ? tint.opacity(0.16) : Color.white)
        .clipShape(Circle())
        .overlay(Circle().stroke(toolMode == mode ? tint.opacity(0.55) : Color.black.opacity(0.08), lineWidth: 1))
        .frame(width: 44, height: 44)
    }
    .accessibilityLabel(
      mode == .move ? "Bewegen" :
        (mode == .doors ? "Tür-Modus" : (mode == .connect ? "Räume verbinden" : "Raum zeichnen"))
    )
  }

  private var roomChips: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 10) {
        ForEach(project.roomScans) { scan in
          let selected = scan.id == selectedScanId
          Button {
            selectedScanId = scan.id
            activeWallSelection = nil
            activePassageSelection = nil
            showRoomHandles(for: 2.2)
          } label: {
            VStack(alignment: .leading, spacing: 2) {
              Text(RoomTaxonomy.room(id: scan.roomId).displayName)
                .font(.system(size: 12, weight: .semibold))
              Text(FloorTaxonomy.floor(id: scan.floorId).shortDisplayName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.55))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(selected ? Color(red: 0.29, green: 0.35, blue: 0.29).opacity(0.18) : Color.white)
            .overlay(
              RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(selected ? Color(red: 0.29, green: 0.35, blue: 0.29).opacity(0.55) : Color.black.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
          }
        }
      }
      .padding(.vertical, 2)
    }
  }

  private func loadSegments() {
    var dict: [UUID: FloorplanSegmentsFile] = [:]
    for scan in project.roomScans {
      if let url = try? FloorplanProjectStore.resolve(projectKey: projectKey, relativePath: scan.segmentsJSONPath),
         let data = try? Data(contentsOf: url),
         let decoded = try? JSONDecoder().decode(FloorplanSegmentsFile.self, from: data) {
        dict[scan.id] = decoded.normalizedForDisplay()
      }
    }
    geometryByScanId = dict
    if lastCanvasSize.width > 1, lastCanvasSize.height > 1 {
      ensureBaseFit(viewSize: lastCanvasSize, force: true)
    }
  }

  private func ensureBaseFit(viewSize: CGSize, force: Bool = false) {
    guard viewSize.width > 20, viewSize.height > 20 else { return }
    lastCanvasSize = viewSize
    if hasBaseFit && !force { return }

    let bounds = combinedBoundsMeters()
    let widthM = max(bounds.maxX - bounds.minX, 0.5)
    let heightM = max(bounds.maxY - bounds.minY, 0.5)
    let margin: CGFloat = 40
    let fitScale = min(
      (viewSize.width - margin * 2) / CGFloat(widthM),
      (viewSize.height - margin * 2) / CGFloat(heightM)
    )

    baseFitScale = max(20, fitScale)
    baseFitCenterWorld = DPoint(
      x: (bounds.minX + bounds.maxX) * 0.5,
      y: (bounds.minY + bounds.maxY) * 0.5
    )
    hasBaseFit = true
  }

  private func resetView() {
    zoom = 1.0
    pan = .zero
    lastPan = .zero
    lastZoom = 1.0
    if lastCanvasSize.width > 1, lastCanvasSize.height > 1 {
      ensureBaseFit(viewSize: lastCanvasSize, force: true)
    } else {
      hasBaseFit = false
    }
  }

  private func autoLayout() {
    guard !project.roomScans.isEmpty else { return }
    let floorOrder = Dictionary(uniqueKeysWithValues: FloorTaxonomy.floors.enumerated().map { ($1.id, $0) })
    let indexByScanId = Dictionary(uniqueKeysWithValues: project.roomScans.enumerated().map { ($1.id, $0) })
    let orderedFloorIds = Array(Set(project.roomScans.map(\.floorId))).sorted {
      (floorOrder[$0] ?? Int.max) < (floorOrder[$1] ?? Int.max)
    }

    let floorGapY = 2.8
    var floorTopY = 0.0
    var previousFloorHeight = 0.0
    var createdConnections = 0

    for (floorIndex, floorId) in orderedFloorIds.enumerated() {
      let floorScanIds = project.roomScans
        .filter { $0.floorId == floorId }
        .map(\.id)
        .sorted { (indexByScanId[$0] ?? Int.max) < (indexByScanId[$1] ?? Int.max) }

      guard !floorScanIds.isEmpty else { continue }

      createdConnections += autoDockRoomsOnFloor(scanIds: floorScanIds)

      guard let floorBounds = componentBoundsMeters(scanIds: floorScanIds) else { continue }

      if floorIndex > 0 {
        floorTopY -= (previousFloorHeight + floorGapY)
      }

      let dx = -floorBounds.minX
      let dy = floorTopY - floorBounds.maxY

      for scanId in floorScanIds {
        guard let idx = project.roomScans.firstIndex(where: { $0.id == scanId }) else { continue }
        project.roomScans[idx].transform.translationX += dx
        project.roomScans[idx].transform.translationY += dy
      }

      previousFloorHeight = max(1.0, floorBounds.maxY - floorBounds.minY)
    }

    try? FloorplanProjectStore.save(project: project)
    if showRouteOverlay {
      recomputeRouteOverlay()
    }
    resetView()
    if createdConnections > 0 {
      showToast("Auto-Anordnung hat \(createdConnections) Raumverbindung(en) kompakt angedockt und den Grundriss neu ausgerichtet.")
    } else {
      showToast("Auto-Anordnung erhält die aktuelle Raumlage jetzt stabiler und richtet nur den Gesamtgrundriss aus.")
    }
  }

  private func autoDockRoomsOnFloor(scanIds: [UUID]) -> Int {
    guard scanIds.count >= 2 else { return 0 }

    var createdConnections = 0
    let dockDistance = max(doorDockThresholdMeters * 2.4, 1.8)

    for movingScanId in scanIds.dropFirst() {
      guard let preview = computeBestDoorDockPreview(
        movingScanId: movingScanId,
        maxDistanceMeters: dockDistance
      ) else { continue }
      guard scanIds.contains(preview.otherScanId) else { continue }
      guard let roomIndex = project.roomScans.firstIndex(where: { $0.id == movingScanId }) else { continue }

      project.roomScans[roomIndex].transform = preview.targetTransform

      let movingMid = midpoint(of: preview.movingDoorWorld)
      let otherMid = midpoint(of: preview.otherDoorWorld)
      if let source = nearestPassageSelection(
        scanId: preview.otherScanId,
        nearWorldPoint: otherMid,
        maxDistanceMeters: 0.45
      ),
         let target = nearestPassageSelection(
           scanId: movingScanId,
           nearWorldPoint: movingMid,
           maxDistanceMeters: 0.45
         ),
         upsertConnection(a: source, b: target) {
        createdConnections += 1
      }
    }

    return createdConnections
  }

  private func componentBoundsMeters(scanIds: [UUID]) -> Bounds? {
    var minX = Double.greatestFiniteMagnitude
    var minY = Double.greatestFiniteMagnitude
    var maxX = -Double.greatestFiniteMagnitude
    var maxY = -Double.greatestFiniteMagnitude

    for scanId in scanIds {
      guard let scan = project.roomScans.first(where: { $0.id == scanId }),
            let bounds = roomBoundsMeters(scan: scan) else { continue }
      minX = min(minX, bounds.minX)
      minY = min(minY, bounds.minY)
      maxX = max(maxX, bounds.maxX)
      maxY = max(maxY, bounds.maxY)
    }

    guard minX.isFinite, minY.isFinite, maxX.isFinite, maxY.isFinite else { return nil }
    return Bounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
  }

  private func setToolMode(_ mode: ToolMode) {
    // Tapping the same mode again returns to Move.
    toolMode = (toolMode == mode) ? .move : mode
    withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
      isToolPaletteExpanded = toolMode != .move
    }
    connectSourceDoor = nil
    doorDockPreview = nil
    if toolMode != .move {
      activeWallSelection = nil
    }
    if toolMode != .drawRoom {
      manualRoomDraftPoints.removeAll()
      isFourCornerManualRoomMode = false
    }
    if toolMode == .drawRoom {
      isPlacingStairConnection = false
    }

    switch toolMode {
    case .move:
      showToast("Bewegen: Tap = Raum wählen · Drag = bewegen · Drehpfeil = Rotation · Pinch = Zoom")
    case .doors:
      showToast("Passagen: Werkzeug oben auf Tür, Durchgang oder Entfernen stellen.")
    case .connect:
      showToast("Verbinden: Tippe Tür/Öffnung A · Tippe Tür/Öffnung B")
    case .drawRoom:
      showToast("Zeichnen: Eckpunkte setzen · \"Raum speichern\" für Raumtyp/Etage.")
    }
  }

  private func toggleRouteOverlay() {
    if showRouteOverlay {
      showRouteOverlay = false
      routePointsWorld = []
      return
    }

    showRouteOverlay = true
    recomputeRouteOverlay()
    switch routeMode {
    case .manual:
      if project.routePoints.isEmpty {
        showToast("Route: Tippe den Startpunkt. Weitere Taps setzen Wegpunkte.")
      } else {
        showToast("Route: Tippe, um Wegpunkte hinzuzufügen. Tap nahe einem Punkt entfernt ihn.")
      }
    case .suggested:
      showToast("Auto-Route auf Basis der Tür-Verbindungen aktiviert.")
    }
  }

  private func setRouteMode(_ mode: RouteOverlayMode) {
    routeMode = mode
    if showRouteOverlay {
      recomputeRouteOverlay()
    }
    if mode == .manual {
      showToast("Manuelle Route: Startpunkt + Wegpunkte per Tap setzen.")
    } else {
      showToast("Auto-Route: Vorschlag aus Raumverbindungen.")
    }
  }

  private func clearManualRoutePoints() {
    project.routePoints.removeAll()
    try? FloorplanProjectStore.save(project: project)
    if showRouteOverlay {
      recomputeRouteOverlay()
    }
    showToast("Manuelle Route gelöscht.")
  }

  private func removeLastManualRoutePoint() {
    guard !project.routePoints.isEmpty else { return }
    project.routePoints.removeLast()
    try? FloorplanProjectStore.save(project: project)
    if showRouteOverlay {
      recomputeRouteOverlay()
    }
    showToast("Letzter Wegpunkt entfernt.")
  }

  private func showToast(_ text: String) {
    withAnimation {
      routeMessage = text
    }
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 5_000_000_000)
      withAnimation {
        routeMessage = nil
      }
    }
  }

  private func showRoomHandles(for seconds: Double = 2.0) {
    let token = UUID()
    handlesVisibilityToken = token
    handlesVisibleUntil = Date().addingTimeInterval(seconds)
    Task { @MainActor in
      let ns = UInt64(max(0.1, seconds + 0.05) * 1_000_000_000)
      try? await Task.sleep(nanoseconds: ns)
      guard handlesVisibilityToken == token else { return }
      if let until = handlesVisibleUntil, until <= Date() {
        handlesVisibleUntil = nil
      }
    }
  }

  private func canvasGestures(viewSize: CGSize) -> some Gesture {
    let drag = DragGesture()
      .onChanged { value in
        // In door/connect modes, dragging should always pan (avoid accidental room moves).
        if toolMode != .move {
          if activeDragKind == nil { activeDragKind = .pan }
          if activePanStart == nil { activePanStart = lastPan }
          let start = activePanStart ?? lastPan
          pan = CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height)
          doorDockPreview = nil
          return
        }

        let (scale, origin) = mapping(viewSize: viewSize)

        if let selectedScanId, let idx = project.roomScans.firstIndex(where: { $0.id == selectedScanId }) {
          // Determine whether this drag is a move or rotate when it begins (based on handle hit-test).
          if activeDragKind == nil {
            let startPt = value.startLocation
            let startWorld = screenPointToWorld(startPt, scale: scale, origin: origin)
            if let handles = handleCentersPx(scanId: selectedScanId, viewSize: viewSize, scale: scale, origin: origin) {
              let rotateDist = distancePx(startPt, handles.rotateCenter)
              let moveDist = distancePx(startPt, handles.moveCenter)
              if rotateDist <= (handleRotateRadiusPx + 14) {
                activeDragKind = .roomRotate
              } else if moveDist <= (handleMoveRadiusPx + 14) {
                activeDragKind = .roomMove
              } else if let wall = pickWall(at: startWorld, maxDistanceMeters: tapHitThresholdMeters) {
                self.selectedScanId = wall.scanId
                activeWallSelection = wall
                activePassageSelection = nil
                activeDragKind = .wallMove
                activeWallDragStartGeometry = geometryByScanId[wall.scanId]
              } else {
                // Default: dragging anywhere moves the selected room.
                activeDragKind = .roomMove
              }
            } else {
              if let wall = pickWall(at: startWorld, maxDistanceMeters: tapHitThresholdMeters) {
                self.selectedScanId = wall.scanId
                activeWallSelection = wall
                activePassageSelection = nil
                activeDragKind = .wallMove
                activeWallDragStartGeometry = geometryByScanId[wall.scanId]
              } else {
                activeDragKind = .roomMove
              }
            }

            if activeDragKind == .roomRotate {
              guard let pivotLocal = roomPivotLocal(scanId: selectedScanId) else {
                activeDragKind = .roomMove
                return
              }
              let startTransform = project.roomScans[idx].transform
              let pivotWorld = mapLocalPointToWorld(pivotLocal, t: startTransform)
              let pivotScreen = mapPoint(x: pivotWorld.x, y: pivotWorld.y, scale: scale, origin: origin)
              // Convert to a y-up angle so rotation direction matches user expectation on screen.
              let startAngle = atan2(
                Double(-(value.startLocation.y - pivotScreen.y)),
                Double(value.startLocation.x - pivotScreen.x)
              )
              activeRoomRotation = ActiveRoomRotationState(
                scanId: selectedScanId,
                startTransform: startTransform,
                pivotLocal: pivotLocal,
                pivotWorld: pivotWorld,
                pivotScreen: DPoint(x: Double(pivotScreen.x), y: Double(pivotScreen.y)),
                startAngleScreenRadians: startAngle
              )
            } else {
              if activeRoomDragStart == nil {
                activeRoomDragStart = project.roomScans[idx].transform
              }
            }
          }

          switch activeDragKind {
          case .roomRotate:
            doorDockPreview = nil
            guard let state = activeRoomRotation else { return }
            let currentAngle = atan2(
              Double(-(Double(value.location.y) - state.pivotScreen.y)),
              Double(value.location.x) - state.pivotScreen.x
            )
            let delta = normalizeAngle(currentAngle - state.startAngleScreenRadians)
            let newRotation = state.startTransform.rotationRadians + delta
            applyRotation(at: idx, rotationRadians: newRotation, pivotLocal: state.pivotLocal, pivotWorld: state.pivotWorld)

          case .roomMove:
            if activeRoomDragStart == nil {
              activeRoomDragStart = project.roomScans[idx].transform
            }
            let start = activeRoomDragStart ?? project.roomScans[idx].transform
            // Move selected room
            let dxM = Double(value.translation.width / scale)
            let dyM = Double(-value.translation.height / scale)
            project.roomScans[idx].transform.translationX = start.translationX + dxM
            project.roomScans[idx].transform.translationY = start.translationY + dyM

            doorDockPreview = computeBestDoorDockPreview(movingScanId: selectedScanId, maxDistanceMeters: doorDockThresholdMeters * 1.35)

          case .wallMove:
            doorDockPreview = nil
            guard let selection = activeWallSelection,
                  let startGeo = activeWallDragStartGeometry,
                  let scan = project.roomScans.first(where: { $0.id == selection.scanId }) else { return }
            let dxWorld = Double(value.translation.width / scale)
            let dyWorld = Double(-value.translation.height / scale)
            let deltaLocal = worldDeltaToLocal(DPoint(x: dxWorld, y: dyWorld), rotationRadians: scan.transform.rotationRadians)
            moveWall(selection: selection, from: startGeo, byLocalDelta: deltaLocal)

          case .pan, .none:
            if activePanStart == nil {
              activePanStart = lastPan
            }
            let start = activePanStart ?? lastPan
            pan = CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height)
            doorDockPreview = nil
          }
        } else {
          // Pan view
          if activeDragKind == nil { activeDragKind = .pan }
          if activePanStart == nil {
            activePanStart = lastPan
          }
          let start = activePanStart ?? lastPan
          pan = CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height)
          doorDockPreview = nil
        }
      }
      .onEnded { _ in
        let endedKind = activeDragKind
        let movedRoomId = (endedKind == .roomMove && activeRoomDragStart != nil) ? selectedScanId : nil
        let movedWallId = (endedKind == .wallMove) ? activeWallSelection?.scanId : nil

        if endedKind == .roomRotate {
          pendingRotationSnapId = selectedScanId
          activeRoomRotation = nil
          snapRotationIfNeeded()
        }

        activeRoomDragStart = nil
        activePanStart = nil
        activeRoomRotation = nil
        activeWallDragStartGeometry = nil
        activeDragKind = nil
        lastPan = pan
        // Handles should not "stick" on screen; show them only while interacting.
        handlesVisibleUntil = nil
        if let movedRoomId {
          snapRoomIfNeeded(scanId: movedRoomId)
        }
        if let movedWallId, let geo = geometryByScanId[movedWallId] {
          persistGeometry(scanId: movedWallId, geo: geo)
        }
        doorDockPreview = nil
        try? FloorplanProjectStore.save(project: project)
        if showRouteOverlay {
          recomputeRouteOverlay()
        }
      }

    let magnify = MagnificationGesture()
      .onChanged { value in
        zoom = max(0.4, min(4.0, lastZoom * value))
      }
      .onEnded { _ in
        lastZoom = zoom
      }

    return drag.simultaneously(with: magnify)
  }

  private func draw(context: inout GraphicsContext, size: CGSize) {
    let (scale, origin) = mapping(viewSize: size)

    drawGrid(context: &context, size: size, scale: scale, origin: origin)
    drawManualRoomDraft(context: &context, scale: scale, origin: origin)

    let renderRooms = planRenderRooms()
    let planLayout = FloorplanPlanRenderer.layout(for: renderRooms)
    let mapping = FloorplanPlanRenderer.Mapping(scale: scale, origin: origin)
    let highlightedRooms = selectedScanId.map { Set([$0]) } ?? []

    context.withCGContext { cg in
      FloorplanPlanRenderer.drawBasePlan(
        cg: cg,
        rooms: renderRooms,
        layout: planLayout,
        mapping: mapping,
        style: .composer,
        labelMode: .roomName,
        highlightedScanIds: highlightedRooms
      )
    }

    drawRoomConnections(context: &context, scale: scale, origin: origin)

    drawStairConnections(context: &context, scale: scale, origin: origin)

    if showAllWallMeasurements {
      for scan in project.roomScans {
        guard let geo = geometryByScanId[scan.id] else { continue }
        let worldSegs = transform(segments: geo.segments, t: scan.transform)
        drawWallMeasurements(context: &context, size: size, scale: scale, origin: origin, segmentsWorld: worldSegs)
      }
    } else if let selectedScanId,
              let scan = project.roomScans.first(where: { $0.id == selectedScanId }),
              let geo = geometryByScanId[selectedScanId] {
      let worldSegs = transform(segments: geo.segments, t: scan.transform)
      drawWallMeasurements(context: &context, size: size, scale: scale, origin: origin, segmentsWorld: worldSegs)
    }

    drawScaleBar(context: &context, size: size, pxPerMeter: scale)

    if showRouteOverlay, !routePointsWorld.isEmpty {
      if routePointsWorld.count >= 2 {
        var p = Path()
        for (idx, pt) in routePointsWorld.enumerated() {
          let mapped = mapPoint(x: pt.x, y: pt.y, scale: scale, origin: origin)
          if idx == 0 {
            p.move(to: mapped)
          } else {
            p.addLine(to: mapped)
          }
        }
        context.stroke(
          p,
          with: .color(Color(red: 0.12, green: 0.12, blue: 0.12).opacity(0.55)),
          style: StrokeStyle(
            lineWidth: 3.5,
            lineCap: .round,
            lineJoin: .round,
            dash: routeMode == .manual ? [7, 5] : [10, 8]
          )
        )
      }

      for (idx, pt) in routePointsWorld.enumerated() {
        let center = mapPoint(x: pt.x, y: pt.y, scale: scale, origin: origin)
        let radius: CGFloat = idx == 0 ? 8.5 : 7
        let color = idx == 0 ? Color(red: 0.16, green: 0.48, blue: 0.94) : Color.black.opacity(0.62)
        let circleRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: circleRect), with: .color(color))
        context.stroke(Path(ellipseIn: circleRect), with: .color(.white.opacity(0.92)), lineWidth: 1.4)

        let number = context.resolve(
          Text("\(idx + 1)")
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.white)
        )
        context.draw(number, at: center, anchor: .center)
      }
    }

    if let preview = doorDockPreview {
      var p = Path()
      for seg in [preview.otherDoorWorld, preview.movingDoorWorld] {
        let a = mapPoint(x: seg.ax, y: seg.ay, scale: scale, origin: origin)
        let b = mapPoint(x: seg.bx, y: seg.by, scale: scale, origin: origin)
        p.move(to: a)
        p.addLine(to: b)
      }
      context.stroke(
        p,
        with: .color(Color(red: 0.10, green: 0.70, blue: 0.25).opacity(0.88)),
        style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round)
      )
    }

    if let selection = connectSourceDoor,
       let segWorld = doorSegmentWorld(for: selection) {
      var p = Path()
      let a = mapPoint(x: segWorld.ax, y: segWorld.ay, scale: scale, origin: origin)
      let b = mapPoint(x: segWorld.bx, y: segWorld.by, scale: scale, origin: origin)
      p.move(to: a)
      p.addLine(to: b)
      context.stroke(
        p,
        with: .color(Color(red: 0.10, green: 0.70, blue: 0.25).opacity(0.95)),
        style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round)
      )
    }

    drawActivePassageSelection(context: &context, scale: scale, origin: origin)
    drawActiveWallSelection(context: &context, scale: scale, origin: origin)

    let shouldShowHandles = (activeDragKind == .roomMove || activeDragKind == .roomRotate) || ((handlesVisibleUntil ?? Date.distantPast) > Date())
    if toolMode == .move,
       shouldShowHandles,
       let selectedScanId,
       let scan = project.roomScans.first(where: { $0.id == selectedScanId }),
       geometryByScanId[selectedScanId] != nil,
       let pivotLocal = roomPivotLocal(scanId: selectedScanId) {
      let pivotWorld = mapLocalPointToWorld(pivotLocal, t: scan.transform)
      let moveCenter = mapPoint(x: pivotWorld.x, y: pivotWorld.y, scale: scale, origin: origin)
      if let handles = handleCentersPx(scanId: selectedScanId, viewSize: size, scale: scale, origin: origin) {
        drawMoveRotateHandles(context: &context, moveCenter: handles.moveCenter, rotateCenter: handles.rotateCenter)
      } else {
        drawMoveRotateHandles(context: &context, moveCenter: moveCenter, rotateCenter: CGPoint(x: moveCenter.x + handleRotateOffsetXPx, y: moveCenter.y))
      }
    }
  }

  private func planRenderRooms() -> [FloorplanPlanRenderer.Room] {
    project.roomScans.compactMap { scan in
      guard let geo = geometryByScanId[scan.id], !geo.segments.isEmpty else { return nil }
      return FloorplanPlanRenderer.Room(
        scanId: scan.id,
        roomId: scan.roomId,
        floorId: scan.floorId,
        walls: transform(segments: geo.segments, t: scan.transform),
        doors: transform(segments: geo.doors ?? [], t: scan.transform),
        openings: transform(segments: geo.openings ?? [], t: scan.transform),
        windows: transform(segments: geo.windows ?? [], t: scan.transform),
        doorSwingOverrides: geo.doorSwingOverrides ?? []
      )
    }
  }

  private func drawActivePassageSelection(
    context: inout GraphicsContext,
    scale: CGFloat,
    origin: CGPoint
  ) {
    guard let selection = activePassageSelection,
          let segWorld = doorSegmentWorld(for: selection) else {
      return
    }

    let a = mapPoint(x: segWorld.ax, y: segWorld.ay, scale: scale, origin: origin)
    let b = mapPoint(x: segWorld.bx, y: segWorld.by, scale: scale, origin: origin)
    let mid = CGPoint(x: (a.x + b.x) * 0.5, y: (a.y + b.y) * 0.5)
    let color: Color = {
      switch selection.kind {
      case .door:
        return FloorplanTheme.accent
      case .opening:
        return FloorplanTheme.secondary
      case .window:
        return FloorplanTheme.primary
      }
    }()

    var segmentPath = Path()
    segmentPath.move(to: a)
    segmentPath.addLine(to: b)
    context.stroke(
      segmentPath,
      with: .color(.white.opacity(0.92)),
      style: StrokeStyle(lineWidth: 13, lineCap: .round, lineJoin: .round)
    )
    context.stroke(
      segmentPath,
      with: .color(color.opacity(0.92)),
      style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round)
    )

    let radius: CGFloat = selection.kind == .door ? 7 : 6
    let markerRect = CGRect(x: mid.x - radius, y: mid.y - radius, width: radius * 2, height: radius * 2)
    context.fill(Path(ellipseIn: markerRect), with: .color(color.opacity(0.98)))
    context.stroke(Path(ellipseIn: markerRect), with: .color(.white.opacity(0.95)), lineWidth: 1.6)
  }

  private func drawActiveWallSelection(
    context: inout GraphicsContext,
    scale: CGFloat,
    origin: CGPoint
  ) {
    guard let selection = activeWallSelection,
          let segWorld = wallSegmentWorld(for: selection) else {
      return
    }

    let a = mapPoint(x: segWorld.ax, y: segWorld.ay, scale: scale, origin: origin)
    let b = mapPoint(x: segWorld.bx, y: segWorld.by, scale: scale, origin: origin)
    let mid = CGPoint(x: (a.x + b.x) * 0.5, y: (a.y + b.y) * 0.5)

    var path = Path()
    path.move(to: a)
    path.addLine(to: b)
    context.stroke(
      path,
      with: .color(.white.opacity(0.95)),
      style: StrokeStyle(lineWidth: selectedWallHighlightWidthPx + 5, lineCap: .round, lineJoin: .round)
    )
    context.stroke(
      path,
      with: .color(FloorplanTheme.accent.opacity(0.94)),
      style: StrokeStyle(lineWidth: selectedWallHighlightWidthPx, lineCap: .round, lineJoin: .round)
    )

    let markerRect = CGRect(x: mid.x - 6, y: mid.y - 6, width: 12, height: 12)
    context.fill(Path(ellipseIn: markerRect), with: .color(FloorplanTheme.accent.opacity(0.98)))
    context.stroke(Path(ellipseIn: markerRect), with: .color(.white.opacity(0.95)), lineWidth: 1.4)
  }

  private func pickWall(at pWorld: DPoint, maxDistanceMeters: Double) -> WallSelection? {
    var best: (selection: WallSelection, dist: Double)? = nil
    let selectedFirst: [FloorplanRoomScan] = {
      guard let selectedScanId,
            let selected = project.roomScans.first(where: { $0.id == selectedScanId }) else {
        return project.roomScans
      }
      return [selected] + project.roomScans.filter { $0.id != selectedScanId }
    }()

    for scan in selectedFirst {
      guard let geo = geometryByScanId[scan.id], !geo.segments.isEmpty else { continue }
      let pLocal = toLocal(pWorld, t: scan.transform)
      for (idx, segment) in geo.segments.enumerated() {
        let res = pointSegmentDistance(p: pLocal, seg: segment)
        guard res.dist <= maxDistanceMeters else { continue }
        if best == nil || res.dist < best!.dist {
          best = (WallSelection(scanId: scan.id, index: idx), res.dist)
        }
      }
    }

    return best?.selection
  }

  private func wallSegmentWorld(for selection: WallSelection) -> FloorplanSegment? {
    guard let scan = project.roomScans.first(where: { $0.id == selection.scanId }),
          let geo = geometryByScanId[selection.scanId],
          geo.segments.indices.contains(selection.index) else {
      return nil
    }
    return transform(segments: [geo.segments[selection.index]], t: scan.transform).first
  }

  private func moveWall(selection: WallSelection, from startGeo: FloorplanSegmentsFile, byLocalDelta delta: DPoint) {
    guard startGeo.segments.indices.contains(selection.index) else { return }
    var geo = startGeo
    let originalWall = startGeo.segments[selection.index]
    let movedWall = translated(originalWall, by: delta)
    geo.segments[selection.index] = movedWall

    func moveAttached(_ segments: [FloorplanSegment]?) -> [FloorplanSegment]? {
      guard var out = segments else { return nil }
      for idx in out.indices where segmentLiesOnWall(out[idx], wall: originalWall) {
        out[idx] = translated(out[idx], by: delta)
      }
      return out.isEmpty ? nil : out
    }

    geo.doors = moveAttached(startGeo.doors)
    geo.openings = moveAttached(startGeo.openings)
    geo.windows = moveAttached(startGeo.windows)
    applyEditedGeometry(scanId: selection.scanId, geo: geo, persist: false)
  }

  private func removeActiveWall() {
    guard let selection = activeWallSelection else { return }
    guard var geo = geometryByScanId[selection.scanId],
          geo.segments.indices.contains(selection.index) else {
      activeWallSelection = nil
      showToast("Wand nicht mehr gefunden.")
      return
    }
    guard geo.segments.count > 1 else {
      showToast("Letzte Wand kann nicht gelöscht werden.")
      return
    }

    let removedWall = geo.segments.remove(at: selection.index)
    geo.doors = removePassages(on: removedWall, from: geo.doors)
    geo.openings = removePassages(on: removedWall, from: geo.openings)
    geo.windows = removePassages(on: removedWall, from: geo.windows)

    activeWallSelection = nil
    activePassageSelection = nil
    applyEditedGeometry(scanId: selection.scanId, geo: geo, persist: true)
    try? FloorplanProjectStore.save(project: project)
    if showRouteOverlay { recomputeRouteOverlay() }
    showToast("Wand gelöscht.")
  }

  private func removePassages(on wall: FloorplanSegment, from passages: [FloorplanSegment]?) -> [FloorplanSegment]? {
    guard let passages else { return nil }
    let filtered = passages.filter { !segmentLiesOnWall($0, wall: wall) }
    return filtered.isEmpty ? nil : filtered
  }

  private func translated(_ segment: FloorplanSegment, by delta: DPoint) -> FloorplanSegment {
    FloorplanSegment(
      ax: segment.ax + delta.x,
      ay: segment.ay + delta.y,
      bx: segment.bx + delta.x,
      by: segment.by + delta.y
    )
  }

  private func segmentLiesOnWall(_ segment: FloorplanSegment, wall: FloorplanSegment) -> Bool {
    let directionSimilarity = abs(dot(direction(of: segment), direction(of: wall)))
    guard directionSimilarity >= 0.72 else { return false }

    let mid = midpoint(of: segment)
    let distanceToWall = pointSegmentDistance(p: mid, seg: wall).dist
    guard distanceToWall <= 0.18 else { return false }

    let wallLength = segmentLength(wall)
    guard wallLength > 0.001 else { return false }
    let aT = pointSegmentDistance(p: DPoint(x: segment.ax, y: segment.ay), seg: wall).t
    let bT = pointSegmentDistance(p: DPoint(x: segment.bx, y: segment.by), seg: wall).t
    return min(aT, bT) >= -0.05 && max(aT, bT) <= 1.05
  }

  private func applyEditedGeometry(scanId: UUID, geo: FloorplanSegmentsFile, persist: Bool) {
    var updated = geo
    updated.metrics = RoomPlanFloorplanRenderer.metrics(for: updated.segments)
    geometryByScanId[scanId] = updated
    if let scanIndex = project.roomScans.firstIndex(where: { $0.id == scanId }) {
      project.roomScans[scanIndex].metrics = updated.metrics
    }
    if persist {
      persistGeometry(scanId: scanId, geo: updated)
    }
  }

  private struct WallSourceSegment {
    let scanId: UUID
    let seg: FloorplanSegment
  }

  private struct RenderedWallSegment {
    let seg: FloorplanSegment
    let isInterior: Bool
  }

  private func buildRenderedWallSegments() -> [RenderedWallSegment] {
    var sources: [WallSourceSegment] = []
    for scan in project.roomScans {
      guard let geo = geometryByScanId[scan.id], !geo.segments.isEmpty else { continue }
      for seg in transform(segments: geo.segments, t: scan.transform) {
        sources.append(WallSourceSegment(scanId: scan.id, seg: seg))
      }
    }
    guard !sources.isEmpty else { return [] }

    let clusters = clusterWallSources(sources)
    var rendered: [RenderedWallSegment] = []
    for cluster in clusters {
      rendered.append(contentsOf: splitWallCluster(cluster, allSources: sources))
    }
    return rendered
  }

  private func drawRoomConnections(
    context: inout GraphicsContext,
    scale: CGFloat,
    origin: CGPoint
  ) {
    let connections = validConnections()
    guard !connections.isEmpty else { return }

    for connection in connections {
      guard let segA = passageSegmentWorld(for: connection.a),
            let segB = passageSegmentWorld(for: connection.b) else { continue }

      let startWorld = midpoint(of: segA)
      let endWorld = midpoint(of: segB)
      let start = mapPoint(x: startWorld.x, y: startWorld.y, scale: scale, origin: origin)
      let end = mapPoint(x: endWorld.x, y: endWorld.y, scale: scale, origin: origin)
      let center = CGPoint(x: (start.x + end.x) * 0.5, y: (start.y + end.y) * 0.5)
      let involvesSelection = selectedScanId == connection.a.scanId || selectedScanId == connection.b.scanId

      var path = Path()
      path.move(to: start)
      path.addLine(to: end)

      context.stroke(
        path,
        with: .color((involvesSelection ? FloorplanTheme.secondary : FloorplanTheme.neutral).opacity(involvesSelection ? 0.58 : 0.34)),
        style: StrokeStyle(
          lineWidth: involvesSelection ? 3.2 : 2.4,
          lineCap: .round,
          lineJoin: .round,
          dash: [7, 5]
        )
      )

      let markerRadius: CGFloat = involvesSelection ? 6 : 5
      let markerRect = CGRect(
        x: center.x - markerRadius,
        y: center.y - markerRadius,
        width: markerRadius * 2,
        height: markerRadius * 2
      )
      context.fill(
        Path(ellipseIn: markerRect),
        with: .color((involvesSelection ? FloorplanTheme.secondary : FloorplanTheme.neutral).opacity(involvesSelection ? 0.92 : 0.74))
      )
      context.stroke(
        Path(ellipseIn: markerRect),
        with: .color(.white.opacity(0.92)),
        lineWidth: 1.1
      )
    }
  }

  private func clusterWallSources(_ sources: [WallSourceSegment]) -> [[WallSourceSegment]] {
    guard !sources.isEmpty else { return [] }
    var remaining = Set(sources.indices)
    var groups: [[WallSourceSegment]] = []

    while let seed = remaining.first {
      remaining.remove(seed)
      var queue: [Int] = [seed]
      var groupIndices: [Int] = [seed]

      while let current = queue.popLast() {
        let neighbors = remaining.filter { shouldClusterAsSameWall(sources[current].seg, sources[$0].seg) }
        for neighbor in neighbors {
          remaining.remove(neighbor)
          queue.append(neighbor)
          groupIndices.append(neighbor)
        }
      }

      groups.append(groupIndices.map { sources[$0] })
    }

    return groups
  }

  private func splitWallCluster(_ cluster: [WallSourceSegment], allSources: [WallSourceSegment]) -> [RenderedWallSegment] {
    guard !cluster.isEmpty else { return [] }

    let anchor = cluster.max(by: { segmentLength($0.seg) < segmentLength($1.seg) })?.seg ?? cluster[0].seg
    let axis = direction(of: anchor)
    let normal = DPoint(x: -axis.y, y: axis.x)

    let midpoints = cluster.map { midpoint(of: $0.seg) }
    let meanOffset = midpoints.map { dot($0, normal) }.reduce(0, +) / Double(max(midpoints.count, 1))
    let reference = midpoints.first ?? DPoint(x: 0, y: 0)
    let refOffset = dot(reference, normal)
    let lineOrigin = DPoint(
      x: reference.x + normal.x * (meanOffset - refOffset),
      y: reference.y + normal.y * (meanOffset - refOffset)
    )

    var knots: [Double] = []
    for source in cluster {
      let interval = projectionInterval(of: source.seg, origin: lineOrigin, axis: axis)
      knots.append(interval.min)
      knots.append(interval.max)
    }
    knots.sort()

    let knotEpsilon = 0.03
    var uniqueKnots: [Double] = []
    for knot in knots {
      if let last = uniqueKnots.last, abs(last - knot) <= knotEpsilon { continue }
      uniqueKnots.append(knot)
    }
    guard uniqueKnots.count >= 2 else { return [] }

    let segmentMinLength = 0.08
    let projectionPad = 0.03
    let coverDistanceTolerance = 0.12

    var pieces: [RenderedWallSegment] = []
    for idx in 0..<(uniqueKnots.count - 1) {
      let s0 = uniqueKnots[idx]
      let s1 = uniqueKnots[idx + 1]
      guard (s1 - s0) >= segmentMinLength else { continue }

      let midS = (s0 + s1) * 0.5
      let midPoint = DPoint(x: lineOrigin.x + axis.x * midS, y: lineOrigin.y + axis.y * midS)

      var coverageCount = 0
      var coveringRoomIds: Set<UUID> = []
      for source in cluster {
        let interval = projectionInterval(of: source.seg, origin: lineOrigin, axis: axis)
        if midS < interval.min - projectionPad || midS > interval.max + projectionPad { continue }
        if pointSegmentDistance(p: midPoint, seg: source.seg).dist <= coverDistanceTolerance {
          coverageCount += 1
          coveringRoomIds.insert(source.scanId)
        }
      }
      guard coverageCount > 0 else { continue }

      let isLikelySharedWall =
        coveringRoomIds.count >= 2 ||
        hasNearbyParallelWall(
          midpoint: midPoint,
          axis: axis,
          excludedScanIds: coveringRoomIds,
          allSources: allSources
        )

      let a = DPoint(x: lineOrigin.x + axis.x * s0, y: lineOrigin.y + axis.y * s0)
      let b = DPoint(x: lineOrigin.x + axis.x * s1, y: lineOrigin.y + axis.y * s1)
      pieces.append(
        RenderedWallSegment(
          seg: FloorplanSegment(ax: a.x, ay: a.y, bx: b.x, by: b.y),
          isInterior: isLikelySharedWall
        )
      )
    }

    return mergeRenderedWallPieces(pieces)
  }

  private func hasNearbyParallelWall(
    midpoint: DPoint,
    axis: DPoint,
    excludedScanIds: Set<UUID>,
    allSources: [WallSourceSegment]
  ) -> Bool {
    let axisN = normalized(axis)
    let axisOrigin = midpoint
    for source in allSources {
      if excludedScanIds.contains(source.scanId) { continue }
      let dir = direction(of: source.seg)
      if abs(dot(axisN, dir)) < 0.90 { continue }
      let interval = projectionInterval(of: source.seg, origin: axisOrigin, axis: axisN)
      if interval.max < -0.45 || interval.min > 0.45 { continue }
      if pointSegmentDistance(p: midpoint, seg: source.seg).dist <= 0.26 {
        return true
      }
    }
    return false
  }

  private func mergeRenderedWallPieces(_ pieces: [RenderedWallSegment]) -> [RenderedWallSegment] {
    guard !pieces.isEmpty else { return [] }
    var merged: [RenderedWallSegment] = []

    for piece in pieces {
      guard let last = merged.last else {
        merged.append(piece)
        continue
      }

      let sameType = last.isInterior == piece.isInterior
      let lastEnd = DPoint(x: last.seg.bx, y: last.seg.by)
      let currentStart = DPoint(x: piece.seg.ax, y: piece.seg.ay)
      let touching = distance(lastEnd, currentStart) <= 0.04
      let nearlyCollinear = abs(cross(direction(of: last.seg), direction(of: piece.seg))) <= 0.01

      if sameType && touching && nearlyCollinear {
        let extended = FloorplanSegment(ax: last.seg.ax, ay: last.seg.ay, bx: piece.seg.bx, by: piece.seg.by)
        merged[merged.count - 1] = RenderedWallSegment(seg: extended, isInterior: last.isInterior)
      } else {
        merged.append(piece)
      }
    }

    return merged
  }

  private func shouldClusterAsSameWall(_ a: FloorplanSegment, _ b: FloorplanSegment) -> Bool {
    let lenA = segmentLength(a)
    let lenB = segmentLength(b)
    guard lenA >= 0.08, lenB >= 0.08 else { return false }

    let dirA = direction(of: a)
    let dirB = direction(of: b)
    guard abs(cross(dirA, dirB)) <= 0.12 else { return false }

    let midA = midpoint(of: a)
    let midB = midpoint(of: b)
    let lineDistance = min(
      distanceToInfiniteLine(point: midA, linePoint: midB, lineDirection: dirB),
      distanceToInfiniteLine(point: midB, linePoint: midA, lineDirection: dirA)
    )
    guard lineDistance <= 0.18 else { return false }

    let intervalA = projectionInterval(of: a, origin: midA, axis: dirA)
    let intervalB = projectionInterval(of: b, origin: midA, axis: dirA)
    let overlap = min(intervalA.max, intervalB.max) - max(intervalA.min, intervalB.min)
    let minOverlap = max(0.10, min(0.30, min(lenA, lenB) * 0.35))
    return overlap >= minOverlap
  }

  private func projectionInterval(of seg: FloorplanSegment, origin: DPoint, axis: DPoint) -> (min: Double, max: Double) {
    let a = dot(DPoint(x: seg.ax - origin.x, y: seg.ay - origin.y), axis)
    let b = dot(DPoint(x: seg.bx - origin.x, y: seg.by - origin.y), axis)
    return (min(a, b), max(a, b))
  }

  private func distanceToInfiniteLine(point: DPoint, linePoint: DPoint, lineDirection: DPoint) -> Double {
    let rel = DPoint(x: point.x - linePoint.x, y: point.y - linePoint.y)
    return abs(cross(rel, lineDirection))
  }

  private func cross(_ a: DPoint, _ b: DPoint) -> Double {
    a.x * b.y - a.y * b.x
  }

  private func segmentLength(_ seg: FloorplanSegment) -> Double {
    let dx = seg.bx - seg.ax
    let dy = seg.by - seg.ay
    return (dx * dx + dy * dy).squareRoot()
  }

  private func drawGrid(context: inout GraphicsContext, size: CGSize, scale: CGFloat, origin: CGPoint) {
    let minorStepM = chooseMinorGridStepMeters(pxPerMeter: scale)
    let minorStepPx = CGFloat(minorStepM) * scale
    guard minorStepPx >= 10 else { return }

    let majorEvery = 5
    let superEvery = 10

    let minorColor = Color(red: 0.18, green: 0.42, blue: 0.92).opacity(0.06)
    let majorColor = Color(red: 0.18, green: 0.42, blue: 0.92).opacity(0.12)
    let superColor = Color(red: 0.18, green: 0.42, blue: 0.92).opacity(0.18)

    // Determine visible world bounds
    let worldXMin = Double((0 - origin.x) / scale)
    let worldXMax = Double((size.width - origin.x) / scale)
    let worldYTop = Double((origin.y - 0) / scale)
    let worldYBottom = Double((origin.y - size.height) / scale)
    let worldYMin = min(worldYTop, worldYBottom)
    let worldYMax = max(worldYTop, worldYBottom)

    let startXIdx = Int(floor(worldXMin / minorStepM))
    let endXIdx = Int(ceil(worldXMax / minorStepM))
    let startYIdx = Int(floor(worldYMin / minorStepM))
    let endYIdx = Int(ceil(worldYMax / minorStepM))

    var minor = Path()
    var major = Path()
    var superMajor = Path()

    for i in startXIdx...endXIdx {
      let xM = Double(i) * minorStepM
      let x = origin.x + CGFloat(xM) * scale
      if i % superEvery == 0 {
        superMajor.move(to: CGPoint(x: x, y: 0))
        superMajor.addLine(to: CGPoint(x: x, y: size.height))
      } else if i % majorEvery == 0 {
        major.move(to: CGPoint(x: x, y: 0))
        major.addLine(to: CGPoint(x: x, y: size.height))
      } else {
        minor.move(to: CGPoint(x: x, y: 0))
        minor.addLine(to: CGPoint(x: x, y: size.height))
      }
    }

    for j in startYIdx...endYIdx {
      let yM = Double(j) * minorStepM
      let y = origin.y - CGFloat(yM) * scale
      if j % superEvery == 0 {
        superMajor.move(to: CGPoint(x: 0, y: y))
        superMajor.addLine(to: CGPoint(x: size.width, y: y))
      } else if j % majorEvery == 0 {
        major.move(to: CGPoint(x: 0, y: y))
        major.addLine(to: CGPoint(x: size.width, y: y))
      } else {
        minor.move(to: CGPoint(x: 0, y: y))
        minor.addLine(to: CGPoint(x: size.width, y: y))
      }
    }

    context.stroke(minor, with: .color(minorColor), lineWidth: 1)
    context.stroke(major, with: .color(majorColor), lineWidth: 1.2)
    context.stroke(superMajor, with: .color(superColor), lineWidth: 1.6)
  }

  private func drawManualRoomDraft(context: inout GraphicsContext, scale: CGFloat, origin: CGPoint) {
    guard !manualRoomDraftPoints.isEmpty else { return }
    let mapped = manualRoomDraftPoints.map { mapPoint(x: $0.x, y: $0.y, scale: scale, origin: origin) }

    if mapped.count >= 3 {
      var fill = Path()
      fill.move(to: mapped[0])
      for point in mapped.dropFirst() {
        fill.addLine(to: point)
      }
      fill.closeSubpath()
      context.fill(fill, with: .color(Color(red: 0.92, green: 0.56, blue: 0.16).opacity(0.12)))
    }

    if mapped.count >= 2 {
      var p = Path()
      p.move(to: mapped[0])
      for point in mapped.dropFirst() {
        p.addLine(to: point)
      }
      context.stroke(
        p,
        with: .color(Color(red: 0.92, green: 0.56, blue: 0.16).opacity(0.95)),
        style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
      )
    }

    if mapped.count >= 3, let first = mapped.first, let last = mapped.last {
      var closeHint = Path()
      closeHint.move(to: last)
      closeHint.addLine(to: first)
      context.stroke(
        closeHint,
        with: .color(Color(red: 0.92, green: 0.56, blue: 0.16).opacity(0.72)),
        style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round, dash: [6, 4])
      )
    }

    for (idx, point) in mapped.enumerated() {
      let radius: CGFloat = idx == 0 ? 7.0 : 5.8
      let circleRect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
      context.fill(Path(ellipseIn: circleRect), with: .color(Color.white.opacity(0.95)))
      context.stroke(Path(ellipseIn: circleRect), with: .color(Color.black.opacity(0.72)), lineWidth: 1.2)

      let number = context.resolve(
        Text("\(idx + 1)")
          .font(.system(size: 9, weight: .bold))
          .foregroundColor(.black.opacity(0.75))
      )
      context.draw(number, at: point, anchor: .center)
    }
  }

  private func drawStairConnections(context: inout GraphicsContext, scale: CGFloat, origin: CGPoint) {
    guard !project.stairConnections.isEmpty else { return }

    for stair in project.stairConnections {
      let center = mapPoint(x: stair.x, y: stair.y, scale: scale, origin: origin)
      let radius: CGFloat = 11
      let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)

      context.fill(
        Path(ellipseIn: rect),
        with: .color(Color(red: 0.24, green: 0.40, blue: 0.82).opacity(0.92))
      )
      context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.92)), lineWidth: 1.3)

      let icon = context.resolve(
        Text("⇅")
          .font(.system(size: 11, weight: .bold))
          .foregroundColor(.white)
      )
      context.draw(icon, at: center, anchor: .center)

      let fromName = FloorTaxonomy.floor(id: stair.fromFloorId).shortDisplayName
      let toName = FloorTaxonomy.floor(id: stair.toFloorId).shortDisplayName
      let label = context.resolve(
        Text("\(fromName) ↔ \(toName)")
          .font(.system(size: 9, weight: .semibold))
          .foregroundColor(.black.opacity(0.74))
      )
      let measure = label.measure(in: CGSize(width: 140, height: 20))
      let bubble = CGRect(
        x: center.x - measure.width * 0.5 - 6,
        y: center.y + radius + 4,
        width: measure.width + 12,
        height: measure.height + 6
      )
      context.fill(
        Path(roundedRect: bubble, cornerRadius: 8),
        with: .color(Color.white.opacity(0.86))
      )
      context.stroke(
        Path(roundedRect: bubble, cornerRadius: 8),
        with: .color(Color.black.opacity(0.10)),
        lineWidth: 1
      )
      context.draw(label, at: CGPoint(x: bubble.midX, y: bubble.midY), anchor: .center)
    }
  }

  private func drawRoomNameLabel(
    context: inout GraphicsContext,
    center: CGPoint,
    roomName: String
  ) {
    let nameText = Text(roomName)
      .font(.system(size: 12, weight: .semibold))
      .foregroundColor(Color.black.opacity(0.82))

    let nameResolved = context.resolve(nameText)
    let nameSize = nameResolved.measure(in: CGSize(width: 240, height: 34))
    let padX: CGFloat = 10
    let padY: CGFloat = 6
    let rect = CGRect(
      x: center.x - nameSize.width / 2 - padX,
      y: center.y - nameSize.height / 2 - padY,
      width: nameSize.width + padX * 2,
      height: nameSize.height + padY * 2
    )

    context.fill(
      Path(roundedRect: rect, cornerRadius: 12),
      with: .color(Color.white.opacity(0.72))
    )
    context.stroke(
      Path(roundedRect: rect, cornerRadius: 12),
      with: .color(Color.black.opacity(0.10)),
      lineWidth: 1
    )
    context.draw(nameResolved, at: center, anchor: .center)
  }

  private func drawWallMeasurements(
    context: inout GraphicsContext,
    size: CGSize,
    scale: CGFloat,
    origin: CGPoint,
    segmentsWorld: [FloorplanSegment]
  ) {
    // Avoid clutter at low zoom.
    guard scale >= 35 else { return }

    for seg in segmentsWorld {
      let dx = seg.bx - seg.ax
      let dy = seg.by - seg.ay
      let lenM = (dx * dx + dy * dy).squareRoot()
      guard lenM >= wallMeasureMinLengthMeters else { continue }
      let lenPx = CGFloat(lenM) * scale
      guard lenPx >= 72 else { continue }

      let midW = DPoint(x: (seg.ax + seg.bx) * 0.5, y: (seg.ay + seg.by) * 0.5)
      var mid = mapPoint(x: midW.x, y: midW.y, scale: scale, origin: origin)

      // Offset slightly perpendicular so it doesn't sit directly on the wall line.
      let ax = mapPoint(x: seg.ax, y: seg.ay, scale: scale, origin: origin)
      let bx = mapPoint(x: seg.bx, y: seg.by, scale: scale, origin: origin)
      let vx = bx.x - ax.x
      let vy = bx.y - ax.y
      let vlen = max(1e-3, sqrt(vx * vx + vy * vy))
      let nx = -vy / vlen
      let ny = vx / vlen
      mid.x += nx * 14
      mid.y += ny * 14

      // Angle of the segment in screen space; keep labels upright.
      var angle = atan2(vy, vx)
      if angle > .pi / 2 { angle -= .pi }
      if angle < -.pi / 2 { angle += .pi }

      // Skip labels that would be completely off-screen.
      guard mid.x >= -40, mid.x <= size.width + 40, mid.y >= -40, mid.y <= size.height + 40 else { continue }

      let label = formatMeters(lenM)
      drawMeasurementLabel(context: &context, text: label, at: mid, angleRadians: angle)
    }
  }

  private func drawMeasurementLabel(context: inout GraphicsContext, text: String, at pos: CGPoint, angleRadians: CGFloat) {
    let t = Text(text)
      .font(.system(size: 11, weight: .bold))
      .foregroundColor(Color.black.opacity(0.82))

    let resolved = context.resolve(t)
    let measured = resolved.measure(in: CGSize(width: 160, height: 30))
    let padX: CGFloat = 8
    let padY: CGFloat = 4
    let rect = CGRect(
      x: -measured.width / 2 - padX,
      y: -measured.height / 2 - padY,
      width: measured.width + padX * 2,
      height: measured.height + padY * 2
    )

    context.drawLayer { layer in
      layer.translateBy(x: pos.x, y: pos.y)
      layer.rotate(by: Angle(radians: Double(angleRadians)))
      layer.fill(
        Path(roundedRect: rect, cornerRadius: 10),
        with: .color(Color.white.opacity(0.78))
      )
      layer.stroke(
        Path(roundedRect: rect, cornerRadius: 10),
        with: .color(Color.black.opacity(0.12)),
        lineWidth: 1
      )
      layer.draw(resolved, at: .zero, anchor: .center)
    }
  }

  private func drawScaleBar(context: inout GraphicsContext, size: CGSize, pxPerMeter: CGFloat) {
    guard pxPerMeter >= 10 else { return }
    let candidatesM: [Double] = [0.5, 1, 2, 5, 10]
    let targetPx: CGFloat = 110
    var bestM = 1.0
    var bestScore = CGFloat.greatestFiniteMagnitude
    for m in candidatesM {
      let px = CGFloat(m) * pxPerMeter
      let score = abs(px - targetPx)
      if score < bestScore {
        bestScore = score
        bestM = m
      }
    }

    let barPx = CGFloat(bestM) * pxPerMeter
    let start = CGPoint(x: 18, y: size.height - 18)
    let end = CGPoint(x: start.x + barPx, y: start.y)

    var p = Path()
    p.move(to: start)
    p.addLine(to: end)
    context.stroke(p, with: .color(Color.black.opacity(0.55)), style: StrokeStyle(lineWidth: 3, lineCap: .round))

    let label = formatMeters(bestM)
    let t = Text(label)
      .font(.system(size: 11, weight: .bold))
      .foregroundColor(Color.black.opacity(0.70))
    let resolved = context.resolve(t)
    context.draw(resolved, at: CGPoint(x: start.x + barPx / 2, y: start.y - 12), anchor: .center)
  }

  private func formatMeters(_ meters: Double) -> String {
    let rounded = (meters * 100).rounded() / 100 // 1cm
    let s = String(format: "%.2f", rounded).replacingOccurrences(of: ".", with: ",")
    return "\(s) m"
  }

  private func chooseMinorGridStepMeters(pxPerMeter: CGFloat) -> Double {
    let candidates: [Double] = [0.05, 0.1, 0.25, 0.5, 1.0]
    for step in candidates {
      if CGFloat(step) * pxPerMeter >= 12 {
        return step
      }
    }
    return 1.0
  }

  private func handleTap(at location: CGPoint, viewSize: CGSize) {
    let (scale, origin) = mapping(viewSize: viewSize)
    let xM = Double((location.x - origin.x) / scale)
    let yM = Double((origin.y - location.y) / scale)
    let pWorld = DPoint(x: xM, y: yM)

    if isPlacingStairConnection {
      addStairConnection(at: pWorld)
      return
    }

    if toolMode == .drawRoom {
      handleManualRoomDraftTap(at: pWorld)
      return
    }

    if showRouteOverlay, routeMode == .manual, toolMode == .move {
      handleManualRouteTap(at: pWorld)
      return
    }

    if toolMode == .doors {
      handleDoorToolTap(at: pWorld)
      return
    }

    if toolMode == .connect {
      handleConnectToolTap(at: pWorld)
      return
    }

    if let wall = pickWall(at: pWorld, maxDistanceMeters: tapHitThresholdMeters) {
      selectedScanId = wall.scanId
      activeWallSelection = wall
      activePassageSelection = nil
      showToast("Wand ausgewählt. Ziehen zum Verschieben oder Werkzeug > Wand löschen.")
      return
    }

    var best: (id: UUID, score: Double)? = nil
    for scan in project.roomScans {
      guard let bounds = roomBoundsMeters(scan: scan) else { continue }
      let pad = 0.25
      guard xM >= bounds.minX - pad, xM <= bounds.maxX + pad,
            yM >= bounds.minY - pad, yM <= bounds.maxY + pad else { continue }
      let cx = (bounds.minX + bounds.maxX) * 0.5
      let cy = (bounds.minY + bounds.maxY) * 0.5
      let dx = xM - cx
      let dy = yM - cy
      let score = (dx * dx + dy * dy).squareRoot()
      if best == nil || score < best!.score {
        best = (scan.id, score)
      }
    }

    if let best {
      if selectedScanId != best.id {
        activePassageSelection = nil
        activeWallSelection = nil
      }
      selectedScanId = best.id
      showRoomHandles(for: 2.2)
    } else {
      // Tap on empty space: deselect to allow panning.
      selectedScanId = nil
      activePassageSelection = nil
      activeWallSelection = nil
      handlesVisibleUntil = nil
    }
  }

  private func handleManualRoomDraftTap(at pWorld: DPoint) {
    if isFourCornerManualRoomMode, manualRoomDraftPoints.count >= 4 {
      showToast("Vier Ecken sind gesetzt. Punkt zurück oder Raum speichern.")
      return
    }

    if let last = manualRoomDraftPoints.last, distance(last, pWorld) < 0.06 {
      return
    }

    if !isFourCornerManualRoomMode,
       manualRoomDraftPoints.count >= 3,
       let first = manualRoomDraftPoints.first,
       distance(first, pWorld) <= manualDraftCloseHitMeters {
      beginManualRoomMetadataSelection()
      return
    }

    manualRoomDraftPoints.append(pWorld)
    if isFourCornerManualRoomMode, manualRoomDraftPoints.count == 4 {
      showToast("Vier Ecken gesetzt. Raumtyp und Etage wählen.")
      beginManualRoomMetadataSelection()
    }
  }

  private func removeLastManualDraftPoint() {
    guard !manualRoomDraftPoints.isEmpty else { return }
    manualRoomDraftPoints.removeLast()
  }

  private func toggleFourCornerManualRoomMode() {
    isFourCornerManualRoomMode.toggle()
    if isFourCornerManualRoomMode, manualRoomDraftPoints.count > 4 {
      manualRoomDraftPoints = Array(manualRoomDraftPoints.prefix(4))
    }
    showToast(isFourCornerManualRoomMode ? "Vier-Ecken-Modus: 4 Punkte setzen." : "Freies Zeichnen: beliebig viele Eckpunkte setzen.")
  }

  private func cancelManualRoomDrawing() {
    manualRoomDraftPoints.removeAll()
    isFourCornerManualRoomMode = false
    toolMode = .move
    withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
      isToolPaletteExpanded = false
    }
    showToast("Zeichenmodus beendet.")
  }

  private func beginManualRoomMetadataSelection() {
    let polygon = normalizedManualDraftPolygon(manualRoomDraftPoints)
    if isFourCornerManualRoomMode, polygon.count != 4 {
      showToast("Für Vier-Ecken-Raum genau vier Punkte setzen.")
      return
    }
    guard polygon.count >= 3 else {
      showToast("Mindestens drei Eckpunkte setzen.")
      return
    }

    if let selectedScanId,
       let scan = project.roomScans.first(where: { $0.id == selectedScanId }) {
      manualRoomRoomId = isFourCornerManualRoomMode ? "built_in_closet" : RoomTaxonomy.normalizedRoomId(scan.roomId)
      manualRoomFloorId = FloorTaxonomy.normalizedFloorId(scan.floorId)
    } else {
      manualRoomRoomId = isFourCornerManualRoomMode ? "built_in_closet" : RoomTaxonomy.defaultRoomId
      manualRoomFloorId = FloorTaxonomy.defaultFloorId
    }
    isManualRoomPickerPresented = true
  }

  private func finalizeManualRoomDrawing() {
    let polygonWorld = normalizedManualDraftPolygon(manualRoomDraftPoints)
    guard polygonWorld.count >= 3 else {
      showToast("Mindestens drei Eckpunkte setzen.")
      return
    }

    let center = polygonCentroid(points: polygonWorld)
    let localPoints = polygonWorld.map { DPoint(x: $0.x - center.x, y: $0.y - center.y) }

    var segmentsLocal: [FloorplanSegment] = []
    for idx in 0..<localPoints.count {
      let a = localPoints[idx]
      let b = localPoints[(idx + 1) % localPoints.count]
      if distance(a, b) < 0.08 { continue }
      segmentsLocal.append(FloorplanSegment(ax: a.x, ay: a.y, bx: b.x, by: b.y))
    }
    guard segmentsLocal.count >= 3 else {
      showToast("Der gezeichnete Raum ist zu klein oder unvollständig.")
      return
    }

    let metrics = manualRoomMetrics(points: localPoints, segments: segmentsLocal)
    let roomId = RoomTaxonomy.normalizedRoomId(manualRoomRoomId)
    let floorId = FloorTaxonomy.normalizedFloorId(manualRoomFloorId)
    let scanId = UUID()
    let relBase = "rooms/\(scanId.uuidString)"
    let relUSDZ = "\(relBase)/scan.usdz"
    let relPNG = "\(relBase)/floorplan.png"
    let relSegments = "\(relBase)/segments.json"

    let geo = FloorplanSegmentsFile(
      version: 6,
      segments: segmentsLocal,
      metrics: metrics,
      doors: nil,
      openings: nil,
      windows: nil,
      entryPassageHint: nil,
      previousRoomExitPassageHint: nil,
      trackingSessionId: nil,
      worldOffsetX: nil,
      worldOffsetY: nil
    )

    guard let out = try? FloorplanProjectStore.roomScanOutputPaths(projectKey: projectKey, scanId: scanId) else {
      showToast("Konnte Raumdaten nicht speichern.")
      return
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(geo) else {
      showToast("Konnte Raumdaten nicht serialisieren.")
      return
    }
    do {
      try data.write(to: out.segmentsJSON, options: [.atomic])
    } catch {
      showToast("Konnte Raumdatei nicht schreiben.")
      return
    }

    let scan = FloorplanRoomScan(
      id: scanId,
      roomId: roomId,
      floorId: floorId,
      createdAt: Date(),
      usdzPath: relUSDZ,
      floorplanPNGPath: relPNG,
      segmentsJSONPath: relSegments,
      metrics: metrics,
      transform: FloorplanRoomTransform(translationX: center.x, translationY: center.y, rotationRadians: 0)
    )
    project.roomScans.append(scan)
    geometryByScanId[scanId] = geo
    selectedScanId = scanId
    manualRoomDraftPoints.removeAll()
    isFourCornerManualRoomMode = false
    toolMode = .move
    isManualRoomPickerPresented = false
    try? FloorplanProjectStore.save(project: project)
    if showRouteOverlay { recomputeRouteOverlay() }
    if lastCanvasSize.width > 1, lastCanvasSize.height > 1 {
      ensureBaseFit(viewSize: lastCanvasSize, force: true)
    }
    showToast("Raum manuell hinzugefügt.")
  }

  private func toggleStairPlacementFlow() {
    if isPlacingStairConnection {
      isPlacingStairConnection = false
      showToast("Treppen-Platzierung abgebrochen.")
      return
    }
    let baseFloor: String = {
      guard let selectedScanId,
            let scan = project.roomScans.first(where: { $0.id == selectedScanId }) else {
        return FloorTaxonomy.defaultFloorId
      }
      return FloorTaxonomy.normalizedFloorId(scan.floorId)
    }()
    stairFromFloorId = baseFloor
    stairToFloorId = defaultStairTargetFloor(from: baseFloor)
    isStairPickerPresented = true
  }

  private func addStairConnection(at pWorld: DPoint) {
    let fromFloor = FloorTaxonomy.normalizedFloorId(stairFromFloorId)
    let toFloor = FloorTaxonomy.normalizedFloorId(stairToFloorId)
    guard fromFloor != toFloor else {
      showToast("Start- und Ziel-Etage müssen unterschiedlich sein.")
      return
    }

    if let existingIdx = project.stairConnections.firstIndex(where: {
      $0.fromFloorId == fromFloor &&
      $0.toFloorId == toFloor &&
      distance(DPoint(x: $0.x, y: $0.y), pWorld) <= 0.40
    }) {
      project.stairConnections[existingIdx].x = pWorld.x
      project.stairConnections[existingIdx].y = pWorld.y
      showToast("Treppen-Verbindung aktualisiert.")
    } else {
      project.stairConnections.append(
        FloorplanStairConnection(
          id: UUID(),
          createdAt: Date(),
          x: pWorld.x,
          y: pWorld.y,
          fromFloorId: fromFloor,
          toFloorId: toFloor
        )
      )
      showToast("Treppen-Verbindung hinzugefügt.")
    }

    isPlacingStairConnection = false
    try? FloorplanProjectStore.save(project: project)
  }

  private func defaultStairTargetFloor(from floorId: String) -> String {
    let floors = FloorTaxonomy.floors.map(\.id)
    guard let idx = floors.firstIndex(of: floorId) else {
      return floors.first(where: { $0 != floorId }) ?? FloorTaxonomy.defaultFloorId
    }
    if idx + 1 < floors.count {
      return floors[idx + 1]
    }
    if idx > 0 {
      return floors[idx - 1]
    }
    return floors.first(where: { $0 != floorId }) ?? floorId
  }

  private func normalizedManualDraftPolygon(_ points: [DPoint]) -> [DPoint] {
    guard !points.isEmpty else { return [] }
    var out: [DPoint] = []
    out.reserveCapacity(points.count)

    for point in points {
      if let last = out.last, distance(last, point) < 0.03 {
        continue
      }
      out.append(point)
    }

    if out.count >= 2, let first = out.first, let last = out.last, distance(first, last) < 0.03 {
      out.removeLast()
    }
    return out
  }

  private func polygonCentroid(points: [DPoint]) -> DPoint {
    guard points.count >= 3 else {
      let sum = points.reduce(DPoint(x: 0, y: 0)) { partial, point in
        DPoint(x: partial.x + point.x, y: partial.y + point.y)
      }
      let divisor = Double(max(points.count, 1))
      return DPoint(x: sum.x / divisor, y: sum.y / divisor)
    }

    var twiceArea = 0.0
    var cx = 0.0
    var cy = 0.0
    for idx in 0..<points.count {
      let a = points[idx]
      let b = points[(idx + 1) % points.count]
      let cross = (a.x * b.y) - (b.x * a.y)
      twiceArea += cross
      cx += (a.x + b.x) * cross
      cy += (a.y + b.y) * cross
    }
    if abs(twiceArea) <= 1e-9 {
      let sum = points.reduce(DPoint(x: 0, y: 0)) { partial, point in
        DPoint(x: partial.x + point.x, y: partial.y + point.y)
      }
      return DPoint(x: sum.x / Double(points.count), y: sum.y / Double(points.count))
    }
    return DPoint(x: cx / (3.0 * twiceArea), y: cy / (3.0 * twiceArea))
  }

  private func polygonArea(points: [DPoint]) -> Double {
    guard points.count >= 3 else { return 0 }
    var area2 = 0.0
    for idx in 0..<points.count {
      let a = points[idx]
      let b = points[(idx + 1) % points.count]
      area2 += (a.x * b.y) - (b.x * a.y)
    }
    return abs(area2) * 0.5
  }

  private func manualRoomMetrics(points: [DPoint], segments: [FloorplanSegment]) -> FloorplanMetrics {
    _ = points
    return FloorplanPolygonGeometry.evaluate(segments: segments).metrics
  }

  private func handleManualRouteTap(at pWorld: DPoint) {
    if let nearest = nearestManualRoutePointIndex(to: pWorld, maxDistanceMeters: 0.22) {
      project.routePoints.remove(at: nearest)
      showToast("Wegpunkt entfernt.")
    } else {
      project.routePoints.append(
        FloorplanRoutePoint(
          id: UUID(),
          createdAt: Date(),
          x: pWorld.x,
          y: pWorld.y
        )
      )
      if project.routePoints.count == 1 {
        showToast("Startpunkt gesetzt.")
      } else {
        showToast("Wegpunkt \(project.routePoints.count) hinzugefügt.")
      }
    }
    try? FloorplanProjectStore.save(project: project)
    recomputeRouteOverlay()
  }

  private func nearestManualRoutePointIndex(to pWorld: DPoint, maxDistanceMeters: Double) -> Int? {
    var best: (idx: Int, dist: Double)? = nil
    for (idx, point) in project.routePoints.enumerated() {
      let d = distance(pWorld, DPoint(x: point.x, y: point.y))
      if d > maxDistanceMeters { continue }
      if best == nil || d < best!.dist {
        best = (idx, d)
      }
    }
    return best?.idx
  }

  private func handleDoorToolTap(at pWorld: DPoint) {
    if let hit = pickDetectedPassage(at: pWorld) {
      selectedScanId = hit.scanId
      activePassageSelection = hit

      switch passageEditMode {
      case .addDoor:
        if hit.kind == .door {
          showToast("Tür ausgewählt.")
        } else {
          convertActivePassage(to: .door)
        }
      case .addOpening:
        if hit.kind == .opening {
          showToast("Durchgang ausgewählt.")
        } else {
          convertActivePassage(to: .opening)
        }
      case .addWindow:
        if hit.kind == .window {
          showToast("Fenster ausgewählt.")
        } else {
          convertActivePassage(to: .window)
        }
      case .rotateDoor:
        if hit.kind == .door {
          rotateActiveDoor()
        } else {
          showToast("Nur Türen können gedreht werden. Wähle Tür, Durchgang oder Fenster zum Umwandeln.")
        }
      case .remove:
        removeActivePassage()
      }
      return
    }

    guard let hitRoomId = pickRoomId(at: pWorld) else {
      showToast("Tippe in einen Raum, um ihn auszuwählen.")
      return
    }

    if selectedScanId != hitRoomId {
      selectedScanId = hitRoomId
      activePassageSelection = nil
      showToast(doorToolInstructionText())
      return
    }

    guard let selectedScanId else { return }

    if passageEditMode == .rotateDoor {
      if rotateDoorSwingIfHit(world: pWorld, scanId: selectedScanId) {
        showToast("Tür gedreht.")
        try? FloorplanProjectStore.save(project: project)
        if showRouteOverlay { recomputeRouteOverlay() }
        return
      }
      showToast("Keine Tür getroffen.")
      return
    }

    if passageEditMode == .remove {
      if let removedPassage = removeDetectedPassageIfHit(world: pWorld, scanId: selectedScanId) {
        showToast("\(removedPassage.label) entfernt.")
        try? FloorplanProjectStore.save(project: project)
        if showRouteOverlay { recomputeRouteOverlay() }
        return
      }
      showToast("Keine Tür, kein Durchgang und kein Fenster getroffen.")
      return
    }

    if passageEditMode == .addWindow {
      if let conversion = convertDetectedPassageToWindowIfHit(world: pWorld, scanId: selectedScanId) {
        showToast(conversion)
        try? FloorplanProjectStore.save(project: project)
        if showRouteOverlay { recomputeRouteOverlay() }
        return
      }

      if addWindowOnNearestWall(world: pWorld, scanId: selectedScanId) {
        showToast("Fenster hinzugefügt.")
        try? FloorplanProjectStore.save(project: project)
        if showRouteOverlay { recomputeRouteOverlay() }
        return
      }

      showToast("Keine passende Wand für ein Fenster gefunden.")
      return
    }

    let targetKind: PassageKind = (passageEditMode == .addOpening) ? .opening : .door
    if let conversion = convertDetectedPassageIfHit(world: pWorld, scanId: selectedScanId, to: targetKind) {
      showToast(conversion)
      try? FloorplanProjectStore.save(project: project)
      if showRouteOverlay { recomputeRouteOverlay() }
      return
    }

    if let result = addPassageOnNearestWall(world: pWorld, scanId: selectedScanId, kind: targetKind) {
      if let selection = result.selection {
        activePassageSelection = selection
      }
      showToast(result.message)
      if result.changed {
        try? FloorplanProjectStore.save(project: project)
        if showRouteOverlay { recomputeRouteOverlay() }
      }
      return
    }

    showToast(targetKind == .door ? "Keine passende Wand für eine Tür gefunden." : "Keine passende Wand für einen Durchgang gefunden.")
  }

  private func doorToolInstructionText() -> String {
    switch passageEditMode {
    case .addDoor:
      return "Raum gewählt. Tippe auf Durchgang/Fenster zum Umwandeln oder auf eine Wand für eine neue Tür."
    case .addOpening:
      return "Raum gewählt. Tippe auf Tür/Fenster zum Umwandeln oder auf eine Wand für einen neuen Durchgang."
    case .addWindow:
      return "Raum gewählt. Tippe auf Tür/Durchgang zum Umwandeln oder auf eine Wand für ein neues Fenster."
    case .rotateDoor:
      return "Raum gewählt. Tippe auf eine Tür, um Anschlag und Öffnungsrichtung durchzuschalten."
    case .remove:
      return "Raum gewählt. Tippe auf Tür, Durchgang oder Fenster zum Entfernen."
    }
  }

  private func applyPassagePaletteMode(_ mode: PassageEditMode) {
    passageEditMode = mode
    guard activePassageSelection != nil else { return }

    switch mode {
    case .addDoor:
      convertActivePassage(to: .door)
    case .addOpening:
      convertActivePassage(to: .opening)
    case .addWindow:
      convertActivePassage(to: .window)
    case .rotateDoor:
      rotateActiveDoor()
    case .remove:
      removeActivePassage()
    }
  }

  private func convertActivePassage(to targetKind: PassageKind) {
    guard let selection = activePassageSelection else { return }
    if selection.kind == targetKind {
      showToast(activePassageLabel(selection.kind) + " ausgewählt.")
      return
    }
    guard var geo = geometryByScanId[selection.scanId],
          let segment = removeFeature(detectedRemoval(from: selection), from: &geo, scanId: selection.scanId) else {
      activePassageSelection = nil
      showToast("Auswahl nicht mehr gefunden.")
      return
    }

    let newIndex: Int
    switch targetKind {
    case .door:
      var doors = geo.doors ?? []
      newIndex = doors.count
      doors.append(segment)
      geo.doors = doors
    case .opening:
      var openings = geo.openings ?? []
      newIndex = openings.count
      openings.append(segment)
      geo.openings = openings
    case .window:
      var windows = geo.windows ?? []
      newIndex = windows.count
      windows.append(segment)
      geo.windows = windows
    }

    geometryByScanId[selection.scanId] = geo
    activePassageSelection = DoorSelection(scanId: selection.scanId, kind: targetKind, index: newIndex)
    persistGeometry(scanId: selection.scanId, geo: geo)
    try? FloorplanProjectStore.save(project: project)
    if showRouteOverlay { recomputeRouteOverlay() }
    showToast("Als \(activePassageLabel(targetKind)) markiert.")
  }

  private func removeActivePassage() {
    guard let selection = activePassageSelection else { return }
    guard var geo = geometryByScanId[selection.scanId],
          removeFeature(detectedRemoval(from: selection), from: &geo, scanId: selection.scanId) != nil else {
      activePassageSelection = nil
      showToast("Auswahl nicht mehr gefunden.")
      return
    }

    geometryByScanId[selection.scanId] = geo
    activePassageSelection = nil
    persistGeometry(scanId: selection.scanId, geo: geo)
    try? FloorplanProjectStore.save(project: project)
    if showRouteOverlay { recomputeRouteOverlay() }
    showToast("\(activePassageLabel(selection.kind)) entfernt.")
  }

  private func rotateActiveDoor() {
    guard let selection = activePassageSelection else { return }
    guard selection.kind == .door else {
      showToast("Nur Türen können gedreht werden.")
      return
    }
    guard rotateDoorSwing(selection: selection) else {
      activePassageSelection = nil
      showToast("Tür nicht mehr gefunden.")
      return
    }
    try? FloorplanProjectStore.save(project: project)
    if showRouteOverlay { recomputeRouteOverlay() }
    showToast("Tür gedreht.")
  }

  private func activePassageLabel(_ kind: PassageKind) -> String {
    switch kind {
    case .door:
      return "Tür"
    case .opening:
      return "Durchgang"
    case .window:
      return "Fenster"
    }
  }

  private func detectedRemoval(from selection: DoorSelection) -> DetectedPassageRemoval {
    switch selection.kind {
    case .door:
      return .door(index: selection.index)
    case .opening:
      return .opening(index: selection.index)
    case .window:
      return .window(index: selection.index)
    }
  }

  private func handleConnectToolTap(at pWorld: DPoint) {
    doorDockPreview = nil

    guard let hit = pickPassage(at: pWorld) else {
      // Fallback: allow selecting rooms even in connect mode.
      if let roomId = pickRoomId(at: pWorld) {
        selectedScanId = roomId
        return
      }
      selectedScanId = nil
      connectSourceDoor = nil
      showToast("Tippe auf eine Tür/Öffnung, um Räume zu verbinden.")
      return
    }

    selectedScanId = hit.scanId

    if connectSourceDoor == nil {
      connectSourceDoor = hit
      showToast("Quelle gewählt. Tippe jetzt die passende Tür/Öffnung im Nachbarraum.")
      return
    }

    guard let source = connectSourceDoor else { return }

    if source.scanId == hit.scanId {
      connectSourceDoor = hit
      showToast("Quelle geändert. Jetzt Tür/Öffnung im Nachbarraum tippen.")
      return
    }

    if dockRoom(target: hit, to: source) {
      _ = upsertConnection(a: source, b: hit)
      connectSourceDoor = nil
      showToast("Angedockt.")
      try? FloorplanProjectStore.save(project: project)
      if showRouteOverlay { recomputeRouteOverlay() }
    } else {
      showToast("Konnte nicht verbinden. Tippe erneut auf die Türen.")
    }
  }

  private func autoDockAndConnectSelectedRoom() {
    guard let selectedScanId else {
      showToast("Bitte zuerst einen Raum auswählen.")
      return
    }
    guard let idx = project.roomScans.firstIndex(where: { $0.id == selectedScanId }) else {
      showToast("Ausgewählter Raum nicht gefunden.")
      return
    }
    guard let preview = computeBestDoorDockPreview(
      movingScanId: selectedScanId,
      maxDistanceMeters: doorDockThresholdMeters * 1.2
    ) else {
      showToast("Kein passender Nachbarraum zum Andocken gefunden.")
      return
    }

    project.roomScans[idx].transform = preview.targetTransform

    let movingMid = midpoint(of: preview.movingDoorWorld)
    let otherMid = midpoint(of: preview.otherDoorWorld)

    var linked = false
    if let source = nearestPassageSelection(scanId: preview.otherScanId, nearWorldPoint: otherMid, maxDistanceMeters: 0.35),
       let target = nearestPassageSelection(scanId: preview.movingScanId, nearWorldPoint: movingMid, maxDistanceMeters: 0.35) {
      linked = upsertConnection(a: source, b: target)
    }

    try? FloorplanProjectStore.save(project: project)
    if showRouteOverlay { recomputeRouteOverlay() }
    showToast(linked ? "Raum automatisch angedockt und verbunden." : "Raum automatisch angedockt.")
  }

  private func autoConnectNearbyPassages() {
    guard project.roomScans.count >= 2 else {
      showToast("Zu wenige Räume für Auto-Verbindungen.")
      return
    }

    let redocked = sequentialAutoConnectAndDock()

    var added = 0
    var alreadyConnected = 0
    var matchedPairs = 0
    var generatedPassages = 0

    for i in 0..<project.roomScans.count {
      for j in (i + 1)..<project.roomScans.count {
        let a = project.roomScans[i]
        let b = project.roomScans[j]
        guard a.floorId == b.floorId else { continue }
        let strictPair = bestPassagePairBetween(
          scanAId: a.id,
          scanBId: b.id,
          maxDistanceMeters: 0.65,
          minDirectionDot: 0.70
        )

        let boundsGap = roomBoundsGapMeters(scanAId: a.id, scanBId: b.id) ?? Double.greatestFiniteMagnitude
        let relaxedPair: (a: DoorSelection, b: DoorSelection)? = {
          guard strictPair == nil else { return nil }
          guard boundsGap <= 0.75 else { return nil }
          return bestPassagePairBetween(
            scanAId: a.id,
            scanBId: b.id,
            maxDistanceMeters: 1.45,
            minDirectionDot: 0.22
          )
        }()

        var pair = strictPair ?? relaxedPair
        if pair == nil,
           boundsGap <= 1.35,
           let anchors = autoConnectAnchorsBetweenRooms(scanAId: a.id, scanBId: b.id) {
          let beforeA = passagesWorld(scanId: a.id).count
          let beforeB = passagesWorld(scanId: b.id).count

          let ensuredA = ensurePassageForAutoConnect(scanId: a.id, anchorWorld: anchors.a)
          let ensuredB = ensurePassageForAutoConnect(scanId: b.id, anchorWorld: anchors.b)
          if let ensuredA, let ensuredB {
            pair = (a: ensuredA, b: ensuredB)
          }

          let afterA = passagesWorld(scanId: a.id).count
          let afterB = passagesWorld(scanId: b.id).count
          generatedPassages += max(0, afterA - beforeA)
          generatedPassages += max(0, afterB - beforeB)
        }

        guard let pair else { continue }
        matchedPairs += 1
        if upsertConnection(a: pair.a, b: pair.b) {
          added += 1
        } else {
          alreadyConnected += 1
        }
      }
    }

    if added > 0 {
      try? FloorplanProjectStore.save(project: project)
      if showRouteOverlay { recomputeRouteOverlay() }
      if generatedPassages > 0 {
        if alreadyConnected > 0 {
          showToast("\(added) neue Verbindung(en), \(alreadyConnected) bereits vorhanden. \(generatedPassages) Passage(n) ergänzt.\(redocked > 0 ? " \(redocked) Raum/Räume neu ausgerichtet." : "")")
        } else {
          showToast("\(added) Verbindung(en) erkannt. \(generatedPassages) Passage(n) ergänzt.\(redocked > 0 ? " \(redocked) Raum/Räume neu ausgerichtet." : "")")
        }
      } else if alreadyConnected > 0 {
        showToast("\(added) neue Verbindung(en), \(alreadyConnected) bereits vorhanden.\(redocked > 0 ? " \(redocked) Raum/Räume neu ausgerichtet." : "")")
      } else {
        showToast("\(added) Verbindung(en) automatisch erkannt.\(redocked > 0 ? " \(redocked) Raum/Räume neu ausgerichtet." : "")")
      }
    } else if alreadyConnected > 0 {
      showToast("Keine neuen Verbindungen. \(alreadyConnected) waren bereits vorhanden.\(redocked > 0 ? " \(redocked) Raum/Räume wurden neu ausgerichtet." : "")")
    } else if matchedPairs == 0 {
      if redocked > 0 {
        showToast("\(redocked) Raum/Räume neu ausgerichtet, aber noch keine belastbare Verbindung erkannt.")
      } else {
        showToast("Keine passenden Nachbar-Verbindungen erkannt.")
      }
    } else {
      showToast("Keine neuen Verbindungen erkannt.")
    }
  }

  private func sequentialAutoConnectAndDock() -> Int {
    let floorOrder = Dictionary(uniqueKeysWithValues: FloorTaxonomy.floors.enumerated().map { ($1.id, $0) })
    let orderedFloorIds = Array(Set(project.roomScans.map(\.floorId))).sorted {
      (floorOrder[$0] ?? Int.max) < (floorOrder[$1] ?? Int.max)
    }

    var redocked = 0

    for floorId in orderedFloorIds {
      let ordered = project.roomScans
        .filter { $0.floorId == floorId }
        .sorted { lhs, rhs in
          if lhs.createdAt == rhs.createdAt {
            return lhs.id.uuidString < rhs.id.uuidString
          }
          return lhs.createdAt < rhs.createdAt
        }

      guard ordered.count >= 2 else { continue }

      for index in 1..<ordered.count {
        let moving = ordered[index]
        guard let movingGeo = geometryByScanId[moving.id] else { continue }

        var prefixProject = project
        prefixProject.roomScans = project.roomScans.filter { scan in
          guard scan.floorId == floorId else { return true }
          guard scan.id != moving.id else { return false }
          return scan.createdAt < moving.createdAt
            || (scan.createdAt == moving.createdAt && scan.id.uuidString < moving.id.uuidString)
        }

        guard let result = FloorplanAutoDockService.bestAutoDock(
          project: prefixProject,
          newScanId: moving.id,
          newGeo: movingGeo,
          floorId: floorId,
          loadGeo: { scanId in geometryByScanId[scanId] }
        ) else { continue }

        guard let movingIndex = project.roomScans.firstIndex(where: { $0.id == moving.id }) else { continue }
        let oldTransform = project.roomScans[movingIndex].transform
        project.roomScans[movingIndex].transform = result.transform

        let movedDistance = FloorplanAutoDockService.transformDistanceMeters(a: oldTransform, b: result.transform)
        let movedRotation = abs(normalizeAngle(result.transform.rotationRadians - oldTransform.rotationRadians))
        if movedDistance > 0.08 || movedRotation > 0.06 {
          redocked += 1
        }

        _ = upsertConnection(a: result.connection.a, b: result.connection.b)
      }
    }

    return redocked
  }

  private func ensurePassageForAutoConnect(scanId: UUID, anchorWorld: DPoint) -> DoorSelection? {
    if let nearby = nearestPassageSelection(scanId: scanId, nearWorldPoint: anchorWorld, maxDistanceMeters: 1.1) {
      return nearby
    }

    if addPassageOnNearestWall(world: anchorWorld, scanId: scanId, kind: .door, maxHitDistanceMeters: 2.5) != nil,
       let created = nearestPassageSelection(scanId: scanId, nearWorldPoint: anchorWorld, maxDistanceMeters: 1.6) {
      return created
    }

    return nearestPassageSelection(scanId: scanId, nearWorldPoint: anchorWorld, maxDistanceMeters: 50.0)
  }

  private func autoConnectAnchorsBetweenRooms(scanAId: UUID, scanBId: UUID) -> (a: DPoint, b: DPoint)? {
    guard let scanA = project.roomScans.first(where: { $0.id == scanAId }),
          let scanB = project.roomScans.first(where: { $0.id == scanBId }),
          let boundsA = roomBoundsMeters(scan: scanA),
          let boundsB = roomBoundsMeters(scan: scanB) else { return nil }

    let centerA = DPoint(
      x: (boundsA.minX + boundsA.maxX) * 0.5,
      y: (boundsA.minY + boundsA.maxY) * 0.5
    )
    let centerB = DPoint(
      x: (boundsB.minX + boundsB.maxX) * 0.5,
      y: (boundsB.minY + boundsB.maxY) * 0.5
    )

    return (
      a: boundaryPoint(on: boundsA, from: centerA, toward: centerB),
      b: boundaryPoint(on: boundsB, from: centerB, toward: centerA)
    )
  }

  private func hasConnectionForSelectedRoom() -> Bool {
    guard let selectedScanId else { return false }
    return project.connections.contains { conn in
      conn.a.scanId == selectedScanId || conn.b.scanId == selectedScanId
    }
  }

  private func removeConnectionForSelectedRoom() {
    guard let selectedScanId else {
      showToast("Bitte zuerst einen Raum auswählen.")
      return
    }

    let indices = project.connections.indices.filter { idx in
      let conn = project.connections[idx]
      return conn.a.scanId == selectedScanId || conn.b.scanId == selectedScanId
    }
    guard !indices.isEmpty else {
      showToast("Für den ausgewählten Raum existiert keine Verbindung.")
      return
    }

    let selectedCenter = roomCenterWorld(scanId: selectedScanId)
    let removeIndex: Int = {
      guard indices.count > 1, let selectedCenter else { return indices[0] }
      return indices.min(by: { lhs, rhs in
        let leftOther = otherScanId(for: project.connections[lhs], selected: selectedScanId)
        let rightOther = otherScanId(for: project.connections[rhs], selected: selectedScanId)
        let leftDistance = leftOther.flatMap { roomCenterWorld(scanId: $0) }.map { distance($0, selectedCenter) } ?? Double.greatestFiniteMagnitude
        let rightDistance = rightOther.flatMap { roomCenterWorld(scanId: $0) }.map { distance($0, selectedCenter) } ?? Double.greatestFiniteMagnitude
        return leftDistance < rightDistance
      }) ?? indices[0]
    }()

    let removed = project.connections.remove(at: removeIndex)
    try? FloorplanProjectStore.save(project: project)
    if showRouteOverlay { recomputeRouteOverlay() }

    let otherId = otherScanId(for: removed, selected: selectedScanId)
    let otherName = otherId
      .flatMap { id in project.roomScans.first(where: { $0.id == id })?.roomId }
      .map { RoomTaxonomy.room(id: $0).displayName } ?? "Nachbarraum"
    showToast("Verbindung zu \(otherName) gelöst.")
  }

  private func otherScanId(for connection: FloorplanRoomConnection, selected: UUID) -> UUID? {
    if connection.a.scanId == selected { return connection.b.scanId }
    if connection.b.scanId == selected { return connection.a.scanId }
    return nil
  }

  private func nearestPassageSelection(
    scanId: UUID,
    nearWorldPoint pointWorld: DPoint,
    maxDistanceMeters: Double
  ) -> DoorSelection? {
    guard let scan = project.roomScans.first(where: { $0.id == scanId }),
          let geo = geometryByScanId[scanId] else { return nil }
    let pointLocal = toLocal(pointWorld, t: scan.transform)

    var best: (DoorSelection, Double)? = nil
    if let doors = geo.doors {
      for (idx, seg) in doors.enumerated() {
        let dist = pointSegmentDistance(p: pointLocal, seg: seg).dist
        if best == nil || dist < best!.1 {
          best = (DoorSelection(scanId: scanId, kind: .door, index: idx), dist)
        }
      }
    }
    if let openings = geo.openings {
      for (idx, seg) in openings.enumerated() {
        let dist = pointSegmentDistance(p: pointLocal, seg: seg).dist
        if best == nil || dist < best!.1 {
          best = (DoorSelection(scanId: scanId, kind: .opening, index: idx), dist)
        }
      }
    }
    guard let best, best.1 <= maxDistanceMeters else { return nil }
    return best.0
  }

  private func pickDetectedPassage(at pWorld: DPoint) -> DoorSelection? {
    var best: (selection: DoorSelection, dist: Double)? = nil

    for scan in project.roomScans {
      guard let geo = geometryByScanId[scan.id] else { continue }
      let pLocal = toLocal(pWorld, t: scan.transform)
      guard let hit = nearestDetectedPassage(in: geo, pLocal: pLocal),
            hit.dist <= tapHitThresholdMeters else { continue }

      let selection: DoorSelection
      switch hit.match {
      case .door(let idx):
        selection = DoorSelection(scanId: scan.id, kind: .door, index: idx)
      case .opening(let idx):
        selection = DoorSelection(scanId: scan.id, kind: .opening, index: idx)
      case .window(let idx):
        selection = DoorSelection(scanId: scan.id, kind: .window, index: idx)
      }

      if best == nil || hit.dist < best!.dist {
        best = (selection, hit.dist)
      }
    }

    return best?.selection
  }

  private func bestPassagePairBetween(
    scanAId: UUID,
    scanBId: UUID,
    maxDistanceMeters: Double,
    minDirectionDot: Double
  ) -> (a: DoorSelection, b: DoorSelection)? {
    let passagesA = passagesWorld(scanId: scanAId)
    let passagesB = passagesWorld(scanId: scanBId)
    guard !passagesA.isEmpty, !passagesB.isEmpty else { return nil }

    var best: (DoorSelection, DoorSelection, Double)? = nil
    for a in passagesA {
      let aMid = midpoint(of: a.segWorld)
      let aDir = direction(of: a.segWorld)
      let aWidth = segmentLength(a.segWorld)
      for b in passagesB {
        let bMid = midpoint(of: b.segWorld)
        let bDir = direction(of: b.segWorld)
        let bWidth = segmentLength(b.segWorld)
        let dist = distance(aMid, bMid)
        guard dist <= maxDistanceMeters else { continue }

        let directionDot = abs(dot(aDir, bDir))
        guard directionDot >= minDirectionDot else { continue }
        guard FloorplanAutoDockService.passageWidthsLookCompatible(
          kindA: floorplanPassageKind(a.selection.kind),
          lenA: aWidth,
          kindB: floorplanPassageKind(b.selection.kind),
          lenB: bWidth
        ) else { continue }
        var score = dist + (1.0 - directionDot) * 0.25
        score += abs(aWidth - bWidth) * 0.85
        score += FloorplanAutoDockService.passageKindMismatchPenalty(
          kindA: floorplanPassageKind(a.selection.kind),
          kindB: floorplanPassageKind(b.selection.kind)
        ) * 0.08
        if a.selection.kind == .opening && b.selection.kind == .opening {
          score -= min(0.18, min(aWidth, bWidth) * 0.08)
        }
        if best == nil || score < best!.2 {
          best = (a.selection, b.selection, score)
        }
      }
    }
    guard let best else { return nil }
    return (a: best.0, b: best.1)
  }

  private func roomBoundsGapMeters(scanAId: UUID, scanBId: UUID) -> Double? {
    guard let scanA = project.roomScans.first(where: { $0.id == scanAId }),
          let scanB = project.roomScans.first(where: { $0.id == scanBId }),
          let boundsA = roomBoundsMeters(scan: scanA),
          let boundsB = roomBoundsMeters(scan: scanB) else { return nil }

    let dx = max(0.0, max(boundsA.minX - boundsB.maxX, boundsB.minX - boundsA.maxX))
    let dy = max(0.0, max(boundsA.minY - boundsB.maxY, boundsB.minY - boundsA.maxY))
    return (dx * dx + dy * dy).squareRoot()
  }

  private func passagesWorld(scanId: UUID) -> [(selection: DoorSelection, segWorld: FloorplanSegment)] {
    guard let scan = project.roomScans.first(where: { $0.id == scanId }),
          let geo = geometryByScanId[scanId] else { return [] }
    var out: [(selection: DoorSelection, segWorld: FloorplanSegment)] = []

    if let doors = geo.doors {
      for (idx, segLocal) in doors.enumerated() {
        if let segWorld = transform(segments: [segLocal], t: scan.transform).first {
          out.append((DoorSelection(scanId: scanId, kind: .door, index: idx), segWorld))
        }
      }
    }
    if let openings = geo.openings {
      for (idx, segLocal) in openings.enumerated() {
        if let segWorld = transform(segments: [segLocal], t: scan.transform).first {
          out.append((DoorSelection(scanId: scanId, kind: .opening, index: idx), segWorld))
        }
      }
    }

    return out
  }

  private func passagesLocal(scanId: UUID) -> [(selection: DoorSelection, segLocal: FloorplanSegment)] {
    guard let geo = geometryByScanId[scanId] else { return [] }

    var out: [(selection: DoorSelection, segLocal: FloorplanSegment)] = []
    if let doors = geo.doors {
      for (idx, segLocal) in doors.enumerated() {
        out.append((DoorSelection(scanId: scanId, kind: .door, index: idx), segLocal))
      }
    }
    if let openings = geo.openings {
      for (idx, segLocal) in openings.enumerated() {
        out.append((DoorSelection(scanId: scanId, kind: .opening, index: idx), segLocal))
      }
    }
    return out
  }

  private func pickPassage(at pWorld: DPoint) -> DoorSelection? {
    var best: (sel: DoorSelection, dist: Double)? = nil

    for scan in project.roomScans {
      guard let geo = geometryByScanId[scan.id] else { continue }
      let pLocal = toLocal(pWorld, t: scan.transform)

      if let doors = geo.doors {
        for (idx, seg) in doors.enumerated() {
          let res = pointSegmentDistance(p: pLocal, seg: seg)
          if best == nil || res.dist < best!.dist {
            best = (DoorSelection(scanId: scan.id, kind: .door, index: idx), res.dist)
          }
        }
      }

      if let openings = geo.openings {
        for (idx, seg) in openings.enumerated() {
          let res = pointSegmentDistance(p: pLocal, seg: seg)
          if best == nil || res.dist < best!.dist {
            best = (DoorSelection(scanId: scan.id, kind: .opening, index: idx), res.dist)
          }
        }
      }
    }

    guard let best, best.dist <= connectHitThresholdMeters else { return nil }
    return best.sel
  }

  private func dockRoom(target: DoorSelection, to source: DoorSelection) -> Bool {
    guard let sourceSeg = passageSegmentLocal(for: source),
          let targetSeg = passageSegmentLocal(for: target) else { return false }
    guard let sourceScan = project.roomScans.first(where: { $0.id == source.scanId }),
          let targetIdx = project.roomScans.firstIndex(where: { $0.id == target.scanId }) else { return false }

    let targetScan = project.roomScans[targetIdx]
    guard sourceScan.floorId == targetScan.floorId else {
      showToast("Quelle und Ziel müssen auf derselben Etage sein.")
      return false
    }

    let sourceMidWorld = mapLocalPointToWorld(midpoint(of: sourceSeg), t: sourceScan.transform)
    let sourceThetaWorld = normalizeAngle(sourceScan.transform.rotationRadians + angle(of: direction(of: sourceSeg)))

    let targetThetaLocal = angle(of: direction(of: targetSeg))
    let targetThetaWorld = normalizeAngle(targetScan.transform.rotationRadians + targetThetaLocal)

    let diffA = normalizeAngle(sourceThetaWorld - targetThetaWorld)
    let diffB = normalizeAngle((sourceThetaWorld + Double.pi) - targetThetaWorld)
    let rotationDelta = abs(diffA) <= abs(diffB) ? diffA : diffB

    let newRotation = normalizeAngle(targetScan.transform.rotationRadians + rotationDelta)
    let targetMidLocal = midpoint(of: targetSeg)
    let rotated = rotatePoint(targetMidLocal, radians: newRotation)
    let newTx = sourceMidWorld.x - rotated.x
    let newTy = sourceMidWorld.y - rotated.y

    project.roomScans[targetIdx].transform.rotationRadians = newRotation
    project.roomScans[targetIdx].transform.translationX = newTx
    project.roomScans[targetIdx].transform.translationY = newTy
    pruneInvalidConnectionsIfNeeded()
    return true
  }

  private func floorplanPassageKind(_ kind: PassageKind) -> FloorplanPassageKind {
    kind == .door ? .door : .opening
  }

  @discardableResult
  private func upsertConnection(a: DoorSelection, b: DoorSelection) -> Bool {
    return upsertConnection(a: passageRef(from: a), b: passageRef(from: b))
  }

  @discardableResult
  private func upsertConnection(a: FloorplanPassageRef, b: FloorplanPassageRef) -> Bool {
    let ra = a
    let rb = b

    // Normalize ordering to make dedupe stable.
    func key(_ r: FloorplanPassageRef) -> String { "\(r.scanId.uuidString)|\(r.kind.rawValue)|\(r.index)" }
    let (lhs, rhs) = (key(ra) <= key(rb)) ? (ra, rb) : (rb, ra)

    if project.connections.contains(where: { c in
      let ca = c.a
      let cb = c.b
      return (key(ca) == key(lhs) && key(cb) == key(rhs)) || (key(ca) == key(rhs) && key(cb) == key(lhs))
    }) {
      return false
    }

    project.connections.append(
      FloorplanRoomConnection(
        id: UUID(),
        createdAt: Date(),
        a: lhs,
        b: rhs
      )
    )
    return true
  }

  private func validConnections() -> [FloorplanRoomConnection] {
    project.connections.filter(isConnectionPlausible)
  }

  private func pruneInvalidConnectionsIfNeeded(persist: Bool = true) {
    let filtered = validConnections()
    guard filtered.count != project.connections.count else { return }
    project.connections = filtered
    if persist {
      try? FloorplanProjectStore.save(project: project)
    }
    if showRouteOverlay {
      recomputeRouteOverlay()
    }
  }

  private func isConnectionPlausible(_ connection: FloorplanRoomConnection) -> Bool {
    guard let scanA = project.roomScans.first(where: { $0.id == connection.a.scanId }),
          let scanB = project.roomScans.first(where: { $0.id == connection.b.scanId }) else { return false }
    guard scanA.floorId == scanB.floorId else { return false }
    guard let segA = passageSegmentWorld(for: connection.a),
          let segB = passageSegmentWorld(for: connection.b) else { return false }

    let lenA = segmentLength(segA)
    let lenB = segmentLength(segB)
    let maxLen = max(lenA, lenB)
    guard maxLen > 0.001 else { return false }
    let directionDot = abs(dot(direction(of: segA), direction(of: segB)))
    let midpointDistance = distance(midpoint(of: segA), midpoint(of: segB))
    let maxDistance = max(0.95, maxLen * 0.85)

    guard directionDot >= 0.55 else { return false }
    guard midpointDistance <= maxDistance else { return false }
    return FloorplanAutoDockService.passageWidthsLookCompatible(
      kindA: connection.a.kind,
      lenA: lenA,
      kindB: connection.b.kind,
      lenB: lenB
    )
  }

  private func passageRef(from selection: DoorSelection) -> FloorplanPassageRef {
    let kind: FloorplanPassageKind = (selection.kind == .door) ? .door : .opening
    return FloorplanPassageRef(scanId: selection.scanId, kind: kind, index: selection.index)
  }

  private func adjustConnectionsAfterPassageRemoval(scanId: UUID, kind: FloorplanPassageKind, removedIndex: Int) {
    func adjust(_ ref: inout FloorplanPassageRef) -> Bool {
      guard ref.scanId == scanId, ref.kind == kind else { return true }
      if ref.index == removedIndex { return false }
      if ref.index > removedIndex { ref.index -= 1 }
      return true
    }

    project.connections = project.connections.compactMap { conn in
      var c = conn
      guard adjust(&c.a), adjust(&c.b) else { return nil }
      return c
    }
  }

  private func passageSegmentLocal(for selection: DoorSelection) -> FloorplanSegment? {
    guard let geo = geometryByScanId[selection.scanId] else { return nil }
    switch selection.kind {
    case .door:
      return geo.doors?.indices.contains(selection.index) == true ? geo.doors?[selection.index] : nil
    case .opening:
      return geo.openings?.indices.contains(selection.index) == true ? geo.openings?[selection.index] : nil
    case .window:
      return geo.windows?.indices.contains(selection.index) == true ? geo.windows?[selection.index] : nil
    }
  }

  private func doorSegmentWorld(for selection: DoorSelection) -> FloorplanSegment? {
    guard let scan = project.roomScans.first(where: { $0.id == selection.scanId }) else { return nil }
    guard let segLocal = passageSegmentLocal(for: selection) else { return nil }
    return transform(segments: [segLocal], t: scan.transform).first
  }

  private func passageSegmentWorld(for ref: FloorplanPassageRef) -> FloorplanSegment? {
    guard let scan = project.roomScans.first(where: { $0.id == ref.scanId }),
          let geo = geometryByScanId[ref.scanId] else { return nil }

    let segLocal: FloorplanSegment?
    switch ref.kind {
    case .door:
      segLocal = geo.doors?.indices.contains(ref.index) == true ? geo.doors?[ref.index] : nil
    case .opening:
      segLocal = geo.openings?.indices.contains(ref.index) == true ? geo.openings?[ref.index] : nil
    }

    guard let segLocal else { return nil }
    return transform(segments: [segLocal], t: scan.transform).first
  }

  private func pickRoomId(at pWorld: DPoint) -> UUID? {
    var best: (id: UUID, score: Double)? = nil
    for scan in project.roomScans {
      guard let bounds = roomBoundsMeters(scan: scan) else { continue }
      let pad = 0.25
      guard pWorld.x >= bounds.minX - pad, pWorld.x <= bounds.maxX + pad,
            pWorld.y >= bounds.minY - pad, pWorld.y <= bounds.maxY + pad else { continue }
      let cx = (bounds.minX + bounds.maxX) * 0.5
      let cy = (bounds.minY + bounds.maxY) * 0.5
      let dx = pWorld.x - cx
      let dy = pWorld.y - cy
      let score = (dx * dx + dy * dy).squareRoot()
      if best == nil || score < best!.score {
        best = (scan.id, score)
      }
    }
    return best?.id
  }

  private func removeDetectedPassageIfHit(world pWorld: DPoint, scanId: UUID) -> DetectedPassageRemoval? {
    guard var geo = geometryByScanId[scanId] else { return nil }
    guard let scan = project.roomScans.first(where: { $0.id == scanId }) else { return nil }

    let pLocal = toLocal(pWorld, t: scan.transform)
    var best: (match: DetectedPassageRemoval, dist: Double)? = nil

    if let doors = geo.doors {
      for (idx, segment) in doors.enumerated() {
        let res = pointSegmentDistance(p: pLocal, seg: segment)
        if best == nil || res.dist < best!.dist {
          best = (.door(index: idx), res.dist)
        }
      }
    }

    if let openings = geo.openings {
      for (idx, segment) in openings.enumerated() {
        let res = pointSegmentDistance(p: pLocal, seg: segment)
        if best == nil || res.dist < best!.dist {
          best = (.opening(index: idx), res.dist)
        }
      }
    }

    if let windows = geo.windows {
      for (idx, segment) in windows.enumerated() {
        let res = pointSegmentDistance(p: pLocal, seg: segment)
        if best == nil || res.dist < best!.dist {
          best = (.window(index: idx), res.dist)
        }
      }
    }
    guard let best, best.dist <= tapHitThresholdMeters else { return nil }

    switch best.match {
    case .door(let index):
      var doors = geo.doors ?? []
      guard doors.indices.contains(index) else { return nil }
      doors.remove(at: index)
      if var overrides = geo.doorSwingOverrides, overrides.indices.contains(index) {
        overrides.remove(at: index)
        geo.doorSwingOverrides = overrides.isEmpty ? nil : overrides
      }
      adjustConnectionsAfterPassageRemoval(scanId: scanId, kind: .door, removedIndex: index)
      geo.doors = doors.isEmpty ? nil : doors
      if activePassageSelection == DoorSelection(scanId: scanId, kind: .door, index: index) {
        activePassageSelection = nil
      }
    case .opening(let index):
      var openings = geo.openings ?? []
      guard openings.indices.contains(index) else { return nil }
      openings.remove(at: index)
      adjustConnectionsAfterPassageRemoval(scanId: scanId, kind: .opening, removedIndex: index)
      geo.openings = openings.isEmpty ? nil : openings
      if activePassageSelection == DoorSelection(scanId: scanId, kind: .opening, index: index) {
        activePassageSelection = nil
      }
    case .window(let index):
      var windows = geo.windows ?? []
      guard windows.indices.contains(index) else { return nil }
      windows.remove(at: index)
      geo.windows = windows.isEmpty ? nil : windows
      if activePassageSelection == DoorSelection(scanId: scanId, kind: .window, index: index) {
        activePassageSelection = nil
      }
    }

    geometryByScanId[scanId] = geo
    persistGeometry(scanId: scanId, geo: geo)
    return best.match
  }

  private func rotateDoorSwingIfHit(world pWorld: DPoint, scanId: UUID) -> Bool {
    guard let geo = geometryByScanId[scanId],
          let doors = geo.doors,
          !doors.isEmpty else { return false }
    guard let scan = project.roomScans.first(where: { $0.id == scanId }) else { return false }

    let pLocal = toLocal(pWorld, t: scan.transform)
    var best: (index: Int, dist: Double)? = nil
    for (idx, segment) in doors.enumerated() {
      let res = pointSegmentDistance(p: pLocal, seg: segment)
      if best == nil || res.dist < best!.dist {
        best = (idx, res.dist)
      }
    }
    guard let best, best.dist <= tapHitThresholdMeters else { return false }

    return rotateDoorSwing(selection: DoorSelection(scanId: scanId, kind: .door, index: best.index))
  }

  private func rotateDoorSwing(selection: DoorSelection) -> Bool {
    guard selection.kind == .door else { return false }
    guard var geo = geometryByScanId[selection.scanId],
          let doors = geo.doors,
          !doors.isEmpty,
          doors.indices.contains(selection.index) else { return false }

    let collapsed = collapseDuplicatePassages(in: &geo, scanId: selection.scanId, kind: .door, keeping: selection.index)
    let selectedIndex = collapsed.keptIndex
    let doorCount = geo.doors?.count ?? doors.count
    var overrides = normalizedDoorSwingOverrides(for: doorCount, existing: geo.doorSwingOverrides)
    guard overrides.indices.contains(selectedIndex) else { return false }
    let current = overrides[selectedIndex].normalizedQuarterTurns
    overrides[selectedIndex] = FloorplanDoorSwingOverride(rotationQuarterTurns: (current + 1) % 4)
    geo.doorSwingOverrides = overrides
    geometryByScanId[selection.scanId] = geo
    activePassageSelection = DoorSelection(scanId: selection.scanId, kind: .door, index: selectedIndex)
    persistGeometry(scanId: selection.scanId, geo: geo)
    return true
  }

  private func normalizedDoorSwingOverrides(
    for doorCount: Int,
    existing: [FloorplanDoorSwingOverride]?
  ) -> [FloorplanDoorSwingOverride] {
    guard doorCount > 0 else { return [] }
    var overrides = existing ?? []
    if overrides.count < doorCount {
      overrides.append(contentsOf: Array(repeating: FloorplanDoorSwingOverride(rotationQuarterTurns: 0), count: doorCount - overrides.count))
    } else if overrides.count > doorCount {
      overrides = Array(overrides.prefix(doorCount))
    }
    return overrides
  }

  private func convertDetectedPassageIfHit(world pWorld: DPoint, scanId: UUID, to targetKind: PassageKind) -> String? {
    if targetKind == .window {
      return convertDetectedPassageToWindowIfHit(world: pWorld, scanId: scanId)
    }

    guard var geo = geometryByScanId[scanId] else { return nil }
    guard let scan = project.roomScans.first(where: { $0.id == scanId }) else { return nil }

    let pLocal = toLocal(pWorld, t: scan.transform)
    guard let best = nearestDetectedPassage(in: geo, pLocal: pLocal),
          best.dist <= tapHitThresholdMeters else { return nil }

    let isAlreadyTarget: Bool = {
      switch (best.match, targetKind) {
      case (.door(_), .door), (.opening(_), .opening):
        return true
      case (.window(_), _):
        return false
      case (.door(_), .opening), (.opening(_), .door), (.door(_), .window), (.opening(_), .window):
        return false
      }
    }()
    guard !isAlreadyTarget else {
      switch (best.match, targetKind) {
      case (.door(let index), .door):
        let collapsed = collapseDuplicatePassages(in: &geo, scanId: scanId, kind: .door, keeping: index)
        geometryByScanId[scanId] = geo
        if collapsed.changed {
          persistGeometry(scanId: scanId, geo: geo)
        }
        activePassageSelection = DoorSelection(scanId: scanId, kind: .door, index: collapsed.keptIndex)
        return collapsed.changed ? "Tür ausgewählt, Duplikat bereinigt." : "Ist bereits als Tür markiert."
      case (.opening(let index), .opening):
        let collapsed = collapseDuplicatePassages(in: &geo, scanId: scanId, kind: .opening, keeping: index)
        geometryByScanId[scanId] = geo
        if collapsed.changed {
          persistGeometry(scanId: scanId, geo: geo)
        }
        activePassageSelection = DoorSelection(scanId: scanId, kind: .opening, index: collapsed.keptIndex)
        return collapsed.changed ? "Durchgang ausgewählt, Duplikat bereinigt." : "Ist bereits als Durchgang markiert."
      default:
        break
      }
      return targetKind == .door ? "Ist bereits als Tür markiert." : "Ist bereits als Durchgang markiert."
    }

    guard let segment = removeFeature(best.match, from: &geo, scanId: scanId) else { return nil }

    if let duplicate = nearestDuplicateFeature(in: geo, to: segment, maxDistanceMeters: 0.28) {
      switch (duplicate.match, targetKind) {
      case (.door(let index), .door):
        geometryByScanId[scanId] = geo
        persistGeometry(scanId: scanId, geo: geo)
        activePassageSelection = DoorSelection(scanId: scanId, kind: .door, index: index)
        return "Doppelte Markierung bereinigt."
      case (.opening(let index), .opening):
        geometryByScanId[scanId] = geo
        persistGeometry(scanId: scanId, geo: geo)
        activePassageSelection = DoorSelection(scanId: scanId, kind: .opening, index: index)
        return "Doppelte Markierung bereinigt."
      default:
        _ = removeFeature(duplicate.match, from: &geo, scanId: scanId)
      }
    }

    switch targetKind {
    case .door:
      var doors = geo.doors ?? []
      let newIndex = doors.count
      doors.append(segment)
      geo.doors = doors
      activePassageSelection = DoorSelection(scanId: scanId, kind: .door, index: newIndex)
    case .opening:
      var openings = geo.openings ?? []
      let newIndex = openings.count
      openings.append(segment)
      geo.openings = openings
      activePassageSelection = DoorSelection(scanId: scanId, kind: .opening, index: newIndex)
    case .window:
      var windows = geo.windows ?? []
      let newIndex = windows.count
      windows.append(segment)
      geo.windows = windows
      activePassageSelection = DoorSelection(scanId: scanId, kind: .window, index: newIndex)
    }

    geometryByScanId[scanId] = geo
    persistGeometry(scanId: scanId, geo: geo)
    return "Als \(activePassageLabel(targetKind)) markiert."
  }

  private func convertDetectedPassageToWindowIfHit(world pWorld: DPoint, scanId: UUID) -> String? {
    guard var geo = geometryByScanId[scanId] else { return nil }
    guard let scan = project.roomScans.first(where: { $0.id == scanId }) else { return nil }

    let pLocal = toLocal(pWorld, t: scan.transform)
    guard let best = nearestDetectedPassage(in: geo, pLocal: pLocal),
          best.dist <= tapHitThresholdMeters else { return nil }

    if case .window(_) = best.match {
      return "Ist bereits als Fenster markiert."
    }

    guard let segment = removeFeature(best.match, from: &geo, scanId: scanId) else { return nil }
    var windows = geo.windows ?? []
    let newIndex = windows.count
    windows.append(segment)
    geo.windows = windows

    geometryByScanId[scanId] = geo
    activePassageSelection = DoorSelection(scanId: scanId, kind: .window, index: newIndex)
    persistGeometry(scanId: scanId, geo: geo)
    return "Als Fenster markiert."
  }

  private func nearestDetectedPassage(
    in geo: FloorplanSegmentsFile,
    pLocal: DPoint
  ) -> (match: DetectedPassageRemoval, dist: Double)? {
    var best: (match: DetectedPassageRemoval, dist: Double)? = nil

    if let doors = geo.doors {
      for (idx, segment) in doors.enumerated() {
        let res = pointSegmentDistance(p: pLocal, seg: segment)
        if best == nil || res.dist < best!.dist {
          best = (.door(index: idx), res.dist)
        }
      }
    }

    if let openings = geo.openings {
      for (idx, segment) in openings.enumerated() {
        let res = pointSegmentDistance(p: pLocal, seg: segment)
        if best == nil || res.dist < best!.dist {
          best = (.opening(index: idx), res.dist)
        }
      }
    }

    if let windows = geo.windows {
      for (idx, segment) in windows.enumerated() {
        let res = pointSegmentDistance(p: pLocal, seg: segment)
        if best == nil || res.dist < best!.dist {
          best = (.window(index: idx), res.dist)
        }
      }
    }

    return best
  }

  private func nearestDuplicateFeature(
    in geo: FloorplanSegmentsFile,
    to segment: FloorplanSegment,
    maxDistanceMeters: Double
  ) -> (match: DetectedPassageRemoval, dist: Double)? {
    var best: (match: DetectedPassageRemoval, dist: Double)? = nil

    func consider(_ match: DetectedPassageRemoval, _ existing: FloorplanSegment) {
      guard areDuplicatePassages(existing, segment, maxDistanceMeters: maxDistanceMeters) else { return }
      let dist = distance(midpoint(of: existing), midpoint(of: segment))
      if best == nil || dist < best!.dist {
        best = (match, dist)
      }
    }

    if let doors = geo.doors {
      for (idx, existing) in doors.enumerated() {
        consider(.door(index: idx), existing)
      }
    }

    if let openings = geo.openings {
      for (idx, existing) in openings.enumerated() {
        consider(.opening(index: idx), existing)
      }
    }

    if let windows = geo.windows {
      for (idx, existing) in windows.enumerated() {
        consider(.window(index: idx), existing)
      }
    }

    return best
  }

  private func areDuplicatePassages(
    _ lhs: FloorplanSegment,
    _ rhs: FloorplanSegment,
    maxDistanceMeters: Double
  ) -> Bool {
    let lhsMid = midpoint(of: lhs)
    let rhsMid = midpoint(of: rhs)
    let midDistance = distance(lhsMid, rhsMid)
    guard midDistance <= maxDistanceMeters else { return false }

    let lhsToRhs = pointSegmentDistance(p: lhsMid, seg: rhs).dist
    let rhsToLhs = pointSegmentDistance(p: rhsMid, seg: lhs).dist
    if lhsToRhs <= maxDistanceMeters * 0.75 && rhsToLhs <= maxDistanceMeters * 0.75 {
      return true
    }

    let directionSimilarity = abs(dot(direction(of: lhs), direction(of: rhs)))
    return directionSimilarity >= 0.72 && midDistance <= maxDistanceMeters
  }

  private func collapseDuplicatePassages(
    in geo: inout FloorplanSegmentsFile,
    scanId: UUID,
    kind: PassageKind,
    keeping keptIndex: Int,
    maxDistanceMeters: Double = 0.28
  ) -> (changed: Bool, keptIndex: Int) {
    switch kind {
    case .door:
      guard var doors = geo.doors, doors.indices.contains(keptIndex) else {
        return (false, keptIndex)
      }
      let anchor = doors[keptIndex]
      let duplicateIndices = doors.indices
        .filter { $0 != keptIndex && areDuplicatePassages(doors[$0], anchor, maxDistanceMeters: maxDistanceMeters) }
        .sorted(by: >)
      guard !duplicateIndices.isEmpty else { return (false, keptIndex) }

      var adjustedKeptIndex = keptIndex
      var overrides = normalizedDoorSwingOverrides(for: doors.count, existing: geo.doorSwingOverrides)
      for index in duplicateIndices {
        doors.remove(at: index)
        if overrides.indices.contains(index) {
          overrides.remove(at: index)
        }
        adjustConnectionsAfterPassageRemoval(scanId: scanId, kind: .door, removedIndex: index)
        if index < adjustedKeptIndex {
          adjustedKeptIndex -= 1
        }
      }
      geo.doors = doors.isEmpty ? nil : doors
      geo.doorSwingOverrides = overrides.isEmpty ? nil : overrides
      return (true, adjustedKeptIndex)

    case .opening:
      guard var openings = geo.openings, openings.indices.contains(keptIndex) else {
        return (false, keptIndex)
      }
      let anchor = openings[keptIndex]
      let duplicateIndices = openings.indices
        .filter { $0 != keptIndex && areDuplicatePassages(openings[$0], anchor, maxDistanceMeters: maxDistanceMeters) }
        .sorted(by: >)
      guard !duplicateIndices.isEmpty else { return (false, keptIndex) }

      var adjustedKeptIndex = keptIndex
      for index in duplicateIndices {
        openings.remove(at: index)
        adjustConnectionsAfterPassageRemoval(scanId: scanId, kind: .opening, removedIndex: index)
        if index < adjustedKeptIndex {
          adjustedKeptIndex -= 1
        }
      }
      geo.openings = openings.isEmpty ? nil : openings
      return (true, adjustedKeptIndex)

    case .window:
      return (false, keptIndex)
    }
  }

  private func removeFeature(
    _ feature: DetectedPassageRemoval,
    from geo: inout FloorplanSegmentsFile,
    scanId: UUID
  ) -> FloorplanSegment? {
    switch feature {
    case .door(let index):
      var doors = geo.doors ?? []
      guard doors.indices.contains(index) else { return nil }
      let segment = doors.remove(at: index)
      if var overrides = geo.doorSwingOverrides, overrides.indices.contains(index) {
        overrides.remove(at: index)
        geo.doorSwingOverrides = overrides.isEmpty ? nil : overrides
      }
      adjustConnectionsAfterPassageRemoval(scanId: scanId, kind: .door, removedIndex: index)
      geo.doors = doors.isEmpty ? nil : doors
      return segment
    case .opening(let index):
      guard var openings = geo.openings, openings.indices.contains(index) else { return nil }
      let segment = openings.remove(at: index)
      adjustConnectionsAfterPassageRemoval(scanId: scanId, kind: .opening, removedIndex: index)
      geo.openings = openings.isEmpty ? nil : openings
      return segment
    case .window(let index):
      var windows = geo.windows ?? []
      guard windows.indices.contains(index) else { return nil }
      let segment = windows.remove(at: index)
      geo.windows = windows.isEmpty ? nil : windows
      return segment
    }
  }

  private func addPassageOnNearestWall(
    world pWorld: DPoint,
    scanId: UUID,
    kind: PassageKind,
    maxHitDistanceMeters: Double = 0.35
  ) -> PassageEditResult? {
    guard var geo = geometryByScanId[scanId] else { return nil }
    guard let scan = project.roomScans.first(where: { $0.id == scanId }) else { return nil }
    guard !geo.segments.isEmpty else { return nil }

    let pLocal = toLocal(pWorld, t: scan.transform)

    var best: (seg: FloorplanSegment, t: Double, dist: Double)? = nil
    for wall in geo.segments {
      let res = pointSegmentDistance(p: pLocal, seg: wall)
      if best == nil || res.dist < best!.dist {
        best = (wall, res.t, res.dist)
      }
    }
    guard let best else { return nil }
    guard best.dist <= maxHitDistanceMeters else { return nil }

    let ax = best.seg.ax
    let ay = best.seg.ay
    let bx = best.seg.bx
    let by = best.seg.by
    let vx = bx - ax
    let vy = by - ay
    let length = (vx * vx + vy * vy).squareRoot()
    guard length >= 0.4 else { return nil }

    let ux = vx / length
    let uy = vy / length
    var half = (kind == .door) ? doorDefaultHalfWidthMeters : openingDefaultHalfWidthMeters
    half = min(half, max(0.12, length * 0.5 - 0.05))
    guard half >= 0.12 else { return nil }

    let marginT = min(0.49, (half + 0.05) / length)
    let t = min(max(best.t, marginT), 1.0 - marginT)
    let cx = ax + vx * t
    let cy = ay + vy * t

    let da = DPoint(x: cx - ux * half, y: cy - uy * half)
    let db = DPoint(x: cx + ux * half, y: cy + uy * half)

    let newSegment = FloorplanSegment(ax: da.x, ay: da.y, bx: db.x, by: db.y)

    if let duplicate = nearestDuplicateFeature(in: geo, to: newSegment, maxDistanceMeters: 0.28) {
      switch (duplicate.match, kind) {
      case (.door(let index), .door):
        let collapsed = collapseDuplicatePassages(in: &geo, scanId: scanId, kind: .door, keeping: index)
        geometryByScanId[scanId] = geo
        if collapsed.changed {
          persistGeometry(scanId: scanId, geo: geo)
        }
        let selection = DoorSelection(scanId: scanId, kind: .door, index: collapsed.keptIndex)
        return PassageEditResult(
          message: collapsed.changed ? "Tür ausgewählt, Duplikat bereinigt." : "Tür ausgewählt.",
          selection: selection,
          changed: collapsed.changed
        )
      case (.opening(let index), .opening):
        let collapsed = collapseDuplicatePassages(in: &geo, scanId: scanId, kind: .opening, keeping: index)
        geometryByScanId[scanId] = geo
        if collapsed.changed {
          persistGeometry(scanId: scanId, geo: geo)
        }
        let selection = DoorSelection(scanId: scanId, kind: .opening, index: collapsed.keptIndex)
        return PassageEditResult(
          message: collapsed.changed ? "Durchgang ausgewählt, Duplikat bereinigt." : "Durchgang ausgewählt.",
          selection: selection,
          changed: collapsed.changed
        )
      default:
        _ = removeFeature(duplicate.match, from: &geo, scanId: scanId)
      }
    }

    var passages = (kind == .door) ? (geo.doors ?? []) : (geo.openings ?? [])
    let newIndex = passages.count
    passages.append(newSegment)
    if kind == .door {
      geo.doors = passages
    } else {
      geo.openings = passages
    }
    geometryByScanId[scanId] = geo
    persistGeometry(scanId: scanId, geo: geo)
    let selection = DoorSelection(scanId: scanId, kind: kind, index: newIndex)
    return PassageEditResult(
      message: kind == .door ? "Tür hinzugefügt." : "Durchgang hinzugefügt.",
      selection: selection,
      changed: true
    )
  }

  private func addWindowOnNearestWall(
    world pWorld: DPoint,
    scanId: UUID,
    maxHitDistanceMeters: Double = 0.35
  ) -> Bool {
    guard var geo = geometryByScanId[scanId] else { return false }
    guard let scan = project.roomScans.first(where: { $0.id == scanId }) else { return false }
    guard !geo.segments.isEmpty else { return false }

    let pLocal = toLocal(pWorld, t: scan.transform)

    var best: (seg: FloorplanSegment, t: Double, dist: Double)? = nil
    for wall in geo.segments {
      let res = pointSegmentDistance(p: pLocal, seg: wall)
      if best == nil || res.dist < best!.dist {
        best = (wall, res.t, res.dist)
      }
    }
    guard let best, best.dist <= maxHitDistanceMeters else { return false }

    let ax = best.seg.ax
    let ay = best.seg.ay
    let bx = best.seg.bx
    let by = best.seg.by
    let vx = bx - ax
    let vy = by - ay
    let length = (vx * vx + vy * vy).squareRoot()
    guard length >= 0.4 else { return false }

    let ux = vx / length
    let uy = vy / length
    var half = 0.55
    half = min(half, max(0.12, length * 0.5 - 0.05))
    guard half >= 0.12 else { return false }

    let marginT = min(0.49, (half + 0.05) / length)
    let t = min(max(best.t, marginT), 1.0 - marginT)
    let cx = ax + vx * t
    let cy = ay + vy * t

    let da = DPoint(x: cx - ux * half, y: cy - uy * half)
    let db = DPoint(x: cx + ux * half, y: cy + uy * half)
    let newSegment = FloorplanSegment(ax: da.x, ay: da.y, bx: db.x, by: db.y)
    let newMid = DPoint(x: (newSegment.ax + newSegment.bx) * 0.5, y: (newSegment.ay + newSegment.by) * 0.5)

    var windows = geo.windows ?? []
    for existing in windows {
      let em = DPoint(x: (existing.ax + existing.bx) * 0.5, y: (existing.ay + existing.by) * 0.5)
      if distance(newMid, em) <= 0.2 { return false }
    }

    windows.append(newSegment)
    geo.windows = windows
    geometryByScanId[scanId] = geo
    persistGeometry(scanId: scanId, geo: geo)
    return true
  }

  private func persistGeometry(scanId: UUID, geo: FloorplanSegmentsFile) {
    guard let scan = project.roomScans.first(where: { $0.id == scanId }) else { return }
    guard let url = try? FloorplanProjectStore.resolve(projectKey: projectKey, relativePath: scan.segmentsJSONPath) else { return }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(geo) else { return }
    try? data.write(to: url, options: [.atomic])
    pruneInvalidConnectionsIfNeeded()
  }

  private func recomputeRouteOverlay() {
    guard showRouteOverlay else {
      routePointsWorld = []
      return
    }
    switch routeMode {
    case .manual:
      routePointsWorld = project.routePoints.map { DPoint(x: $0.x, y: $0.y) }
    case .suggested:
      routePointsWorld = computeSuggestedRoutePointsWorld()
    }
  }

  private func computeSuggestedRoutePointsWorld() -> [DPoint] {
    // Build world geometry
    var worldWallsById: [UUID: [FloorplanSegment]] = [:]
    var worldPassagesById: [UUID: [FloorplanSegment]] = [:]
    var centroidById: [UUID: DPoint] = [:]

    for scan in project.roomScans {
      guard let geo = geometryByScanId[scan.id], !geo.segments.isEmpty else { continue }
      let worldWalls = transform(segments: geo.segments, t: scan.transform)
      worldWallsById[scan.id] = worldWalls

      var passages: [FloorplanSegment] = []
      if let doors = geo.doors {
        passages.append(contentsOf: transform(segments: doors, t: scan.transform))
      }
      if let openings = geo.openings {
        passages.append(contentsOf: transform(segments: openings, t: scan.transform))
      }
      worldPassagesById[scan.id] = passages

      centroidById[scan.id] = centroidWorld(from: worldWalls) ?? boundsCenterWorld(scan: scan) ?? DPoint(x: 0, y: 0)
    }

    let passageCount = worldPassagesById.values.reduce(0) { $0 + $1.count }
    guard passageCount > 0 else { return [] }

    struct PairKey: Hashable {
      let a: UUID
      let b: UUID
      init(_ u: UUID, _ v: UUID) {
        if u.uuidString < v.uuidString {
          self.a = u
          self.b = v
        } else {
          self.a = v
          self.b = u
        }
      }
    }

    var doorPointByPair: [PairKey: DPoint] = [:]
    var adjacency: [UUID: Set<UUID>] = [:]
    let usableConnections = validConnections()
    if !usableConnections.isEmpty {
      func segmentWorld(for ref: FloorplanPassageRef) -> FloorplanSegment? {
        guard let scan = project.roomScans.first(where: { $0.id == ref.scanId }) else { return nil }
        guard let geo = geometryByScanId[ref.scanId] else { return nil }
        let segLocal: FloorplanSegment?
        switch ref.kind {
        case .door:
          segLocal = geo.doors?.indices.contains(ref.index) == true ? geo.doors?[ref.index] : nil
        case .opening:
          segLocal = geo.openings?.indices.contains(ref.index) == true ? geo.openings?[ref.index] : nil
        }
        guard let segLocal else { return nil }
        return transform(segments: [segLocal], t: scan.transform).first
      }

      for conn in usableConnections {
        guard let sa = segmentWorld(for: conn.a),
              let sb = segmentWorld(for: conn.b) else { continue }
        let midA = DPoint(x: (sa.ax + sa.bx) * 0.5, y: (sa.ay + sa.by) * 0.5)
        let midB = DPoint(x: (sb.ax + sb.bx) * 0.5, y: (sb.ay + sb.by) * 0.5)
        let mid = DPoint(x: (midA.x + midB.x) * 0.5, y: (midA.y + midB.y) * 0.5)

        let key = PairKey(conn.a.scanId, conn.b.scanId)
        doorPointByPair[key] = mid
        adjacency[conn.a.scanId, default: []].insert(conn.b.scanId)
        adjacency[conn.b.scanId, default: []].insert(conn.a.scanId)
      }
    } else {
      // Fallback heuristic: infer adjacency by proximity between passages and neighboring room walls.
      let neighborThreshold = 0.25
      let dotThreshold = 0.6

      for (scanId, passages) in worldPassagesById {
        for doorSeg in passages {
          let mid = DPoint(x: (doorSeg.ax + doorSeg.bx) * 0.5, y: (doorSeg.ay + doorSeg.by) * 0.5)
          let doorDir = normalized(DPoint(x: doorSeg.bx - doorSeg.ax, y: doorSeg.by - doorSeg.ay))

          var bestOther: (id: UUID, dist: Double, dot: Double)? = nil
          for (otherId, walls) in worldWallsById where otherId != scanId {
            var minDist = Double.greatestFiniteMagnitude
            var bestWallDir = DPoint(x: 1, y: 0)
            for wall in walls {
              let res = pointSegmentDistance(p: mid, seg: wall)
              if res.dist < minDist {
                minDist = res.dist
                bestWallDir = normalized(DPoint(x: wall.bx - wall.ax, y: wall.by - wall.ay))
              }
            }
            let dotVal = abs(dot(doorDir, bestWallDir))
            if bestOther == nil || minDist < bestOther!.dist {
              bestOther = (otherId, minDist, dotVal)
            }
          }

          guard let bestOther,
                bestOther.dist <= neighborThreshold,
                bestOther.dot >= dotThreshold else { continue }

          let key = PairKey(scanId, bestOther.id)
          if doorPointByPair[key] == nil {
            doorPointByPair[key] = mid
          }
          adjacency[scanId, default: []].insert(bestOther.id)
          adjacency[bestOther.id, default: []].insert(scanId)
        }
      }
    }

    guard !adjacency.isEmpty else { return [] }

    func degree(_ id: UUID) -> Int { adjacency[id]?.count ?? 0 }

    // Choose start room: hallway/corridor/stairs preferred.
    let preferredRoomIds = ["hallway", "corridor", "stairs"]
    var startId: UUID? = nil
    for roomId in preferredRoomIds {
      let candidates = project.roomScans.filter { $0.roomId == roomId && degree($0.id) > 0 }
      if let best = candidates.max(by: { degree($0.id) < degree($1.id) }) {
        startId = best.id
        break
      }
    }
    if startId == nil {
      startId = adjacency.keys.max(by: { degree($0) < degree($1) })
    }
    guard let startId, let startPoint = centroidById[startId] else { return [] }

    func neighborSortKey(_ id: UUID) -> String {
      let roomId = project.roomScans.first(where: { $0.id == id })?.roomId ?? RoomTaxonomy.defaultRoomId
      return RoomTaxonomy.room(id: roomId).displayName
    }

    var visited: Set<UUID> = []
    var points: [DPoint] = [startPoint]

    func walk(_ u: UUID) {
      visited.insert(u)
      let neighbors = (adjacency[u] ?? []).sorted(by: { neighborSortKey($0) < neighborSortKey($1) })
      for v in neighbors where !visited.contains(v) {
        let pair = PairKey(u, v)
        let door = doorPointByPair[pair] ?? DPoint(
          x: ((centroidById[u]?.x ?? 0) + (centroidById[v]?.x ?? 0)) * 0.5,
          y: ((centroidById[u]?.y ?? 0) + (centroidById[v]?.y ?? 0)) * 0.5
        )
        if let cv = centroidById[v], let cu = centroidById[u] {
          points.append(door)
          points.append(cv)
          walk(v)
          points.append(door)
          points.append(cu)
        }
      }
    }

    walk(startId)
    return points
  }

  private func centroidWorld(from segments: [FloorplanSegment]) -> DPoint? {
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

  private func boundsCenterWorld(scan: FloorplanRoomScan) -> DPoint? {
    guard let bounds = roomBoundsMeters(scan: scan) else { return nil }
    return DPoint(x: (bounds.minX + bounds.maxX) * 0.5, y: (bounds.minY + bounds.maxY) * 0.5)
  }

  private func boundaryPoint(on bounds: Bounds, from center: DPoint, toward target: DPoint) -> DPoint {
    let vx = target.x - center.x
    let vy = target.y - center.y
    guard abs(vx) > 1e-9 || abs(vy) > 1e-9 else { return center }

    var bestT = Double.greatestFiniteMagnitude
    var best = center

    func consider(t: Double, x: Double, y: Double) {
      guard t > 0 else { return }
      guard x >= bounds.minX - 1e-6, x <= bounds.maxX + 1e-6,
            y >= bounds.minY - 1e-6, y <= bounds.maxY + 1e-6 else { return }
      if t < bestT {
        bestT = t
        best = DPoint(
          x: min(max(x, bounds.minX), bounds.maxX),
          y: min(max(y, bounds.minY), bounds.maxY)
        )
      }
    }

    if abs(vx) > 1e-9 {
      let tMinX = (bounds.minX - center.x) / vx
      consider(t: tMinX, x: bounds.minX, y: center.y + vy * tMinX)
      let tMaxX = (bounds.maxX - center.x) / vx
      consider(t: tMaxX, x: bounds.maxX, y: center.y + vy * tMaxX)
    }
    if abs(vy) > 1e-9 {
      let tMinY = (bounds.minY - center.y) / vy
      consider(t: tMinY, x: center.x + vx * tMinY, y: bounds.minY)
      let tMaxY = (bounds.maxY - center.y) / vy
      consider(t: tMaxY, x: center.x + vx * tMaxY, y: bounds.maxY)
    }

    if bestT.isFinite {
      return best
    }

    return DPoint(
      x: min(max(center.x, bounds.minX), bounds.maxX),
      y: min(max(center.y, bounds.minY), bounds.maxY)
    )
  }

  private func roomCenterWorld(scanId: UUID) -> DPoint? {
    guard let scan = project.roomScans.first(where: { $0.id == scanId }) else { return nil }
    return boundsCenterWorld(scan: scan)
  }

  private func toLocal(_ pWorld: DPoint, t: FloorplanRoomTransform) -> DPoint {
    let dx = pWorld.x - t.translationX
    let dy = pWorld.y - t.translationY
    let cosR = cos(t.rotationRadians)
    let sinR = sin(t.rotationRadians)
    // inverse rotation (transpose)
    return DPoint(
      x: dx * cosR + dy * sinR,
      y: -dx * sinR + dy * cosR
    )
  }

  private func screenPointToWorld(_ point: CGPoint, scale: CGFloat, origin: CGPoint) -> DPoint {
    DPoint(
      x: Double((point.x - origin.x) / scale),
      y: Double((origin.y - point.y) / scale)
    )
  }

  private func worldDeltaToLocal(_ delta: DPoint, rotationRadians: Double) -> DPoint {
    let cosR = cos(rotationRadians)
    let sinR = sin(rotationRadians)
    return DPoint(
      x: delta.x * cosR + delta.y * sinR,
      y: -delta.x * sinR + delta.y * cosR
    )
  }

  private func pointSegmentDistance(p: DPoint, seg: FloorplanSegment) -> (dist: Double, t: Double) {
    let ax = seg.ax
    let ay = seg.ay
    let bx = seg.bx
    let by = seg.by
    let vx = bx - ax
    let vy = by - ay
    let wx = p.x - ax
    let wy = p.y - ay
    let vv = vx * vx + vy * vy
    if vv <= 1e-9 {
      let d = ((p.x - ax) * (p.x - ax) + (p.y - ay) * (p.y - ay)).squareRoot()
      return (d, 0)
    }
    var t = (wx * vx + wy * vy) / vv
    t = min(max(t, 0), 1)
    let cx = ax + vx * t
    let cy = ay + vy * t
    let dx = p.x - cx
    let dy = p.y - cy
    let dist = (dx * dx + dy * dy).squareRoot()
    return (dist, t)
  }

  private func dot(_ a: DPoint, _ b: DPoint) -> Double {
    a.x * b.x + a.y * b.y
  }

  private func normalized(_ v: DPoint) -> DPoint {
    let len = (v.x * v.x + v.y * v.y).squareRoot()
    guard len > 1e-9 else { return DPoint(x: 1, y: 0) }
    return DPoint(x: v.x / len, y: v.y / len)
  }

  private func distance(_ a: DPoint, _ b: DPoint) -> Double {
    let dx = a.x - b.x
    let dy = a.y - b.y
    return (dx * dx + dy * dy).squareRoot()
  }

  private func applyRotation(at roomIndex: Int, rotationRadians: Double, pivotLocal: DPoint, pivotWorld: DPoint) {
    let r = normalizeAngle(rotationRadians)
    let rotatedPivotLocal = rotatePoint(pivotLocal, radians: r)
    project.roomScans[roomIndex].transform.rotationRadians = r
    project.roomScans[roomIndex].transform.translationX = pivotWorld.x - rotatedPivotLocal.x
    project.roomScans[roomIndex].transform.translationY = pivotWorld.y - rotatedPivotLocal.y
  }

  private func rotateSelected(by radians: Double) {
    guard let selectedScanId,
          let idx = project.roomScans.firstIndex(where: { $0.id == selectedScanId }) else { return }
    if let pivotLocal = roomPivotLocal(scanId: selectedScanId) {
      let current = project.roomScans[idx].transform
      let pivotWorld = mapLocalPointToWorld(pivotLocal, t: current)
      applyRotation(at: idx, rotationRadians: current.rotationRadians + radians, pivotLocal: pivotLocal, pivotWorld: pivotWorld)
    } else {
      project.roomScans[idx].transform.rotationRadians = normalizeAngle(project.roomScans[idx].transform.rotationRadians + radians)
    }
    pendingRotationSnapId = selectedScanId
    snapRotationIfNeeded(force: true)
    try? FloorplanProjectStore.save(project: project)
    if showRouteOverlay {
      recomputeRouteOverlay()
    }
  }

  private func snapRotationIfNeeded(force: Bool = false) {
    guard let selectedId = pendingRotationSnapId,
          let idx = project.roomScans.firstIndex(where: { $0.id == selectedId }) else { return }
    defer { pendingRotationSnapId = nil }

    let step = Double.pi / 2
    let current = normalizeAngle(project.roomScans[idx].transform.rotationRadians)
    let nearest = (current / step).rounded() * step
    let diff = abs(current - nearest)

    if force || diff <= (8.0 * Double.pi / 180.0) {
      if let pivotLocal = roomPivotLocal(scanId: selectedId) {
        let currentT = project.roomScans[idx].transform
        let pivotWorld = mapLocalPointToWorld(pivotLocal, t: currentT)
        applyRotation(at: idx, rotationRadians: nearest, pivotLocal: pivotLocal, pivotWorld: pivotWorld)
      } else {
        project.roomScans[idx].transform.rotationRadians = normalizeAngle(nearest)
      }
    }
  }

  private func normalizeAngle(_ value: Double) -> Double {
    var v = value
    while v > Double.pi { v -= 2 * Double.pi }
    while v < -Double.pi { v += 2 * Double.pi }
    return v
  }

  private func snapRoomIfNeeded(scanId: UUID) {
    guard let idx = project.roomScans.firstIndex(where: { $0.id == scanId }) else { return }

    // Keep manual links stable: drag snapping only adjusts position and does not change connections.
    if snapRoomByDoorsIfNeeded(scanId: scanId) != nil {
      return
    }

    guard let movingBounds = roomBoundsMeters(scan: project.roomScans[idx]) else { return }

    var bestCandidate: (dx: Double, dy: Double, score: Double)? = nil

    for other in project.roomScans where other.id != scanId {
      guard let otherBounds = roomBoundsMeters(scan: other) else { continue }

      // Horizontal adjacency (left/right)
      let dxCandidates: [Double] = [
        otherBounds.minX - movingBounds.maxX, // move right to touch
        otherBounds.maxX - movingBounds.minX  // move left to touch
      ]
      let yAlignCandidates: [Double] = [
        otherBounds.minY - movingBounds.minY,
        otherBounds.maxY - movingBounds.maxY,
        ((otherBounds.minY + otherBounds.maxY) * 0.5) - ((movingBounds.minY + movingBounds.maxY) * 0.5)
      ]

      for dx in dxCandidates where abs(dx) <= snapThresholdMeters {
        let dy = yAlignCandidates.min(by: { abs($0) < abs($1) }) ?? 0
        guard abs(dy) <= snapThresholdMeters else { continue }
        let score = abs(dx) + abs(dy)
        if bestCandidate == nil || score < bestCandidate!.score {
          bestCandidate = (dx, dy, score)
        }
      }

      // Vertical adjacency (up/down)
      let dyCandidates: [Double] = [
        otherBounds.minY - movingBounds.maxY, // move up to touch
        otherBounds.maxY - movingBounds.minY  // move down to touch
      ]
      let xAlignCandidates: [Double] = [
        otherBounds.minX - movingBounds.minX,
        otherBounds.maxX - movingBounds.maxX,
        ((otherBounds.minX + otherBounds.maxX) * 0.5) - ((movingBounds.minX + movingBounds.maxX) * 0.5)
      ]

      for dy in dyCandidates where abs(dy) <= snapThresholdMeters {
        let dx = xAlignCandidates.min(by: { abs($0) < abs($1) }) ?? 0
        guard abs(dx) <= snapThresholdMeters else { continue }
        let score = abs(dx) + abs(dy)
        if bestCandidate == nil || score < bestCandidate!.score {
          bestCandidate = (dx, dy, score)
        }
      }
    }

    guard let bestCandidate else { return }
    project.roomScans[idx].transform.translationX += bestCandidate.dx
    project.roomScans[idx].transform.translationY += bestCandidate.dy
    pruneInvalidConnectionsIfNeeded(persist: false)
  }

  private func snapRoomByDoorsIfNeeded(scanId: UUID) -> DoorDockPreview? {
    guard let idx = project.roomScans.firstIndex(where: { $0.id == scanId }) else { return nil }
    guard let preview = computeBestDoorDockPreview(movingScanId: scanId, maxDistanceMeters: doorDockThresholdMeters) else { return nil }
    project.roomScans[idx].transform = preview.targetTransform
    pruneInvalidConnectionsIfNeeded(persist: false)
    return preview
  }

  private func computeBestDoorDockPreview(movingScanId: UUID, maxDistanceMeters: Double) -> DoorDockPreview? {
    guard let movingGeo = geometryByScanId[movingScanId] else { return nil }
    guard let movingScan = project.roomScans.first(where: { $0.id == movingScanId }) else { return nil }
    let movingPassages = passagesLocal(scanId: movingScanId)
    guard !movingPassages.isEmpty else { return nil }
    let movingCentroidLocal = centroidLocal(from: movingGeo.segments)

    var best: DoorDockPreview? = nil
    var bestScore = Double.greatestFiniteMagnitude

    for other in project.roomScans where other.id != movingScanId && other.floorId == movingScan.floorId {
      guard let otherGeo = geometryByScanId[other.id] else { continue }
      let otherPassages = passagesLocal(scanId: other.id)
      guard !otherPassages.isEmpty else { continue }
      let otherCentroidLocal = centroidLocal(from: otherGeo.segments)
      let otherCentroidWorld = otherCentroidLocal.map { mapLocalPointToWorld($0, t: other.transform) }
      let otherBoundsWorld = boundsWorld(segmentsLocal: otherGeo.segments, t: other.transform)

      for mPassage in movingPassages {
        let mDoor = mPassage.segLocal
        let mMidWorld = mapLocalPointToWorld(midpoint(of: mDoor), t: movingScan.transform)
        let mThetaLocal = angle(of: direction(of: mDoor))
        let mThetaWorld = normalizeAngle(movingScan.transform.rotationRadians + mThetaLocal)
        let mWidth = segmentLength(mDoor)

        for oPassage in otherPassages {
          let oDoor = oPassage.segLocal
          let oMidWorld = mapLocalPointToWorld(midpoint(of: oDoor), t: other.transform)
          let dist = distance(mMidWorld, oMidWorld)
          guard dist <= maxDistanceMeters else { continue }

          let oThetaLocal = angle(of: direction(of: oDoor))
          let oThetaWorld = normalizeAngle(other.transform.rotationRadians + oThetaLocal)
          let oWidth = segmentLength(oDoor)
          guard FloorplanAutoDockService.passageWidthsLookCompatible(
            kindA: floorplanPassageKind(mPassage.selection.kind),
            lenA: mWidth,
            kindB: floorplanPassageKind(oPassage.selection.kind),
            lenB: oWidth
          ) else { continue }

          let diffA = normalizeAngle(oThetaWorld - mThetaWorld)
          let diffB = normalizeAngle((oThetaWorld + Double.pi) - mThetaWorld)
          let rotationDelta = abs(diffA) <= abs(diffB) ? diffA : diffB
          guard abs(rotationDelta) <= doorDockMaxRotationRadians else { continue }

          let targetRotation = normalizeAngle(movingScan.transform.rotationRadians + rotationDelta)

          let mMidLocal = midpoint(of: mDoor)
          let rotated = rotatePoint(mMidLocal, radians: targetRotation)
          let targetTx = oMidWorld.x - rotated.x
          let targetTy = oMidWorld.y - rotated.y
          let targetTransform = FloorplanRoomTransform(translationX: targetTx, translationY: targetTy, rotationRadians: targetRotation)
          let otherDoorWorld = transform(segments: [oDoor], t: other.transform)[0]
          let otherDoorDirection = direction(of: otherDoorWorld)

          var score = dist + abs(rotationDelta) * 0.15
          score += abs(mWidth - oWidth) * 0.9
          if mPassage.selection.kind != oPassage.selection.kind {
            score += max(mWidth, oWidth) >= 1.10 ? 2.1 : 1.1
          } else if mPassage.selection.kind == .opening {
            score -= min(0.18, min(mWidth, oWidth) * 0.08)
          }
          if let movingCentroidLocal, let otherCentroidWorld {
            let movingCentroidWorld = mapLocalPointToWorld(movingCentroidLocal, t: targetTransform)
            let vOther = DPoint(x: otherCentroidWorld.x - oMidWorld.x, y: otherCentroidWorld.y - oMidWorld.y)
            let vMoving = DPoint(x: movingCentroidWorld.x - oMidWorld.x, y: movingCentroidWorld.y - oMidWorld.y)
            let crossOther = cross(otherDoorDirection, vOther)
            let crossMoving = cross(otherDoorDirection, vMoving)
            let oppositeSides = (crossOther == 0 || crossMoving == 0) ? false : (crossOther * crossMoving) < 0
            let leakRatio = sameSideLeakRatio(
              segmentsLocal: movingGeo.segments,
              t: targetTransform,
              linePoint: oMidWorld,
              lineDirection: otherDoorDirection,
              referenceCrossSign: crossOther
            )
            let lateralOffset = abs(dot(otherDoorDirection, vMoving) - dot(otherDoorDirection, vOther))
            score += oppositeSides ? 0.0 : 20.0
            score += leakRatio * 42.0
            score += max(0.0, lateralOffset - 1.0) * 4.5
          }
          if let otherBoundsWorld,
             let movingBoundsWorld = boundsWorld(segmentsLocal: movingGeo.segments, t: targetTransform) {
            let overlapRatio = boundsOverlapRatio(a: otherBoundsWorld, b: movingBoundsWorld)
            score += overlapRatio * 20.0
            if overlapRatio > 0.14 {
              score += 14.0
            }
          }
          guard score < bestScore else { continue }

          let movingDoorWorld = transform(segments: [mDoor], t: targetTransform)[0]

          bestScore = score
          best = DoorDockPreview(
            movingScanId: movingScanId,
            otherScanId: other.id,
            movingDoorWorld: movingDoorWorld,
            otherDoorWorld: otherDoorWorld,
            targetTransform: targetTransform
          )
        }
      }
    }

    return best
  }

  private func midpoint(of seg: FloorplanSegment) -> DPoint {
    DPoint(x: (seg.ax + seg.bx) * 0.5, y: (seg.ay + seg.by) * 0.5)
  }

  private func direction(of seg: FloorplanSegment) -> DPoint {
    normalized(DPoint(x: seg.bx - seg.ax, y: seg.by - seg.ay))
  }

  private func angle(of v: DPoint) -> Double {
    atan2(v.y, v.x)
  }

  private func rotatePoint(_ p: DPoint, radians: Double) -> DPoint {
    let cosR = cos(radians)
    let sinR = sin(radians)
    return DPoint(x: p.x * cosR - p.y * sinR, y: p.x * sinR + p.y * cosR)
  }

  private func mapLocalPointToWorld(_ p: DPoint, t: FloorplanRoomTransform) -> DPoint {
    let rotated = rotatePoint(p, radians: t.rotationRadians)
    return DPoint(x: rotated.x + t.translationX, y: rotated.y + t.translationY)
  }

  private struct DPoint: Hashable {
    var x: Double
    var y: Double
  }

  private struct Bounds {
    let minX: Double
    let minY: Double
    let maxX: Double
    let maxY: Double
  }

  private func roomBoundsMeters(scan: FloorplanRoomScan) -> Bounds? {
    guard let geo = geometryByScanId[scan.id], !geo.segments.isEmpty else { return nil }
    var minX = Double.greatestFiniteMagnitude
    var minY = Double.greatestFiniteMagnitude
    var maxX = -Double.greatestFiniteMagnitude
    var maxY = -Double.greatestFiniteMagnitude
    for seg in transform(segments: geo.segments, t: scan.transform) {
      minX = min(minX, seg.ax, seg.bx)
      minY = min(minY, seg.ay, seg.by)
      maxX = max(maxX, seg.ax, seg.bx)
      maxY = max(maxY, seg.ay, seg.by)
    }
    guard minX.isFinite, minY.isFinite, maxX.isFinite, maxY.isFinite else { return nil }
    return Bounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
  }

  private func centroidLocal(from segments: [FloorplanSegment]) -> DPoint? {
    guard !segments.isEmpty else { return nil }
    var sumX = 0.0
    var sumY = 0.0
    var count = 0.0
    for segment in segments {
      sumX += segment.ax + segment.bx
      sumY += segment.ay + segment.by
      count += 2.0
    }
    guard count > 0 else { return nil }
    return DPoint(x: sumX / count, y: sumY / count)
  }

  private func boundsWorld(segmentsLocal: [FloorplanSegment], t: FloorplanRoomTransform) -> Bounds? {
    var minX = Double.greatestFiniteMagnitude
    var minY = Double.greatestFiniteMagnitude
    var maxX = -Double.greatestFiniteMagnitude
    var maxY = -Double.greatestFiniteMagnitude
    for segment in segmentsLocal {
      let world = transform(segments: [segment], t: t)[0]
      minX = min(minX, world.ax, world.bx)
      minY = min(minY, world.ay, world.by)
      maxX = max(maxX, world.ax, world.bx)
      maxY = max(maxY, world.ay, world.by)
    }
    guard minX.isFinite, minY.isFinite, maxX.isFinite, maxY.isFinite else { return nil }
    return Bounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
  }

  private func boundsOverlapRatio(a: Bounds, b: Bounds) -> Double {
    let ix = max(0.0, min(a.maxX, b.maxX) - max(a.minX, b.minX))
    let iy = max(0.0, min(a.maxY, b.maxY) - max(a.minY, b.minY))
    let inter = ix * iy
    let areaA = max(0.0, (a.maxX - a.minX) * (a.maxY - a.minY))
    let areaB = max(0.0, (b.maxX - b.minX) * (b.maxY - b.minY))
    let denom = max(0.001, min(areaA, areaB))
    return inter / denom
  }

  private func sameSideLeakRatio(
    segmentsLocal: [FloorplanSegment],
    t: FloorplanRoomTransform,
    linePoint: DPoint,
    lineDirection: DPoint,
    referenceCrossSign: Double
  ) -> Double {
    guard !segmentsLocal.isEmpty, referenceCrossSign != 0 else { return 0 }

    var totalPoints = 0.0
    var wrongPoints = 0.0

    for segment in segmentsLocal {
      let world = transform(segments: [segment], t: t)[0]
      let points = [
        DPoint(x: world.ax, y: world.ay),
        DPoint(x: world.bx, y: world.by)
      ]
      for point in points {
        totalPoints += 1
        let vector = DPoint(x: point.x - linePoint.x, y: point.y - linePoint.y)
        let sign = cross(lineDirection, vector)
        if sign == 0 { continue }
        if sign * referenceCrossSign > 0 {
          wrongPoints += 1
        }
      }
    }

    guard totalPoints > 0 else { return 0 }
    return wrongPoints / totalPoints
  }

  private func roomBoundsLocalMeters(scanId: UUID) -> Bounds? {
    guard let geo = geometryByScanId[scanId], !geo.segments.isEmpty else { return nil }
    var minX = Double.greatestFiniteMagnitude
    var minY = Double.greatestFiniteMagnitude
    var maxX = -Double.greatestFiniteMagnitude
    var maxY = -Double.greatestFiniteMagnitude
    for seg in geo.segments {
      minX = min(minX, seg.ax, seg.bx)
      minY = min(minY, seg.ay, seg.by)
      maxX = max(maxX, seg.ax, seg.bx)
      maxY = max(maxY, seg.ay, seg.by)
    }
    guard minX.isFinite, minY.isFinite, maxX.isFinite, maxY.isFinite else { return nil }
    return Bounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
  }

  private func roomLayoutFootprint(
    scanId: UUID,
    fallbackWidth: Double,
    fallbackDepth: Double
  ) -> (width: Double, depth: Double, localCenter: DPoint) {
    guard let bounds = roomBoundsLocalMeters(scanId: scanId) else {
      return (
        width: max(0.9, fallbackWidth),
        depth: max(0.9, fallbackDepth),
        localCenter: DPoint(x: 0, y: 0)
      )
    }
    return (
      width: max(0.9, bounds.maxX - bounds.minX),
      depth: max(0.9, bounds.maxY - bounds.minY),
      localCenter: DPoint(
        x: (bounds.minX + bounds.maxX) * 0.5,
        y: (bounds.minY + bounds.maxY) * 0.5
      )
    )
  }

  private func roomPivotLocal(scanId: UUID) -> DPoint? {
    guard let b = roomBoundsLocalMeters(scanId: scanId) else { return nil }
    return DPoint(x: (b.minX + b.maxX) * 0.5, y: (b.minY + b.maxY) * 0.5)
  }

  private func roomBoundsPx(scanId: UUID, scale: CGFloat, origin: CGPoint) -> CGRect? {
    guard let scan = project.roomScans.first(where: { $0.id == scanId }) else { return nil }
    guard let geo = geometryByScanId[scanId], !geo.segments.isEmpty else { return nil }
    var minX = CGFloat.greatestFiniteMagnitude
    var minY = CGFloat.greatestFiniteMagnitude
    var maxX = -CGFloat.greatestFiniteMagnitude
    var maxY = -CGFloat.greatestFiniteMagnitude
    for seg in transform(segments: geo.segments, t: scan.transform) {
      let a = mapPoint(x: seg.ax, y: seg.ay, scale: scale, origin: origin)
      let b = mapPoint(x: seg.bx, y: seg.by, scale: scale, origin: origin)
      minX = min(minX, a.x, b.x)
      minY = min(minY, a.y, b.y)
      maxX = max(maxX, a.x, b.x)
      maxY = max(maxY, a.y, b.y)
    }
    guard minX.isFinite, minY.isFinite, maxX.isFinite, maxY.isFinite else { return nil }
    let w = max(1, maxX - minX)
    let h = max(1, maxY - minY)
    return CGRect(x: minX, y: minY, width: w, height: h)
  }

  private func distancePx(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    let dx = a.x - b.x
    let dy = a.y - b.y
    return sqrt(dx * dx + dy * dy)
  }

  private func handleCentersPx(
    scanId: UUID,
    viewSize: CGSize,
    scale: CGFloat,
    origin: CGPoint
  ) -> (moveCenter: CGPoint, rotateCenter: CGPoint)? {
    guard viewSize.width > 20, viewSize.height > 20 else { return nil }
    guard let scan = project.roomScans.first(where: { $0.id == scanId }) else { return nil }
    guard let pivotLocal = roomPivotLocal(scanId: scanId) else { return nil }
    let pivotWorld = mapLocalPointToWorld(pivotLocal, t: scan.transform)
    let moveCenter = mapPoint(x: pivotWorld.x, y: pivotWorld.y, scale: scale, origin: origin)
    guard let bounds = roomBoundsPx(scanId: scanId, scale: scale, origin: origin) else {
      return (moveCenter, CGPoint(x: moveCenter.x + handleRotateOffsetXPx, y: moveCenter.y))
    }

    // Keep handles far enough apart to avoid accidental rotate while trying to move.
    // Place rotate handle OUTSIDE the room bounds, but clamp to the visible canvas.
    let pad: CGFloat = max(handleRotateRadiusPx + 12, 50)
    let candidates: [CGPoint] = [
      CGPoint(x: bounds.maxX + pad, y: moveCenter.y), // right
      CGPoint(x: bounds.minX - pad, y: moveCenter.y), // left
      CGPoint(x: moveCenter.x, y: bounds.minY - pad), // top
      CGPoint(x: moveCenter.x, y: bounds.maxY + pad)  // bottom
    ]

    let clampInset: CGFloat = max(handleRotateRadiusPx + 10, 26)
    func clampToView(_ p: CGPoint) -> CGPoint {
      CGPoint(
        x: min(max(p.x, clampInset), viewSize.width - clampInset),
        y: min(max(p.y, clampInset), viewSize.height - clampInset)
      )
    }

    // Pick a candidate that maximizes distance from move handle (after clamping).
    var best = clampToView(CGPoint(x: moveCenter.x + handleRotateOffsetXPx, y: moveCenter.y))
    var bestDist: CGFloat = distancePx(best, moveCenter)
    for c in candidates {
      let p = clampToView(c)
      let d = distancePx(p, moveCenter)
      if d > bestDist {
        bestDist = d
        best = p
      }
    }
    let rotateCenter = best

    return (moveCenter, rotateCenter)
  }

  private func drawMoveRotateHandles(context: inout GraphicsContext, moveCenter: CGPoint, rotateCenter: CGPoint) {
    let accent = Color(red: 0.18, green: 0.42, blue: 0.92).opacity(0.95)
    let fill = Color.white.opacity(0.92)
    let stroke = Color.black.opacity(0.12)

    let moveRadius: CGFloat = handleMoveRadiusPx
    let rotateRadius: CGFloat = handleRotateRadiusPx
    let moveRect = CGRect(x: moveCenter.x - moveRadius, y: moveCenter.y - moveRadius, width: moveRadius * 2, height: moveRadius * 2)
    let rotateRect = CGRect(x: rotateCenter.x - rotateRadius, y: rotateCenter.y - rotateRadius, width: rotateRadius * 2, height: rotateRadius * 2)

    context.fill(Path(ellipseIn: moveRect), with: .color(fill))
    context.stroke(Path(ellipseIn: moveRect), with: .color(stroke), lineWidth: 1)
    context.fill(Path(ellipseIn: rotateRect), with: .color(fill))
    context.stroke(Path(ellipseIn: rotateRect), with: .color(stroke), lineWidth: 1)

    let moveText = Text(Image(systemName: "arrow.up.and.down.and.arrow.left.and.right"))
      .font(.system(size: 24, weight: .bold))
      .foregroundStyle(accent)
    let rotateText = Text(Image(systemName: "arrow.clockwise"))
      .font(.system(size: 24, weight: .bold))
      .foregroundStyle(accent)

    context.draw(context.resolve(moveText), at: moveCenter, anchor: .center)
    context.draw(context.resolve(rotateText), at: rotateCenter, anchor: .center)
  }

  private func drawOpeningSymbol(
    context: inout GraphicsContext,
    segWorld: FloorplanSegment,
    scale: CGFloat,
    origin: CGPoint,
    isSelected: Bool
  ) {
    let bg = Color(.systemGray6)
    let a = mapPoint(x: segWorld.ax, y: segWorld.ay, scale: scale, origin: origin)
    let b = mapPoint(x: segWorld.bx, y: segWorld.by, scale: scale, origin: origin)

    // "Cut" the wall a bit, then draw a dashed hint across the opening.
    var cut = Path()
    cut.move(to: a)
    cut.addLine(to: b)
    context.stroke(cut, with: .color(bg), style: StrokeStyle(lineWidth: isSelected ? 14 : 12, lineCap: .round))

    var dashed = Path()
    dashed.move(to: a)
    dashed.addLine(to: b)
    context.stroke(
      dashed,
      with: .color(Color(red: 0.92, green: 0.45, blue: 0.16).opacity(isSelected ? 0.92 : 0.78)),
      style: StrokeStyle(lineWidth: isSelected ? 4.5 : 3.5, lineCap: .round, dash: [10, 7])
    )

    let dx = b.x - a.x
    let dy = b.y - a.y
    let len = max((dx * dx + dy * dy).squareRoot(), 0.001)
    let nx = -dy / len
    let ny = dx / len
    let tickLength: CGFloat = isSelected ? 7.5 : 6.0

    func drawTick(at t: CGFloat) {
      let px = a.x + dx * t
      let py = a.y + dy * t
      var tick = Path()
      tick.move(to: CGPoint(x: px - nx * tickLength, y: py - ny * tickLength))
      tick.addLine(to: CGPoint(x: px + nx * tickLength, y: py + ny * tickLength))
      context.stroke(
        tick,
        with: .color(Color(red: 0.92, green: 0.45, blue: 0.16).opacity(isSelected ? 0.96 : 0.84)),
        style: StrokeStyle(lineWidth: isSelected ? 2.2 : 1.7, lineCap: .round)
      )
    }

    drawTick(at: 0.28)
    drawTick(at: 0.72)
  }

  private func drawWindowSymbol(
    context: inout GraphicsContext,
    segWorld: FloorplanSegment,
    scale: CGFloat,
    origin: CGPoint,
    isSelected: Bool
  ) {
    let bg = Color(.systemGray6)
    let a = mapPoint(x: segWorld.ax, y: segWorld.ay, scale: scale, origin: origin)
    let b = mapPoint(x: segWorld.bx, y: segWorld.by, scale: scale, origin: origin)

    let dx = b.x - a.x
    let dy = b.y - a.y
    let len = max((dx * dx + dy * dy).squareRoot(), 0.001)
    let nx = -dy / len
    let ny = dx / len
    let off: CGFloat = 3.2

    // Cut wall segment a bit so the window reads clearly.
    var cut = Path()
    cut.move(to: a)
    cut.addLine(to: b)
    context.stroke(cut, with: .color(bg), style: StrokeStyle(lineWidth: isSelected ? 14 : 12, lineCap: .round))

    var p = Path()
    p.move(to: CGPoint(x: a.x + nx * off, y: a.y + ny * off))
    p.addLine(to: CGPoint(x: b.x + nx * off, y: b.y + ny * off))
    p.move(to: CGPoint(x: a.x - nx * off, y: a.y - ny * off))
    p.addLine(to: CGPoint(x: b.x - nx * off, y: b.y - ny * off))
    context.stroke(
      p,
      with: .color(Color(red: 0.18, green: 0.42, blue: 0.92).opacity(isSelected ? 0.85 : 0.70)),
      style: StrokeStyle(lineWidth: isSelected ? 1.9 : 1.4, lineCap: .round, lineJoin: .round)
    )
  }

  private func drawDoorSymbol(
    context: inout GraphicsContext,
    segWorld: FloorplanSegment,
    scale: CGFloat,
    origin: CGPoint,
    isSelected: Bool
  ) {
    let bg = Color(.systemGray6)
    let a = mapPoint(x: segWorld.ax, y: segWorld.ay, scale: scale, origin: origin)
    let b = mapPoint(x: segWorld.bx, y: segWorld.by, scale: scale, origin: origin)

    // Cut the wall where the door is.
    var cut = Path()
    cut.move(to: a)
    cut.addLine(to: b)
    context.stroke(cut, with: .color(bg), style: StrokeStyle(lineWidth: isSelected ? 13 : 11, lineCap: .round))

    let dx = b.x - a.x
    let dy = b.y - a.y
    let len = max((dx * dx + dy * dy).squareRoot(), 0.001)
    let nx = -dy / len
    let ny = dx / len
    let lift: CGFloat = min(isSelected ? 15.0 : 12.0, max(8.0, len * 0.30))
    let mid = CGPoint(x: (a.x + b.x) * 0.5, y: (a.y + b.y) * 0.5)
    let leafEnd = CGPoint(x: mid.x + nx * lift, y: mid.y + ny * lift)

    var swing = Path()
    swing.move(to: a)
    swing.addQuadCurve(to: b, control: CGPoint(x: mid.x + nx * lift * 1.15, y: mid.y + ny * lift * 1.15))
    context.stroke(
      swing,
      with: .color(Color.black.opacity(isSelected ? 0.58 : 0.46)),
      style: StrokeStyle(lineWidth: isSelected ? 1.8 : 1.4, lineCap: .round, lineJoin: .round)
    )

    var leaf = Path()
    leaf.move(to: a)
    leaf.addLine(to: leafEnd)
    context.stroke(
      leaf,
      with: .color(Color.black.opacity(0.88)),
      style: StrokeStyle(lineWidth: isSelected ? 2.5 : 2.0, lineCap: .round, lineJoin: .round)
    )

    let hingeR: CGFloat = isSelected ? 3.2 : 2.7
    context.fill(
      Path(ellipseIn: CGRect(x: a.x - hingeR, y: a.y - hingeR, width: hingeR * 2, height: hingeR * 2)),
      with: .color(Color.black.opacity(0.90))
    )
  }

  private func mapping(viewSize: CGSize) -> (CGFloat, CGPoint) {
    // Stable view transform:
    // - baseFitScale/baseFitCenterWorld are computed via ensureBaseFit(), not re-fit every frame.
    // - This prevents the canvas from "jumping" when rooms rotate (bbox changes).
    let scale = max(20, baseFitScale) * zoom
    let centerM = CGPoint(x: baseFitCenterWorld.x, y: baseFitCenterWorld.y)
    let origin = CGPoint(
      x: viewSize.width / 2 + pan.width - CGFloat(centerM.x) * scale,
      y: viewSize.height / 2 + pan.height + CGFloat(centerM.y) * scale
    )
    return (scale, origin)
  }

  private func combinedBoundsMeters() -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
    var minX = Double.greatestFiniteMagnitude
    var minY = Double.greatestFiniteMagnitude
    var maxX = -Double.greatestFiniteMagnitude
    var maxY = -Double.greatestFiniteMagnitude

    for scan in project.roomScans {
      guard let geo = geometryByScanId[scan.id], !geo.segments.isEmpty else { continue }
      for seg in transform(segments: geo.segments, t: scan.transform) {
        minX = min(minX, seg.ax, seg.bx)
        minY = min(minY, seg.ay, seg.by)
        maxX = max(maxX, seg.ax, seg.bx)
        maxY = max(maxY, seg.ay, seg.by)
      }
    }

    if !minX.isFinite || !minY.isFinite || !maxX.isFinite || !maxY.isFinite {
      return (0, 0, 5, 5)
    }
    return (minX, minY, maxX, maxY)
  }

  private func transform(segments: [FloorplanSegment], t: FloorplanRoomTransform) -> [FloorplanSegment] {
    let cosR = cos(t.rotationRadians)
    let sinR = sin(t.rotationRadians)
    func apply(x: Double, y: Double) -> (Double, Double) {
      let rx = x * cosR - y * sinR
      let ry = x * sinR + y * cosR
      return (rx + t.translationX, ry + t.translationY)
    }
    return segments.map { seg in
      let (ax, ay) = apply(x: seg.ax, y: seg.ay)
      let (bx, by) = apply(x: seg.bx, y: seg.by)
      return FloorplanSegment(ax: ax, ay: ay, bx: bx, by: by)
    }
  }

  private func mapPoint(x: Double, y: Double, scale: CGFloat, origin: CGPoint) -> CGPoint {
    // origin maps (0,0) meters to screen; y is flipped.
    let px = origin.x + CGFloat(x) * scale
    let py = origin.y - CGFloat(y) * scale
    return CGPoint(x: px, y: py)
  }

  private func l10n(_ key: String) -> String {
    settings.localized(key)
  }
}

private struct StairConnectionPickerSheet: View {
  @Binding var fromFloorId: String
  @Binding var toFloorId: String
  let onCancel: () -> Void
  let onStartPlacement: () -> Void

  var body: some View {
    NavigationStack {
      Form {
        Section("Etagen verbinden") {
          Picker("Von", selection: $fromFloorId) {
            ForEach(FloorTaxonomy.floors) { floor in
              Text(floor.displayName).tag(floor.id)
            }
          }
          Picker("Nach", selection: $toFloorId) {
            ForEach(FloorTaxonomy.floors) { floor in
              Text(floor.displayName).tag(floor.id)
            }
          }
        }

        Section {
          Text("Nach dem Start einmal im Plan auf die Treppenposition tippen.")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
      }
      .navigationTitle("Treppe einzeichnen")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Abbrechen", action: onCancel)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Position wählen", action: onStartPlacement)
        }
      }
    }
  }
}
