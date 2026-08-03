import Foundation

enum FloorplanLayoutResolver {
  private enum TrackedLayoutDisposition {
    case none
    case preserveRelativeAndAlignComponent
    case preserveAll
  }

  static func normalizedProject(
    project: FloorplanProject,
    loadGeo: (FloorplanRoomScan) -> FloorplanSegmentsFile?
  ) -> FloorplanProject {
    guard !project.roomScans.isEmpty else { return project }

    let scansById = Dictionary(uniqueKeysWithValues: project.roomScans.map { ($0.id, $0) })
    let geometryByScanId: [UUID: FloorplanSegmentsFile] = Dictionary(
      uniqueKeysWithValues: project.roomScans.compactMap { scan in
        guard let geo = loadGeo(scan)?.normalizedForDisplay() else { return nil }
        return (scan.id, geo)
      }
    )

    var normalized = project
    let usableConnections = project.connections.filter {
      isConnectionUsable($0, scansById: scansById, geometryByScanId: geometryByScanId)
    }
    var transformByScanId = Dictionary(uniqueKeysWithValues: project.roomScans.map { ($0.id, $0.transform) })

    let scanIdsByFloor = Dictionary(grouping: project.roomScans, by: \.floorId)
    for (_, floorScans) in scanIdsByFloor {
      resolveFloorTransforms(
        floorScans: floorScans,
        scansById: scansById,
        geometryByScanId: geometryByScanId,
        connections: usableConnections,
        transformByScanId: &transformByScanId
      )
      alignFloorToCanonicalAxes(
        floorScans: floorScans,
        scansById: scansById,
        geometryByScanId: geometryByScanId,
        connections: usableConnections,
        transformByScanId: &transformByScanId
      )
    }

    normalized.roomScans = project.roomScans.map { scan in
      var adjusted = scan
      if let transform = transformByScanId[scan.id] {
        adjusted.transform = transform
      }
      return adjusted
    }
    normalized.connections = usableConnections
    return normalized
  }

  private static func resolveFloorTransforms(
    floorScans: [FloorplanRoomScan],
    scansById: [UUID: FloorplanRoomScan],
    geometryByScanId: [UUID: FloorplanSegmentsFile],
    connections: [FloorplanRoomConnection],
    transformByScanId: inout [UUID: FloorplanRoomTransform]
  ) {
    let floorIds = Set(floorScans.map(\.id))
    let floorConnections = connections.filter { floorIds.contains($0.a.scanId) && floorIds.contains($0.b.scanId) }
    guard !floorConnections.isEmpty else { return }

    var adjacency: [UUID: [FloorplanRoomConnection]] = [:]
    for connection in floorConnections {
      adjacency[connection.a.scanId, default: []].append(connection)
      adjacency[connection.b.scanId, default: []].append(connection)
    }

    var visited: Set<UUID> = []
    let orderedScans = floorScans.sorted(by: { $0.createdAt < $1.createdAt })

    for scan in orderedScans {
      guard !visited.contains(scan.id) else { continue }

      let componentIds = connectedComponent(
        seed: scan.id,
        allowedIds: floorIds,
        adjacency: adjacency,
        visited: &visited
      )
      guard componentIds.count > 1 else { continue }
      guard trackedLayoutDisposition(componentIds: componentIds, geometryByScanId: geometryByScanId) == .none else { continue }
      guard componentNeedsResolution(
        componentIds: componentIds,
        connections: floorConnections,
        scansById: scansById,
        geometryByScanId: geometryByScanId,
        transformByScanId: transformByScanId
      ) else { continue }

      let componentScans = componentIds.compactMap { scansById[$0] }.sorted(by: { $0.createdAt < $1.createdAt })
      guard let root = componentScans.first else { continue }
      guard geometryByScanId[root.id] != nil else { continue }

      var solved: [UUID: FloorplanRoomTransform] = [
        root.id: transformByScanId[root.id] ?? root.transform
      ]
      var queue: [UUID] = [root.id]

      while !queue.isEmpty {
        let sourceId = queue.removeFirst()
        guard let sourceTransform = solved[sourceId],
              let sourceGeo = geometryByScanId[sourceId] else { continue }

        for connection in adjacency[sourceId] ?? [] {
          let targetId = (connection.a.scanId == sourceId) ? connection.b.scanId : connection.a.scanId
          guard componentIds.contains(targetId), solved[targetId] == nil else { continue }
          guard let targetScan = scansById[targetId],
                let targetGeo = geometryByScanId[targetId] else { continue }

          let sourceRef = (connection.a.scanId == sourceId) ? connection.a : connection.b
          let targetRef = (connection.a.scanId == sourceId) ? connection.b : connection.a
          let storedTargetTransform = transformByScanId[targetId] ?? targetScan.transform

          guard let resolved = resolvedTransform(
            sourceRef: sourceRef,
            targetRef: targetRef,
            sourceTransform: sourceTransform,
            sourceGeo: sourceGeo,
            targetGeo: targetGeo,
            targetStoredTransform: storedTargetTransform
          ) else { continue }

          solved[targetId] = resolved
          queue.append(targetId)
        }
      }

      for (scanId, transform) in solved {
        transformByScanId[scanId] = transform
      }
    }
  }

  private static func alignFloorToCanonicalAxes(
    floorScans: [FloorplanRoomScan],
    scansById: [UUID: FloorplanRoomScan],
    geometryByScanId: [UUID: FloorplanSegmentsFile],
    connections: [FloorplanRoomConnection],
    transformByScanId: inout [UUID: FloorplanRoomTransform]
  ) {
    let floorIds = Set(floorScans.map(\.id))
    let floorConnections = connections.filter { floorIds.contains($0.a.scanId) && floorIds.contains($0.b.scanId) }

    var adjacency: [UUID: [FloorplanRoomConnection]] = [:]
    for connection in floorConnections {
      adjacency[connection.a.scanId, default: []].append(connection)
      adjacency[connection.b.scanId, default: []].append(connection)
    }

    var visited: Set<UUID> = []
    let orderedScans = floorScans.sorted(by: { $0.createdAt < $1.createdAt })

    // Room-sequence tracking can legitimately produce a coherent shared-world layout even before
    // a passage connection is persisted. Keep those scans together so we do not snap each room
    // onto its own axis and accidentally tear the shared layout apart.
    for componentIds in implicitTrackedComponents(
      floorScans: floorScans,
      scansById: scansById,
      geometryByScanId: geometryByScanId
    ) {
      visited.formUnion(componentIds)
      guard trackedLayoutDisposition(componentIds: componentIds, geometryByScanId: geometryByScanId) != .preserveAll else {
        continue
      }

      alignComponentToCanonicalAxes(
        componentIds: componentIds,
        scansById: scansById,
        geometryByScanId: geometryByScanId,
        transformByScanId: &transformByScanId
      )
    }

    for scan in orderedScans {
      guard !visited.contains(scan.id) else { continue }

      let componentIds = connectedComponent(
        seed: scan.id,
        allowedIds: floorIds,
        adjacency: adjacency,
        visited: &visited
      )
      guard !componentIds.isEmpty else { continue }
      guard trackedLayoutDisposition(componentIds: componentIds, geometryByScanId: geometryByScanId) != .preserveAll else { continue }

      alignComponentToCanonicalAxes(
        componentIds: componentIds,
        scansById: scansById,
        geometryByScanId: geometryByScanId,
        transformByScanId: &transformByScanId
      )
    }
  }

  private static func connectedComponent(
    seed: UUID,
    allowedIds: Set<UUID>,
    adjacency: [UUID: [FloorplanRoomConnection]],
    visited: inout Set<UUID>
  ) -> Set<UUID> {
    var component: Set<UUID> = []
    var queue: [UUID] = [seed]
    visited.insert(seed)

    while !queue.isEmpty {
      let current = queue.removeFirst()
      component.insert(current)

      for connection in adjacency[current] ?? [] {
        let other = (connection.a.scanId == current) ? connection.b.scanId : connection.a.scanId
        guard allowedIds.contains(other), !visited.contains(other) else { continue }
        visited.insert(other)
        queue.append(other)
      }
    }

    return component
  }

  private static func implicitTrackedComponents(
    floorScans: [FloorplanRoomScan],
    scansById: [UUID: FloorplanRoomScan],
    geometryByScanId: [UUID: FloorplanSegmentsFile]
  ) -> [Set<UUID>] {
    let grouped = Dictionary(grouping: floorScans.compactMap { scan -> (Date, String, UUID)? in
      guard let geometry = geometryByScanId[scan.id],
            geometry.trackingSource == .roomSequenceSharedWorld,
            let trackingSessionId = normalizedTrackingSessionId(geometry.trackingSessionId) else {
        return nil
      }
      return (scan.createdAt, trackingSessionId, scan.id)
    }, by: \.1)

    return grouped.values
      .compactMap { entries -> (Date, Set<UUID>)? in
        let ids = Set(entries.map(\.2))
        guard ids.count > 1 else { return nil }
        let earliest = entries.map(\.0).min() ?? .distantFuture
        return (earliest, ids)
      }
      .sorted(by: { $0.0 < $1.0 })
      .map(\.1)
  }

  private static func alignComponentToCanonicalAxes(
    componentIds: Set<UUID>,
    scansById: [UUID: FloorplanRoomScan],
    geometryByScanId: [UUID: FloorplanSegmentsFile],
    transformByScanId: inout [UUID: FloorplanRoomTransform]
  ) {
    let orderedScans = componentIds.compactMap { scansById[$0] }.sorted(by: { $0.createdAt < $1.createdAt })
    guard let rootScan = orderedScans.first,
          let rootGeo = geometryByScanId[rootScan.id],
          let rootTransform = transformByScanId[rootScan.id],
          let axisLocal = dominantAxisAngle(for: rootGeo.segments) else { return }

    let worldAxis = normalizeAngle(rootTransform.rotationRadians + axisLocal)
    let delta = nearestOrthogonalDelta(for: worldAxis)
    guard abs(delta) >= 0.03 else { return }

    let anchorWorld = centroidLocal(from: rootGeo.segments).map {
      mapLocalPointToWorld($0, t: rootTransform)
    } ?? DPoint(x: rootTransform.translationX, y: rootTransform.translationY)

    for scan in orderedScans {
      guard let geo = geometryByScanId[scan.id],
            let transform = transformByScanId[scan.id] else { continue }
      transformByScanId[scan.id] = rotatedTransform(
        transform: transform,
        geometry: geo,
        anchorWorld: anchorWorld,
        deltaRadians: delta
      )
    }
  }

  private static func trackedLayoutDisposition(
    componentIds: Set<UUID>,
    geometryByScanId: [UUID: FloorplanSegmentsFile]
  ) -> TrackedLayoutDisposition {
    let trackingInfo = componentIds.compactMap { scanId -> (sessionId: String, source: FloorplanTrackingSource?)? in
      guard let geometry = geometryByScanId[scanId],
            let trackingSessionId = geometry.trackingSessionId?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trackingSessionId.isEmpty else {
        return nil
      }
      return (trackingSessionId, geometry.trackingSource)
    }
    guard trackingInfo.count == componentIds.count else { return .none }
    guard Set(trackingInfo.map(\.sessionId)).count == 1 else { return .none }

    if trackingInfo.contains(where: { $0.source == .roomSequenceSharedWorld }) {
      return .preserveRelativeAndAlignComponent
    }
    return .preserveAll
  }

  private static func normalizedTrackingSessionId(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func componentNeedsResolution(
    componentIds: Set<UUID>,
    connections: [FloorplanRoomConnection],
    scansById: [UUID: FloorplanRoomScan],
    geometryByScanId: [UUID: FloorplanSegmentsFile],
    transformByScanId: [UUID: FloorplanRoomTransform]
  ) -> Bool {
    let componentConnections = connections.filter {
      componentIds.contains($0.a.scanId) && componentIds.contains($0.b.scanId)
    }
    guard !componentConnections.isEmpty else { return false }

    return componentConnections.contains {
      !isConnectionSatisfiedInWorld(
        $0,
        scansById: scansById,
        geometryByScanId: geometryByScanId,
        transformByScanId: transformByScanId
      )
    }
  }

  private static func isConnectionUsable(
    _ connection: FloorplanRoomConnection,
    scansById: [UUID: FloorplanRoomScan],
    geometryByScanId: [UUID: FloorplanSegmentsFile]
  ) -> Bool {
    guard connection.a.scanId != connection.b.scanId else { return false }
    guard let scanA = scansById[connection.a.scanId],
          let scanB = scansById[connection.b.scanId] else { return false }
    guard scanA.floorId == scanB.floorId else { return false }
    guard let geoA = geometryByScanId[scanA.id],
          let geoB = geometryByScanId[scanB.id],
          let segA = passageSegmentLocal(for: connection.a, geometry: geoA),
          let segB = passageSegmentLocal(for: connection.b, geometry: geoB) else { return false }

    let lenA = segmentLength(segA)
    let lenB = segmentLength(segB)
    let maxLen = max(lenA, lenB)
    guard maxLen > 0.001 else { return false }
    return FloorplanAutoDockService.passageWidthsLookCompatible(
      kindA: connection.a.kind,
      lenA: lenA,
      kindB: connection.b.kind,
      lenB: lenB
    )
  }

  private static func isConnectionSatisfiedInWorld(
    _ connection: FloorplanRoomConnection,
    scansById: [UUID: FloorplanRoomScan],
    geometryByScanId: [UUID: FloorplanSegmentsFile],
    transformByScanId: [UUID: FloorplanRoomTransform]
  ) -> Bool {
    guard let scanA = scansById[connection.a.scanId],
          let scanB = scansById[connection.b.scanId],
          let geoA = geometryByScanId[scanA.id],
          let geoB = geometryByScanId[scanB.id],
          let segALocal = passageSegmentLocal(for: connection.a, geometry: geoA),
          let segBLocal = passageSegmentLocal(for: connection.b, geometry: geoB),
          let transformA = transformByScanId[scanA.id],
          let transformB = transformByScanId[scanB.id] else { return false }

    let segA = transformSegment(segLocal: segALocal, t: transformA)
    let segB = transformSegment(segLocal: segBLocal, t: transformB)
    let lenA = segmentLength(segA)
    let lenB = segmentLength(segB)
    let maxLen = max(lenA, lenB)
    guard maxLen > 0.001 else { return false }

    let directionDot = abs(dot(direction(segA), direction(segB)))
    let midpointDistance = distance(midpoint(segA), midpoint(segB))
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

  private static func resolvedTransform(
    sourceRef: FloorplanPassageRef,
    targetRef: FloorplanPassageRef,
    sourceTransform: FloorplanRoomTransform,
    sourceGeo: FloorplanSegmentsFile,
    targetGeo: FloorplanSegmentsFile,
    targetStoredTransform: FloorplanRoomTransform
  ) -> FloorplanRoomTransform? {
    guard let sourceSegLocal = passageSegmentLocal(for: sourceRef, geometry: sourceGeo),
          let targetSegLocal = passageSegmentLocal(for: targetRef, geometry: targetGeo) else { return nil }

    let sourceSegWorld = transformSegment(segLocal: sourceSegLocal, t: sourceTransform)
    let sourceMidWorld = midpoint(sourceSegWorld)
    let sourceDirWorld = normalized(direction(sourceSegWorld))
    let sourceThetaWorld = atan2(sourceDirWorld.y, sourceDirWorld.x)
    let targetThetaLocal = atan2(direction(targetSegLocal).y, direction(targetSegLocal).x)
    let targetMidLocal = midpoint(targetSegLocal)
    let sourceBoundsWorld = boundsWorld(segmentsLocal: sourceGeo.segments, t: sourceTransform)
    let sourceCentroidWorld = centroidLocal(from: sourceGeo.segments).map { mapLocalPointToWorld($0, t: sourceTransform) }
    let targetCentroidLocal = centroidLocal(from: targetGeo.segments)

    let rotations = [
      normalizeAngle(sourceThetaWorld - targetThetaLocal),
      normalizeAngle((sourceThetaWorld + Double.pi) - targetThetaLocal)
    ]

    var best: (score: Double, transform: FloorplanRoomTransform)? = nil
    for rotation in dedupedRotations(rotations) {
      let rotatedMid = rotatePoint(targetMidLocal, radians: rotation)
      let candidate = FloorplanRoomTransform(
        translationX: sourceMidWorld.x - rotatedMid.x,
        translationY: sourceMidWorld.y - rotatedMid.y,
        rotationRadians: rotation
      )

      let targetBoundsWorld = boundsWorld(segmentsLocal: targetGeo.segments, t: candidate)
      var score = FloorplanAutoDockService.transformDistanceMeters(a: candidate, b: targetStoredTransform) * 0.35
      score += abs(normalizeAngle(rotation - targetStoredTransform.rotationRadians)) * 1.2
      score += boundsOverlapRatio(a: sourceBoundsWorld, b: targetBoundsWorld) * 22.0

      if let sourceCentroidWorld, let targetCentroidLocal {
        let targetCentroidWorld = mapLocalPointToWorld(targetCentroidLocal, t: candidate)
        let sourceVector = DPoint(x: sourceCentroidWorld.x - sourceMidWorld.x, y: sourceCentroidWorld.y - sourceMidWorld.y)
        let targetVector = DPoint(x: targetCentroidWorld.x - sourceMidWorld.x, y: targetCentroidWorld.y - sourceMidWorld.y)
        let sourceCross = cross(sourceDirWorld, sourceVector)
        let targetCross = cross(sourceDirWorld, targetVector)
        let oppositeSides = sourceCross != 0 && targetCross != 0 && (sourceCross * targetCross) < 0
        if !oppositeSides {
          score += 28.0
        }
        score += sameSideLeakRatio(
          segmentsLocal: targetGeo.segments,
          t: candidate,
          linePoint: sourceMidWorld,
          lineDirection: sourceDirWorld,
          referenceCrossSign: sourceCross
        ) * 52.0
      }

      if best == nil || score < best!.score {
        best = (score, candidate)
      }
    }

    return best?.transform
  }

  private static func dedupedRotations(_ rotations: [Double]) -> [Double] {
    var out: [Double] = []
    for rotation in rotations {
      if out.contains(where: { abs(normalizeAngle($0 - rotation)) < 0.0001 }) {
        continue
      }
      out.append(rotation)
    }
    return out
  }

  private static func passageSegmentLocal(
    for ref: FloorplanPassageRef,
    geometry: FloorplanSegmentsFile
  ) -> FloorplanSegment? {
    switch ref.kind {
    case .door:
      return geometry.doors?.indices.contains(ref.index) == true ? geometry.doors?[ref.index] : nil
    case .opening:
      return geometry.openings?.indices.contains(ref.index) == true ? geometry.openings?[ref.index] : nil
    }
  }

  private static func centroidLocal(from segments: [FloorplanSegment]) -> DPoint? {
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

  private static func dominantAxisAngle(for segments: [FloorplanSegment]) -> Double? {
    var candidateAngles: [Double] = []
    var weightedSumX = 0.0
    var weightedSumY = 0.0
    var longest: (length: Double, angle: Double)?

    for segment in segments {
      let length = segmentLength(segment)
      guard length > 0.05 else { continue }
      let angle = normalizeQuarterTurnAngle(atan2(segment.by - segment.ay, segment.bx - segment.ax))
      candidateAngles.append(angle)
      weightedSumX += cos(angle * 4.0) * length
      weightedSumY += sin(angle * 4.0) * length

      if longest == nil || length > longest!.length {
        longest = (length, angle)
      }
    }

    guard !candidateAngles.isEmpty else { return nil }
    candidateAngles.append(normalizeQuarterTurnAngle(atan2(weightedSumY, weightedSumX) / 4.0))
    if let longest {
      candidateAngles.append(normalizeQuarterTurnAngle(longest.angle))
    }

    var best: (score: Double, angle: Double)?
    for candidate in candidateAngles {
      var score = 0.0
      for segment in segments {
        let length = segmentLength(segment)
        guard length > 0.05 else { continue }
        let angle = normalizeQuarterTurnAngle(atan2(segment.by - segment.ay, segment.bx - segment.ax))
        let residual = abs(normalizeQuarterTurnAngle(angle - candidate))
        score += residual * residual * length
      }

      if best == nil || score < best!.score {
        best = (score, candidate)
      }
    }

    return best?.angle
  }

  private static func nearestOrthogonalDelta(for angle: Double) -> Double {
    let quarterTurn = Double.pi / 2.0
    let snapped = (angle / quarterTurn).rounded() * quarterTurn
    return normalizeAngle(snapped - angle)
  }

  private static func normalizeQuarterTurnAngle(_ angle: Double) -> Double {
    var normalized = normalizeAngle(angle)
    while normalized > Double.pi / 4.0 { normalized -= Double.pi / 2.0 }
    while normalized < -Double.pi / 4.0 { normalized += Double.pi / 2.0 }
    return normalized
  }

  private static func boundsWorld(
    segmentsLocal: [FloorplanSegment],
    t: FloorplanRoomTransform
  ) -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
    var minX = Double.greatestFiniteMagnitude
    var minY = Double.greatestFiniteMagnitude
    var maxX = -Double.greatestFiniteMagnitude
    var maxY = -Double.greatestFiniteMagnitude

    for segment in segmentsLocal {
      let world = transformSegment(segLocal: segment, t: t)
      minX = min(minX, world.ax, world.bx)
      minY = min(minY, world.ay, world.by)
      maxX = max(maxX, world.ax, world.bx)
      maxY = max(maxY, world.ay, world.by)
    }

    if !minX.isFinite || !minY.isFinite || !maxX.isFinite || !maxY.isFinite {
      return (0, 0, 0, 0)
    }
    return (minX, minY, maxX, maxY)
  }

  private static func boundsOverlapRatio(
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

  private static func sameSideLeakRatio(
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
      let world = transformSegment(segLocal: segment, t: t)
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

  private static func transformSegment(
    segLocal: FloorplanSegment,
    t: FloorplanRoomTransform
  ) -> FloorplanSegment {
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

  private static func mapLocalPointToWorld(_ point: DPoint, t: FloorplanRoomTransform) -> DPoint {
    let rotated = rotatePoint(point, radians: t.rotationRadians)
    return DPoint(x: rotated.x + t.translationX, y: rotated.y + t.translationY)
  }

  private static func rotateWorldPoint(_ point: DPoint, around anchor: DPoint, radians: Double) -> DPoint {
    let translated = DPoint(x: point.x - anchor.x, y: point.y - anchor.y)
    let rotated = rotatePoint(translated, radians: radians)
    return DPoint(x: anchor.x + rotated.x, y: anchor.y + rotated.y)
  }

  private static func rotatedTransform(
    transform: FloorplanRoomTransform,
    geometry: FloorplanSegmentsFile,
    anchorWorld: DPoint,
    deltaRadians: Double
  ) -> FloorplanRoomTransform {
    let localAnchor = centroidLocal(from: geometry.segments) ?? DPoint(x: 0, y: 0)
    let currentAnchorWorld = mapLocalPointToWorld(localAnchor, t: transform)
    let nextAnchorWorld = rotateWorldPoint(currentAnchorWorld, around: anchorWorld, radians: deltaRadians)
    let nextRotation = normalizeAngle(transform.rotationRadians + deltaRadians)
    let rotatedLocalAnchor = rotatePoint(localAnchor, radians: nextRotation)
    return FloorplanRoomTransform(
      translationX: nextAnchorWorld.x - rotatedLocalAnchor.x,
      translationY: nextAnchorWorld.y - rotatedLocalAnchor.y,
      rotationRadians: nextRotation
    )
  }

  private static func rotatePoint(_ point: DPoint, radians: Double) -> DPoint {
    let cosR = cos(radians)
    let sinR = sin(radians)
    return DPoint(
      x: point.x * cosR - point.y * sinR,
      y: point.x * sinR + point.y * cosR
    )
  }

  private static func midpoint(_ segment: FloorplanSegment) -> DPoint {
    DPoint(x: (segment.ax + segment.bx) * 0.5, y: (segment.ay + segment.by) * 0.5)
  }

  private static func direction(_ segment: FloorplanSegment) -> DPoint {
    normalized(DPoint(x: segment.bx - segment.ax, y: segment.by - segment.ay))
  }

  private static func segmentLength(_ segment: FloorplanSegment) -> Double {
    let dx = segment.bx - segment.ax
    let dy = segment.by - segment.ay
    return (dx * dx + dy * dy).squareRoot()
  }

  private static func distance(_ a: DPoint, _ b: DPoint) -> Double {
    let dx = a.x - b.x
    let dy = a.y - b.y
    return (dx * dx + dy * dy).squareRoot()
  }

  private static func normalized(_ point: DPoint) -> DPoint {
    let len = (point.x * point.x + point.y * point.y).squareRoot()
    guard len > 1e-9 else { return DPoint(x: 1, y: 0) }
    return DPoint(x: point.x / len, y: point.y / len)
  }

  private static func dot(_ a: DPoint, _ b: DPoint) -> Double {
    a.x * b.x + a.y * b.y
  }

  private static func cross(_ a: DPoint, _ b: DPoint) -> Double {
    a.x * b.y - a.y * b.x
  }

  private static func normalizeAngle(_ value: Double) -> Double {
    var normalized = value
    while normalized > Double.pi { normalized -= 2 * Double.pi }
    while normalized < -Double.pi { normalized += 2 * Double.pi }
    return normalized
  }

  private struct DPoint: Hashable {
    let x: Double
    let y: Double
  }
}
