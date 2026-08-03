import Foundation

enum FloorplanTrackingSource: String, Codable, Hashable {
  case floorScanSharedWorld = "floor_scan_shared_world"
  case roomSequenceSharedWorld = "room_sequence_shared_world"
  case manualCornersSharedWorld = "manual_corners_shared_world"
}

struct FloorplanSegmentsFile: Codable, Hashable {
  var version: Int
  var segments: [FloorplanSegment]
  var metrics: FloorplanMetrics
  // Optional overlays to help orient rooms (e.g. doors/openings). Missing in legacy files.
  var doors: [FloorplanSegment]?
  var openings: [FloorplanSegment]?
  // Windows are important for orientation/light direction in later video workflows.
  // Optional for backwards compatibility with older segment files.
  var windows: [FloorplanSegment]?
  // Optional per-door display overrides. Indexes align with `doors`.
  var doorSwingOverrides: [FloorplanDoorSwingOverride]?

  // Hint for auto-docking: which passage is the most likely entry to this room.
  // Determined from AR tracking camera path during capture. Optional for backwards compatibility.
  var entryPassageHint: FloorplanEntryPassageHint?

  // If this room was started from a previous-room overlay, remember which passage of the
  // previous room the user most likely walked through. This lets auto-docking use the actual
  // transition instead of guessing among all old-room doors/openings.
  var previousRoomExitPassageHint: FloorplanEntryPassageHint?

  // If present, this scan was captured as part of a "floor scan" session where all rooms share
  // one continuous AR tracking coordinate system (iOS 17+).
  // This enables low-friction auto-placement without manual "sticking rooms together".
  var trackingSessionId: String?
  var trackingSource: FloorplanTrackingSource?

  // World-space offset of the room geometry prior to normalization (meters).
  // We still store normalized local segments for consistent rendering, but this gives us a stable
  // initial placement when all rooms share one AR session.
  var worldOffsetX: Double?
  var worldOffsetY: Double?
  var worldRotationRadians: Double?

  init(
    version: Int,
    segments: [FloorplanSegment],
    metrics: FloorplanMetrics,
    doors: [FloorplanSegment]? = nil,
    openings: [FloorplanSegment]? = nil,
    windows: [FloorplanSegment]? = nil,
    doorSwingOverrides: [FloorplanDoorSwingOverride]? = nil,
    entryPassageHint: FloorplanEntryPassageHint? = nil,
    previousRoomExitPassageHint: FloorplanEntryPassageHint? = nil,
    trackingSessionId: String? = nil,
    trackingSource: FloorplanTrackingSource? = nil,
    worldOffsetX: Double? = nil,
    worldOffsetY: Double? = nil,
    worldRotationRadians: Double? = nil
  ) {
    self.version = version
    self.segments = segments
    self.metrics = metrics
    self.doors = doors
    self.openings = openings
    self.windows = windows
    self.doorSwingOverrides = doorSwingOverrides
    self.entryPassageHint = entryPassageHint
    self.previousRoomExitPassageHint = previousRoomExitPassageHint
    self.trackingSessionId = trackingSessionId
    self.trackingSource = trackingSource
    self.worldOffsetX = worldOffsetX
    self.worldOffsetY = worldOffsetY
    self.worldRotationRadians = worldRotationRadians
  }
}

struct FloorplanEntryPassageHint: Codable, Hashable {
  // "door" or "opening"
  var kind: String
  var index: Int
}

struct FloorplanDoorSwingOverride: Codable, Hashable {
  // 0 = default; 1 = same hinge, opposite side; 2 = opposite hinge, default side; 3 = opposite hinge, opposite side.
  var rotationQuarterTurns: Int

  var normalizedQuarterTurns: Int {
    ((rotationQuarterTurns % 4) + 4) % 4
  }
}

extension FloorplanSegmentsFile {
  /// Compatibility fix: early exports were mirrored along X compared to the USDZ/3D preview.
  /// We fix it at load-time for legacy files so old projects don't mix orientations.
  func normalizedForDisplay() -> FloorplanSegmentsFile {
    // v4: x-mirror fixed at source in RoomPlanFloorplanRenderer.segment(for:).
    guard version <= 3 else { return self }

    let allForBounds: [FloorplanSegment] = {
      if !segments.isEmpty { return segments }
      var out: [FloorplanSegment] = []
      if let doors { out.append(contentsOf: doors) }
      if let openings { out.append(contentsOf: openings) }
      if let windows { out.append(contentsOf: windows) }
      return out
    }()

    guard let bounds = boundsXY(allForBounds), bounds.maxX.isFinite, bounds.minX.isFinite else { return self }
    let sum = bounds.minX + bounds.maxX // mirror around midX

    func flip(_ s: FloorplanSegment) -> FloorplanSegment {
      FloorplanSegment(ax: sum - s.ax, ay: s.ay, bx: sum - s.bx, by: s.by)
    }

    var out = self
    out.segments = segments.map(flip)
    out.doors = doors?.map(flip)
    out.openings = openings?.map(flip)
    out.windows = windows?.map(flip)
    return out
  }

  private func boundsXY(_ segs: [FloorplanSegment]) -> (minX: Double, maxX: Double, minY: Double, maxY: Double)? {
    guard !segs.isEmpty else { return nil }
    var minX = Double.greatestFiniteMagnitude
    var maxX = -Double.greatestFiniteMagnitude
    var minY = Double.greatestFiniteMagnitude
    var maxY = -Double.greatestFiniteMagnitude
    for s in segs {
      minX = min(minX, s.ax, s.bx)
      maxX = max(maxX, s.ax, s.bx)
      minY = min(minY, s.ay, s.by)
      maxY = max(maxY, s.ay, s.by)
    }
    guard minX.isFinite, maxX.isFinite, minY.isFinite, maxY.isFinite else { return nil }
    return (minX, maxX, minY, maxY)
  }
}
