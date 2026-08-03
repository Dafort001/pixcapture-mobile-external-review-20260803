import Foundation

#if canImport(RoomPlan)
import RoomPlan
import UIKit
import simd

enum RoomPlanFloorplanRenderer {
  struct Segment {
    let a: SIMD2<Float>
    let b: SIMD2<Float>
  }

  static func wallSegments(capturedRoom: CapturedRoom) -> [FloorplanSegment] {
    capturedRoom.walls.compactMap { wall in
      guard let seg = segment(for: wall) else { return nil }
      return FloorplanSegment(
        ax: Double(seg.a.x),
        ay: Double(seg.a.y),
        bx: Double(seg.b.x),
        by: Double(seg.b.y)
      )
    }
  }

  static func doorSegments(capturedRoom: CapturedRoom) -> [FloorplanSegment] {
    capturedRoom.doors.compactMap { door in
      guard let seg = segment(for: door) else { return nil }
      return FloorplanSegment(
        ax: Double(seg.a.x),
        ay: Double(seg.a.y),
        bx: Double(seg.b.x),
        by: Double(seg.b.y)
      )
    }
  }

  static func openingSegments(capturedRoom: CapturedRoom) -> [FloorplanSegment] {
    capturedRoom.openings.compactMap { opening in
      guard let seg = segment(for: opening) else { return nil }
      return FloorplanSegment(
        ax: Double(seg.a.x),
        ay: Double(seg.a.y),
        bx: Double(seg.b.x),
        by: Double(seg.b.y)
      )
    }
  }

  static func windowSegments(capturedRoom: CapturedRoom) -> [FloorplanSegment] {
    capturedRoom.windows.compactMap { window in
      guard let seg = segment(for: window) else { return nil }
      return FloorplanSegment(
        ax: Double(seg.a.x),
        ay: Double(seg.a.y),
        bx: Double(seg.b.x),
        by: Double(seg.b.y)
      )
    }
  }

  static func metrics(for segments: [FloorplanSegment]) -> FloorplanMetrics {
    FloorplanPolygonGeometry.evaluate(segments: segments).metrics
  }

  static func writeSegmentsJSON(
    capturedRoom: CapturedRoom,
    outputURL: URL,
    entryPassageHint: FloorplanEntryPassageHint? = nil,
    previousRoomExitPassageHint: FloorplanEntryPassageHint? = nil,
    trackingSessionId: String? = nil,
    trackingSource: FloorplanTrackingSource? = nil
  ) throws {
    let file = segmentsFile(
      capturedRoom: capturedRoom,
      entryPassageHint: entryPassageHint,
      previousRoomExitPassageHint: previousRoomExitPassageHint,
      trackingSessionId: trackingSessionId,
      trackingSource: trackingSource
    )
    try writeSegmentsFile(file, to: outputURL)
  }

  static func segmentsFile(
    capturedRoom: CapturedRoom,
    entryPassageHint: FloorplanEntryPassageHint? = nil,
    previousRoomExitPassageHint: FloorplanEntryPassageHint? = nil,
    trackingSessionId: String? = nil,
    trackingSource: FloorplanTrackingSource? = nil
  ) -> FloorplanSegmentsFile {
    let rawWalls = wallSegments(capturedRoom: capturedRoom)
    let rawDoors = doorSegments(capturedRoom: capturedRoom)
    let rawOpenings = openingSegments(capturedRoom: capturedRoom)
    let rawWindows = windowSegments(capturedRoom: capturedRoom)

    let fallback = rawDoors + rawOpenings
    let (minX, minY) = originOffset(segments: rawWalls.isEmpty ? fallback : rawWalls) ?? (0, 0)
    let worldRotation = worldRotationRadians(capturedRoom: capturedRoom)

    let walls = applyOffset(segments: rawWalls, dx: -minX, dy: -minY)
    let doors = applyOffset(segments: rawDoors, dx: -minX, dy: -minY)
    let openings = applyOffset(segments: rawOpenings, dx: -minX, dy: -minY)
    let windows = applyOffset(segments: rawWindows, dx: -minX, dy: -minY)

    return FloorplanSegmentsFile(
      version: 7,
      segments: walls,
      metrics: metrics(for: walls),
      doors: doors.isEmpty ? nil : doors,
      openings: openings.isEmpty ? nil : openings,
      windows: windows.isEmpty ? nil : windows,
      entryPassageHint: entryPassageHint,
      previousRoomExitPassageHint: previousRoomExitPassageHint,
      trackingSessionId: trackingSessionId,
      trackingSource: trackingSource,
      worldOffsetX: minX,
      worldOffsetY: minY,
      worldRotationRadians: worldRotation
    )
  }

  static func writeSegmentsFile(_ file: FloorplanSegmentsFile, to outputURL: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(file)
    try data.write(to: outputURL, options: [.atomic])
  }

  static func renderPNG(
    capturedRoom: CapturedRoom,
    outputURL: URL,
    canvasSize: CGSize = CGSize(width: 1400, height: 1400)
  ) throws {
    let wallSegments = wallSegments(capturedRoom: capturedRoom)
    let doorSegments = doorSegments(capturedRoom: capturedRoom)
    let openingSegments = openingSegments(capturedRoom: capturedRoom)
    let windowSegments = windowSegments(capturedRoom: capturedRoom)

    guard !wallSegments.isEmpty else {
      throw NSError(domain: "RoomPlanFloorplanRenderer", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "Keine Wände im RoomPlan-Scan gefunden."
      ])
    }

    let padding: CGFloat = 70
    let previewRoom = FloorplanPlanRenderer.Room(
      scanId: UUID(),
      roomId: "room_preview",
      floorId: FloorTaxonomy.defaultFloorId,
      walls: wallSegments,
      doors: doorSegments,
      openings: openingSegments,
      windows: windowSegments,
      doorSwingOverrides: []
    )
    let layout = FloorplanPlanRenderer.layout(for: [previewRoom])
    let viewport = CGRect(
      x: padding,
      y: padding,
      width: max(1, canvasSize.width - padding * 2),
      height: max(1, canvasSize.height - padding * 2)
    )
    let mapping = FloorplanPlanRenderer.makeMapping(
      bounds: layout.bounds,
      viewport: viewport,
      minimumScale: 0
    )

    let renderer = UIGraphicsImageRenderer(size: canvasSize)
    let image = renderer.image { ctx in
      let cg = ctx.cgContext
      cg.setFillColor(UIColor.white.cgColor)
      cg.fill(CGRect(origin: .zero, size: canvasSize))

      // Keep the subtle coverage grid, but let the actual plan symbols come from the shared renderer.
      cg.setStrokeColor(UIColor.black.withAlphaComponent(0.05).cgColor)
      cg.setLineWidth(1)
      let gridStep: CGFloat = 80
      for x in stride(from: padding, through: canvasSize.width - padding, by: gridStep) {
        cg.move(to: CGPoint(x: x, y: padding))
        cg.addLine(to: CGPoint(x: x, y: canvasSize.height - padding))
      }
      for y in stride(from: padding, through: canvasSize.height - padding, by: gridStep) {
        cg.move(to: CGPoint(x: padding, y: y))
        cg.addLine(to: CGPoint(x: canvasSize.width - padding, y: y))
      }
      cg.strokePath()

      FloorplanPlanRenderer.drawBasePlan(
        cg: cg,
        rooms: [previewRoom],
        layout: layout,
        mapping: mapping,
        style: .singleRoomPreview,
        labelMode: .none
      )
    }

    guard let data = image.pngData() else {
      throw NSError(domain: "RoomPlanFloorplanRenderer", code: 2, userInfo: [
        NSLocalizedDescriptionKey: "PNG konnte nicht erzeugt werden."
      ])
    }

    try data.write(to: outputURL, options: [.atomic])
  }

  static func renderPNG(
    segmentsFile: FloorplanSegmentsFile,
    outputURL: URL,
    canvasSize: CGSize = CGSize(width: 1400, height: 1400)
  ) throws {
    guard !segmentsFile.segments.isEmpty else {
      throw NSError(domain: "RoomPlanFloorplanRenderer", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "Keine Wände im manuellen Raumgrundriss gefunden."
      ])
    }
    let room = FloorplanPlanRenderer.Room(
      scanId: UUID(),
      roomId: "manual_room_preview",
      floorId: FloorTaxonomy.defaultFloorId,
      walls: segmentsFile.segments,
      doors: segmentsFile.doors ?? [],
      openings: segmentsFile.openings ?? [],
      windows: segmentsFile.windows ?? [],
      doorSwingOverrides: segmentsFile.doorSwingOverrides ?? []
    )
    let layout = FloorplanPlanRenderer.layout(for: [room])
    let padding: CGFloat = 70
    let viewport = CGRect(
      x: padding,
      y: padding,
      width: max(1, canvasSize.width - padding * 2),
      height: max(1, canvasSize.height - padding * 2)
    )
    let mapping = FloorplanPlanRenderer.makeMapping(bounds: layout.bounds, viewport: viewport, minimumScale: 0)
    let renderer = UIGraphicsImageRenderer(size: canvasSize)
    let image = renderer.image { context in
      let cg = context.cgContext
      cg.setFillColor(UIColor.white.cgColor)
      cg.fill(CGRect(origin: .zero, size: canvasSize))
      FloorplanPlanRenderer.drawBasePlan(
        cg: cg,
        rooms: [room],
        layout: layout,
        mapping: mapping,
        style: .singleRoomPreview,
        labelMode: .none
      )
    }
    guard let data = image.pngData() else {
      throw NSError(domain: "RoomPlanFloorplanRenderer", code: 2, userInfo: [
        NSLocalizedDescriptionKey: "PNG konnte nicht erzeugt werden."
      ])
    }
    try data.write(to: outputURL, options: [.atomic])
  }

  private static func worldRotationRadians(capturedRoom: CapturedRoom) -> Double? {
    if let floor = capturedRoom.floors.first {
      return yawRadians(from: floor.transform)
    }
    if let wall = capturedRoom.walls.first {
      return yawRadians(from: wall.transform)
    }
    return nil
  }

  private static func yawRadians(from transform: simd_float4x4) -> Double? {
    let xAxis = transform.columns.0
    let yaw = Double(atan2(xAxis.z, xAxis.x))
    return yaw.isFinite ? yaw : nil
  }

  private static func segment(for surface: CapturedRoom.Surface) -> Segment? {
    let width = surface.dimensions.x
    guard width.isFinite, width > 0.02 else { return nil }

    // RoomPlan uses ARKit coordinates (x/z horizontal plane, y up).
    let a4 = surface.transform * SIMD4<Float>(-width / 2, 0, 0, 1)
    let b4 = surface.transform * SIMD4<Float>( width / 2, 0, 0, 1)
    return Segment(
      // Note: The USDZ export as previewed in SceneKit is mirrored vs. raw RoomPlan surface x.
      // Negating x here makes the 2D floorplan match the 3D preview (and real-world left/right).
      a: SIMD2<Float>(-a4.x, a4.z),
      b: SIMD2<Float>(-b4.x, b4.z)
    )
  }

  private static func originOffset(segments: [FloorplanSegment]) -> (Double, Double)? {
    guard !segments.isEmpty else { return nil }
    var minX = Double.greatestFiniteMagnitude
    var minY = Double.greatestFiniteMagnitude
    for seg in segments {
      minX = min(minX, seg.ax, seg.bx)
      minY = min(minY, seg.ay, seg.by)
    }
    guard minX.isFinite, minY.isFinite else { return nil }
    return (minX, minY)
  }

  private static func applyOffset(segments: [FloorplanSegment], dx: Double, dy: Double) -> [FloorplanSegment] {
    guard !segments.isEmpty else { return segments }
    return segments.map {
      FloorplanSegment(
        ax: $0.ax + dx,
        ay: $0.ay + dy,
        bx: $0.bx + dx,
        by: $0.by + dy
      )
    }
  }

}
#endif
