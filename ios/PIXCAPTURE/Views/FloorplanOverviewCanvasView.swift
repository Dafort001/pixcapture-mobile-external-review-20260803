import SwiftUI

struct FloorplanOverviewCanvasView: View {
  let projectKey: String
  let project: FloorplanProject
  var showsEmptyHint: Bool = true
  private let wallMeasureMinLengthMeters = 0.55

  @State private var geometryByScanId: [UUID: FloorplanSegmentsFile] = [:]

  @State private var zoom: CGFloat = 1.0
  @State private var pan: CGSize = .zero
  @State private var lastPan: CGSize = .zero
  @State private var lastZoom: CGFloat = 1.0
  @State private var activePanStart: CGSize? = nil

  var body: some View {
    GeometryReader { geo in
      ZStack {
        Canvas { context, size in
          draw(context: &context, size: size)
        }
        .contentShape(Rectangle())
        .gesture(canvasGestures(viewSize: geo.size))

        if showsEmptyHint, project.roomScans.isEmpty {
          VStack(spacing: 10) {
            Image(systemName: "square.grid.3x3")
              .font(.system(size: 24, weight: .semibold))
              .foregroundStyle(Color.black.opacity(0.25))
            Text("Noch keine Räume")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(Color.black.opacity(0.55))
            Text("Unten auf „Raum scannen“ tippen, um zu starten.")
              .font(.system(size: 12))
              .foregroundStyle(Color.black.opacity(0.45))
          }
          .padding(18)
          .background(Color.white.opacity(0.92))
          .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
          .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.08), lineWidth: 1))
          .padding(.horizontal, 18)
        }
      }
      .clipped()
      .task(id: reloadKey) {
        loadSegments()
      }
    }
  }

  private var reloadKey: String {
    // Reload when scans change.
    project.roomScans.map {
      let t = $0.transform
      return "\($0.id.uuidString):\($0.segmentsJSONPath):\(t.translationX):\(t.translationY):\(t.rotationRadians)"
    }
    .joined(separator: "|")
  }

  private func loadSegments() {
    var dict: [UUID: FloorplanSegmentsFile] = [:]
    for scan in project.roomScans {
      guard let url = try? FloorplanProjectStore.resolve(projectKey: projectKey, relativePath: scan.segmentsJSONPath),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(FloorplanSegmentsFile.self, from: data) else { continue }
      dict[scan.id] = decoded.normalizedForDisplay()
    }
    geometryByScanId = dict
  }

  private func canvasGestures(viewSize: CGSize) -> some Gesture {
    let drag = DragGesture()
      .onChanged { value in
        if activePanStart == nil {
          activePanStart = lastPan
        }
        let start = activePanStart ?? lastPan
        pan = CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height)
      }
      .onEnded { _ in
        activePanStart = nil
        lastPan = pan
      }

    let magnify = MagnificationGesture()
      .onChanged { value in
        zoom = max(0.45, min(4.0, lastZoom * value))
      }
      .onEnded { _ in
        lastZoom = zoom
      }

    return drag.simultaneously(with: magnify)
  }

  private func draw(context: inout GraphicsContext, size: CGSize) {
    let (scale, origin) = mapping(viewSize: size)

    drawGrid(context: &context, size: size, scale: scale, origin: origin)
    let rooms = renderRooms()
    let layout = FloorplanPlanRenderer.layout(for: rooms)
    let mapping = FloorplanPlanRenderer.Mapping(scale: scale, origin: origin)
    context.withCGContext { cg in
      FloorplanPlanRenderer.drawBasePlan(
        cg: cg,
        rooms: rooms,
        layout: layout,
        mapping: mapping,
        style: .overview,
        labelMode: .roomName
      )
    }

    for scan in project.roomScans {
      guard let geo = geometryByScanId[scan.id] else { continue }
      let worldSegs = transform(segments: geo.segments, t: scan.transform)
      drawWallMeasurements(
        context: &context,
        size: size,
        scale: scale,
        origin: origin,
        segmentsWorld: worldSegs
      )
    }
  }

  private func renderRooms() -> [FloorplanPlanRenderer.Room] {
    FloorplanPlanRenderer.rooms(project: project, geometryByScanId: geometryByScanId)
  }

  private struct DPoint {
    let x: Double
    let y: Double
  }

  private struct WallSourceSegment {
    let scanId: UUID
    let seg: FloorplanSegment
  }

  private struct RenderedWallSegment {
    let seg: FloorplanSegment
    let isInterior: Bool
  }

  private func buildRenderedWallSegments(using geometryByScanId: [UUID: FloorplanSegmentsFile]) -> [RenderedWallSegment] {
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

  private func pointSegmentDistance(p: DPoint, seg: FloorplanSegment) -> (dist: Double, t: Double) {
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
    let dist = (dx * dx + dy * dy).squareRoot()
    return (dist, t)
  }

  private func segmentLength(_ seg: FloorplanSegment) -> Double {
    let dx = seg.bx - seg.ax
    let dy = seg.by - seg.ay
    return (dx * dx + dy * dy).squareRoot()
  }

  private func midpoint(of seg: FloorplanSegment) -> DPoint {
    DPoint(x: (seg.ax + seg.bx) * 0.5, y: (seg.ay + seg.by) * 0.5)
  }

  private func direction(of seg: FloorplanSegment) -> DPoint {
    normalized(DPoint(x: seg.bx - seg.ax, y: seg.by - seg.ay))
  }

  private func normalized(_ p: DPoint) -> DPoint {
    let len = max((p.x * p.x + p.y * p.y).squareRoot(), 1e-9)
    return DPoint(x: p.x / len, y: p.y / len)
  }

  private func dot(_ a: DPoint, _ b: DPoint) -> Double {
    a.x * b.x + a.y * b.y
  }

  private func cross(_ a: DPoint, _ b: DPoint) -> Double {
    a.x * b.y - a.y * b.x
  }

  private func distance(_ a: DPoint, _ b: DPoint) -> Double {
    let dx = a.x - b.x
    let dy = a.y - b.y
    return (dx * dx + dy * dy).squareRoot()
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

  private func drawGrid(context: inout GraphicsContext, size: CGSize, scale: CGFloat, origin: CGPoint) {
    let minorStepM = chooseMinorGridStepMeters(pxPerMeter: scale)
    let minorStepPx = CGFloat(minorStepM) * scale
    guard minorStepPx >= 10 else { return }

    let majorEvery = 5
    let superEvery = 10

    let minorColor = Color(red: 0.18, green: 0.42, blue: 0.92).opacity(0.05)
    let majorColor = Color(red: 0.18, green: 0.42, blue: 0.92).opacity(0.10)
    let superColor = Color(red: 0.18, green: 0.42, blue: 0.92).opacity(0.16)

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

  private func mapping(viewSize: CGSize) -> (CGFloat, CGPoint) {
    let bounds = combinedBoundsMeters()
    let widthM = max(bounds.maxX - bounds.minX, 0.8)
    let heightM = max(bounds.maxY - bounds.minY, 0.8)
    let margin: CGFloat = 36
    let fitScale = min(
      (viewSize.width - margin * 2) / CGFloat(widthM),
      (viewSize.height - margin * 2) / CGFloat(heightM)
    )
    let scale = max(18, fitScale) * zoom

    let centerM = CGPoint(x: (bounds.minX + bounds.maxX) * 0.5, y: (bounds.minY + bounds.maxY) * 0.5)
    let origin = CGPoint(
      x: viewSize.width / 2 + pan.width - CGFloat(centerM.x) * scale,
      y: viewSize.height / 2 + pan.height + CGFloat(centerM.y) * scale
    )
    return (scale, origin)
  }

  private func combinedBoundsMeters() -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
    let bounds = FloorplanPlanRenderer.worldBounds(rooms: renderRooms())
    return (bounds.minX, bounds.minY, bounds.maxX, bounds.maxY)
  }

  private func boundsCenterWorld(scan: FloorplanRoomScan) -> (x: Double, y: Double)? {
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
    return ((minX + maxX) * 0.5, (minY + maxY) * 0.5)
  }

  private func transform(segments: [FloorplanSegment], t: FloorplanRoomTransform) -> [FloorplanSegment] {
    if segments.isEmpty { return [] }
    let cosR = cos(t.rotationRadians)
    let sinR = sin(t.rotationRadians)
    return segments.map { seg in
      func rot(_ x: Double, _ y: Double) -> (Double, Double) {
        (x * cosR - y * sinR, x * sinR + y * cosR)
      }
      let (ax, ay) = rot(seg.ax, seg.ay)
      let (bx, by) = rot(seg.bx, seg.by)
      return FloorplanSegment(
        ax: ax + t.translationX,
        ay: ay + t.translationY,
        bx: bx + t.translationX,
        by: by + t.translationY
      )
    }
  }

  private func mapPoint(x: Double, y: Double, scale: CGFloat, origin: CGPoint) -> CGPoint {
    CGPoint(x: origin.x + CGFloat(x) * scale, y: origin.y - CGFloat(y) * scale)
  }

  private func drawWallMeasurements(
    context: inout GraphicsContext,
    size: CGSize,
    scale: CGFloat,
    origin: CGPoint,
    segmentsWorld: [FloorplanSegment]
  ) {
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

      let ax = mapPoint(x: seg.ax, y: seg.ay, scale: scale, origin: origin)
      let bx = mapPoint(x: seg.bx, y: seg.by, scale: scale, origin: origin)
      let vx = bx.x - ax.x
      let vy = bx.y - ax.y
      let vlen = max(1e-3, sqrt(vx * vx + vy * vy))
      let nx = -vy / vlen
      let ny = vx / vlen
      mid.x += nx * 14
      mid.y += ny * 14

      var angle = atan2(vy, vx)
      if angle > .pi / 2 { angle -= .pi }
      if angle < -.pi / 2 { angle += .pi }

      guard mid.x >= -40, mid.x <= size.width + 40, mid.y >= -40, mid.y <= size.height + 40 else { continue }
      drawMeasurementLabel(context: &context, text: formatMeters(lenM), at: mid, angleRadians: angle)
    }
  }

  private func drawMeasurementLabel(
    context: inout GraphicsContext,
    text: String,
    at pos: CGPoint,
    angleRadians: CGFloat
  ) {
    let resolved = context.resolve(
      Text(text)
        .font(.system(size: 11, weight: .bold))
        .foregroundColor(.black.opacity(0.82))
    )
    let measured = resolved.measure(in: CGSize(width: 160, height: 30))
    let rect = CGRect(
      x: -measured.width / 2 - 8,
      y: -measured.height / 2 - 4,
      width: measured.width + 16,
      height: measured.height + 8
    )

    context.drawLayer { layer in
      layer.translateBy(x: pos.x, y: pos.y)
      layer.rotate(by: Angle(radians: Double(angleRadians)))
      layer.fill(
        Path(roundedRect: rect, cornerRadius: 10),
        with: .color(.white.opacity(0.78))
      )
      layer.stroke(
        Path(roundedRect: rect, cornerRadius: 10),
        with: .color(.black.opacity(0.12)),
        lineWidth: 1
      )
      layer.draw(resolved, at: .zero, anchor: .center)
    }
  }

  private func formatMeters(_ value: Double) -> String {
    let formatted = String(format: "%.2f", value).replacingOccurrences(of: ".", with: ",")
    return "\(formatted) m"
  }
}
