import Foundation
import Testing
@testable import PIXCAPTURE

struct PhotoUploadIndicesTests {

  @Test("Photo upload indices follow bracket exposure order")
  func resolvesExposureIndicesByExposureValue() {
    let seriesId = UUID(uuidString: "0F0E0D0C-0B0A-0908-0706-050403020100")!
    let records = [
      makeRecord(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
        seriesId: seriesId,
        filename: "livingroom-fl01-5-5.dng",
        seriesIndex: 3,
        exposureEV: 4.0
      ),
      makeRecord(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
        seriesId: seriesId,
        filename: "livingroom-fl01-1-5.dng",
        seriesIndex: 3,
        exposureEV: -4.0
      ),
      makeRecord(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!,
        seriesId: seriesId,
        filename: "livingroom-fl01-3-5.dng",
        seriesIndex: 3,
        exposureEV: 0.0
      ),
      makeRecord(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!,
        seriesId: seriesId,
        filename: "livingroom-fl01-2-5.dng",
        seriesIndex: 3,
        exposureEV: -2.0
      ),
      makeRecord(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000005")!,
        seriesId: seriesId,
        filename: "livingroom-fl01-4-5.dng",
        seriesIndex: 3,
        exposureEV: 2.0
      ),
    ]

    let resolved = resolvePhotoUploadIndices(records: records)

    #expect(resolved[records[0].id]?.motifIndex == 3)
    #expect(resolved[records[0].id]?.exposureIndex == 5)
    #expect(resolved[records[1].id]?.exposureIndex == 1)
    #expect(resolved[records[2].id]?.exposureIndex == 3)
    #expect(resolved[records[3].id]?.exposureIndex == 2)
    #expect(resolved[records[4].id]?.exposureIndex == 4)
  }

  @Test("Photo upload indices use filename as stable tiebreaker")
  func resolvesStableIndicesWhenExposureMatches() {
    let seriesId = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    let records = [
      makeRecord(
        id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
        seriesId: seriesId,
        filename: "livingroom-fl01-2-5.dng",
        seriesIndex: 1,
        exposureEV: 0.0
      ),
      makeRecord(
        id: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!,
        seriesId: seriesId,
        filename: "livingroom-fl01-1-5.dng",
        seriesIndex: 1,
        exposureEV: 0.0
      ),
    ]

    let resolved = resolvePhotoUploadIndices(records: records)

    #expect(resolved[records[1].id]?.exposureIndex == 1)
    #expect(resolved[records[0].id]?.exposureIndex == 2)
  }
}

private func makeRecord(
  id: UUID,
  seriesId: UUID,
  filename: String,
  seriesIndex: Int,
  exposureEV: Double
) -> UploadRecord {
  UploadRecord(
    id: id,
    seriesId: seriesId,
    localShootId: "shoot-test",
    fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(filename),
    originalFileURL: nil,
    exifLogURL: nil,
    roomId: "living_room",
    floorId: "eg",
    jobLabel: "Test Job",
    jobId: nil,
    seriesIndex: seriesIndex,
    exposureEV: exposureEV,
    exposureSeconds: 0.02,
    iso: 100,
    captureMode: .standardBracket,
    captureOrientation: "portrait",
    metadataReady: true,
    createdAt: Date(timeIntervalSince1970: 1_731_000_000),
    status: .pending,
    remoteKey: nil
  )
}
