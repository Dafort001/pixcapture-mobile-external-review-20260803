import Foundation

struct FloorplanProjectPaths {
  let root: URL
  let roomsDir: URL
  let projectJSON: URL
  let combinedPNG: URL
  let combinedPDF: URL
  let visualPDF: URL
  let dataPDF: URL
  let dataCSV: URL
  let summaryCSV: URL
  let roomsCSV: URL
  let crmPropertyCSV: URL
  let crmRoomsCSV: URL
  let openImmoXML: URL
  let measurementsJSON: URL
}

struct FloorplanUserExportCopy {
  let directory: URL
  let files: [URL]
}

enum FloorplanProjectStore {
  static func projectPaths(projectKey: String) throws -> FloorplanProjectPaths {
    let base = try FileStore.ensureCaptureDirectory()
    let safeKey = try normalizedProjectKey(projectKey)

    let root = base
      .appendingPathComponent("FloorplanProjects", isDirectory: true)
      .appendingPathComponent(safeKey, isDirectory: true)
    try ensureDirectory(root)

    let roomsDir = root.appendingPathComponent("rooms", isDirectory: true)
    try ensureDirectory(roomsDir)

    return FloorplanProjectPaths(
      root: root,
      roomsDir: roomsDir,
      projectJSON: root.appendingPathComponent("project.json"),
      combinedPNG: root.appendingPathComponent("floorplan.png"),
      combinedPDF: root.appendingPathComponent("floorplan.pdf"),
      visualPDF: root.appendingPathComponent("floorplan_plan.pdf"),
      dataPDF: root.appendingPathComponent("floorplan_data.pdf"),
      dataCSV: root.appendingPathComponent("floorplan_data.csv"),
      summaryCSV: root.appendingPathComponent("floorplan_summary.csv"),
      roomsCSV: root.appendingPathComponent("floorplan_rooms.csv"),
      crmPropertyCSV: root.appendingPathComponent("floorplan_crm_property_import.csv"),
      crmRoomsCSV: root.appendingPathComponent("floorplan_crm_rooms_import.csv"),
      openImmoXML: root.appendingPathComponent("floorplan_openimmo.xml"),
      measurementsJSON: root.appendingPathComponent("measurements.json")
    )
  }

  static func loadOrCreate(projectKey: String) throws -> FloorplanProject {
    let normalizedProjectKey = try normalizedProjectKey(projectKey)
    let paths = try projectPaths(projectKey: normalizedProjectKey)
    if FileManager.default.fileExists(atPath: paths.projectJSON.path) {
      let data = try Data(contentsOf: paths.projectJSON)
      return try JSONDecoder().decode(FloorplanProject.self, from: data)
    }

    let project = FloorplanProject(
      version: 5,
      projectKey: normalizedProjectKey,
      createdAt: Date(),
      roomScans: [],
      connections: []
    )
    try save(project: project)
    return project
  }

  static func loadExisting(projectKey: String) throws -> (project: FloorplanProject, paths: FloorplanProjectPaths)? {
    let paths = try projectPaths(projectKey: projectKey)
    guard FileManager.default.fileExists(atPath: paths.projectJSON.path) else {
      return nil
    }
    let data = try Data(contentsOf: paths.projectJSON)
    let project = try JSONDecoder().decode(FloorplanProject.self, from: data)
    return (project, paths)
  }

  static func save(project: FloorplanProject) throws {
    let paths = try projectPaths(projectKey: project.projectKey)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(project)
    try data.write(to: paths.projectJSON, options: [.atomic])
  }

  static func loadMeasurements(projectKey: String) throws -> [FloorplanMeasurementRecord] {
    let paths = try projectPaths(projectKey: projectKey)
    guard FileManager.default.fileExists(atPath: paths.measurementsJSON.path) else {
      return []
    }
    let data = try Data(contentsOf: paths.measurementsJSON)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode([FloorplanMeasurementRecord].self, from: data)
  }

  static func saveMeasurements(projectKey: String, records: [FloorplanMeasurementRecord]) throws {
    let paths = try projectPaths(projectKey: projectKey)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(records)
    try data.write(to: paths.measurementsJSON, options: [.atomic])
  }

  static func appendMeasurement(projectKey: String, record: FloorplanMeasurementRecord) throws {
    var records = try loadMeasurements(projectKey: projectKey)
    records.append(record)
    try saveMeasurements(projectKey: projectKey, records: records)
  }

  static func normalizedLayout(project: FloorplanProject) -> FloorplanProject {
    FloorplanLayoutResolver.normalizedProject(project: project) { scan in
      guard let url = try? resolve(projectKey: project.projectKey, relativePath: scan.segmentsJSONPath),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(FloorplanSegmentsFile.self, from: data) else {
        return nil
      }
      return decoded
    }
  }

  static func roomScanDirectory(projectKey: String, scanId: UUID) throws -> URL {
    let paths = try projectPaths(projectKey: projectKey)
    let dir = paths.roomsDir.appendingPathComponent(scanId.uuidString, isDirectory: true)
    try ensureDirectory(dir)
    return dir
  }

  static func roomScanOutputPaths(projectKey: String, scanId: UUID) throws -> RoomPlanOutputPaths {
    let dir = try roomScanDirectory(projectKey: projectKey, scanId: scanId)
    return RoomPlanOutputPaths(
      usdz: dir.appendingPathComponent("scan.usdz"),
      floorplanPNG: dir.appendingPathComponent("floorplan.png"),
      segmentsJSON: dir.appendingPathComponent("segments.json"),
      capturedRoomDataJSON: dir.appendingPathComponent("captured_room_data.json"),
      capturedRoomJSON: dir.appendingPathComponent("captured_room.json")
    )
  }

  static func resolve(projectKey: String, relativePath: String) throws -> URL {
    let paths = try projectPaths(projectKey: projectKey)
    return paths.root.appendingPathComponent(relativePath)
  }

  static func resetWorkingDataAfterFinalExport(projectKey: String) throws {
    let normalizedProjectKey = try normalizedProjectKey(projectKey)
    let paths = try projectPaths(projectKey: normalizedProjectKey)
    let fm = FileManager.default

    if fm.fileExists(atPath: paths.roomsDir.path) {
      try fm.removeItem(at: paths.roomsDir)
    }
    try ensureDirectory(paths.roomsDir)

    let resetProject = FloorplanProject(
      version: 5,
      projectKey: normalizedProjectKey,
      createdAt: Date(),
      roomScans: [],
      connections: [],
      routePoints: [],
      stairConnections: []
    )
    try save(project: resetProject)
  }

  static func finalExportURLs(paths: FloorplanProjectPaths) -> [URL] {
    [
      paths.combinedPDF,
      paths.combinedPNG,
      paths.visualPDF,
      paths.dataPDF,
      paths.openImmoXML,
      paths.dataCSV,
      paths.summaryCSV,
      paths.roomsCSV,
      paths.crmPropertyCSV,
      paths.crmRoomsCSV
    ]
  }

  static func visualExportURLs(paths: FloorplanProjectPaths) -> [URL] {
    [paths.combinedPDF, paths.combinedPNG, paths.visualPDF]
  }

  static func dataExportURLs(paths: FloorplanProjectPaths) -> [URL] {
    [
      paths.dataPDF,
      paths.openImmoXML,
      paths.summaryCSV,
      paths.roomsCSV,
      paths.dataCSV,
      paths.crmPropertyCSV,
      paths.crmRoomsCSV
    ]
  }

  static func existingFiles(from urls: [URL]) -> [URL] {
    let fm = FileManager.default
    return urls.filter { url in
      var isDirectory: ObjCBool = false
      return fm.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }
  }

  static func copyFinalExportsToUserVisibleDirectory(projectKey: String, paths: FloorplanProjectPaths) throws -> FloorplanUserExportCopy {
    let safeKey = try normalizedProjectKey(projectKey)
    let exportRoot = try FileStore.ensureUserFilesDirectory()
      .appendingPathComponent("FloorplanExports", isDirectory: true)
      .appendingPathComponent(safeKey, isDirectory: true)
    try ensureDirectory(exportRoot)

    let fm = FileManager.default
    var copied: [URL] = []
    for sourceURL in existingFiles(from: finalExportURLs(paths: paths)) {
      let targetURL = exportRoot.appendingPathComponent(sourceURL.lastPathComponent)
      if fm.fileExists(atPath: targetURL.path) {
        try fm.removeItem(at: targetURL)
      }
      try fm.copyItem(at: sourceURL, to: targetURL)
      copied.append(targetURL)
    }

    guard !copied.isEmpty else {
      throw NSError(
        domain: "FloorplanProjectStore",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Keine fertigen Grundriss-Exportdateien gefunden."]
      )
    }

    return FloorplanUserExportCopy(directory: exportRoot, files: copied)
  }

  private static func ensureDirectory(_ url: URL) throws {
    if !FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
  }

  private static func sanitizeKey(_ value: String) -> String {
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
    let filtered = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
    let collapsed = String(filtered).replacingOccurrences(of: "__+", with: "_", options: .regularExpression)
    return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
  }

  private static func normalizedProjectKey(_ projectKey: String) throws -> String {
    let trimmed = projectKey.trimmingCharacters(in: .whitespacesAndNewlines)
    let safeKey = sanitizeKey(trimmed)
    guard !safeKey.isEmpty else {
      throw NSError(
        domain: "FloorplanProjectStore",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Grundriss-Projekte brauchen einen gueltigen Job-Schluessel."]
      )
    }
    return safeKey
  }
}
