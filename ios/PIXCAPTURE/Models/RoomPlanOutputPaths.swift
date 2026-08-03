import Foundation

struct RoomPlanOutputPaths: Hashable {
  let usdz: URL
  let floorplanPNG: URL
  let segmentsJSON: URL
  let capturedRoomDataJSON: URL
  let capturedRoomJSON: URL
}
