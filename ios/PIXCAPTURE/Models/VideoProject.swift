import Foundation

enum VideoCaptureKind: String, Codable, CaseIterable, Hashable, Identifiable {
  case walkthrough
  case cameraMove
  case detail

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .walkthrough:
      return NSLocalizedString("video.capture.kind.walkthrough", comment: "Walkthrough capture kind")
    case .cameraMove:
      return NSLocalizedString("video.capture.kind.cameraMove", comment: "Camera move capture kind")
    case .detail:
      return NSLocalizedString("video.capture.kind.detail", comment: "Detail capture kind")
    }
  }

  var icon: String {
    switch self {
    case .walkthrough:
      return "figure.walk"
    case .cameraMove:
      return "video"
    case .detail:
      return "scope"
    }
  }
}

enum VideoCaptureFinalRole: String, Codable, CaseIterable, Hashable, Identifiable {
  case primary
  case detail
  case excluded

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .primary:
      return NSLocalizedString("video.capture.finalRole.primary", comment: "Primary final role")
    case .detail:
      return NSLocalizedString("video.capture.finalRole.detail", comment: "Detail final role")
    case .excluded:
      return NSLocalizedString("video.capture.finalRole.excluded", comment: "Excluded final role")
    }
  }

  var icon: String {
    switch self {
    case .primary:
      return "star.fill"
    case .detail:
      return "smallcircle.filled.circle"
    case .excluded:
      return "xmark.circle"
    }
  }
}

struct VideoCaptureTake: Identifiable, Codable, Hashable {
  var id: UUID
  var createdAt: Date
  var kind: VideoCaptureKind
  var roomId: String
  var floorId: String
  // Paths are relative to VideoProject root to keep projects movable.
  var videoRelativePath: String
  var motionRelativePath: String
  var intrinsicsRelativePath: String
  var trackingRelativePath: String
  var durationSeconds: Double?
  // Final cut metadata: user can rank/select takes after recording.
  var finalRole: VideoCaptureFinalRole
  var priorityScore: Int
  var sequenceIndex: Int
  var editorNote: String

  init(
    id: UUID,
    createdAt: Date,
    kind: VideoCaptureKind,
    roomId: String,
    floorId: String,
    videoRelativePath: String,
    motionRelativePath: String,
    intrinsicsRelativePath: String,
    trackingRelativePath: String? = nil,
    durationSeconds: Double? = nil,
    finalRole: VideoCaptureFinalRole = .detail,
    priorityScore: Int = 3,
    sequenceIndex: Int = 0,
    editorNote: String = ""
  ) {
    self.id = id
    self.createdAt = createdAt
    self.kind = kind
    self.roomId = roomId
    self.floorId = floorId
    self.videoRelativePath = videoRelativePath
    self.motionRelativePath = motionRelativePath
    self.intrinsicsRelativePath = intrinsicsRelativePath
    self.trackingRelativePath = trackingRelativePath ?? Self.defaultTrackingRelativePath(for: videoRelativePath)
    self.durationSeconds = durationSeconds
    self.finalRole = finalRole
    self.priorityScore = min(max(priorityScore, 1), 5)
    self.sequenceIndex = max(sequenceIndex, 0)
    self.editorNote = editorNote
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case createdAt
    case kind
    case roomId
    case floorId
    case videoRelativePath
    case motionRelativePath
    case intrinsicsRelativePath
    case trackingRelativePath
    case durationSeconds
    case finalRole
    case priorityScore
    case sequenceIndex
    case editorNote
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(UUID.self, forKey: .id)
    createdAt = try c.decode(Date.self, forKey: .createdAt)
    kind = try c.decode(VideoCaptureKind.self, forKey: .kind)
    roomId = try c.decode(String.self, forKey: .roomId)
    floorId = try c.decode(String.self, forKey: .floorId)
    videoRelativePath = try c.decode(String.self, forKey: .videoRelativePath)
    motionRelativePath = try c.decode(String.self, forKey: .motionRelativePath)
    intrinsicsRelativePath = try c.decode(String.self, forKey: .intrinsicsRelativePath)
    trackingRelativePath = try c.decodeIfPresent(String.self, forKey: .trackingRelativePath) ?? Self.defaultTrackingRelativePath(for: videoRelativePath)
    durationSeconds = try c.decodeIfPresent(Double.self, forKey: .durationSeconds)

    let decodedRole = try c.decodeIfPresent(VideoCaptureFinalRole.self, forKey: .finalRole) ?? .detail
    let decodedPriority = try c.decodeIfPresent(Int.self, forKey: .priorityScore) ?? 3
    let decodedSequence = try c.decodeIfPresent(Int.self, forKey: .sequenceIndex) ?? 0
    let decodedNote = try c.decodeIfPresent(String.self, forKey: .editorNote) ?? ""

    finalRole = decodedRole
    priorityScore = min(max(decodedPriority, 1), 5)
    sequenceIndex = max(decodedSequence, 0)
    editorNote = decodedNote
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(id, forKey: .id)
    try c.encode(createdAt, forKey: .createdAt)
    try c.encode(kind, forKey: .kind)
    try c.encode(roomId, forKey: .roomId)
    try c.encode(floorId, forKey: .floorId)
    try c.encode(videoRelativePath, forKey: .videoRelativePath)
    try c.encode(motionRelativePath, forKey: .motionRelativePath)
    try c.encode(intrinsicsRelativePath, forKey: .intrinsicsRelativePath)
    try c.encode(trackingRelativePath, forKey: .trackingRelativePath)
    try c.encodeIfPresent(durationSeconds, forKey: .durationSeconds)
    try c.encode(finalRole, forKey: .finalRole)
    try c.encode(min(max(priorityScore, 1), 5), forKey: .priorityScore)
    try c.encode(max(sequenceIndex, 0), forKey: .sequenceIndex)
    try c.encode(editorNote, forKey: .editorNote)
  }

  var isIncludedInFinalCut: Bool {
    finalRole != .excluded
  }

  private static func defaultTrackingRelativePath(for videoRelativePath: String) -> String {
    let ns = videoRelativePath as NSString
    let ext = ns.pathExtension
    if !ext.isEmpty {
      let base = ns.deletingPathExtension
      return "\(base)_tracking.json"
    }
    return "\(videoRelativePath)_tracking.json"
  }
}

struct VideoProject: Identifiable {
  let id: UUID
  let createdAt: Date

  var jobId: String?
  var jobLabel: String
  var roomId: String
  var floorId: String

  var lidarUSDZURL: URL?
  var mainVideoURL: URL?
  var motionCSVURL: URL?
  var intrinsicsJSONURL: URL?
  var trackingJSONURL: URL?
  var captures: [VideoCaptureTake] = []

  init(
    id: UUID = UUID(),
    createdAt: Date = Date(),
    jobId: String?,
    jobLabel: String,
    roomId: String,
    floorId: String
  ) {
    self.id = id
    self.createdAt = createdAt
    self.jobId = jobId
    self.jobLabel = jobLabel
    self.roomId = roomId
    self.floorId = floorId
  }

  var preferredCapture: VideoCaptureTake? {
    let candidates = captures.filter { $0.finalRole != .excluded }
    guard !candidates.isEmpty else { return nil }

    let ordered = candidates.sorted { lhs, rhs in
      if lhs.sequenceIndex != rhs.sequenceIndex { return lhs.sequenceIndex < rhs.sequenceIndex }
      if lhs.priorityScore != rhs.priorityScore { return lhs.priorityScore > rhs.priorityScore }
      return lhs.createdAt < rhs.createdAt
    }

    if let primary = ordered.first(where: { $0.finalRole == .primary }) {
      return primary
    }
    return ordered.first(where: { $0.kind == .walkthrough }) ?? ordered.first
  }
}
