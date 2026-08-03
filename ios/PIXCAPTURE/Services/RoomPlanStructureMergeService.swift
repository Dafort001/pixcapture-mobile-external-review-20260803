import Foundation
import os

#if canImport(RoomPlan)
import RoomPlan

enum RoomPlanStructureMergeService {
  private static let log = Logger(subsystem: "app.pixcapture.PIXCAPTURE", category: "RoomPlanStructureMerge")

  private struct TrackingGroupKey: Hashable {
    let floorId: String
    let trackingSessionId: String
  }

  private struct GroupEntry {
    let scanIndex: Int
    let scan: FloorplanRoomScan
    let segmentsFile: FloorplanSegmentsFile
    let capturedRoom: CapturedRoom
  }

  private struct RoomSignature {
    let wallCount: Int
    let doorCount: Int
    let openingCount: Int
    let windowCount: Int
    let areaSqmApprox: Double
    let perimeterMeters: Double
    let widthMeters: Double
    let depthMeters: Double
    let totalDoorWidthMeters: Double
    let totalOpeningWidthMeters: Double
    let totalWindowWidthMeters: Double
  }

  static func saveCapturedRoomData(_ data: CapturedRoomData, to url: URL) throws {
    try writeJSON(data, to: url)
  }

  static func saveCapturedRoom(_ room: CapturedRoom, to url: URL) throws {
    try writeJSON(room, to: url)
  }

  static func saveCapturedArtifactsBestEffort(
    data: CapturedRoomData,
    room: CapturedRoom,
    outputPaths: RoomPlanOutputPaths
  ) {
    do {
      try saveCapturedRoomData(data, to: outputPaths.capturedRoomDataJSON)
    } catch {
      try? FileManager.default.removeItem(at: outputPaths.capturedRoomDataJSON)
      log.error("Persisting CapturedRoomData failed: \(error.localizedDescription, privacy: .public)")
    }

    do {
      try saveCapturedRoom(room, to: outputPaths.capturedRoomJSON)
    } catch {
      try? FileManager.default.removeItem(at: outputPaths.capturedRoomJSON)
      log.error("Persisting CapturedRoom failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  static func loadCapturedRoom(from url: URL) throws -> CapturedRoom {
    let data = try Data(contentsOf: url)
    return try makeJSONDecoder().decode(CapturedRoom.self, from: data)
  }

  static func reconcileProject(
    projectKey: String,
    project: FloorplanProject
  ) async throws -> FloorplanProject {
    var updatedProject = project
    let groups = try loadTrackingGroups(projectKey: projectKey, project: updatedProject)
    guard !groups.isEmpty else { return project }

    var didApplyMerge = false

    for group in groups {
      do {
        let mergedRooms = try await mergedRooms(entries: group)
        let matchedRooms = matchedMergedRooms(entries: group, mergedRooms: mergedRooms)
        if matchedRooms.count != group.count {
          log.error(
            "RoomPlan merge produced only \(matchedRooms.count, privacy: .public) matches for \(group.count, privacy: .public) scans in session \(group.first?.segmentsFile.trackingSessionId ?? "unknown", privacy: .public)"
          )
        }
        for entry in group {
          guard let mergedRoom = matchedRooms[entry.scanIndex] else { continue }

          let mergedSegments = RoomPlanFloorplanRenderer.segmentsFile(
            capturedRoom: mergedRoom,
            entryPassageHint: entry.segmentsFile.entryPassageHint,
            previousRoomExitPassageHint: entry.segmentsFile.previousRoomExitPassageHint,
            trackingSessionId: entry.segmentsFile.trackingSessionId,
            trackingSource: entry.segmentsFile.trackingSource
          )

          let segmentsURL = try FloorplanProjectStore.resolve(
            projectKey: projectKey,
            relativePath: entry.scan.segmentsJSONPath
          )
          try RoomPlanFloorplanRenderer.writeSegmentsFile(mergedSegments, to: segmentsURL)

          updatedProject.roomScans[entry.scanIndex].metrics = mergedSegments.metrics
          updatedProject.roomScans[entry.scanIndex].transform = FloorplanRoomTransform(
            translationX: mergedSegments.worldOffsetX ?? entry.scan.transform.translationX,
            translationY: mergedSegments.worldOffsetY ?? entry.scan.transform.translationY,
            rotationRadians: 0
          )
          updatedProject.roomScans[entry.scanIndex].capturedRoomIdentifier = mergedRoom.identifier.uuidString
          didApplyMerge = true
        }
      } catch {
        log.error("Structure merge failed for session \(group.first?.segmentsFile.trackingSessionId ?? "unknown", privacy: .public): \(error.localizedDescription, privacy: .public)")
      }
    }

    guard didApplyMerge else { return project }
    return FloorplanProjectStore.normalizedLayout(project: updatedProject)
  }

  private static func mergedRooms(entries: [GroupEntry]) async throws -> [CapturedRoom] {
    let builder = StructureBuilder(options: [])
    let structure = try await builder.capturedStructure(from: entries.map(\.capturedRoom))
    return structure.rooms
  }

  private static func matchedMergedRooms(
    entries: [GroupEntry],
    mergedRooms: [CapturedRoom]
  ) -> [Int: CapturedRoom] {
    guard !entries.isEmpty, !mergedRooms.isEmpty else { return [:] }

    var matches: [Int: CapturedRoom] = [:]
    var remainingEntries = entries
    var remainingRooms = mergedRooms

    // Prefer a stable identifier match if RoomPlan preserved identifiers through the merge.
    if !remainingRooms.isEmpty {
      let roomsByIdentifier = Dictionary(
        uniqueKeysWithValues: remainingRooms.map { room in
          (normalizedIdentifier(room.identifier), room)
        }
      )

      var directlyMatchedEntryIds: Set<Int> = []
      var directlyMatchedRoomIds: Set<String> = []
      for entry in remainingEntries {
        guard let storedIdentifier = normalizedIdentifierString(entry.scan.capturedRoomIdentifier),
              let room = roomsByIdentifier[storedIdentifier] else {
          continue
        }
        matches[entry.scanIndex] = room
        directlyMatchedEntryIds.insert(entry.scanIndex)
        directlyMatchedRoomIds.insert(normalizedIdentifier(room.identifier))
      }

      if !directlyMatchedEntryIds.isEmpty {
        remainingEntries.removeAll { directlyMatchedEntryIds.contains($0.scanIndex) }
        remainingRooms.removeAll { directlyMatchedRoomIds.contains(normalizedIdentifier($0.identifier)) }
      }
    }

    guard !remainingEntries.isEmpty, !remainingRooms.isEmpty else { return matches }

    let mergedSignatures = remainingRooms.map { room in
      (room: room, signature: signature(for: RoomPlanFloorplanRenderer.segmentsFile(capturedRoom: room)))
    }

    struct ScoredPair {
      let score: Double
      let entryIndex: Int
      let mergedIndex: Int
    }

    let scoredPairs: [ScoredPair] = remainingEntries.enumerated().flatMap { entryOffset, entry in
      let entrySignature = signature(for: entry.segmentsFile)
      return mergedSignatures.enumerated().map { mergedOffset, merged in
        ScoredPair(
          score: signatureDistance(entrySignature, merged.signature),
          entryIndex: entryOffset,
          mergedIndex: mergedOffset
        )
      }
    }
    .sorted { lhs, rhs in
      if lhs.score != rhs.score { return lhs.score < rhs.score }
      if lhs.entryIndex != rhs.entryIndex { return lhs.entryIndex < rhs.entryIndex }
      return lhs.mergedIndex < rhs.mergedIndex
    }

    var usedEntryOffsets: Set<Int> = []
    var usedMergedOffsets: Set<Int> = []
    for pair in scoredPairs {
      guard !usedEntryOffsets.contains(pair.entryIndex),
            !usedMergedOffsets.contains(pair.mergedIndex) else { continue }
      let entry = remainingEntries[pair.entryIndex]
      matches[entry.scanIndex] = mergedSignatures[pair.mergedIndex].room
      usedEntryOffsets.insert(pair.entryIndex)
      usedMergedOffsets.insert(pair.mergedIndex)
    }

    return matches
  }

  private static func signature(for segmentsFile: FloorplanSegmentsFile) -> RoomSignature {
    RoomSignature(
      wallCount: segmentsFile.segments.count,
      doorCount: segmentsFile.doors?.count ?? 0,
      openingCount: segmentsFile.openings?.count ?? 0,
      windowCount: segmentsFile.windows?.count ?? 0,
      areaSqmApprox: segmentsFile.metrics.areaSqmApprox,
      perimeterMeters: segmentsFile.metrics.perimeterMeters,
      widthMeters: segmentsFile.metrics.widthMeters,
      depthMeters: segmentsFile.metrics.depthMeters,
      totalDoorWidthMeters: totalWidth(of: segmentsFile.doors),
      totalOpeningWidthMeters: totalWidth(of: segmentsFile.openings),
      totalWindowWidthMeters: totalWidth(of: segmentsFile.windows)
    )
  }

  private static func signatureDistance(_ lhs: RoomSignature, _ rhs: RoomSignature) -> Double {
    var score = 0.0
    score += Double(abs(lhs.wallCount - rhs.wallCount)) * 12.0
    score += Double(abs(lhs.doorCount - rhs.doorCount)) * 10.0
    score += Double(abs(lhs.openingCount - rhs.openingCount)) * 10.0
    score += Double(abs(lhs.windowCount - rhs.windowCount)) * 4.0
    score += abs(lhs.areaSqmApprox - rhs.areaSqmApprox) * 2.2
    score += abs(lhs.perimeterMeters - rhs.perimeterMeters) * 1.6
    score += abs(lhs.widthMeters - rhs.widthMeters) * 1.4
    score += abs(lhs.depthMeters - rhs.depthMeters) * 1.4
    score += abs(lhs.totalDoorWidthMeters - rhs.totalDoorWidthMeters) * 4.0
    score += abs(lhs.totalOpeningWidthMeters - rhs.totalOpeningWidthMeters) * 4.0
    score += abs(lhs.totalWindowWidthMeters - rhs.totalWindowWidthMeters) * 1.8
    return score
  }

  private static func totalWidth(of segments: [FloorplanSegment]?) -> Double {
    guard let segments else { return 0 }
    return segments.reduce(0) { partial, segment in
      let dx = segment.bx - segment.ax
      let dy = segment.by - segment.ay
      return partial + (dx * dx + dy * dy).squareRoot()
    }
  }

  private static func loadTrackingGroups(
    projectKey: String,
    project: FloorplanProject
  ) throws -> [[GroupEntry]] {
    let decoder = makeJSONDecoder()
    var grouped: [TrackingGroupKey: [GroupEntry]] = [:]

    for (index, scan) in project.roomScans.enumerated() {
      guard let capturedRoomJSONPath = scan.capturedRoomJSONPath,
            !capturedRoomJSONPath.isEmpty else { continue }

      let segmentsURL = try FloorplanProjectStore.resolve(projectKey: projectKey, relativePath: scan.segmentsJSONPath)
      let capturedRoomURL = try FloorplanProjectStore.resolve(projectKey: projectKey, relativePath: capturedRoomJSONPath)
      guard FileManager.default.fileExists(atPath: segmentsURL.path),
            FileManager.default.fileExists(atPath: capturedRoomURL.path) else { continue }

      let segmentsData = try Data(contentsOf: segmentsURL)
      let segmentsFile = try decoder.decode(FloorplanSegmentsFile.self, from: segmentsData)
      guard let trackingSessionId = normalizedTrackingSessionId(segmentsFile.trackingSessionId) else { continue }

      let capturedRoomData = try Data(contentsOf: capturedRoomURL)
      let capturedRoom = try decoder.decode(CapturedRoom.self, from: capturedRoomData)

      let key = TrackingGroupKey(
        floorId: scan.floorId,
        trackingSessionId: trackingSessionId
      )
      grouped[key, default: []].append(
        GroupEntry(
          scanIndex: index,
          scan: scan,
          segmentsFile: segmentsFile,
          capturedRoom: capturedRoom
        )
      )
    }

    return grouped.values
      .filter { $0.count > 1 }
      .sorted {
        let lhs = $0.map(\.scan.createdAt).min() ?? .distantFuture
        let rhs = $1.map(\.scan.createdAt).min() ?? .distantFuture
        return lhs < rhs
      }
  }

  private static func normalizedTrackingSessionId(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func normalizedIdentifier(_ value: UUID) -> String {
    value.uuidString.lowercased()
  }

  private static func normalizedIdentifierString(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed.lowercased()
  }

  private static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = makeJSONEncoder()
    let data = try encoder.encode(value)
    try data.write(to: url, options: [.atomic])
  }

  private static func makeJSONEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.nonConformingFloatEncodingStrategy = .convertToString(
      positiveInfinity: "Infinity",
      negativeInfinity: "-Infinity",
      nan: "NaN"
    )
    return encoder
  }

  private static func makeJSONDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.nonConformingFloatDecodingStrategy = .convertFromString(
      positiveInfinity: "Infinity",
      negativeInfinity: "-Infinity",
      nan: "NaN"
    )
    return decoder
  }
}
#endif
