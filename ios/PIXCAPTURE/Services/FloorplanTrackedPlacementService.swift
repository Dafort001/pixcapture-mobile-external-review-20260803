import Foundation

enum FloorplanTrackedPlacementService {
  static func trackedTransform(
    project: FloorplanProject,
    newGeo: FloorplanSegmentsFile,
    floorId: String,
    loadGeo: (_ scanId: UUID) -> FloorplanSegmentsFile?
  ) -> FloorplanRoomTransform? {
    guard let trackingSessionId = normalizedTrackingSessionId(newGeo.trackingSessionId),
          let newWorldOffsetX = newGeo.worldOffsetX,
          let newWorldOffsetY = newGeo.worldOffsetY else {
      return nil
    }

    let sameSessionScans = project.roomScans
      .filter { $0.floorId == floorId }
      .compactMap { scan -> (scan: FloorplanRoomScan, geo: FloorplanSegmentsFile)? in
        guard let geo = loadGeo(scan.id),
              normalizedTrackingSessionId(geo.trackingSessionId) == trackingSessionId,
              geo.worldOffsetX != nil,
              geo.worldOffsetY != nil else {
          return nil
        }
        return (scan, geo)
      }
      .sorted(by: { $0.scan.createdAt < $1.scan.createdAt })

    guard let base = sameSessionScans.first,
          let baseWorldOffsetX = base.geo.worldOffsetX,
          let baseWorldOffsetY = base.geo.worldOffsetY else {
      return nil
    }

    let deltaX = newWorldOffsetX - baseWorldOffsetX
    let deltaY = newWorldOffsetY - baseWorldOffsetY
    let displayDelta = displayDeltaRadians(baseTransform: base.scan.transform, baseGeo: base.geo)
    let rotatedDelta = rotate(x: deltaX, y: deltaY, radians: displayDelta)

    let resolvedRotation: Double = {
      guard let newWorldRotation = newGeo.worldRotationRadians else {
        return base.scan.transform.rotationRadians
      }
      return normalizeAngle(newWorldRotation + displayDelta)
    }()

    return FloorplanRoomTransform(
      translationX: base.scan.transform.translationX + rotatedDelta.x,
      translationY: base.scan.transform.translationY + rotatedDelta.y,
      rotationRadians: resolvedRotation
    )
  }

  private static func normalizedTrackingSessionId(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func rotate(x: Double, y: Double, radians: Double) -> (x: Double, y: Double) {
    let cosR = cos(radians)
    let sinR = sin(radians)
    return (
      x: x * cosR - y * sinR,
      y: x * sinR + y * cosR
    )
  }

  private static func displayDeltaRadians(
    baseTransform: FloorplanRoomTransform,
    baseGeo: FloorplanSegmentsFile
  ) -> Double {
    guard let baseWorldRotation = baseGeo.worldRotationRadians else {
      return baseTransform.rotationRadians
    }
    return normalizeAngle(baseTransform.rotationRadians - baseWorldRotation)
  }

  private static func normalizeAngle(_ value: Double) -> Double {
    var normalized = value
    while normalized > Double.pi { normalized -= 2 * Double.pi }
    while normalized < -Double.pi { normalized += 2 * Double.pi }
    return normalized
  }
}
