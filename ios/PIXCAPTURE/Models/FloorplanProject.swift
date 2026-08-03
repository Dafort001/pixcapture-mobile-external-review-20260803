import Foundation

struct FloorplanMetrics: Codable, Hashable {
  var perimeterMeters: Double
  var widthMeters: Double
  var depthMeters: Double
  var areaSqmApprox: Double
}

struct FloorplanSegment: Codable, Hashable {
  var ax: Double
  var ay: Double
  var bx: Double
  var by: Double
}

struct FloorplanRoomTransform: Codable, Hashable {
  var translationX: Double
  var translationY: Double
  var rotationRadians: Double

  static let identity = FloorplanRoomTransform(translationX: 0, translationY: 0, rotationRadians: 0)
}

struct FloorplanRoomScan: Identifiable, Codable, Hashable {
  var id: UUID
  var roomId: String
  var floorId: String
  var createdAt: Date

  // Paths are stored relative to the project root so projects can be moved as a folder.
  var usdzPath: String
  var floorplanPNGPath: String
  var segmentsJSONPath: String
  var capturedRoomDataPath: String? = nil
  var capturedRoomJSONPath: String? = nil
  var capturedRoomIdentifier: String? = nil

  var metrics: FloorplanMetrics
  var transform: FloorplanRoomTransform
}

enum FloorplanPassageKind: String, Codable, Hashable {
  case door
  case opening
}

struct FloorplanPassageRef: Codable, Hashable {
  var scanId: UUID
  var kind: FloorplanPassageKind
  var index: Int
}

struct FloorplanRoomConnection: Identifiable, Codable, Hashable {
  var id: UUID
  var createdAt: Date
  var a: FloorplanPassageRef
  var b: FloorplanPassageRef
}

struct FloorplanRoutePoint: Identifiable, Codable, Hashable {
  var id: UUID
  var createdAt: Date
  var x: Double
  var y: Double
}

struct FloorplanStairConnection: Identifiable, Codable, Hashable {
  var id: UUID
  var createdAt: Date
  var x: Double
  var y: Double
  var fromFloorId: String
  var toFloorId: String
}

struct FloorplanProject: Codable, Hashable {
  var version: Int
  var projectKey: String
  var createdAt: Date
  var roomScans: [FloorplanRoomScan]
  // Persistent adjacency between rooms (door/opening pairs). Important for later video routes.
  var connections: [FloorplanRoomConnection]
  // Manual route points in world coordinates. Point order defines the intended camera path.
  var routePoints: [FloorplanRoutePoint]
  // Vertical links between floors (e.g. stairs).
  var stairConnections: [FloorplanStairConnection]

  private enum CodingKeys: String, CodingKey {
    case version
    case projectKey
    case createdAt
    case roomScans
    case connections
    case routePoints
    case stairConnections
  }

  init(
    version: Int,
    projectKey: String,
    createdAt: Date,
    roomScans: [FloorplanRoomScan],
    connections: [FloorplanRoomConnection] = [],
    routePoints: [FloorplanRoutePoint] = [],
    stairConnections: [FloorplanStairConnection] = []
  ) {
    self.version = version
    self.projectKey = projectKey
    self.createdAt = createdAt
    self.roomScans = roomScans
    self.connections = connections
    self.routePoints = routePoints
    self.stairConnections = stairConnections
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.version = (try? c.decode(Int.self, forKey: .version)) ?? 1
    self.projectKey = try c.decode(String.self, forKey: .projectKey)
    self.createdAt = try c.decode(Date.self, forKey: .createdAt)
    self.roomScans = (try? c.decode([FloorplanRoomScan].self, forKey: .roomScans)) ?? []
    self.connections = (try? c.decode([FloorplanRoomConnection].self, forKey: .connections)) ?? []
    self.routePoints = (try? c.decode([FloorplanRoutePoint].self, forKey: .routePoints)) ?? []
    self.stairConnections = (try? c.decode([FloorplanStairConnection].self, forKey: .stairConnections)) ?? []
  }
}
