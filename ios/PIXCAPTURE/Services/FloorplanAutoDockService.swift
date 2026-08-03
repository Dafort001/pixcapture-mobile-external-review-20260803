import Foundation

// Shared auto-docking logic for placing a newly scanned room next to the previously scanned room
// using door/opening geometry. Used both by the single-room flow and the floor-scan flow.
enum FloorplanAutoDockService {
  struct Result {
    let transform: FloorplanRoomTransform
    let connection: FloorplanRoomConnection
  }

  private struct ScoredCandidate {
    let score: Double
    let transform: FloorplanRoomTransform
    let previousId: UUID
    let previousPassage: PassageCandidate
    let newPassage: PassageCandidate
    let matchesPreviousHint: Bool
    let matchesEntryHint: Bool
  }

  private struct PassageCandidate {
    let kind: FloorplanPassageKind
    let index: Int
    let seg: FloorplanSegment
  }

  private struct DPoint: Hashable {
    var x: Double
    var y: Double
  }

  private static let severeFootprintOverlapThreshold = 0.025

  static func bestAutoDock(
    project: FloorplanProject,
    newScanId: UUID,
    newGeo: FloorplanSegmentsFile,
    floorId: String,
    loadGeo: (_ scanId: UUID) -> FloorplanSegmentsFile?,
    preferredTransform: FloorplanRoomTransform? = nil,
    requiresTrackedAgreement: Bool = false
  ) -> Result? {
    let candidateRoomsSorted = project.roomScans
      .filter { $0.floorId == floorId }
      .sorted(by: { $0.createdAt < $1.createdAt })
    guard !candidateRoomsSorted.isEmpty else { return nil }

    let candidateRooms: [FloorplanRoomScan] = {
      if newGeo.previousRoomExitPassageHint != nil {
        return Array(candidateRoomsSorted.suffix(1))
      }
      return Array(candidateRoomsSorted.reversed())
    }()

    let previousHint = hintCandidate(from: newGeo.previousRoomExitPassageHint)
    let entryHint = hintCandidate(from: newGeo.entryPassageHint)

    let newPassages = passageCandidates(from: newGeo)
    guard !newPassages.isEmpty else { return nil }

    guard let newCentroidLocal = centroidLocal(from: newGeo.segments) else { return nil }

    var bestOverall: ScoredCandidate? = nil
    var bestAllHintsAligned: ScoredCandidate? = nil
    var bestPreviousHintAligned: ScoredCandidate? = nil
    var bestEntryHintAligned: ScoredCandidate? = nil

    for (candidateIndex, previous) in candidateRooms.enumerated() {
      guard let prevDecoded = loadGeo(previous.id) else { continue }
      let prevGeo = prevDecoded.normalizedForDisplay()
      let prevPassages = passageCandidates(from: prevGeo)
      guard !prevPassages.isEmpty,
            let prevCentroidLocal = centroidLocal(from: prevGeo.segments) else { continue }

      let prevCentroidWorld = mapLocalPointToWorld(prevCentroidLocal, t: previous.transform)
      let prevBoundsWorld = boundsWorld(segmentsLocal: prevGeo.segments, t: previous.transform)

      for a in prevPassages {
        let aWorld = transformSegment(segLocal: a.seg, t: previous.transform)
        let aMidWorld = midpoint(aWorld)
        let aDirWorld = normalized(direction(aWorld))
        let lenA = lengthMeters(aWorld)

        for b in newPassages {
          for (candidateT, rotDeltaAbs) in dockTransforms(
            sourceDirWorld: aDirWorld,
            sourceMidWorld: aMidWorld,
            targetSegLocal: b.seg
          ) {
            let preferredDistance = preferredTransform.map { transformDistanceMeters(a: candidateT, b: $0) } ?? 0
            let preferredRotationDelta = preferredTransform.map {
              abs(normalizeAngle(candidateT.rotationRadians - $0.rotationRadians))
            } ?? 0
            if requiresTrackedAgreement,
               preferredTransform != nil,
               !candidateRespectsTrackedPlacement(
                translationDelta: preferredDistance,
                rotationDelta: preferredRotationDelta,
                hasTrackedWorldRotation: newGeo.worldRotationRadians != nil
               ) {
              continue
            }

            let newCentroidWorld = mapLocalPointToWorld(newCentroidLocal, t: candidateT)
            let vOld = DPoint(x: prevCentroidWorld.x - aMidWorld.x, y: prevCentroidWorld.y - aMidWorld.y)
            let vNew = DPoint(x: newCentroidWorld.x - aMidWorld.x, y: newCentroidWorld.y - aMidWorld.y)
            let crossOld = cross(aDirWorld, vOld)
            let crossNew = cross(aDirWorld, vNew)
            let oppositeSides = (crossOld == 0 || crossNew == 0) ? false : (crossOld * crossNew) < 0
            let wrongSideRatio = sameSideLeakRatio(
              segmentsLocal: newGeo.segments,
              t: candidateT,
              linePoint: aMidWorld,
              lineDirection: aDirWorld,
              referenceCrossSign: crossOld
            )

            let newBoundsWorld = boundsWorld(segmentsLocal: newGeo.segments, t: candidateT)
            let overlapRatio = boundsOverlapRatio(a: prevBoundsWorld, b: newBoundsWorld)
            let footprintOverlap = footprintOverlapRatio(
              segmentsA: prevGeo.segments,
              transformA: previous.transform,
              segmentsB: newGeo.segments,
              transformB: candidateT
            )
            guard footprintOverlap <= severeFootprintOverlapThreshold else { continue }

            let lenB = lengthMeters(transformSegment(segLocal: b.seg, t: candidateT))
            let lenPenalty = abs(lenA - lenB) * 4.0
            let lateralOffset = abs(dot(aDirWorld, vNew) - dot(aDirWorld, vOld))

            var score = 0.0
            score += oppositeSides ? 0.0 : 35.0
            score += overlapRatio * 10.0
            score += footprintOverlap * 70.0
            score += wrongSideRatio * 56.0
            score += lenPenalty
            score += rotDeltaAbs * 0.8
            score += max(0.0, lateralOffset - 1.2) * 5.5
            score += Double(candidateIndex) * 0.75
            score += passageKindMismatchPenalty(kindA: a.kind, kindB: b.kind)
            if preferredTransform != nil {
              score += preferredDistance * (requiresTrackedAgreement ? 3.8 : 2.1)
              score += preferredRotationDelta * (requiresTrackedAgreement ? 6.4 : 3.2)
            }
            if a.kind == .opening && b.kind == .opening {
              score -= min(3.2, min(lenA, lenB) * 1.1)
            }
            let widthDiff = abs(lenA - lenB)
            if a.kind == b.kind {
              if widthDiff <= 0.20 {
                score -= 3.2
              } else if widthDiff <= 0.40 {
                score -= 1.4
              }
            }
            if previousHint != nil, !matchesHint(a, hint: previousHint) {
              if requiresTrackedAgreement {
                score += 1.25
              } else {
                score += (previousHint?.kind == .door) ? 9.0 : 4.25
              }
            }
            if previousHint == nil, entryHint != nil, !matchesHint(b, hint: entryHint) {
              score += 2.75
            }
            guard passageWidthsLookCompatible(kindA: a.kind, lenA: lenA, kindB: b.kind, lenB: lenB) else { continue }
            if overlapRatio > 0.16 {
              score += 18.0
            }
            if wrongSideRatio > 0.10 {
              score += 20.0
            }

            let scored = ScoredCandidate(
              score: score,
              transform: candidateT,
              previousId: previous.id,
              previousPassage: a,
              newPassage: b,
              matchesPreviousHint: matchesHint(a, hint: previousHint),
              matchesEntryHint: matchesHint(b, hint: entryHint)
            )

            if bestOverall == nil || score < bestOverall!.score {
              bestOverall = scored
            }

            let matchesAllProvidedHints =
              (previousHint == nil || scored.matchesPreviousHint) &&
              (entryHint == nil || scored.matchesEntryHint)
            if matchesAllProvidedHints,
               (bestAllHintsAligned == nil || score < bestAllHintsAligned!.score) {
              bestAllHintsAligned = scored
            }

            if previousHint != nil,
               scored.matchesPreviousHint,
               (bestPreviousHintAligned == nil || score < bestPreviousHintAligned!.score) {
              bestPreviousHintAligned = scored
            }

            if entryHint != nil,
               scored.matchesEntryHint,
               (bestEntryHintAligned == nil || score < bestEntryHintAligned!.score) {
              bestEntryHintAligned = scored
            }
          }
        }
      }
    }

    guard let bestOverall else {
      if requiresTrackedAgreement, let preferredTransform {
        return refinedTrackedPlacement(
          project: project,
          newScanId: newScanId,
          newGeo: newGeo,
          trackedTransform: preferredTransform,
          floorId: floorId,
          loadGeo: loadGeo
        )
      }
      return nil
    }
    let previousHintFavorMargin: Double = {
      guard let previousHint else { return 0.0 }
      if requiresTrackedAgreement {
        return previousHint.kind == .door ? 0.75 : 0.5
      }
      return previousHint.kind == .door ? 5.0 : 2.0
    }()

    let selected: ScoredCandidate = {
      if let bestAllHintsAligned,
         bestAllHintsAligned.score <= bestOverall.score + 0.6 {
        return bestAllHintsAligned
      }
      if let bestPreviousHintAligned,
         bestPreviousHintAligned.score <= bestOverall.score + previousHintFavorMargin {
        return bestPreviousHintAligned
      }
      if previousHint == nil,
         let bestEntryHintAligned,
         bestEntryHintAligned.score <= bestOverall.score + 0.75 {
        return bestEntryHintAligned
      }
      return bestOverall
    }()
    // Require at least "somewhat plausible" placement.
    guard selected.score <= 52 else {
      if requiresTrackedAgreement, let preferredTransform {
        return refinedTrackedPlacement(
          project: project,
          newScanId: newScanId,
          newGeo: newGeo,
          trackedTransform: preferredTransform,
          floorId: floorId,
          loadGeo: loadGeo
        )
      }
      return nil
    }

    let connection = FloorplanRoomConnection(
      id: UUID(),
      createdAt: Date(),
      a: FloorplanPassageRef(
        scanId: selected.previousId,
        kind: selected.previousPassage.kind,
        index: selected.previousPassage.index
      ),
      b: FloorplanPassageRef(
        scanId: newScanId,
        kind: selected.newPassage.kind,
        index: selected.newPassage.index
      )
    )
    return Result(transform: selected.transform, connection: connection)
  }

  static func transformDistanceMeters(a: FloorplanRoomTransform, b: FloorplanRoomTransform) -> Double {
    let dx = a.translationX - b.translationX
    let dy = a.translationY - b.translationY
    return (dx * dx + dy * dy).squareRoot()
  }

  static func placementHasSevereOverlap(
    project: FloorplanProject,
    newGeo: FloorplanSegmentsFile,
    newTransform: FloorplanRoomTransform,
    floorId: String,
    loadGeo: (_ scanId: UUID) -> FloorplanSegmentsFile?
  ) -> Bool {
    for existing in project.roomScans where existing.floorId == floorId {
      guard let existingDecoded = loadGeo(existing.id) else { continue }
      let existingGeo = existingDecoded.normalizedForDisplay()
      let overlap = footprintOverlapRatio(
        segmentsA: existingGeo.segments,
        transformA: existing.transform,
        segmentsB: newGeo.segments,
        transformB: newTransform
      )
      if overlap > severeFootprintOverlapThreshold {
        return true
      }
    }
    return false
  }

  static func bestConnectionForPlacedRoom(
    project: FloorplanProject,
    newScanId: UUID,
    newGeo: FloorplanSegmentsFile,
    newTransform: FloorplanRoomTransform,
    floorId: String,
    loadGeo: (_ scanId: UUID) -> FloorplanSegmentsFile?
  ) -> FloorplanRoomConnection? {
    let candidateRooms = project.roomScans
      .filter { $0.floorId == floorId }
      .sorted(by: { $0.createdAt > $1.createdAt })
    guard !candidateRooms.isEmpty else { return nil }

    let newPassages = passageCandidates(from: newGeo)
    guard !newPassages.isEmpty else { return nil }
    guard let newCentroidLocal = centroidLocal(from: newGeo.segments) else { return nil }

    let newCentroidWorld = mapLocalPointToWorld(newCentroidLocal, t: newTransform)
    let newBoundsWorld = boundsWorld(segmentsLocal: newGeo.segments, t: newTransform)

    var best: ScoredCandidate? = nil

    for (candidateIndex, previous) in candidateRooms.enumerated() {
      guard let prevDecoded = loadGeo(previous.id) else { continue }
      let prevGeo = prevDecoded.normalizedForDisplay()
      let prevPassages = passageCandidates(from: prevGeo)
      guard !prevPassages.isEmpty,
            let prevCentroidLocal = centroidLocal(from: prevGeo.segments) else { continue }

      let prevCentroidWorld = mapLocalPointToWorld(prevCentroidLocal, t: previous.transform)
      let prevBoundsWorld = boundsWorld(segmentsLocal: prevGeo.segments, t: previous.transform)

      for a in prevPassages {
        let aWorld = transformSegment(segLocal: a.seg, t: previous.transform)
        let aMidWorld = midpoint(aWorld)
        let aDirWorld = normalized(direction(aWorld))
        let lenA = lengthMeters(aWorld)
        let vOld = DPoint(x: prevCentroidWorld.x - aMidWorld.x, y: prevCentroidWorld.y - aMidWorld.y)
        let crossOld = cross(aDirWorld, vOld)

        for b in newPassages {
          let bWorld = transformSegment(segLocal: b.seg, t: newTransform)
          let bMidWorld = midpoint(bWorld)
          let lenB = lengthMeters(bWorld)
          guard passageWidthsLookCompatible(kindA: a.kind, lenA: lenA, kindB: b.kind, lenB: lenB) else { continue }

          let vNew = DPoint(x: newCentroidWorld.x - aMidWorld.x, y: newCentroidWorld.y - aMidWorld.y)
          let crossNew = cross(aDirWorld, vNew)
          let oppositeSides = (crossOld == 0 || crossNew == 0) ? false : (crossOld * crossNew) < 0
          let wrongSideRatio = sameSideLeakRatio(
            segmentsLocal: newGeo.segments,
            t: newTransform,
            linePoint: aMidWorld,
            lineDirection: aDirWorld,
            referenceCrossSign: crossOld
          )

          let midpointDistance = distance(aMidWorld, bMidWorld)
          let directionDot = abs(dot(aDirWorld, normalized(direction(bWorld))))
          let overlapRatio = boundsOverlapRatio(a: prevBoundsWorld, b: newBoundsWorld)
          let footprintOverlap = footprintOverlapRatio(
            segmentsA: prevGeo.segments,
            transformA: previous.transform,
            segmentsB: newGeo.segments,
            transformB: newTransform
          )
          guard footprintOverlap <= severeFootprintOverlapThreshold else { continue }
          let widthDiff = abs(lenA - lenB)

          var score = 0.0
          score += midpointDistance * 8.0
          score += (1.0 - min(1.0, directionDot)) * 18.0
          score += overlapRatio * 8.0
          score += footprintOverlap * 60.0
          score += wrongSideRatio * 44.0
          score += passageKindMismatchPenalty(kindA: a.kind, kindB: b.kind)
          score += max(0.0, widthDiff - 0.12) * 6.0
          score += Double(candidateIndex) * 0.5
          if !oppositeSides {
            score += 10.0
          }
          if a.kind == .opening && b.kind == .opening {
            score -= min(2.5, min(lenA, lenB))
          }
          if widthDiff <= 0.20 {
            score -= 2.0
          }
          if midpointDistance <= 0.35 {
            score -= 2.0
          }

          let scored = ScoredCandidate(
            score: score,
            transform: newTransform,
            previousId: previous.id,
            previousPassage: a,
            newPassage: b,
            matchesPreviousHint: false,
            matchesEntryHint: false
          )

          if best == nil || scored.score < best!.score {
            best = scored
          }
        }
      }
    }

    guard let best, best.score <= 26.0 else { return nil }
    return FloorplanRoomConnection(
      id: UUID(),
      createdAt: Date(),
      a: FloorplanPassageRef(
        scanId: best.previousId,
        kind: best.previousPassage.kind,
        index: best.previousPassage.index
      ),
      b: FloorplanPassageRef(
        scanId: newScanId,
        kind: best.newPassage.kind,
        index: best.newPassage.index
      )
    )
  }

  static func refinedTrackedPlacement(
    project: FloorplanProject,
    newScanId: UUID,
    newGeo: FloorplanSegmentsFile,
    trackedTransform: FloorplanRoomTransform,
    floorId: String,
    loadGeo: (_ scanId: UUID) -> FloorplanSegmentsFile?
  ) -> Result? {
    let candidateRooms = project.roomScans
      .filter { $0.floorId == floorId }
      .sorted(by: { $0.createdAt > $1.createdAt })
    guard !candidateRooms.isEmpty else { return nil }

    let trackingSessionId = normalizedTrackingSessionId(newGeo.trackingSessionId)
    let previousHint = hintCandidate(from: newGeo.previousRoomExitPassageHint)
    let entryHint = hintCandidate(from: newGeo.entryPassageHint)
    let newPassages = passageCandidates(from: newGeo)
    guard !newPassages.isEmpty,
          let newCentroidLocal = centroidLocal(from: newGeo.segments) else {
      return nil
    }

    var best: ScoredCandidate? = nil
    var bestSharesTrackedSession = false
    var bestSameTrackedOpeningPair: ScoredCandidate? = nil

    for (candidateIndex, previous) in candidateRooms.enumerated() {
      guard let prevDecoded = loadGeo(previous.id) else { continue }
      let prevGeo = prevDecoded.normalizedForDisplay()
      let prevPassages = passageCandidates(from: prevGeo)
      guard !prevPassages.isEmpty,
            let prevCentroidLocal = centroidLocal(from: prevGeo.segments) else {
        continue
      }

      let previousTrackingSessionId = normalizedTrackingSessionId(prevGeo.trackingSessionId)
      let sameTrackedSession = trackingSessionId != nil && previousTrackingSessionId == trackingSessionId
      let prevCentroidWorld = mapLocalPointToWorld(prevCentroidLocal, t: previous.transform)
      let prevBoundsWorld = boundsWorld(segmentsLocal: prevGeo.segments, t: previous.transform)

      for a in prevPassages {
        let aWorld = transformSegment(segLocal: a.seg, t: previous.transform)
        let aMidWorld = midpoint(aWorld)
        let aDirWorld = normalized(direction(aWorld))
        let lenA = lengthMeters(aWorld)
        let vOld = DPoint(x: prevCentroidWorld.x - aMidWorld.x, y: prevCentroidWorld.y - aMidWorld.y)
        let crossOld = cross(aDirWorld, vOld)

        for b in newPassages {
          let trackedPassageWorld = transformSegment(segLocal: b.seg, t: trackedTransform)
          let trackedMidpointDistance = distance(aMidWorld, midpoint(trackedPassageWorld))
          let trackedDirectionDot = abs(dot(aDirWorld, normalized(direction(trackedPassageWorld))))
          let maxTrackedMidpointDistance = sameTrackedSession ? 8.0 : 3.25
          guard trackedMidpointDistance <= maxTrackedMidpointDistance else { continue }
          guard trackedDirectionDot >= 0.62 else { continue }

          let lenBTracked = lengthMeters(trackedPassageWorld)
          guard passageWidthsLookCompatible(kindA: a.kind, lenA: lenA, kindB: b.kind, lenB: lenBTracked) else {
            continue
          }

          let candidateTransform = alignedTransformPreservingRotation(
            sourceMidWorld: aMidWorld,
            targetSegLocal: b.seg,
            rotationRadians: trackedTransform.rotationRadians
          )

          let translationDelta = transformDistanceMeters(a: candidateTransform, b: trackedTransform)
          let maxTranslationDelta = sameTrackedSession ? 8.0 : 3.5
          guard translationDelta <= maxTranslationDelta else { continue }

          let newBoundsWorld = boundsWorld(segmentsLocal: newGeo.segments, t: candidateTransform)
          let overlapRatio = boundsOverlapRatio(a: prevBoundsWorld, b: newBoundsWorld)
          let footprintOverlap = footprintOverlapRatio(
            segmentsA: prevGeo.segments,
            transformA: previous.transform,
            segmentsB: newGeo.segments,
            transformB: candidateTransform
          )
          let maxFootprintOverlap = sameTrackedSession ? 0.55 : severeFootprintOverlapThreshold
          guard footprintOverlap <= maxFootprintOverlap else { continue }

          let newCentroidWorld = mapLocalPointToWorld(newCentroidLocal, t: candidateTransform)
          let vNew = DPoint(x: newCentroidWorld.x - aMidWorld.x, y: newCentroidWorld.y - aMidWorld.y)
          let crossNew = cross(aDirWorld, vNew)
          let oppositeSides = (crossOld == 0 || crossNew == 0) ? false : (crossOld * crossNew) < 0
          let wrongSideRatio = sameSideLeakRatio(
            segmentsLocal: newGeo.segments,
            t: candidateTransform,
            linePoint: aMidWorld,
            lineDirection: aDirWorld,
            referenceCrossSign: crossOld
          )

          var score = 0.0
          score += trackedMidpointDistance * 8.5
          score += (1.0 - trackedDirectionDot) * 20.0
          score += translationDelta * 3.0
          score += overlapRatio * 10.0
          score += footprintOverlap * 70.0
          score += wrongSideRatio * 52.0
          score += passageKindMismatchPenalty(kindA: a.kind, kindB: b.kind)
          score += Double(candidateIndex) * 0.5
          if !oppositeSides {
            score += 9.0
          }
          if sameTrackedSession {
            score -= 3.5
          }
          if a.kind == .opening && b.kind == .opening {
            score -= sameTrackedSession ? 8.0 : 2.5
          }
          if previousHint != nil, !matchesHint(a, hint: previousHint) {
            score += sameTrackedSession ? 0.75 : 4.0
          }
          if entryHint != nil, !matchesHint(b, hint: entryHint) {
            score += 2.5
          }

          let scored = ScoredCandidate(
            score: score,
            transform: candidateTransform,
            previousId: previous.id,
            previousPassage: a,
            newPassage: b,
            matchesPreviousHint: matchesHint(a, hint: previousHint),
            matchesEntryHint: matchesHint(b, hint: entryHint)
          )

          if best == nil || scored.score < best!.score {
            best = scored
            bestSharesTrackedSession = sameTrackedSession
          }
          if sameTrackedSession,
             a.kind == .opening,
             b.kind == .opening {
            let currentMatchesEntryHint = scored.matchesEntryHint
            let bestMatchesEntryHint = bestSameTrackedOpeningPair?.matchesEntryHint ?? false
            if bestSameTrackedOpeningPair == nil ||
               (currentMatchesEntryHint && !bestMatchesEntryHint) ||
               (currentMatchesEntryHint == bestMatchesEntryHint && scored.score < bestSameTrackedOpeningPair!.score) {
              bestSameTrackedOpeningPair = scored
            }
          }
        }
      }
    }

    let selected = bestSameTrackedOpeningPair ?? best
    let maxAcceptedScore = bestSameTrackedOpeningPair != nil ? 220.0 : (bestSharesTrackedSession ? 95.0 : 34.0)
    guard let selected, selected.score <= maxAcceptedScore else { return nil }
    return Result(
      transform: selected.transform,
      connection: FloorplanRoomConnection(
        id: UUID(),
        createdAt: Date(),
        a: FloorplanPassageRef(
          scanId: selected.previousId,
          kind: selected.previousPassage.kind,
          index: selected.previousPassage.index
        ),
        b: FloorplanPassageRef(
          scanId: newScanId,
          kind: selected.newPassage.kind,
          index: selected.newPassage.index
        )
      )
    )
  }

  static func passageWidthsLookCompatible(
    kindA: FloorplanPassageKind,
    lenA: Double,
    kindB: FloorplanPassageKind,
    lenB: Double
  ) -> Bool {
    let widestPassage = max(lenA, lenB)
    let narrowestPassage = min(lenA, lenB)
    guard widestPassage > 0.001 else { return false }

    let widthRatio = narrowestPassage / widestPassage
    let widthDiff = abs(lenA - lenB)

    if kindA == kindB {
      switch kindA {
      case .door:
        return widthRatio >= 0.68 || widthDiff <= max(0.28, widestPassage * 0.22)
      case .opening:
        return widthRatio >= 0.54 || widthDiff <= max(0.55, widestPassage * 0.32)
      }
    }

    return widthRatio >= 0.50 || widthDiff <= max(0.70, widestPassage * 0.38)
  }

  static func passageKindMismatchPenalty(
    kindA: FloorplanPassageKind,
    kindB: FloorplanPassageKind
  ) -> Double {
    kindA == kindB ? 0.0 : 4.5
  }

  private static func candidateRespectsTrackedPlacement(
    translationDelta: Double,
    rotationDelta: Double,
    hasTrackedWorldRotation: Bool
  ) -> Bool {
    let maxTranslation = hasTrackedWorldRotation ? 2.6 : 3.6
    let maxRotation = hasTrackedWorldRotation ? 0.3 : 0.6
    return translationDelta <= maxTranslation && rotationDelta <= maxRotation
  }

  private static func hintCandidate(
    from hint: FloorplanEntryPassageHint?
  ) -> (kind: FloorplanPassageKind, index: Int)? {
    guard let hint else { return nil }
    let kind: FloorplanPassageKind? = {
      switch hint.kind {
      case "door": return .door
      case "opening": return .opening
      default: return nil
      }
    }()
    guard let kind else { return nil }
    return (kind, hint.index)
  }

  private static func matchesHint(
    _ candidate: PassageCandidate,
    hint: (kind: FloorplanPassageKind, index: Int)?
  ) -> Bool {
    guard let hint else { return false }
    return candidate.kind == hint.kind && candidate.index == hint.index
  }

  private static func passageCandidates(from geo: FloorplanSegmentsFile) -> [PassageCandidate] {
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

  private static func centroidLocal(from segments: [FloorplanSegment]) -> DPoint? {
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

  private static func boundsWorld(segmentsLocal: [FloorplanSegment], t: FloorplanRoomTransform) -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
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

  private static func footprintOverlapRatio(
    segmentsA: [FloorplanSegment],
    transformA: FloorplanRoomTransform,
    segmentsB: [FloorplanSegment],
    transformB: FloorplanRoomTransform
  ) -> Double {
    let hullA = convexHullWorld(segmentsLocal: segmentsA, t: transformA)
    let hullB = convexHullWorld(segmentsLocal: segmentsB, t: transformB)
    guard hullA.count >= 3, hullB.count >= 3 else { return 0 }

    let areaA = polygonArea(hullA)
    let areaB = polygonArea(hullB)
    guard areaA > 1e-6, areaB > 1e-6 else { return 0 }

    let intersection = convexPolygonIntersection(subject: hullA, clip: hullB)
    let intersectionArea = polygonArea(intersection)
    return intersectionArea / min(areaA, areaB)
  }

  private static func convexHullWorld(
    segmentsLocal: [FloorplanSegment],
    t: FloorplanRoomTransform
  ) -> [DPoint] {
    let points = uniquePoints(from: segmentsLocal)
    let sorted = points.sorted()
    guard sorted.count >= 3 else {
      return sorted.map { mapLocalPointToWorld(DPoint(x: $0.x, y: $0.y), t: t) }
    }

    func hullCross(_ o: Point, _ a: Point, _ b: Point) -> Double {
      (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
    }

    var lower: [Point] = []
    for point in sorted {
      while lower.count >= 2 && hullCross(lower[lower.count - 2], lower[lower.count - 1], point) <= 0 {
        lower.removeLast()
      }
      lower.append(point)
    }

    var upper: [Point] = []
    for point in sorted.reversed() {
      while upper.count >= 2 && hullCross(upper[upper.count - 2], upper[upper.count - 1], point) <= 0 {
        upper.removeLast()
      }
      upper.append(point)
    }

    var hull = Array(lower.dropLast() + upper.dropLast())
      .map { mapLocalPointToWorld(DPoint(x: $0.x, y: $0.y), t: t) }
    if polygonSignedArea(hull) < 0 {
      hull.reverse()
    }
    return hull
  }

  private struct Point: Comparable, Hashable {
    let x: Double
    let y: Double

    static func < (lhs: Point, rhs: Point) -> Bool {
      if lhs.x != rhs.x { return lhs.x < rhs.x }
      return lhs.y < rhs.y
    }
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

    for segment in segments {
      insert(Point(x: segment.ax, y: segment.ay))
      insert(Point(x: segment.bx, y: segment.by))
    }

    return points
  }

  private static func convexPolygonIntersection(
    subject: [DPoint],
    clip: [DPoint]
  ) -> [DPoint] {
    guard subject.count >= 3, clip.count >= 3 else { return [] }
    var output = subject

    for idx in 0..<clip.count {
      let clipA = clip[idx]
      let clipB = clip[(idx + 1) % clip.count]
      let input = output
      output = []
      guard !input.isEmpty else { break }

      var previous = input[input.count - 1]
      for current in input {
        let currentInside = isInsideConvexClip(current, edgeA: clipA, edgeB: clipB)
        let previousInside = isInsideConvexClip(previous, edgeA: clipA, edgeB: clipB)

        if currentInside {
          if !previousInside,
             let intersection = lineIntersection(previous, current, clipA, clipB) {
            output.append(intersection)
          }
          output.append(current)
        } else if previousInside,
                  let intersection = lineIntersection(previous, current, clipA, clipB) {
          output.append(intersection)
        }

        previous = current
      }
    }

    return output
  }

  private static func isInsideConvexClip(
    _ point: DPoint,
    edgeA: DPoint,
    edgeB: DPoint
  ) -> Bool {
    let edge = DPoint(x: edgeB.x - edgeA.x, y: edgeB.y - edgeA.y)
    let relative = DPoint(x: point.x - edgeA.x, y: point.y - edgeA.y)
    return cross(edge, relative) >= -1e-8
  }

  private static func lineIntersection(
    _ p1: DPoint,
    _ p2: DPoint,
    _ q1: DPoint,
    _ q2: DPoint
  ) -> DPoint? {
    let r = DPoint(x: p2.x - p1.x, y: p2.y - p1.y)
    let s = DPoint(x: q2.x - q1.x, y: q2.y - q1.y)
    let denom = cross(r, s)
    guard abs(denom) > 1e-9 else { return nil }
    let qp = DPoint(x: q1.x - p1.x, y: q1.y - p1.y)
    let t = cross(qp, s) / denom
    return DPoint(x: p1.x + t * r.x, y: p1.y + t * r.y)
  }

  private static func polygonSignedArea(_ points: [DPoint]) -> Double {
    guard points.count >= 3 else { return 0 }
    var sum = 0.0
    for idx in 0..<points.count {
      let next = points[(idx + 1) % points.count]
      sum += points[idx].x * next.y - next.x * points[idx].y
    }
    return sum * 0.5
  }

  private static func polygonArea(_ points: [DPoint]) -> Double {
    abs(polygonSignedArea(points))
  }

  private static func dockTransforms(
    sourceDirWorld: DPoint,
    sourceMidWorld: DPoint,
    targetSegLocal: FloorplanSegment
  ) -> [(FloorplanRoomTransform, Double)] {
    let sourceTheta = atan2(sourceDirWorld.y, sourceDirWorld.x)

    let targetDirLocal = direction(targetSegLocal)
    let targetThetaLocal = atan2(targetDirLocal.y, targetDirLocal.x)

    let diffA = normalizeAngle(sourceTheta - targetThetaLocal)
    let diffB = normalizeAngle((sourceTheta + Double.pi) - targetThetaLocal)

    let targetMidLocal = midpoint(targetSegLocal)
    let rotations = [diffA, diffB]
    var out: [(FloorplanRoomTransform, Double)] = []
    for rotation in rotations {
      if out.contains(where: { abs($0.0.rotationRadians - rotation) < 0.0001 }) {
        continue
      }
      let rotatedMid = rotatePoint(targetMidLocal, radians: rotation)
      let tx = sourceMidWorld.x - rotatedMid.x
      let ty = sourceMidWorld.y - rotatedMid.y
      out.append((
        FloorplanRoomTransform(
          translationX: tx,
          translationY: ty,
          rotationRadians: rotation
        ),
        abs(rotation)
      ))
    }
    return out
  }

  private static func alignedTransformPreservingRotation(
    sourceMidWorld: DPoint,
    targetSegLocal: FloorplanSegment,
    rotationRadians: Double
  ) -> FloorplanRoomTransform {
    let targetMidLocal = midpoint(targetSegLocal)
    let rotatedMid = rotatePoint(targetMidLocal, radians: rotationRadians)
    return FloorplanRoomTransform(
      translationX: sourceMidWorld.x - rotatedMid.x,
      translationY: sourceMidWorld.y - rotatedMid.y,
      rotationRadians: rotationRadians
    )
  }

  private static func transformSegment(segLocal: FloorplanSegment, t: FloorplanRoomTransform) -> FloorplanSegment {
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

  private static func mapLocalPointToWorld(_ p: DPoint, t: FloorplanRoomTransform) -> DPoint {
    let rotated = rotatePoint(p, radians: t.rotationRadians)
    return DPoint(x: rotated.x + t.translationX, y: rotated.y + t.translationY)
  }

  private static func rotatePoint(_ p: DPoint, radians: Double) -> DPoint {
    let cosR = cos(radians)
    let sinR = sin(radians)
    return DPoint(x: p.x * cosR - p.y * sinR, y: p.x * sinR + p.y * cosR)
  }

  private static func normalizeAngle(_ value: Double) -> Double {
    var v = value
    while v > Double.pi { v -= 2 * Double.pi }
    while v < -Double.pi { v += 2 * Double.pi }
    return v
  }

  private static func normalizedTrackingSessionId(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func midpoint(_ seg: FloorplanSegment) -> DPoint {
    DPoint(x: (seg.ax + seg.bx) * 0.5, y: (seg.ay + seg.by) * 0.5)
  }

  private static func direction(_ seg: FloorplanSegment) -> DPoint {
    let vx = seg.bx - seg.ax
    let vy = seg.by - seg.ay
    return normalized(DPoint(x: vx, y: vy))
  }

  private static func lengthMeters(_ seg: FloorplanSegment) -> Double {
    let dx = seg.bx - seg.ax
    let dy = seg.by - seg.ay
    return (dx * dx + dy * dy).squareRoot()
  }

  private static func normalized(_ v: DPoint) -> DPoint {
    let len = (v.x * v.x + v.y * v.y).squareRoot()
    guard len > 1e-9 else { return DPoint(x: 1, y: 0) }
    return DPoint(x: v.x / len, y: v.y / len)
  }

  private static func dot(_ a: DPoint, _ b: DPoint) -> Double {
    a.x * b.x + a.y * b.y
  }

  private static func distance(_ a: DPoint, _ b: DPoint) -> Double {
    let dx = a.x - b.x
    let dy = a.y - b.y
    return (dx * dx + dy * dy).squareRoot()
  }

  private static func cross(_ a: DPoint, _ b: DPoint) -> Double {
    a.x * b.y - a.y * b.x
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
}
