import Foundation
import UIKit

enum FloorplanPlanRenderer {
  struct Room {
    let scanId: UUID
    let roomId: String
    let floorId: String
    let walls: [FloorplanSegment]
    let doors: [FloorplanSegment]
    let openings: [FloorplanSegment]
    let windows: [FloorplanSegment]
    let doorSwingOverrides: [FloorplanDoorSwingOverride]
  }

  struct Bounds {
    let minX: Double
    let minY: Double
    let maxX: Double
    let maxY: Double

    var width: Double { max(0, maxX - minX) }
    var height: Double { max(0, maxY - minY) }
    var center: DPoint { DPoint(x: (minX + maxX) * 0.5, y: (minY + maxY) * 0.5) }

    static let fallback = Bounds(minX: 0, minY: 0, maxX: 5, maxY: 5)
  }

  struct Mapping {
    let scale: CGFloat
    let origin: CGPoint

    func map(_ point: DPoint) -> CGPoint {
      CGPoint(x: origin.x + CGFloat(point.x) * scale, y: origin.y - CGFloat(point.y) * scale)
    }

    func map(x: Double, y: Double) -> CGPoint {
      CGPoint(x: origin.x + CGFloat(x) * scale, y: origin.y - CGFloat(y) * scale)
    }
  }

  struct RenderedWallSegment {
    let seg: FloorplanSegment
    let isInterior: Bool
  }

  struct Layout {
    let bounds: Bounds
    let mergedWalls: [RenderedWallSegment]
    let roomCenters: [UUID: DPoint]
    let floorCount: Int
  }

  enum LabelMode {
    case none
    case roomName
    case roomNameAndFloorAlways
    case roomNameAndFloorIfMultipleFloors
  }

  struct Style {
    let roomFillColor: UIColor?
    let highlightedRoomFillColor: UIColor?
    let highlightedRoomStrokeColor: UIColor?
    let highlightedRoomStrokeWidth: CGFloat
    let exteriorWallColor: UIColor
    let interiorWallColor: UIColor
    let cutoutColor: UIColor
    let openingColor: UIColor
    let windowColor: UIColor
    let doorColor: UIColor
    let labelColor: UIColor
    let exteriorWallThicknessMeters: CGFloat
    let interiorWallThicknessMeters: CGFloat
    let wallMinWidth: CGFloat
    let wallMaxWidth: CGFloat
    let labelFontSize: CGFloat

    static let overview = Style(
      roomFillColor: UIColor(white: 1.0, alpha: 0.28),
      highlightedRoomFillColor: nil,
      highlightedRoomStrokeColor: nil,
      highlightedRoomStrokeWidth: 0,
      exteriorWallColor: UIColor.black.withAlphaComponent(0.86),
      interiorWallColor: UIColor.black.withAlphaComponent(0.52),
      cutoutColor: UIColor(red: 0.97, green: 0.98, blue: 0.99, alpha: 1.0),
      openingColor: UIColor.black.withAlphaComponent(0.48),
      windowColor: UIColor.black.withAlphaComponent(0.68),
      doorColor: UIColor.black.withAlphaComponent(0.82),
      labelColor: UIColor.black.withAlphaComponent(0.56),
      exteriorWallThicknessMeters: 0.18,
      interiorWallThicknessMeters: 0.11,
      wallMinWidth: 2.2,
      wallMaxWidth: 18.0,
      labelFontSize: 12
    )

    static let composer = Style(
      roomFillColor: UIColor(white: 1.0, alpha: 0.72),
      highlightedRoomFillColor: UIColor(red: 0.27, green: 0.49, blue: 0.91, alpha: 0.10),
      highlightedRoomStrokeColor: UIColor(red: 0.27, green: 0.49, blue: 0.91, alpha: 0.44),
      highlightedRoomStrokeWidth: 3.2,
      exteriorWallColor: UIColor.black.withAlphaComponent(0.94),
      interiorWallColor: UIColor.black.withAlphaComponent(0.60),
      cutoutColor: UIColor(red: 0.97, green: 0.98, blue: 0.99, alpha: 1.0),
      openingColor: UIColor.black.withAlphaComponent(0.52),
      windowColor: UIColor.black.withAlphaComponent(0.72),
      doorColor: UIColor.black.withAlphaComponent(0.86),
      labelColor: UIColor.black.withAlphaComponent(0.72),
      exteriorWallThicknessMeters: 0.18,
      interiorWallThicknessMeters: 0.11,
      wallMinWidth: 2.4,
      wallMaxWidth: 18.0,
      labelFontSize: 11
    )

    static let export = Style(
      roomFillColor: UIColor(white: 0.965, alpha: 1.0),
      highlightedRoomFillColor: nil,
      highlightedRoomStrokeColor: nil,
      highlightedRoomStrokeWidth: 0,
      exteriorWallColor: UIColor.black.withAlphaComponent(0.98),
      interiorWallColor: UIColor.black.withAlphaComponent(0.90),
      cutoutColor: UIColor.white,
      openingColor: UIColor.black.withAlphaComponent(0.46),
      windowColor: UIColor.black.withAlphaComponent(0.78),
      doorColor: UIColor.black.withAlphaComponent(0.84),
      labelColor: UIColor.black.withAlphaComponent(0.72),
      exteriorWallThicknessMeters: 0.24,
      interiorWallThicknessMeters: 0.095,
      wallMinWidth: 2.8,
      wallMaxWidth: 11.0,
      labelFontSize: 11
    )

    static let singleRoomPreview = Style(
      roomFillColor: nil,
      highlightedRoomFillColor: nil,
      highlightedRoomStrokeColor: nil,
      highlightedRoomStrokeWidth: 0,
      exteriorWallColor: UIColor.black.withAlphaComponent(0.94),
      interiorWallColor: UIColor.black.withAlphaComponent(0.94),
      cutoutColor: UIColor.white,
      openingColor: UIColor.black.withAlphaComponent(0.48),
      windowColor: UIColor.black.withAlphaComponent(0.68),
      doorColor: UIColor.black.withAlphaComponent(0.84),
      labelColor: UIColor.black.withAlphaComponent(0.65),
      exteriorWallThicknessMeters: 0.18,
      interiorWallThicknessMeters: 0.18,
      wallMinWidth: 3.8,
      wallMaxWidth: 22.0,
      labelFontSize: 11
    )
  }

  struct DPoint: Hashable {
    let x: Double
    let y: Double
  }

  static func room(scan: FloorplanRoomScan, geometry: FloorplanSegmentsFile) -> Room {
    Room(
      scanId: scan.id,
      roomId: scan.roomId,
      floorId: scan.floorId,
      walls: transform(segments: geometry.segments, t: scan.transform),
      doors: transform(segments: geometry.doors ?? [], t: scan.transform),
      openings: transform(segments: geometry.openings ?? [], t: scan.transform),
      windows: transform(segments: geometry.windows ?? [], t: scan.transform),
      doorSwingOverrides: geometry.doorSwingOverrides ?? []
    )
  }

  static func rooms(project: FloorplanProject, geometryByScanId: [UUID: FloorplanSegmentsFile]) -> [Room] {
    project.roomScans.compactMap { scan in
      guard let geometry = geometryByScanId[scan.id] else { return nil }
      return room(scan: scan, geometry: geometry)
    }
  }

  static func layout(for rooms: [Room]) -> Layout {
    let bounds = worldBounds(rooms: rooms)
    let mergedWalls = buildRenderedWallSegments(rooms: rooms)
    var roomCenters: [UUID: DPoint] = [:]
    for room in rooms {
      if let center = roomCenter(room) {
        roomCenters[room.scanId] = center
      }
    }
    return Layout(
      bounds: bounds,
      mergedWalls: mergedWalls,
      roomCenters: roomCenters,
      floorCount: Set(rooms.map(\.floorId)).count
    )
  }

  static func worldBounds(rooms: [Room]) -> Bounds {
    var minX = Double.greatestFiniteMagnitude
    var minY = Double.greatestFiniteMagnitude
    var maxX = -Double.greatestFiniteMagnitude
    var maxY = -Double.greatestFiniteMagnitude

    for room in rooms {
      for seg in room.walls {
        minX = min(minX, seg.ax, seg.bx)
        minY = min(minY, seg.ay, seg.by)
        maxX = max(maxX, seg.ax, seg.bx)
        maxY = max(maxY, seg.ay, seg.by)
      }
    }

    guard minX.isFinite, minY.isFinite, maxX.isFinite, maxY.isFinite else {
      return .fallback
    }
    return Bounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
  }

  static func makeMapping(
    bounds: Bounds,
    viewport: CGRect,
    minimumScale: CGFloat,
    zoom: CGFloat = 1.0,
    pan: CGSize = .zero
  ) -> Mapping {
    let widthM = max(bounds.width, 0.8)
    let heightM = max(bounds.height, 0.8)
    let fitScale = min(
      viewport.width / CGFloat(widthM),
      viewport.height / CGFloat(heightM)
    )
    let scale = max(minimumScale, fitScale) * zoom
    let center = bounds.center
    let origin = CGPoint(
      x: viewport.midX + pan.width - CGFloat(center.x) * scale,
      y: viewport.midY + pan.height + CGFloat(center.y) * scale
    )
    return Mapping(scale: scale, origin: origin)
  }

  static func drawBasePlan(
    cg: CGContext,
    rooms: [Room],
    layout: Layout,
    mapping: Mapping,
    style: Style,
    labelMode: LabelMode,
    highlightedScanIds: Set<UUID> = []
  ) {
    guard !rooms.isEmpty else { return }
    var doorFeatures: [DoorRenderFeature] = []

    drawRoomFills(
      cg: cg,
      rooms: rooms,
      mapping: mapping,
      style: style,
      highlightedScanIds: highlightedScanIds
    )

    drawWalls(cg: cg, walls: layout.mergedWalls, mapping: mapping, style: style)

    for room in rooms {
      let roomCenter = layout.roomCenters[room.scanId]
      let indexedDoors = room.doors.enumerated().map { (index: $0.offset, seg: $0.element) }
      let displayDoors = indexedDoors.filter { shouldRenderAsDoor($0.seg, walls: layout.mergedWalls) }
      let doorLikeWindows = indexedDoors.filter { !shouldRenderAsDoor($0.seg, walls: layout.mergedWalls) }
      drawOpenings(cg: cg, segments: room.openings, walls: layout.mergedWalls, mapping: mapping, style: style)
      drawWindows(cg: cg, segments: room.windows + doorLikeWindows.map(\.seg), walls: layout.mergedWalls, roomCenter: roomCenter, mapping: mapping, style: style)
      for door in displayDoors {
        let display = displaySegment(door.seg, walls: layout.mergedWalls)
        doorFeatures.append(
          DoorRenderFeature(
            seg: display.seg,
            doorSwingOverride: override(at: door.index, in: room.doorSwingOverrides),
            roomCenter: roomCenter,
            hasAlignedWall: display.wall != nil
          )
        )
      }
    }

    for door in deduplicatedDoorFeatures(doorFeatures) {
      drawDoors(
        cg: cg,
        segments: [door.seg],
        doorSwingOverrides: [door.doorSwingOverride],
        walls: layout.mergedWalls,
        roomCenter: door.roomCenter,
        mapping: mapping,
        style: style
      )
    }

    drawLabels(
      cg: cg,
      rooms: rooms,
      layout: layout,
      mapping: mapping,
      style: style,
      labelMode: labelMode
    )

    if let highlightColor = style.highlightedRoomStrokeColor,
       style.highlightedRoomStrokeWidth > 0,
       !highlightedScanIds.isEmpty {
      for room in rooms where highlightedScanIds.contains(room.scanId) {
        let worldWalls = room.walls
        guard !worldWalls.isEmpty else { continue }
        cg.saveGState()
        cg.setStrokeColor(highlightColor.cgColor)
        cg.setLineWidth(style.highlightedRoomStrokeWidth)
        cg.setLineCap(.butt)
        cg.setLineJoin(.miter)
        for seg in worldWalls {
          cg.move(to: mapping.map(x: seg.ax, y: seg.ay))
          cg.addLine(to: mapping.map(x: seg.bx, y: seg.by))
        }
        cg.strokePath()
        cg.restoreGState()
      }
    }
  }

  private static func drawRoomFills(
    cg: CGContext,
    rooms: [Room],
    mapping: Mapping,
    style: Style,
    highlightedScanIds: Set<UUID>
  ) {
    for room in rooms {
      let fillColor: UIColor?
      if highlightedScanIds.contains(room.scanId),
         let highlight = style.highlightedRoomFillColor {
        fillColor = highlight
      } else {
        fillColor = style.roomFillColor
      }
      guard let fillColor, fillColor.cgColor.alpha > 0.001 else { continue }
      let hull = convexHullPoints(segments: room.walls)
      guard hull.count >= 3 else { continue }

      cg.saveGState()
      cg.beginPath()
      cg.move(to: mapping.map(hull[0]))
      for point in hull.dropFirst() {
        cg.addLine(to: mapping.map(point))
      }
      cg.closePath()
      cg.setFillColor(fillColor.cgColor)
      cg.fillPath()
      cg.restoreGState()
    }
  }

  private static func drawWalls(
    cg: CGContext,
    walls: [RenderedWallSegment],
    mapping: Mapping,
    style: Style
  ) {
    for rendered in walls {
      let thicknessMeters = rendered.isInterior ? style.interiorWallThicknessMeters : style.exteriorWallThicknessMeters
      let width = min(style.wallMaxWidth, max(style.wallMinWidth, thicknessMeters * mapping.scale))
      let color = rendered.isInterior ? style.interiorWallColor : style.exteriorWallColor
      cg.saveGState()
      cg.setStrokeColor(color.cgColor)
      cg.setLineWidth(width)
      cg.setLineCap(.butt)
      cg.setLineJoin(.miter)
      cg.move(to: mapping.map(x: rendered.seg.ax, y: rendered.seg.ay))
      cg.addLine(to: mapping.map(x: rendered.seg.bx, y: rendered.seg.by))
      cg.strokePath()
      cg.restoreGState()
    }
  }

  private struct DisplayFeatureSegment {
    let seg: FloorplanSegment
    let wall: RenderedWallSegment?
  }

  private struct DoorRenderFeature {
    let seg: FloorplanSegment
    let doorSwingOverride: FloorplanDoorSwingOverride?
    let roomCenter: DPoint?
    let hasAlignedWall: Bool
  }

  private static func deduplicatedDoorFeatures(_ features: [DoorRenderFeature]) -> [DoorRenderFeature] {
    guard features.count > 1 else { return features }
    var kept: [DoorRenderFeature] = []

    for feature in features {
      guard segmentLength(feature.seg) >= 0.40 else { continue }
      if let duplicateIndex = kept.firstIndex(where: { shouldCollapseDoorFeature(feature, with: $0) }) {
        if shouldPreferDoorFeature(feature, over: kept[duplicateIndex]) {
          kept[duplicateIndex] = feature
        }
      } else {
        kept.append(feature)
      }
    }

    return kept
  }

  private static func shouldCollapseDoorFeature(_ a: DoorRenderFeature, with b: DoorRenderFeature) -> Bool {
    let midA = midpoint(of: a.seg)
    let midB = midpoint(of: b.seg)
    let midDistance = distance(midA, midB)
    if midDistance <= 0.20 {
      return true
    }

    let dirSimilarity = abs(dot(direction(of: a.seg), direction(of: b.seg)))
    let aToB = pointSegmentDistance(p: midA, seg: b.seg).dist
    let bToA = pointSegmentDistance(p: midB, seg: a.seg).dist
    if dirSimilarity >= 0.62,
       midDistance <= 0.46,
       min(aToB, bToA) <= 0.22 {
      return true
    }

    let lengthRatio = min(segmentLength(a.seg), segmentLength(b.seg)) / max(segmentLength(a.seg), segmentLength(b.seg), 0.01)
    return dirSimilarity >= 0.78
      && lengthRatio >= 0.62
      && aToB <= 0.28
      && bToA <= 0.28
  }

  private static func shouldPreferDoorFeature(_ candidate: DoorRenderFeature, over current: DoorRenderFeature) -> Bool {
    doorFeatureScore(candidate) < doorFeatureScore(current)
  }

  private static func doorFeatureScore(_ feature: DoorRenderFeature) -> Double {
    let preferredDoorWidth = 0.90
    var score = abs(segmentLength(feature.seg) - preferredDoorWidth)
    if feature.hasAlignedWall {
      score -= 0.10
    }
    if feature.doorSwingOverride != nil {
      score -= 0.16
    }
    return score
  }

  private static func shouldRenderAsDoor(_ seg: FloorplanSegment, walls: [RenderedWallSegment]) -> Bool {
    let length = segmentLength(seg)
    guard length >= 0.48 else { return false }
    let nearestWall = nearestAlignedWall(to: seg, walls: walls)?.wall

    if nearestWall?.isInterior == true {
      return length <= 1.65
    }

    // RoomPlan sometimes reports wide window fronts as doors. For a broker memory plan,
    // a conservative window symbol is less misleading than inventing a door swing.
    return length <= 1.28
  }

  private static func displaySegment(_ seg: FloorplanSegment, walls: [RenderedWallSegment]) -> DisplayFeatureSegment {
    guard let nearest = nearestAlignedWall(to: seg, walls: walls),
          nearest.distance <= 0.34 else {
      return DisplayFeatureSegment(seg: seg, wall: nil)
    }

    let wall = nearest.wall
    let axis = direction(of: wall.seg)
    let origin = DPoint(x: wall.seg.ax, y: wall.seg.ay)
    let wallInterval = projectionInterval(of: wall.seg, origin: origin, axis: axis)

    let rawA = dot(DPoint(x: seg.ax - origin.x, y: seg.ay - origin.y), axis)
    let rawB = dot(DPoint(x: seg.bx - origin.x, y: seg.by - origin.y), axis)
    let minProjection = min(rawA, rawB)
    let maxProjection = max(rawA, rawB)

    if maxProjection < wallInterval.min - 0.30 || minProjection > wallInterval.max + 0.30 {
      return DisplayFeatureSegment(seg: seg, wall: wall)
    }

    let aS = clamp(rawA, min: wallInterval.min, max: wallInterval.max)
    let bS = clamp(rawB, min: wallInterval.min, max: wallInterval.max)
    guard abs(aS - bS) >= 0.08 else {
      return DisplayFeatureSegment(seg: seg, wall: wall)
    }

    let a = DPoint(x: origin.x + axis.x * aS, y: origin.y + axis.y * aS)
    let b = DPoint(x: origin.x + axis.x * bS, y: origin.y + axis.y * bS)
    return DisplayFeatureSegment(
      seg: FloorplanSegment(ax: a.x, ay: a.y, bx: b.x, by: b.y),
      wall: wall
    )
  }

  private static func nearestAlignedWall(
    to seg: FloorplanSegment,
    walls: [RenderedWallSegment]
  ) -> (wall: RenderedWallSegment, distance: Double)? {
    let segDirection = direction(of: seg)
    let segMidpoint = midpoint(of: seg)
    var best: (wall: RenderedWallSegment, distance: Double, score: Double)?

    for wall in walls {
      let wallDirection = direction(of: wall.seg)
      let directionAlignment = abs(dot(segDirection, wallDirection))
      guard directionAlignment >= 0.72 else { continue }

      let origin = DPoint(x: wall.seg.ax, y: wall.seg.ay)
      let wallInterval = projectionInterval(of: wall.seg, origin: origin, axis: wallDirection)
      let featureInterval = projectionInterval(of: seg, origin: origin, axis: wallDirection)
      let overlap = min(wallInterval.max, featureInterval.max) - max(wallInterval.min, featureInterval.min)
      let gap = max(wallInterval.min, featureInterval.min) - min(wallInterval.max, featureInterval.max)
      guard overlap >= -0.30 || gap <= 0.30 else { continue }

      let distance = pointSegmentDistance(p: segMidpoint, seg: wall.seg).dist
      guard distance <= 0.46 else { continue }

      let score = distance - (directionAlignment * 0.08) - (wall.isInterior ? 0.0 : 0.02)
      if best == nil || score < best!.score {
        best = (wall, distance, score)
      }
    }

    guard let best else { return nil }
    return (best.wall, best.distance)
  }

  private static func wallWidthPixels(
    for wall: RenderedWallSegment?,
    mapping: Mapping,
    style: Style
  ) -> CGFloat {
    let thicknessMeters = (wall?.isInterior == true) ? style.interiorWallThicknessMeters : style.exteriorWallThicknessMeters
    return min(style.wallMaxWidth, max(style.wallMinWidth, thicknessMeters * mapping.scale))
  }

  private static func override(
    at index: Int,
    in overrides: [FloorplanDoorSwingOverride]
  ) -> FloorplanDoorSwingOverride? {
    guard overrides.indices.contains(index) else { return nil }
    return overrides[index]
  }

  private static func drawOpenings(
    cg: CGContext,
    segments: [FloorplanSegment],
    walls: [RenderedWallSegment],
    mapping: Mapping,
    style: Style
  ) {
    guard !segments.isEmpty else { return }

    for rawSeg in segments {
      let display = displaySegment(rawSeg, walls: walls)
      let seg = display.seg
      let wallWidth = wallWidthPixels(for: display.wall, mapping: mapping, style: style)
      let tickLength = clamp(wallWidth * 0.42, min: 4.0, max: 8.0)
      let tickWidth = clamp(wallWidth * 0.18, min: 1.1, max: 2.0)
      let jambInset = clamp(wallWidth * 0.16, min: 1.2, max: 2.6)
      let a = mapping.map(x: seg.ax, y: seg.ay)
      let b = mapping.map(x: seg.bx, y: seg.by)
      let axis = normalizedScreenVector(from: a, to: b)
      let normal = CGPoint(x: -axis.y, y: axis.x)

      cg.saveGState()
      cg.setStrokeColor(style.cutoutColor.cgColor)
      cg.setLineWidth(wallWidth * 1.34)
      cg.setLineCap(.butt)
      cg.move(to: a)
      cg.addLine(to: b)
      cg.strokePath()
      cg.restoreGState()

      for t in [CGFloat(0.0), CGFloat(1.0)] {
        let px = a.x + (b.x - a.x) * t
        let py = a.y + (b.y - a.y) * t
        let base = CGPoint(
          x: px + axis.x * (t == 0 ? jambInset : -jambInset),
          y: py + axis.y * (t == 0 ? jambInset : -jambInset)
        )
        cg.saveGState()
        cg.setStrokeColor(style.openingColor.cgColor)
        cg.setLineWidth(tickWidth)
        cg.setLineCap(.butt)
        cg.move(to: CGPoint(x: base.x - normal.x * tickLength, y: base.y - normal.y * tickLength))
        cg.addLine(to: CGPoint(x: base.x + normal.x * tickLength, y: base.y + normal.y * tickLength))
        cg.strokePath()
        cg.restoreGState()
      }
    }
  }

  private static func drawWindows(
    cg: CGContext,
    segments: [FloorplanSegment],
    walls: [RenderedWallSegment],
    roomCenter: DPoint?,
    mapping: Mapping,
    style: Style
  ) {
    guard !segments.isEmpty else { return }

    for rawSeg in segments {
      let display = displaySegment(rawSeg, walls: walls)
      let seg = display.seg
      let wallWidth = wallWidthPixels(for: display.wall, mapping: mapping, style: style)
      let frameInset = clamp(wallWidth * 0.20, min: 1.4, max: 2.8)
      let frameDepth = clamp(wallWidth * 0.56, min: 4.0, max: 8.0)
      let frameLineWidth = clamp(wallWidth * 0.13, min: 1.0, max: 1.8)
      let a = mapping.map(x: seg.ax, y: seg.ay)
      let b = mapping.map(x: seg.bx, y: seg.by)
      let axis = normalizedScreenVector(from: a, to: b)
      var inward = CGPoint(x: -axis.y, y: axis.x)
      inward = orientedTowardRoom(
        normal: inward,
        midpointWorld: midpoint(of: seg),
        roomCenter: roomCenter,
        mapping: mapping
      )

      cg.saveGState()
      cg.setStrokeColor(style.cutoutColor.cgColor)
      cg.setLineWidth(wallWidth * 1.34)
      cg.setLineCap(.butt)
      cg.move(to: a)
      cg.addLine(to: b)
      cg.strokePath()
      cg.restoreGState()

      let outerA = CGPoint(x: a.x + inward.x * frameInset, y: a.y + inward.y * frameInset)
      let outerB = CGPoint(x: b.x + inward.x * frameInset, y: b.y + inward.y * frameInset)
      let innerA = CGPoint(x: a.x + inward.x * (frameInset + frameDepth), y: a.y + inward.y * (frameInset + frameDepth))
      let innerB = CGPoint(x: b.x + inward.x * (frameInset + frameDepth), y: b.y + inward.y * (frameInset + frameDepth))

      cg.saveGState()
      cg.setStrokeColor(style.windowColor.cgColor)
      cg.setLineWidth(frameLineWidth)
      cg.setLineCap(.butt)
      cg.setLineJoin(.miter)
      cg.move(to: outerA)
      cg.addLine(to: outerB)
      cg.move(to: innerA)
      cg.addLine(to: innerB)
      cg.move(to: outerA)
      cg.addLine(to: innerA)
      cg.move(to: outerB)
      cg.addLine(to: innerB)
      cg.strokePath()
      cg.restoreGState()
    }
  }

  private static func drawDoors(
    cg: CGContext,
    segments: [FloorplanSegment],
    doorSwingOverrides: [FloorplanDoorSwingOverride?],
    walls: [RenderedWallSegment],
    roomCenter: DPoint?,
    mapping: Mapping,
    style: Style
  ) {
    guard !segments.isEmpty else { return }

    for (index, rawSeg) in segments.enumerated() {
      let display = displaySegment(rawSeg, walls: walls)
      let seg = display.seg
      let override = index < doorSwingOverrides.count ? doorSwingOverrides[index] : nil
      let wallWidth = wallWidthPixels(for: display.wall, mapping: mapping, style: style)
      let arcWidth = clamp(wallWidth * 0.18, min: 1.2, max: 1.9)
      let leafWidth = clamp(wallWidth * 0.24, min: 1.4, max: 2.4)
      let hingeRadius = clamp(wallWidth * 0.12, min: 1.2, max: 2.0)
      let a = mapping.map(x: seg.ax, y: seg.ay)
      let b = mapping.map(x: seg.bx, y: seg.by)
      let len = distance(a, b)
      guard len > 0.001 else { continue }

      cg.saveGState()
      cg.setStrokeColor(style.cutoutColor.cgColor)
      cg.setLineWidth(wallWidth * 1.34)
      cg.setLineCap(.butt)
      cg.move(to: a)
      cg.addLine(to: b)
      cg.strokePath()
      cg.restoreGState()

      let centerPoint = roomCenter ?? midpoint(of: seg)
      let centroidScreen = mapping.map(centerPoint)
      let defaultHingeIsA = distance(a, centroidScreen) <= distance(b, centroidScreen)
      let quarterTurns = override?.normalizedQuarterTurns ?? 0
      let useOppositeHinge = quarterTurns >= 2
      let hingeIsA = useOppositeHinge ? !defaultHingeIsA : defaultHingeIsA
      let hinge = hingeIsA ? a : b
      let latch = hingeIsA ? b : a
      let axis = normalizedScreenVector(from: hinge, to: latch)
      var inward = CGPoint(x: -axis.y, y: axis.x)
      let segMid = midpoint(of: seg)
      inward = orientedTowardRoom(
        normal: inward,
        midpointWorld: segMid,
        roomCenter: roomCenter,
        mapping: mapping
      )
      if quarterTurns == 1 || quarterTurns == 3 {
        inward = CGPoint(x: -inward.x, y: -inward.y)
      }

      let leafEnd = CGPoint(x: hinge.x + inward.x * len, y: hinge.y + inward.y * len)
      let startVector = CGPoint(x: latch.x - hinge.x, y: latch.y - hinge.y)
      let endVector = CGPoint(x: leafEnd.x - hinge.x, y: leafEnd.y - hinge.y)
      let startAngle = atan2(startVector.y, startVector.x)
      let endAngle = atan2(endVector.y, endVector.x)
      let clockwise = (startVector.x * endVector.y - startVector.y * endVector.x) > 0

      cg.saveGState()
      cg.setStrokeColor(style.doorColor.withAlphaComponent(0.48).cgColor)
      cg.setLineWidth(arcWidth)
      cg.setLineCap(.butt)
      cg.addPath(UIBezierPath(
        arcCenter: hinge,
        radius: len,
        startAngle: startAngle,
        endAngle: endAngle,
        clockwise: clockwise
      ).cgPath)
      cg.strokePath()
      cg.restoreGState()

      cg.saveGState()
      cg.setStrokeColor(style.doorColor.cgColor)
      cg.setLineWidth(leafWidth)
      cg.setLineCap(.butt)
      cg.move(to: hinge)
      cg.addLine(to: leafEnd)
      cg.strokePath()
      cg.restoreGState()

      cg.saveGState()
      cg.setFillColor(style.doorColor.cgColor)
      cg.fillEllipse(in: CGRect(x: hinge.x - hingeRadius, y: hinge.y - hingeRadius, width: hingeRadius * 2, height: hingeRadius * 2))
      cg.restoreGState()
    }
  }

  private static func drawLabels(
    cg: CGContext,
    rooms: [Room],
    layout: Layout,
    mapping: Mapping,
    style: Style,
    labelMode: LabelMode
  ) {
    guard labelMode != .none else { return }

    let font = UIFont.systemFont(ofSize: style.labelFontSize, weight: .semibold)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: style.labelColor,
      .paragraphStyle: paragraph
    ]

    for room in rooms {
      guard let center = layout.roomCenters[room.scanId] else { continue }
      let labelText: String
      switch labelMode {
      case .none:
        labelText = ""
      case .roomName:
        labelText = RoomTaxonomy.room(id: room.roomId).displayName
      case .roomNameAndFloorAlways:
        labelText = "\(RoomTaxonomy.room(id: room.roomId).displayName)\n\(FloorTaxonomy.floor(id: room.floorId).shortDisplayName)"
      case .roomNameAndFloorIfMultipleFloors:
        if layout.floorCount > 1 {
          labelText = "\(RoomTaxonomy.room(id: room.roomId).displayName)\n\(FloorTaxonomy.floor(id: room.floorId).shortDisplayName)"
        } else {
          labelText = RoomTaxonomy.room(id: room.roomId).displayName
        }
      }
      guard !labelText.isEmpty else { continue }

      let textRect = (labelText as NSString).boundingRect(
        with: CGSize(width: 240, height: 100),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: attributes,
        context: nil
      ).integral
      let point = mapping.map(center)
      (labelText as NSString).draw(
        with: CGRect(
          x: point.x - textRect.width * 0.5,
          y: point.y - textRect.height * 0.5,
          width: textRect.width,
          height: textRect.height
        ),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: attributes,
        context: nil
      )
    }
  }

  private static func roomCenter(_ room: Room) -> DPoint? {
    let hull = convexHullPoints(segments: room.walls)
    if let centroid = polygonCentroid(points: hull) {
      return centroid
    }
    guard !room.walls.isEmpty else { return nil }
    var minX = Double.greatestFiniteMagnitude
    var minY = Double.greatestFiniteMagnitude
    var maxX = -Double.greatestFiniteMagnitude
    var maxY = -Double.greatestFiniteMagnitude
    for seg in room.walls {
      minX = min(minX, seg.ax, seg.bx)
      minY = min(minY, seg.ay, seg.by)
      maxX = max(maxX, seg.ax, seg.bx)
      maxY = max(maxY, seg.ay, seg.by)
    }
    guard minX.isFinite, minY.isFinite, maxX.isFinite, maxY.isFinite else { return nil }
    return DPoint(x: (minX + maxX) * 0.5, y: (minY + maxY) * 0.5)
  }

  private static func transform(segments: [FloorplanSegment], t: FloorplanRoomTransform) -> [FloorplanSegment] {
    if segments.isEmpty { return [] }
    let cosR = cos(t.rotationRadians)
    let sinR = sin(t.rotationRadians)
    return segments.map { seg in
      func rotate(_ x: Double, _ y: Double) -> (Double, Double) {
        (x * cosR - y * sinR, x * sinR + y * cosR)
      }
      let (ax, ay) = rotate(seg.ax, seg.ay)
      let (bx, by) = rotate(seg.bx, seg.by)
      return FloorplanSegment(
        ax: ax + t.translationX,
        ay: ay + t.translationY,
        bx: bx + t.translationX,
        by: by + t.translationY
      )
    }
  }

  private struct WallSourceSegment {
    let scanId: UUID
    let seg: FloorplanSegment
  }

  private static func buildRenderedWallSegments(rooms: [Room]) -> [RenderedWallSegment] {
    var sources: [WallSourceSegment] = []
    for room in rooms {
      for seg in room.walls {
        sources.append(WallSourceSegment(scanId: room.scanId, seg: seg))
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

  private static func clusterWallSources(_ sources: [WallSourceSegment]) -> [[WallSourceSegment]] {
    guard !sources.isEmpty else { return [] }
    var remaining = Set(sources.indices)
    var groups: [[WallSourceSegment]] = []

    while let seed = remaining.first {
      remaining.remove(seed)
      var queue: [Int] = [seed]
      var group: [Int] = [seed]

      while let current = queue.popLast() {
        let neighbors = remaining.filter { shouldClusterAsSameWall(sources[current].seg, sources[$0].seg) }
        for neighbor in neighbors {
          remaining.remove(neighbor)
          queue.append(neighbor)
          group.append(neighbor)
        }
      }

      groups.append(group.map { sources[$0] })
    }

    return groups
  }

  private static func splitWallCluster(
    _ cluster: [WallSourceSegment],
    allSources: [WallSourceSegment]
  ) -> [RenderedWallSegment] {
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

  private static func hasNearbyParallelWall(
    midpoint: DPoint,
    axis: DPoint,
    excludedScanIds: Set<UUID>,
    allSources: [WallSourceSegment]
  ) -> Bool {
    let axisN = normalized(axis)
    for source in allSources {
      if excludedScanIds.contains(source.scanId) { continue }
      let dir = direction(of: source.seg)
      if abs(dot(axisN, dir)) < 0.90 { continue }
      let interval = projectionInterval(of: source.seg, origin: midpoint, axis: axisN)
      if interval.max < -0.45 || interval.min > 0.45 { continue }
      if pointSegmentDistance(p: midpoint, seg: source.seg).dist <= 0.26 {
        return true
      }
    }
    return false
  }

  private static func mergeRenderedWallPieces(_ pieces: [RenderedWallSegment]) -> [RenderedWallSegment] {
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
      let touching = distance(lastEnd, currentStart) <= 0.20
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

  private static func shouldClusterAsSameWall(_ a: FloorplanSegment, _ b: FloorplanSegment) -> Bool {
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
    if overlap >= minOverlap { return true }

    let gap = max(intervalA.min, intervalB.min) - min(intervalA.max, intervalB.max)
    return gap >= 0 && gap <= 0.22
  }

  private static func projectionInterval(of seg: FloorplanSegment, origin: DPoint, axis: DPoint) -> (min: Double, max: Double) {
    let a = dot(DPoint(x: seg.ax - origin.x, y: seg.ay - origin.y), axis)
    let b = dot(DPoint(x: seg.bx - origin.x, y: seg.by - origin.y), axis)
    return (min(a, b), max(a, b))
  }

  private static func distanceToInfiniteLine(point: DPoint, linePoint: DPoint, lineDirection: DPoint) -> Double {
    let rel = DPoint(x: point.x - linePoint.x, y: point.y - linePoint.y)
    return abs(cross(rel, lineDirection))
  }

  private static func pointSegmentDistance(p: DPoint, seg: FloorplanSegment) -> (dist: Double, t: Double) {
    let vx = seg.bx - seg.ax
    let vy = seg.by - seg.ay
    let wx = p.x - seg.ax
    let wy = p.y - seg.ay
    let vv = vx * vx + vy * vy
    if vv <= 1e-9 {
      let d = ((p.x - seg.ax) * (p.x - seg.ax) + (p.y - seg.ay) * (p.y - seg.ay)).squareRoot()
      return (d, 0)
    }
    var t = (wx * vx + wy * vy) / vv
    t = min(max(t, 0), 1)
    let cx = seg.ax + vx * t
    let cy = seg.ay + vy * t
    let dx = p.x - cx
    let dy = p.y - cy
    return ((dx * dx + dy * dy).squareRoot(), t)
  }

  private static func midpoint(of seg: FloorplanSegment) -> DPoint {
    DPoint(x: (seg.ax + seg.bx) * 0.5, y: (seg.ay + seg.by) * 0.5)
  }

  private static func direction(of seg: FloorplanSegment) -> DPoint {
    normalized(DPoint(x: seg.bx - seg.ax, y: seg.by - seg.ay))
  }

  private static func segmentLength(_ seg: FloorplanSegment) -> Double {
    let dx = seg.bx - seg.ax
    let dy = seg.by - seg.ay
    return (dx * dx + dy * dy).squareRoot()
  }

  private static func normalized(_ point: DPoint) -> DPoint {
    let len = max((point.x * point.x + point.y * point.y).squareRoot(), 1e-9)
    return DPoint(x: point.x / len, y: point.y / len)
  }

  private static func dot(_ a: DPoint, _ b: DPoint) -> Double {
    a.x * b.x + a.y * b.y
  }

  private static func cross(_ a: DPoint, _ b: DPoint) -> Double {
    a.x * b.y - a.y * b.x
  }

  private static func distance(_ a: DPoint, _ b: DPoint) -> Double {
    let dx = a.x - b.x
    let dy = a.y - b.y
    return (dx * dx + dy * dy).squareRoot()
  }

  private struct Point: Comparable, Hashable {
    let x: Double
    let y: Double

    static func < (lhs: Point, rhs: Point) -> Bool {
      if lhs.x != rhs.x { return lhs.x < rhs.x }
      return lhs.y < rhs.y
    }
  }

  private static func convexHullPoints(segments: [FloorplanSegment]) -> [DPoint] {
    let points = uniquePoints(from: segments)
    let pts = points.sorted()
    guard pts.count >= 3 else {
      return pts.map { DPoint(x: $0.x, y: $0.y) }
    }

    func hullCross(_ o: Point, _ a: Point, _ b: Point) -> Double {
      (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
    }

    var lower: [Point] = []
    for p in pts {
      while lower.count >= 2 && hullCross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 {
        lower.removeLast()
      }
      lower.append(p)
    }

    var upper: [Point] = []
    for p in pts.reversed() {
      while upper.count >= 2 && hullCross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 {
        upper.removeLast()
      }
      upper.append(p)
    }

    let hull = Array(lower.dropLast() + upper.dropLast())
    return hull.map { DPoint(x: $0.x, y: $0.y) }
  }

  private static func uniquePoints(from segments: [FloorplanSegment]) -> [Point] {
    let tolerance = 0.03
    var points: [Point] = []
    points.reserveCapacity(segments.count * 2)

    func insert(_ candidate: Point) {
      for existing in points {
        let dx = existing.x - candidate.x
        let dy = existing.y - candidate.y
        if (dx * dx + dy * dy).squareRoot() < tolerance {
          return
        }
      }
      points.append(candidate)
    }

    for seg in segments {
      insert(Point(x: seg.ax, y: seg.ay))
      insert(Point(x: seg.bx, y: seg.by))
    }

    return points
  }

  private static func polygonCentroid(points: [DPoint]) -> DPoint? {
    guard points.count >= 3 else { return nil }
    var areaTwice = 0.0
    var cx = 0.0
    var cy = 0.0

    for idx in 0..<points.count {
      let next = (idx + 1) % points.count
      let cross = points[idx].x * points[next].y - points[next].x * points[idx].y
      areaTwice += cross
      cx += (points[idx].x + points[next].x) * cross
      cy += (points[idx].y + points[next].y) * cross
    }

    guard abs(areaTwice) > 1e-8 else { return nil }
    return DPoint(x: cx / (3 * areaTwice), y: cy / (3 * areaTwice))
  }

  private static func normalizedScreenVector(from a: CGPoint, to b: CGPoint) -> CGPoint {
    let dx = b.x - a.x
    let dy = b.y - a.y
    let len = max((dx * dx + dy * dy).squareRoot(), 1e-6)
    return CGPoint(x: dx / len, y: dy / len)
  }

  private static func orientedTowardRoom(
    normal: CGPoint,
    midpointWorld: DPoint,
    roomCenter: DPoint?,
    mapping: Mapping
  ) -> CGPoint {
    guard let roomCenter else { return normal }
    let midpointScreen = mapping.map(midpointWorld)
    let centerScreen = mapping.map(roomCenter)
    let vx = centerScreen.x - midpointScreen.x
    let vy = centerScreen.y - midpointScreen.y
    let dot = vx * normal.x + vy * normal.y
    return dot >= 0 ? normal : CGPoint(x: -normal.x, y: -normal.y)
  }

  private static func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
    Swift.max(minValue, Swift.min(maxValue, value))
  }

  private static func clamp(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
    Swift.max(minValue, Swift.min(maxValue, value))
  }

  private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    let dx = b.x - a.x
    let dy = b.y - a.y
    return (dx * dx + dy * dy).squareRoot()
  }
}
