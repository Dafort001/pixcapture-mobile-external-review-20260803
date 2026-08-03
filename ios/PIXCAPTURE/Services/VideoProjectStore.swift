import Foundation

struct VideoProjectPaths {
  let root: URL
  let lidarUSDZ: URL
  let floorplanPNG: URL
  let floorplanSegmentsJSON: URL
  let videoDir: URL
  let mainVideo: URL
  let motionCSV: URL
  let intrinsicsJSON: URL
  let trackingJSON: URL
  let acousticsWAV: URL
  let manifestUPJ: URL
  let capturesJSON: URL
}

struct VideoCapturePaths {
  let takeId: UUID
  let videoURL: URL
  let motionCSVURL: URL
  let intrinsicsJSONURL: URL
  let trackingJSONURL: URL
  let videoRelativePath: String
  let motionRelativePath: String
  let intrinsicsRelativePath: String
  let trackingRelativePath: String
}

enum VideoProjectStore {
  static func createProjectPaths(projectId: UUID) throws -> VideoProjectPaths {
    let base = try FileStore.ensureUserFilesDirectory()
    let root = base.appendingPathComponent("VideoProjects", isDirectory: true)
      .appendingPathComponent(projectId.uuidString, isDirectory: true)

    // Migrate legacy storage (older builds stored under internal app directories).
    try migrateLegacyProjectIfNeeded(projectId: projectId, newRoot: root)
    try ensureDirectory(root)

    let videoDir = root.appendingPathComponent("video", isDirectory: true)
    try ensureDirectory(videoDir)
    cleanupLegacyCaptureLayout(root: root, videoDir: videoDir)

    return VideoProjectPaths(
      root: root,
      lidarUSDZ: root.appendingPathComponent("scan.usdz"),
      floorplanPNG: root.appendingPathComponent("floorplan.png"),
      floorplanSegmentsJSON: root.appendingPathComponent("segments.json"),
      videoDir: videoDir,
      mainVideo: videoDir.appendingPathComponent("main_scan.mov"),
      motionCSV: root.appendingPathComponent("sensors.csv"),
      intrinsicsJSON: root.appendingPathComponent("intrinsics.json"),
      trackingJSON: root.appendingPathComponent("tracking.json"),
      acousticsWAV: root.appendingPathComponent("acoustics.wav"),
      manifestUPJ: root.appendingPathComponent("manifest.upj"),
      capturesJSON: root.appendingPathComponent("captures.json")
    )
  }

  static func createCapturePaths(projectId: UUID, takeId: UUID) throws -> VideoCapturePaths {
    let project = try createProjectPaths(projectId: projectId)
    let takeFolder = takeId.uuidString
    let takeFolderRel = "video/\(takeFolder)"
    let takeBaseRel = "\(takeFolderRel)/\(takeFolder)"
    let takeFolderURL = project.root.appendingPathComponent(takeFolderRel, isDirectory: true)
    try ensureDirectory(takeFolderURL)

    let videoRel = "\(takeBaseRel).mov"
    let motionRel = "\(takeBaseRel)_sensors.csv"
    let intrinsicsRel = "\(takeBaseRel)_intrinsics.json"
    let trackingRel = "\(takeBaseRel)_tracking.json"
    return VideoCapturePaths(
      takeId: takeId,
      videoURL: project.root.appendingPathComponent(videoRel),
      motionCSVURL: project.root.appendingPathComponent(motionRel),
      intrinsicsJSONURL: project.root.appendingPathComponent(intrinsicsRel),
      trackingJSONURL: project.root.appendingPathComponent(trackingRel),
      videoRelativePath: videoRel,
      motionRelativePath: motionRel,
      intrinsicsRelativePath: intrinsicsRel,
      trackingRelativePath: trackingRel
    )
  }

  static func isTakeFolderName(_ folderName: String) -> Bool {
    let trimmed = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
    if UUID(uuidString: trimmed) != nil {
      return true
    }

    if trimmed.lowercased().hasPrefix("take_") {
      let suffix = String(trimmed.dropFirst(5))
      if UUID(uuidString: suffix) != nil {
        return true
      }
    }

    return false
  }

  static func loadCaptures(projectId: UUID) throws -> [VideoCaptureTake] {
    let project = try createProjectPaths(projectId: projectId)
    guard FileManager.default.fileExists(atPath: project.capturesJSON.path) else { return [] }
    let data = try Data(contentsOf: project.capturesJSON)
    let captures = try JSONDecoder().decode([VideoCaptureTake].self, from: data)
    let filtered = captures.filter { !isLegacyCapturePath($0.videoRelativePath) }
    if filtered.count != captures.count {
      try? saveCaptures(projectId: projectId, captures: filtered)
    }
    return filtered
  }

  static func saveCaptures(projectId: UUID, captures: [VideoCaptureTake]) throws {
    let project = try createProjectPaths(projectId: projectId)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(captures)
    try data.write(to: project.capturesJSON, options: [.atomic])
  }

  static func deleteProjectCompletely(projectId: UUID) throws {
    let fm = FileManager.default
    var firstError: Error?

    for projectsRoot in allVideoProjectsRoots(fileManager: fm) {
      let projectURL = projectsRoot.appendingPathComponent(projectId.uuidString, isDirectory: true)
      guard fm.fileExists(atPath: projectURL.path) else { continue }
      do {
        try fm.removeItem(at: projectURL)
      } catch {
        if firstError == nil {
          firstError = error
        }
      }
    }

    if let firstError {
      throw firstError
    }
  }

  static func deleteAllProjectsCompletely() throws {
    let fm = FileManager.default
    var firstError: Error?

    for projectsRoot in allVideoProjectsRoots(fileManager: fm) {
      guard fm.fileExists(atPath: projectsRoot.path) else { continue }
      do {
        try fm.removeItem(at: projectsRoot)
      } catch {
        if firstError == nil {
          firstError = error
        }
      }
    }

    if let firstError {
      throw firstError
    }
  }

  private static func migrateLegacyProjectIfNeeded(projectId: UUID, newRoot: URL) throws {
    let fm = FileManager.default
    if fm.fileExists(atPath: newRoot.path) {
      return
    }

    for projectsRoot in legacyVideoProjectsRoots(fileManager: fm) {
      let legacy = projectsRoot.appendingPathComponent(projectId.uuidString, isDirectory: true)
      guard fm.fileExists(atPath: legacy.path) else { continue }

      // Ensure destination parent exists before moving.
      try ensureDirectory(newRoot.deletingLastPathComponent())
      do {
        try fm.moveItem(at: legacy, to: newRoot)
      } catch {
        // If move fails (e.g. cross-volume), fall back to copy+delete.
        try? fm.copyItem(at: legacy, to: newRoot)
        try? fm.removeItem(at: legacy)
      }
      return
    }
  }

  private static func allVideoProjectsRoots(fileManager fm: FileManager) -> [URL] {
    var roots: [URL] = []

    if let userBase = try? FileStore.ensureUserFilesDirectory() {
      roots.append(userBase.appendingPathComponent("VideoProjects", isDirectory: true))
    }
    roots.append(contentsOf: legacyVideoProjectsRoots(fileManager: fm))

    var uniquePaths = Set<String>()
    return roots.filter { url in
      let key = url.standardizedFileURL.path
      if uniquePaths.contains(key) {
        return false
      }
      uniquePaths.insert(key)
      return true
    }
  }

  private static func legacyVideoProjectsRoots(fileManager fm: FileManager) -> [URL] {
    let legacyBases: [URL] = [
      fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("PixCapture", isDirectory: true),
      fm.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("PixCapture", isDirectory: true)
    ].compactMap { $0 }
    return legacyBases.map { $0.appendingPathComponent("VideoProjects", isDirectory: true) }
  }

  private static func ensureDirectory(_ url: URL) throws {
    if !FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
  }

  private static func cleanupLegacyCaptureLayout(root: URL, videoDir: URL) {
    let fm = FileManager.default

    // Legacy root-level sidecar files from older builds.
    let legacyRootFiles = [
      "sensors.csv",
      "intrinsics.json",
      "tracking.json"
    ]
    for name in legacyRootFiles {
      let url = root.appendingPathComponent(name)
      if fm.fileExists(atPath: url.path) {
        try? fm.removeItem(at: url)
      }
    }

    // Legacy root-level main video from older builds.
    let legacyMainVideo = videoDir.appendingPathComponent("main_scan.mov")
    if fm.fileExists(atPath: legacyMainVideo.path) {
      try? fm.removeItem(at: legacyMainVideo)
    }

    // Legacy flat take files: video/take_<id>.mov + sidecars in the same folder.
    let items = (try? fm.contentsOfDirectory(
      at: videoDir,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    )) ?? []

    for url in items {
      let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
      if isDirectory { continue }

      let name = url.lastPathComponent.lowercased()
      let isLegacyTakeVideo = name.hasPrefix("take_") && url.pathExtension.lowercased() == "mov"
      let isLegacyTakeSensor = name.hasPrefix("take_") && name.hasSuffix("_sensors.csv")
      let isLegacyTakeIntrinsics = name.hasPrefix("take_") && name.hasSuffix("_intrinsics.json")
      let isLegacyTakeTracking = name.hasPrefix("take_") && name.hasSuffix("_tracking.json")

      if isLegacyTakeVideo || isLegacyTakeSensor || isLegacyTakeIntrinsics || isLegacyTakeTracking {
        try? fm.removeItem(at: url)
      }
    }
  }

  private static func isLegacyCapturePath(_ videoRelativePath: String) -> Bool {
    let normalized = videoRelativePath.lowercased()
    if normalized == "video/main_scan.mov" {
      return true
    }

    let ns = normalized as NSString
    let parent = ns.deletingLastPathComponent
    let filename = ns.lastPathComponent
    return parent == "video" && filename.hasPrefix("take_") && ns.pathExtension == "mov"
  }
}
