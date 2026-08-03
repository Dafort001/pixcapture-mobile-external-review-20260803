import Foundation
import Testing
@testable import PIXCAPTURE

struct VideoTrackingMetadataTests {

  @Test("VideoCaptureTake initializer derives tracking sidecar path from video path")
  func defaultTrackingPathFromInitializer() {
    let take = VideoCaptureTake(
      id: UUID(),
      createdAt: Date(),
      kind: .walkthrough,
      roomId: RoomTaxonomy.defaultRoomId,
      floorId: FloorTaxonomy.defaultFloorId,
      videoRelativePath: "video/take_abc.mov",
      motionRelativePath: "video/take_abc_sensors.csv",
      intrinsicsRelativePath: "video/take_abc_intrinsics.json"
    )
    #expect(take.trackingRelativePath == "video/take_abc_tracking.json")
  }

  @Test("Legacy capture JSON without trackingRelativePath falls back to derived path")
  func legacyDecodeFallback() throws {
    let json = """
    {
      "id": "46F6EA98-4512-4B87-97DA-D3A8A4CA3C35",
      "createdAt": "2026-02-19T12:00:00Z",
      "kind": "walkthrough",
      "roomId": "living_room",
      "floorId": "eg",
      "videoRelativePath": "video/take_legacy.mov",
      "motionRelativePath": "video/take_legacy_sensors.csv",
      "intrinsicsRelativePath": "video/take_legacy_intrinsics.json",
      "durationSeconds": 6.2,
      "finalRole": "primary",
      "priorityScore": 5,
      "sequenceIndex": 1,
      "editorNote": ""
    }
    """

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let take = try decoder.decode(VideoCaptureTake.self, from: Data(json.utf8))
    #expect(take.trackingRelativePath == "video/take_legacy_tracking.json")
  }

  @Test("Explicit trackingRelativePath survives encode/decode roundtrip")
  func explicitTrackingPathRoundtrip() throws {
    let input = VideoCaptureTake(
      id: UUID(uuidString: "81D87E51-44A4-422A-BE27-3B0FF8B5B2DE")!,
      createdAt: Date(timeIntervalSince1970: 1_739_970_000),
      kind: .detail,
      roomId: "kitchen",
      floorId: "og",
      videoRelativePath: "video/take_custom.mov",
      motionRelativePath: "video/take_custom_sensors.csv",
      intrinsicsRelativePath: "video/take_custom_intrinsics.json",
      trackingRelativePath: "video/custom_tracking.json",
      durationSeconds: 4.0,
      finalRole: .detail,
      priorityScore: 3,
      sequenceIndex: 2,
      editorNote: "test"
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(input)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(VideoCaptureTake.self, from: data)

    #expect(decoded.trackingRelativePath == "video/custom_tracking.json")
  }
}
