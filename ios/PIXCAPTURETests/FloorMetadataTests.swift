import Foundation
import Testing
@testable import PIXCAPTURE

struct FloorMetadataTests {

  @Test("Floor taxonomy normalizes unknown values to undefined")
  func floorNormalization() {
    #expect(FloorTaxonomy.normalizedFloorId("eg") == "eg")
    #expect(FloorTaxonomy.normalizedFloorId("invalid") == FloorTaxonomy.defaultFloorId)
    #expect(FloorTaxonomy.floor(id: "invalid").id == FloorTaxonomy.defaultFloorId)
  }

  @Test("Undefined floor uses dash token for filenames")
  func undefinedFloorToken() {
    let undefined = FloorTaxonomy.floor(id: FloorTaxonomy.defaultFloorId)
    #expect(undefined.fileToken == "--")
  }

  @Test("UploadRecord decoding without floorId falls back to undefined")
  @MainActor
  func uploadRecordLegacyDecodeFallback() throws {
    let json = """
    {
      "id": "4D3DA4B7-7478-4D21-9AFA-0730D030887A",
      "seriesId": "0E264787-2A4B-467D-BBD2-417C72726E89",
      "fileURL": "file:///tmp/test.heic",
      "roomId": "living_room",
      "jobLabel": "Ohne Job",
      "seriesIndex": 1,
      "exposureEV": 0.0,
      "exposureSeconds": 0.01,
      "iso": 100,
      "createdAt": "2026-02-11T10:00:00Z",
      "status": "pending"
    }
    """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let record = try decoder.decode(UploadRecord.self, from: Data(json.utf8))
    #expect(record.floorId == FloorTaxonomy.defaultFloorId)
  }
}
