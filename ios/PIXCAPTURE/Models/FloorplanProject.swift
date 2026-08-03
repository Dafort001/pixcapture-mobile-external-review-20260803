import Foundation

enum FloorplanAreaMethod: String, Codable, Hashable {
  case closedPolygon = "closed_polygon"
  case convexHullFallback = "convex_hull_fallback"
  case unavailable
}

struct FloorplanMetrics: Codable, Hashable {
  var perimeterMeters: Double
  var widthMeters: Double
  var depthMeters: Double
  var areaSqmApprox: Double
  var areaMethod: FloorplanAreaMethod? = nil
}

struct FloorplanSegment: Codable, Hashable {
  var ax: Double
  var ay: Double
  var bx: Double
  var by: Double
}

struct FloorplanPoint2D: Codable, Hashable {
  var x: Double
  var y: Double
}

struct FloorplanGeometryEvaluation: Hashable {
  var metrics: FloorplanMetrics
  var polygon: [FloorplanPoint2D]
}

enum FloorplanPolygonGeometry {
  static func evaluate(
    segments: [FloorplanSegment],
    endpointToleranceMeters: Double = 0.18
  ) -> FloorplanGeometryEvaluation {
    guard !segments.isEmpty else {
      return FloorplanGeometryEvaluation(
        metrics: FloorplanMetrics(
          perimeterMeters: 0,
          widthMeters: 0,
          depthMeters: 0,
          areaSqmApprox: 0,
          areaMethod: .unavailable
        ),
        polygon: []
      )
    }

    let endpoints = segments.flatMap {
      [FloorplanPoint2D(x: $0.ax, y: $0.ay), FloorplanPoint2D(x: $0.bx, y: $0.by)]
    }
    let xs = endpoints.map(\.x)
    let ys = endpoints.map(\.y)
    let width = max(0, (xs.max() ?? 0) - (xs.min() ?? 0))
    let depth = max(0, (ys.max() ?? 0) - (ys.min() ?? 0))
    let perimeter = segments.reduce(0.0) { partial, segment in
      partial + hypot(segment.bx - segment.ax, segment.by - segment.ay)
    }

    if let polygon = closedPolygon(from: segments, tolerance: max(endpointToleranceMeters, 0.001)) {
      return FloorplanGeometryEvaluation(
        metrics: FloorplanMetrics(
          perimeterMeters: perimeter,
          widthMeters: width,
          depthMeters: depth,
          areaSqmApprox: polygonArea(polygon),
          areaMethod: .closedPolygon
        ),
        polygon: polygon
      )
    }

    let hull = convexHull(endpoints)
    return FloorplanGeometryEvaluation(
      metrics: FloorplanMetrics(
        perimeterMeters: perimeter,
        widthMeters: width,
        depthMeters: depth,
        areaSqmApprox: polygonArea(hull),
        areaMethod: hull.count >= 3 ? .convexHullFallback : .unavailable
      ),
      polygon: hull
    )
  }

  static func segments(forClosedPolygon points: [FloorplanPoint2D]) -> [FloorplanSegment] {
    guard points.count >= 3 else { return [] }
    return points.indices.map { index in
      let a = points[index]
      let b = points[(index + 1) % points.count]
      return FloorplanSegment(ax: a.x, ay: a.y, bx: b.x, by: b.y)
    }
  }

  private struct Cluster {
    var point: FloorplanPoint2D
    var count: Int
  }

  private static func closedPolygon(
    from segments: [FloorplanSegment],
    tolerance: Double
  ) -> [FloorplanPoint2D]? {
    var clusters: [Cluster] = []

    func nearestCluster(to point: FloorplanPoint2D, in clusters: [Cluster]) -> Int? {
      clusters.indices
        .map { ($0, hypot(clusters[$0].point.x - point.x, clusters[$0].point.y - point.y)) }
        .filter { $0.1 <= tolerance }
        .min { $0.1 < $1.1 }?.0
    }

    func clusterIndex(for point: FloorplanPoint2D) -> Int {
      if let index = nearestCluster(to: point, in: clusters) {
        let old = clusters[index]
        let nextCount = old.count + 1
        clusters[index] = Cluster(
          point: FloorplanPoint2D(
            x: (old.point.x * Double(old.count) + point.x) / Double(nextCount),
            y: (old.point.y * Double(old.count) + point.y) / Double(nextCount)
          ),
          count: nextCount
        )
        return index
      }
      clusters.append(Cluster(point: point, count: 1))
      return clusters.count - 1
    }

    var edges: [(Int, Int)] = []
    for segment in segments {
      let a = clusterIndex(for: FloorplanPoint2D(x: segment.ax, y: segment.ay))
      let b = clusterIndex(for: FloorplanPoint2D(x: segment.bx, y: segment.by))
      if a != b { edges.append((a, b)) }
    }
    guard edges.count >= 3, edges.count == clusters.count else { return nil }

    var adjacency = Array(repeating: [Int](), count: clusters.count)
    for edge in edges {
      adjacency[edge.0].append(edge.1)
      adjacency[edge.1].append(edge.0)
    }
    guard adjacency.allSatisfy({ $0.count == 2 }) else { return nil }

    var order: [Int] = [0]
    var previous: Int? = nil
    var current = 0
    repeat {
      guard let next = adjacency[current].first(where: { $0 != previous }) else { return nil }
      previous = current
      current = next
      if current != 0 { order.append(current) }
      if order.count > clusters.count { return nil }
    } while current != 0

    guard order.count == clusters.count else { return nil }
    let polygon = order.map { clusters[$0].point }
    guard !hasSelfIntersection(polygon) else { return nil }
    return polygon
  }

  private static func hasSelfIntersection(_ polygon: [FloorplanPoint2D]) -> Bool {
    guard polygon.count >= 4 else { return false }
    for firstIndex in polygon.indices {
      let firstNext = (firstIndex + 1) % polygon.count
      for secondIndex in polygon.indices where secondIndex > firstIndex {
        let secondNext = (secondIndex + 1) % polygon.count
        if firstIndex == secondIndex || firstNext == secondIndex || secondNext == firstIndex {
          continue
        }
        if segmentsIntersect(
          polygon[firstIndex],
          polygon[firstNext],
          polygon[secondIndex],
          polygon[secondNext]
        ) {
          return true
        }
      }
    }
    return false
  }

  private static func segmentsIntersect(
    _ a: FloorplanPoint2D,
    _ b: FloorplanPoint2D,
    _ c: FloorplanPoint2D,
    _ d: FloorplanPoint2D
  ) -> Bool {
    func orientation(_ p: FloorplanPoint2D, _ q: FloorplanPoint2D, _ r: FloorplanPoint2D) -> Double {
      (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)
    }
    let o1 = orientation(a, b, c)
    let o2 = orientation(a, b, d)
    let o3 = orientation(c, d, a)
    let o4 = orientation(c, d, b)
    return ((o1 > 0 && o2 < 0) || (o1 < 0 && o2 > 0))
      && ((o3 > 0 && o4 < 0) || (o3 < 0 && o4 > 0))
  }

  private static func polygonArea(_ points: [FloorplanPoint2D]) -> Double {
    guard points.count >= 3 else { return 0 }
    let area2 = points.indices.reduce(0.0) { partial, index in
      let a = points[index]
      let b = points[(index + 1) % points.count]
      return partial + (a.x * b.y) - (b.x * a.y)
    }
    return abs(area2) * 0.5
  }

  private static func convexHull(_ points: [FloorplanPoint2D]) -> [FloorplanPoint2D] {
    let unique = Array(Set(points)).sorted { lhs, rhs in
      lhs.x == rhs.x ? lhs.y < rhs.y : lhs.x < rhs.x
    }
    guard unique.count > 2 else { return unique }
    func cross(_ o: FloorplanPoint2D, _ a: FloorplanPoint2D, _ b: FloorplanPoint2D) -> Double {
      (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
    }
    var lower: [FloorplanPoint2D] = []
    for point in unique {
      while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], point) <= 0 {
        lower.removeLast()
      }
      lower.append(point)
    }
    var upper: [FloorplanPoint2D] = []
    for point in unique.reversed() {
      while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], point) <= 0 {
        upper.removeLast()
      }
      upper.append(point)
    }
    lower.removeLast()
    upper.removeLast()
    return lower + upper
  }
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
