import Foundation
import UIKit

enum FloorplanComposerRenderer {
  struct CombinedResult {
    let pngURL: URL
    let pdfURL: URL
    let metricsText: String
  }

  private struct ExportMetadata {
    let projectKey: String
    let projectName: String
    let jobId: String
    let jobAddress: String
    let projectCreatedAt: Date
    let generatedAt: Date

    var propertyExternalId: String {
      let normalizedJobId = jobId.trimmingCharacters(in: .whitespacesAndNewlines)
      if !normalizedJobId.isEmpty { return normalizedJobId }
      return projectKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
  }

  private struct HeaderStats {
    let totalArea: Double
    let livingArea: Double
    let totalPerimeter: Double
    let roomCount: Int
    let routePointCount: Int

    var headlineText: String {
      String(
        format: "BEMASSTER GRUNDRISS   ·   RÄUME: %d   ·   WEGPUNKTE: %d",
        max(roomCount, 0),
        max(routePointCount, 0)
      )
    }

    var sublineText: String {
      "Maßangaben dienen der Grundrissdarstellung · keine Wohnflächenberechnung"
    }

    var exportText: String {
      String(
        format: "Bemaßter Grundriss | Räume: %d | Wegpunkte: %d | keine Wohnflächenberechnung",
        max(roomCount, 0),
        max(routePointCount, 0)
      )
    }
  }

  static func exportCombinedFloorplan(
    project: FloorplanProject,
    outputPNG: URL,
    outputVisualPDF: URL,
    legacyOutputURLs: [URL],
    exportTitle: String,
    resolveURL: (String) throws -> URL
  ) throws -> CombinedResult {
    let resolvedProject = FloorplanLayoutResolver.normalizedProject(project: project) { scan in
      guard let url = try? resolveURL(scan.segmentsJSONPath),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(FloorplanSegmentsFile.self, from: data) else {
        return nil
      }
      return decoded
    }

    let rooms = try loadRoomSegments(project: resolvedProject, resolveURL: resolveURL)
    let stats = buildStats(project: resolvedProject, rooms: rooms)
    let metricsText = stats.exportText
    let routePoints = resolvedProject.routePoints.map { DPoint(x: $0.x, y: $0.y) }
    // PNG
    try renderPNG(
      rooms: rooms,
      routePoints: routePoints,
      stairConnections: resolvedProject.stairConnections,
      outputURL: outputPNG,
      title: exportTitle,
      headerStats: stats
    )

    // The public handoff contains only a measured drawing. Area calculations,
    // WoFlV, job/address data and CRM/OpenImmo payloads remain outside it.
    try renderPlanPDF(
      rooms: rooms,
      routePoints: routePoints,
      stairConnections: resolvedProject.stairConnections,
      outputURL: outputVisualPDF,
      title: exportTitle,
      headerStats: stats
    )

    for legacyURL in legacyOutputURLs where FileManager.default.fileExists(atPath: legacyURL.path) {
      try FileManager.default.removeItem(at: legacyURL)
    }

    return CombinedResult(pngURL: outputPNG, pdfURL: outputVisualPDF, metricsText: metricsText)
  }

  struct RoomSegments {
    let scan: FloorplanRoomScan
    let segments: [FloorplanSegment]
    let metrics: FloorplanMetrics
    let doors: [FloorplanSegment]
    let openings: [FloorplanSegment]
    let windows: [FloorplanSegment]
    let doorSwingOverrides: [FloorplanDoorSwingOverride]
  }

  private struct RoomReportEntry {
    let roomId: String
    let roomName: String
    let floorId: String
    let floorName: String
    let areaSqm: Double
    let livingAreaFactor: Double
    let livingAreaSqm: Double
    let perimeterMeters: Double
    let widthMeters: Double
    let depthMeters: Double
    let doorWidths: [Double]
    let openingWidths: [Double]
    let windowWidths: [Double]
  }

  private struct PropertyExportSummary {
    let floorCount: Int
    let totalDoorCount: Int
    let totalOpeningCount: Int
    let totalWindowCount: Int
    let floorNamesText: String
    let roomNamesText: String
    let roomDistributionText: String
    let roomAreaDistributionText: String
  }

  private struct ParsedAddress {
    let street: String
    let houseNumber: String?
    let postalCode: String?
    let city: String?
  }

  private struct AreaFootprint {
    let hull: [DPoint]
    let bounds: (minX: Double, minY: Double, maxX: Double, maxY: Double)
    let livingFactor: Double
  }

  private static func loadRoomSegments(
    project: FloorplanProject,
    resolveURL: (String) throws -> URL
  ) throws -> [RoomSegments] {
    var out: [RoomSegments] = []
    out.reserveCapacity(project.roomScans.count)
    for scan in project.roomScans {
      let url = try resolveURL(scan.segmentsJSONPath)
      guard FileManager.default.fileExists(atPath: url.path) else { continue }
      let data = try Data(contentsOf: url)
      let decoded = try JSONDecoder().decode(FloorplanSegmentsFile.self, from: data).normalizedForDisplay()
      out.append(
        RoomSegments(
          scan: scan,
          segments: decoded.segments,
          metrics: decoded.metrics,
          doors: decoded.doors ?? [],
          openings: decoded.openings ?? [],
          windows: decoded.windows ?? [],
          doorSwingOverrides: decoded.doorSwingOverrides ?? []
        )
      )
    }
    return out
  }

  // WoFlV-inspired approximation:
  // - indoor residential spaces count fully,
  // - balconies/terraces count partially,
  // - non-residential/exterior/support spaces count as 0.
  private static let livingAreaFactorOverrides: [String: Double] = [
    "attic": 0.0,
    "balcony": 0.25,
    "basement": 0.0,
    "carport": 0.0,
    "conservatory": 0.50,
    "courtyard": 0.0,
    "driveway": 0.0,
    "exterior": 0.0,
    "garage": 0.0,
    "garden": 0.0,
    "outbuilding": 0.0,
    "roof_terrace": 0.25,
    "stairs": 0.0,
    "street": 0.0,
    "terrace": 0.25,
    "unknown": 0.0,
  ]

  private static func buildStats(project: FloorplanProject, rooms: [RoomSegments]) -> HeaderStats {
    let coverage = approximateCoverageSummary(rooms: rooms)
    let totalArea = coverage?.totalArea ?? rooms.reduce(0.0) { $0 + $1.metrics.areaSqmApprox }
    let totalPerimeter = rooms.reduce(0.0) { $0 + $1.metrics.perimeterMeters }
    let roomCount = rooms.count
    let routePointCount = project.routePoints.count
    let livingArea = coverage?.livingArea ?? rooms.reduce(0.0) { partial, room in
      let factor = livingAreaFactor(for: room.scan.roomId)
      guard factor > 0 else { return partial }
      return partial + (room.metrics.areaSqmApprox * factor)
    }

    return HeaderStats(
      totalArea: totalArea,
      livingArea: livingArea,
      totalPerimeter: totalPerimeter,
      roomCount: roomCount,
      routePointCount: routePointCount
    )
  }

  private static func approximateCoverageSummary(rooms: [RoomSegments]) -> (totalArea: Double, livingArea: Double)? {
    let footprints: [AreaFootprint] = rooms.compactMap { room in
      let hull = convexHullPoints(segments: transformedSegments(room: room))
      guard hull.count >= 3 else { return nil }
      return AreaFootprint(
        hull: hull,
        bounds: polygonBounds(points: hull),
        livingFactor: livingAreaFactor(for: room.scan.roomId)
      )
    }

    guard !footprints.isEmpty else { return nil }

    let sceneBounds = footprints.reduce(
      (minX: Double.greatestFiniteMagnitude, minY: Double.greatestFiniteMagnitude, maxX: -Double.greatestFiniteMagnitude, maxY: -Double.greatestFiniteMagnitude)
    ) { partial, footprint in
      (
        min(partial.minX, footprint.bounds.minX),
        min(partial.minY, footprint.bounds.minY),
        max(partial.maxX, footprint.bounds.maxX),
        max(partial.maxY, footprint.bounds.maxY)
      )
    }

    let width = sceneBounds.maxX - sceneBounds.minX
    let height = sceneBounds.maxY - sceneBounds.minY
    guard width > 0.001, height > 0.001 else { return nil }

    let resolutionMeters = min(0.10, max(0.04, max(width, height) / 500.0))
    let cellArea = resolutionMeters * resolutionMeters
    var totalArea = 0.0
    var livingArea = 0.0
    var y = sceneBounds.minY + (resolutionMeters * 0.5)

    while y < sceneBounds.maxY {
      var x = sceneBounds.minX + (resolutionMeters * 0.5)
      while x < sceneBounds.maxX {
        let sample = DPoint(x: x, y: y)
        var covered = false
        var maxFactor = 0.0

        for footprint in footprints {
          guard x >= footprint.bounds.minX,
                x <= footprint.bounds.maxX,
                y >= footprint.bounds.minY,
                y <= footprint.bounds.maxY else { continue }
          guard pointInPolygon(sample, polygon: footprint.hull) else { continue }
          covered = true
          maxFactor = max(maxFactor, footprint.livingFactor)
        }

        if covered {
          totalArea += cellArea
          livingArea += cellArea * maxFactor
        }
        x += resolutionMeters
      }
      y += resolutionMeters
    }

    return (totalArea: totalArea, livingArea: livingArea)
  }

  private static func polygonBounds(
    points: [DPoint]
  ) -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
    var minX = Double.greatestFiniteMagnitude
    var minY = Double.greatestFiniteMagnitude
    var maxX = -Double.greatestFiniteMagnitude
    var maxY = -Double.greatestFiniteMagnitude

    for point in points {
      minX = min(minX, point.x)
      minY = min(minY, point.y)
      maxX = max(maxX, point.x)
      maxY = max(maxY, point.y)
    }

    if !minX.isFinite || !minY.isFinite || !maxX.isFinite || !maxY.isFinite {
      return (0, 0, 0, 0)
    }
    return (minX, minY, maxX, maxY)
  }

  private static func pointInPolygon(_ point: DPoint, polygon: [DPoint]) -> Bool {
    guard polygon.count >= 3 else { return false }
    var isInside = false

    for idx in 0..<polygon.count {
      let a = polygon[idx]
      let b = polygon[(idx + 1) % polygon.count]

      if isPoint(point, onSegmentFrom: a, to: b) {
        return true
      }

      let deltaY = b.y - a.y
      let safeDeltaY = abs(deltaY) > 1e-9 ? deltaY : (deltaY >= 0 ? 1e-9 : -1e-9)
      let intersects = ((a.y > point.y) != (b.y > point.y)) &&
        (point.x < ((b.x - a.x) * (point.y - a.y) / safeDeltaY) + a.x)
      if intersects {
        isInside.toggle()
      }
    }

    return isInside
  }

  private static func isPoint(_ point: DPoint, onSegmentFrom a: DPoint, to b: DPoint) -> Bool {
    let cross = abs((point.y - a.y) * (b.x - a.x) - (point.x - a.x) * (b.y - a.y))
    guard cross <= 1e-6 else { return false }

    let dot = (point.x - a.x) * (point.x - b.x) + (point.y - a.y) * (point.y - b.y)
    return dot <= 1e-6
  }

  private static func buildRoomReportEntries(rooms: [RoomSegments]) -> [RoomReportEntry] {
    let floorOrder = Dictionary(uniqueKeysWithValues: FloorTaxonomy.floors.enumerated().map { ($1.id, $0) })
    let sortedRooms = rooms.sorted { lhs, rhs in
      let lhsFloor = floorOrder[FloorTaxonomy.normalizedFloorId(lhs.scan.floorId)] ?? Int.max
      let rhsFloor = floorOrder[FloorTaxonomy.normalizedFloorId(rhs.scan.floorId)] ?? Int.max
      if lhsFloor != rhsFloor { return lhsFloor < rhsFloor }
      if lhs.scan.createdAt != rhs.scan.createdAt { return lhs.scan.createdAt < rhs.scan.createdAt }
      return lhs.scan.id.uuidString < rhs.scan.id.uuidString
    }

    return sortedRooms.map { room in
      let livingFactor = livingAreaFactor(for: room.scan.roomId)
      return RoomReportEntry(
        roomId: room.scan.roomId,
        roomName: RoomTaxonomy.room(id: room.scan.roomId).displayName,
        floorId: room.scan.floorId,
        floorName: FloorTaxonomy.floor(id: room.scan.floorId).displayName,
        areaSqm: room.metrics.areaSqmApprox,
        livingAreaFactor: livingFactor,
        livingAreaSqm: room.metrics.areaSqmApprox * livingFactor,
        perimeterMeters: room.metrics.perimeterMeters,
        widthMeters: room.metrics.widthMeters,
        depthMeters: room.metrics.depthMeters,
        doorWidths: room.doors.map { segmentLength($0) }.filter { $0 > 0.01 }.sorted(),
        openingWidths: room.openings.map { segmentLength($0) }.filter { $0 > 0.01 }.sorted(),
        windowWidths: room.windows.map { segmentLength($0) }.filter { $0 > 0.01 }.sorted()
      )
    }
  }

  private static func buildPropertyExportSummary(roomReportEntries: [RoomReportEntry]) -> PropertyExportSummary {
    let floorNames = uniqueOrderedStrings(roomReportEntries.map(\.floorName))
    let roomNames = uniqueOrderedStrings(roomReportEntries.map(\.roomName))
    let roomDistribution = roomReportEntries.map {
      "\($0.roomName) (\($0.floorName))"
    }.joined(separator: " | ")
    let roomAreaDistribution = roomReportEntries.map {
      "\($0.roomName) (\($0.floorName))=\(formattedMachineDecimalValue($0.areaSqm)) m2"
    }.joined(separator: " | ")

    return PropertyExportSummary(
      floorCount: floorNames.count,
      totalDoorCount: roomReportEntries.reduce(0) { $0 + $1.doorWidths.count },
      totalOpeningCount: roomReportEntries.reduce(0) { $0 + $1.openingWidths.count },
      totalWindowCount: roomReportEntries.reduce(0) { $0 + $1.windowWidths.count },
      floorNamesText: floorNames.joined(separator: " | "),
      roomNamesText: roomNames.joined(separator: " | "),
      roomDistributionText: roomDistribution,
      roomAreaDistributionText: roomAreaDistribution
    )
  }

  private static func renderPNG(
    rooms: [RoomSegments],
    routePoints: [DPoint],
    stairConnections: [FloorplanStairConnection],
    outputURL: URL,
    title: String,
    headerStats: HeaderStats
  ) throws {
    let size = CGSize(width: 2200, height: 2200)
    let image = renderImage(
      rooms: rooms,
      routePoints: routePoints,
      stairConnections: stairConnections,
      canvasSize: size,
      title: title,
      headerStats: headerStats
    )
    guard let data = image.pngData() else {
      throw NSError(domain: "FloorplanComposerRenderer", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "PNG konnte nicht erzeugt werden."
      ])
    }
    try data.write(to: outputURL, options: [.atomic])
  }

  private static func renderCombinedPDF(
    rooms: [RoomSegments],
    routePoints: [DPoint],
    stairConnections: [FloorplanStairConnection],
    outputURL: URL,
    title: String,
    headerStats: HeaderStats,
    roomReportEntries: [RoomReportEntry]
  ) throws {
    let page = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 @ 72dpi
    let renderer = UIGraphicsPDFRenderer(bounds: page)
    try renderer.writePDF(to: outputURL) { ctx in
      ctx.beginPage()
      let cg = ctx.cgContext
      draw(
        rooms: rooms,
        routePoints: routePoints,
        stairConnections: stairConnections,
        cg: cg,
        rect: page,
        title: title,
        headerStats: headerStats
      )
      drawRoomReportPages(
        entries: roomReportEntries,
        headerStats: headerStats,
        in: ctx,
        pageRect: page,
        projectTitle: title
      )
    }
  }

  private static func renderPlanPDF(
    rooms: [RoomSegments],
    routePoints: [DPoint],
    stairConnections: [FloorplanStairConnection],
    outputURL: URL,
    title: String,
    headerStats: HeaderStats
  ) throws {
    let page = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 @ 72dpi
    let renderer = UIGraphicsPDFRenderer(bounds: page)
    try renderer.writePDF(to: outputURL) { ctx in
      ctx.beginPage()
      let cg = ctx.cgContext
      draw(
        rooms: rooms,
        routePoints: routePoints,
        stairConnections: stairConnections,
        cg: cg,
        rect: page,
        title: title,
        headerStats: headerStats
      )
    }
  }

  private static func renderDataPDF(
    roomReportEntries: [RoomReportEntry],
    outputURL: URL,
    title: String,
    headerStats: HeaderStats
  ) throws {
    let page = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 @ 72dpi
    let renderer = UIGraphicsPDFRenderer(bounds: page)
    try renderer.writePDF(to: outputURL) { ctx in
      drawRoomReportPages(
        entries: roomReportEntries,
        headerStats: headerStats,
        in: ctx,
        pageRect: page,
        projectTitle: title
      )
    }
  }

  private static func renderDataCSV(
    roomReportEntries: [RoomReportEntry],
    outputURL: URL,
    metadata: ExportMetadata,
    headerStats: HeaderStats
  ) throws {
    let propertySummary = buildPropertyExportSummary(roomReportEntries: roomReportEntries)
    let generatedAt = iso8601String(from: metadata.generatedAt)
    let createdAt = iso8601String(from: metadata.projectCreatedAt)
    let separator = ";"
    let headers = [
      "row_type",
      "project_key",
      "project_name",
      "property_external_id",
      "job_id",
      "property_address",
      "export_generated_at",
      "project_created_at",
      "room_id",
      "room_name",
      "floor_id",
      "floor_name",
      "area_sqm",
      "area_share_percent",
      "living_area_factor",
      "living_area_sqm",
      "perimeter_m",
      "width_m",
      "depth_m",
      "room_door_count",
      "room_opening_count",
      "room_window_count",
      "door_widths_m",
      "opening_widths_m",
      "window_widths_m",
      "total_area_sqm",
      "total_living_area_sqm",
      "total_perimeter_m",
      "room_count",
      "route_point_count",
      "floor_count",
      "total_door_count",
      "total_opening_count",
      "total_window_count",
      "floor_names",
      "room_distribution",
      "room_area_distribution"
    ]

    var lines: [String] = []
    lines.reserveCapacity(roomReportEntries.count + 2)
    lines.append(csvRow(headers, separator: separator))
    lines.append(
      csvRow(
        [
          "summary",
          metadata.projectKey,
          metadata.projectName,
          metadata.propertyExternalId,
          metadata.jobId,
          metadata.jobAddress,
          generatedAt,
          createdAt,
          "",
          "",
          "",
          "",
          "",
          "",
          "",
          "",
          "",
          "",
          "",
          "",
          "",
          "",
          "",
          "",
          "",
          formattedDecimalValue(headerStats.totalArea),
          formattedDecimalValue(headerStats.livingArea),
          formattedDecimalValue(headerStats.totalPerimeter),
          "\(headerStats.roomCount)",
          "\(headerStats.routePointCount)",
          "\(propertySummary.floorCount)",
          "\(propertySummary.totalDoorCount)",
          "\(propertySummary.totalOpeningCount)",
          "\(propertySummary.totalWindowCount)",
          propertySummary.floorNamesText,
          propertySummary.roomDistributionText,
          propertySummary.roomAreaDistributionText
        ],
        separator: separator
      )
    )

    let totalArea = max(headerStats.totalArea, 0)
    for entry in roomReportEntries {
      let sharePercent = totalArea > 0 ? (entry.areaSqm / totalArea) * 100 : 0
      lines.append(
        csvRow(
          [
            "room",
            metadata.projectKey,
            metadata.projectName,
            metadata.propertyExternalId,
            metadata.jobId,
            metadata.jobAddress,
            generatedAt,
            createdAt,
            entry.roomId,
            entry.roomName,
            entry.floorId,
            entry.floorName,
            formattedDecimalValue(entry.areaSqm),
            formattedPercentNumberValue(sharePercent),
            formattedDecimalValue(entry.livingAreaFactor),
            formattedDecimalValue(entry.livingAreaSqm),
            formattedDecimalValue(entry.perimeterMeters),
            formattedDecimalValue(entry.widthMeters),
            formattedDecimalValue(entry.depthMeters),
            "\(entry.doorWidths.count)",
            "\(entry.openingWidths.count)",
            "\(entry.windowWidths.count)",
            formattedCSVList(entry.doorWidths),
            formattedCSVList(entry.openingWidths),
            formattedCSVList(entry.windowWidths),
            "",
            "",
            "",
            "",
            "",
            "",
            "",
            "",
            "",
            "",
            "",
            ""
          ],
          separator: separator
        )
      )
    }

    try writeCSV(lines: lines, to: outputURL)
  }

  private static func renderSummaryCSV(
    roomReportEntries: [RoomReportEntry],
    outputURL: URL,
    metadata: ExportMetadata,
    headerStats: HeaderStats
  ) throws {
    let propertySummary = buildPropertyExportSummary(roomReportEntries: roomReportEntries)
    let separator = ";"
    let headers = [
      "project_key",
      "project_name",
      "property_external_id",
      "job_id",
      "property_address",
      "export_generated_at",
      "project_created_at",
      "total_area_sqm",
      "living_area_sqm",
      "total_perimeter_m",
      "room_count",
      "floor_count",
      "route_point_count",
      "door_count",
      "opening_count",
      "window_count",
      "floor_names",
      "room_names",
      "room_distribution",
      "room_area_distribution"
    ]
    let values = [
      metadata.projectKey,
      metadata.projectName,
      metadata.propertyExternalId,
      metadata.jobId,
      metadata.jobAddress,
      iso8601String(from: metadata.generatedAt),
      iso8601String(from: metadata.projectCreatedAt),
      formattedDecimalValue(headerStats.totalArea),
      formattedDecimalValue(headerStats.livingArea),
      formattedDecimalValue(headerStats.totalPerimeter),
      "\(headerStats.roomCount)",
      "\(propertySummary.floorCount)",
      "\(headerStats.routePointCount)",
      "\(propertySummary.totalDoorCount)",
      "\(propertySummary.totalOpeningCount)",
      "\(propertySummary.totalWindowCount)",
      propertySummary.floorNamesText,
      propertySummary.roomNamesText,
      propertySummary.roomDistributionText,
      propertySummary.roomAreaDistributionText
    ]
    try writeCSV(lines: [csvRow(headers, separator: separator), csvRow(values, separator: separator)], to: outputURL)
  }

  private static func renderRoomsCSV(
    roomReportEntries: [RoomReportEntry],
    outputURL: URL,
    metadata: ExportMetadata,
    headerStats: HeaderStats
  ) throws {
    let separator = ";"
    let headers = [
      "project_key",
      "project_name",
      "property_external_id",
      "job_id",
      "property_address",
      "export_generated_at",
      "room_sequence",
      "room_id",
      "room_name",
      "floor_id",
      "floor_name",
      "area_sqm",
      "area_share_percent",
      "living_area_factor",
      "living_area_sqm",
      "perimeter_m",
      "width_m",
      "depth_m",
      "door_count",
      "opening_count",
      "window_count",
      "door_widths_m",
      "opening_widths_m",
      "window_widths_m",
      "total_area_sqm",
      "total_living_area_sqm"
    ]

    var lines = [csvRow(headers, separator: separator)]
    let totalArea = max(headerStats.totalArea, 0)
    for (index, entry) in roomReportEntries.enumerated() {
      let sharePercent = totalArea > 0 ? (entry.areaSqm / totalArea) * 100 : 0
      lines.append(
        csvRow(
          [
            metadata.projectKey,
            metadata.projectName,
            metadata.propertyExternalId,
            metadata.jobId,
            metadata.jobAddress,
            iso8601String(from: metadata.generatedAt),
            "\(index + 1)",
            entry.roomId,
            entry.roomName,
            entry.floorId,
            entry.floorName,
            formattedDecimalValue(entry.areaSqm),
            formattedPercentNumberValue(sharePercent),
            formattedDecimalValue(entry.livingAreaFactor),
            formattedDecimalValue(entry.livingAreaSqm),
            formattedDecimalValue(entry.perimeterMeters),
            formattedDecimalValue(entry.widthMeters),
            formattedDecimalValue(entry.depthMeters),
            "\(entry.doorWidths.count)",
            "\(entry.openingWidths.count)",
            "\(entry.windowWidths.count)",
            formattedCSVList(entry.doorWidths),
            formattedCSVList(entry.openingWidths),
            formattedCSVList(entry.windowWidths),
            formattedDecimalValue(headerStats.totalArea),
            formattedDecimalValue(headerStats.livingArea)
          ],
          separator: separator
        )
      )
    }

    try writeCSV(lines: lines, to: outputURL)
  }

  private static func renderCRMPropertyCSV(
    roomReportEntries: [RoomReportEntry],
    outputURL: URL,
    metadata: ExportMetadata,
    headerStats: HeaderStats
  ) throws {
    let propertySummary = buildPropertyExportSummary(roomReportEntries: roomReportEntries)
    let separator = ","
    let headers = [
      "source_system",
      "export_type",
      "export_version",
      "property_external_id",
      "project_key",
      "project_name",
      "job_id",
      "property_address",
      "export_generated_at",
      "project_created_at",
      "total_area_sqm",
      "living_area_sqm",
      "total_perimeter_m",
      "room_count",
      "floor_count",
      "route_point_count",
      "door_count",
      "opening_count",
      "window_count",
      "floor_names",
      "room_names",
      "room_distribution",
      "room_area_distribution"
    ]
    let values = [
      "PIXCAPTURE",
      "property",
      "1",
      metadata.propertyExternalId,
      metadata.projectKey,
      metadata.projectName,
      metadata.jobId,
      metadata.jobAddress,
      iso8601String(from: metadata.generatedAt),
      iso8601String(from: metadata.projectCreatedAt),
      formattedMachineDecimalValue(headerStats.totalArea),
      formattedMachineDecimalValue(headerStats.livingArea),
      formattedMachineDecimalValue(headerStats.totalPerimeter),
      "\(headerStats.roomCount)",
      "\(propertySummary.floorCount)",
      "\(headerStats.routePointCount)",
      "\(propertySummary.totalDoorCount)",
      "\(propertySummary.totalOpeningCount)",
      "\(propertySummary.totalWindowCount)",
      propertySummary.floorNamesText,
      propertySummary.roomNamesText,
      propertySummary.roomDistributionText,
      propertySummary.roomAreaDistributionText
    ]
    try writeCSV(
      lines: [csvRow(headers, separator: separator), csvRow(values, separator: separator)],
      to: outputURL
    )
  }

  private static func renderCRMRoomsCSV(
    roomReportEntries: [RoomReportEntry],
    outputURL: URL,
    metadata: ExportMetadata,
    headerStats: HeaderStats
  ) throws {
    let propertySummary = buildPropertyExportSummary(roomReportEntries: roomReportEntries)
    let separator = ","
    let headers = [
      "source_system",
      "export_type",
      "export_version",
      "property_external_id",
      "project_key",
      "project_name",
      "job_id",
      "property_address",
      "export_generated_at",
      "project_created_at",
      "total_area_sqm",
      "living_area_sqm",
      "total_perimeter_m",
      "room_count",
      "floor_count",
      "route_point_count",
      "room_sequence",
      "room_id",
      "room_name",
      "floor_id",
      "floor_name",
      "room_area_sqm",
      "room_share_percent",
      "room_living_area_factor",
      "room_living_area_sqm",
      "room_perimeter_m",
      "room_width_m",
      "room_depth_m",
      "door_count",
      "opening_count",
      "window_count",
      "door_widths_m",
      "opening_widths_m",
      "window_widths_m",
      "room_distribution",
      "room_area_distribution"
    ]

    var lines = [csvRow(headers, separator: separator)]
    let totalArea = max(headerStats.totalArea, 0)
    for (index, entry) in roomReportEntries.enumerated() {
      let sharePercent = totalArea > 0 ? (entry.areaSqm / totalArea) * 100 : 0
      lines.append(
        csvRow(
          [
            "PIXCAPTURE",
            "room",
            "1",
            metadata.propertyExternalId,
            metadata.projectKey,
            metadata.projectName,
            metadata.jobId,
            metadata.jobAddress,
            iso8601String(from: metadata.generatedAt),
            iso8601String(from: metadata.projectCreatedAt),
            formattedMachineDecimalValue(headerStats.totalArea),
            formattedMachineDecimalValue(headerStats.livingArea),
            formattedMachineDecimalValue(headerStats.totalPerimeter),
            "\(headerStats.roomCount)",
            "\(propertySummary.floorCount)",
            "\(headerStats.routePointCount)",
            "\(index + 1)",
            entry.roomId,
            entry.roomName,
            entry.floorId,
            entry.floorName,
            formattedMachineDecimalValue(entry.areaSqm),
            formattedMachinePercentNumberValue(sharePercent),
            formattedMachineDecimalValue(entry.livingAreaFactor),
            formattedMachineDecimalValue(entry.livingAreaSqm),
            formattedMachineDecimalValue(entry.perimeterMeters),
            formattedMachineDecimalValue(entry.widthMeters),
            formattedMachineDecimalValue(entry.depthMeters),
            "\(entry.doorWidths.count)",
            "\(entry.openingWidths.count)",
            "\(entry.windowWidths.count)",
            formattedMachineCSVList(entry.doorWidths),
            formattedMachineCSVList(entry.openingWidths),
            formattedMachineCSVList(entry.windowWidths),
            propertySummary.roomDistributionText,
            propertySummary.roomAreaDistributionText
          ],
          separator: separator
        )
      )
    }

    try writeCSV(lines: lines, to: outputURL)
  }

  private static func renderOpenImmoXML(
    roomReportEntries: [RoomReportEntry],
    outputURL: URL,
    metadata: ExportMetadata,
    headerStats: HeaderStats,
    referencedFileNames: [String]
  ) throws {
    let propertySummary = buildPropertyExportSummary(roomReportEntries: roomReportEntries)
    let parsedAddress = parseAddress(metadata.jobAddress)
    let openImmoRoomCount = roomReportEntries.filter { $0.livingAreaFactor > 0.0 }.count
    let effectiveRoomCount = openImmoRoomCount > 0 ? openImmoRoomCount : roomReportEntries.count
    let livingArea = max(headerStats.livingArea, 0)
    let usableArea = max(headerStats.totalArea, 0)
    let generatedDate = openImmoDateString(from: metadata.generatedAt)
    let generatedTimestamp = openImmoDateTimeString(from: metadata.generatedAt)

    let objectDescription = [
      metadata.projectName,
      "Grundrissdaten aus PIXCAPTURE.",
      "Gesamtflaeche: \(formattedMachineDecimalValue(usableArea)) m2.",
      "Wohnflaeche: \(formattedMachineDecimalValue(livingArea)) m2.",
      "Raeume gescannt: \(headerStats.roomCount).",
      propertySummary.floorCount > 0 ? "Etagen: \(propertySummary.floorNamesText)." : nil
    ]
      .compactMap { $0 }
      .joined(separator: " ")

    let additionalDetails = [
      !propertySummary.roomDistributionText.isEmpty ? "Raumverteilung: \(propertySummary.roomDistributionText)" : nil,
      !propertySummary.roomAreaDistributionText.isEmpty ? "Flaechenverteilung: \(propertySummary.roomAreaDistributionText)" : nil,
      "Umfang gesamt: \(formattedMachineDecimalValue(headerStats.totalPerimeter)) m",
      "Wegpunkte: \(headerStats.routePointCount)"
    ]
      .compactMap { $0 }
      .joined(separator: " | ")

    var customFields: [(String, String)] = [
      ("pixcapture_project_key", metadata.projectKey),
      ("pixcapture_project_name", metadata.projectName),
      ("pixcapture_job_id", metadata.jobId),
      ("pixcapture_property_address", metadata.jobAddress),
      ("pixcapture_total_area_sqm", formattedMachineDecimalValue(usableArea)),
      ("pixcapture_living_area_sqm", formattedMachineDecimalValue(livingArea)),
      ("pixcapture_total_perimeter_m", formattedMachineDecimalValue(headerStats.totalPerimeter)),
      ("pixcapture_room_count_scanned", "\(headerStats.roomCount)"),
      ("pixcapture_floor_count", "\(propertySummary.floorCount)"),
      ("pixcapture_route_point_count", "\(headerStats.routePointCount)"),
      ("pixcapture_floor_names", propertySummary.floorNamesText),
      ("pixcapture_room_distribution", propertySummary.roomDistributionText),
      ("pixcapture_room_area_distribution", propertySummary.roomAreaDistributionText),
      ("pixcapture_export_files", referencedFileNames.joined(separator: "|"))
    ]

    for (index, entry) in roomReportEntries.enumerated() {
      let token = String(format: "%02d", index + 1)
      let totalArea = max(headerStats.totalArea, 0)
      let sharePercent = totalArea > 0 ? (entry.areaSqm / totalArea) * 100 : 0
      customFields.append(("pixcapture_room_\(token)_name", entry.roomName))
      customFields.append(("pixcapture_room_\(token)_floor", entry.floorName))
      customFields.append(("pixcapture_room_\(token)_area_sqm", formattedMachineDecimalValue(entry.areaSqm)))
      customFields.append(("pixcapture_room_\(token)_share_percent", formattedMachinePercentNumberValue(sharePercent)))
    }

    var xmlLines: [String] = []
    xmlLines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
    xmlLines.append("<openimmo xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xsi:noNamespaceSchemaLocation=\"http://www.openimmo.de/openimmo.xsd\">")
    xmlLines.append(
      "  <uebertragung art=\"OFFLINE\" umfang=\"VOLL\" version=\"1.2.7\" sendersoftware=\"PIXCAPTURE\" senderversion=\"1\" techn_email=\"support@pixcapture.app\" regi_id=\"\(xmlEscapedAttributeValue(metadata.propertyExternalId))\" timestamp=\"\(xmlEscapedAttributeValue(generatedTimestamp))\"/>"
    )
    xmlLines.append("  <anbieter>")
    xmlLines.append("    <anbieternr>\(xmlEscapedValue(metadata.propertyExternalId))</anbieternr>")
    xmlLines.append("    <firma>PIXCAPTURE Export</firma>")
    xmlLines.append("    <openimmo_anid>\(xmlEscapedValue(metadata.propertyExternalId))</openimmo_anid>")
    xmlLines.append("    <immobilie status=\"aktiv\">")
    xmlLines.append("      <verwaltung_techn>")
    xmlLines.append("        <objektnr_extern>\(xmlEscapedValue(metadata.propertyExternalId))</objektnr_extern>")
    xmlLines.append("        <aktiv_von>\(xmlEscapedValue(generatedDate))</aktiv_von>")
    xmlLines.append("      </verwaltung_techn>")
    xmlLines.append("      <objektkategorie>")
    xmlLines.append("        <nutzungsart WOHNEN=\"true\"/>")
    xmlLines.append("        <vermarktungsart KAUF=\"true\"/>")
    xmlLines.append("        <objektart>")
    xmlLines.append("          <wohnung wohnungtyp=\"ETAGE\"/>")
    xmlLines.append("        </objektart>")
    xmlLines.append("      </objektkategorie>")
    xmlLines.append("      <flaechen>")
    xmlLines.append("        <wohnflaeche>\(formattedMachineDecimalValue(livingArea))</wohnflaeche>")
    xmlLines.append("        <nutzflaeche>\(formattedMachineDecimalValue(usableArea))</nutzflaeche>")
    xmlLines.append("        <anzahl_zimmer>\(effectiveRoomCount)</anzahl_zimmer>")
    xmlLines.append("      </flaechen>")

    if let parsedAddress {
      xmlLines.append("      <geo>")
      xmlLines.append("        <strasse>\(xmlEscapedValue(parsedAddress.street))</strasse>")
      if let houseNumber = parsedAddress.houseNumber, !houseNumber.isEmpty {
        xmlLines.append("        <hausnummer>\(xmlEscapedValue(houseNumber))</hausnummer>")
      }
      if let postalCode = parsedAddress.postalCode, !postalCode.isEmpty {
        xmlLines.append("        <plz>\(xmlEscapedValue(postalCode))</plz>")
      }
      if let city = parsedAddress.city, !city.isEmpty {
        xmlLines.append("        <ort>\(xmlEscapedValue(city))</ort>")
      }
      xmlLines.append("        <land iso_land=\"DEU\"/>")
      xmlLines.append("      </geo>")
    } else if !metadata.jobAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      xmlLines.append("      <geo>")
      xmlLines.append("        <strasse>\(xmlEscapedValue(metadata.jobAddress))</strasse>")
      xmlLines.append("        <land iso_land=\"DEU\"/>")
      xmlLines.append("      </geo>")
    }

    xmlLines.append("      <freitexte>")
    xmlLines.append("        <objekttitel>\(xmlEscapedValue(metadata.projectName))</objekttitel>")
    xmlLines.append("        <objektbeschreibung>\(xmlEscapedValue(objectDescription))</objektbeschreibung>")
    xmlLines.append("        <sonstige_angaben>\(xmlEscapedValue(additionalDetails))</sonstige_angaben>")
    xmlLines.append("      </freitexte>")

    for (fieldName, fieldValue) in customFields where !fieldValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      xmlLines.append(
        "      <user_defined_simplefield feldname=\"\(xmlEscapedAttributeValue(fieldName))\">\(xmlEscapedValue(fieldValue))</user_defined_simplefield>"
      )
    }

    xmlLines.append("    </immobilie>")
    xmlLines.append("  </anbieter>")
    xmlLines.append("</openimmo>")

    try writeTextFile(xmlLines.joined(separator: "\n"), to: outputURL)
  }

  private static func writeCSV(lines: [String], to outputURL: URL) throws {
    let payload = "\u{FEFF}" + lines.joined(separator: "\r\n")
    guard let data = payload.data(using: .utf8) else {
      throw NSError(
        domain: "FloorplanComposerRenderer",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "CSV konnte nicht erzeugt werden."]
      )
    }
    try data.write(to: outputURL, options: [.atomic])
  }

  private static func writeTextFile(_ payload: String, to outputURL: URL) throws {
    guard let data = payload.data(using: .utf8) else {
      throw NSError(
        domain: "FloorplanComposerRenderer",
        code: 3,
        userInfo: [NSLocalizedDescriptionKey: "Textdatei konnte nicht erzeugt werden."]
      )
    }
    try data.write(to: outputURL, options: [.atomic])
  }

  private static func csvRow(_ values: [String], separator: String) -> String {
    values.map { csvEscapedValue($0, separator: separator) }.joined(separator: separator)
  }

  private static func csvEscapedValue(_ value: String, separator: String) -> String {
    let needsQuotes = value.contains(separator) || value.contains("\"") || value.contains("\n") || value.contains("\r")
    let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
    return needsQuotes ? "\"\(escaped)\"" : escaped
  }

  private static func formattedCSVList(_ values: [Double]) -> String {
    values.map { formattedDecimalValue($0) }.joined(separator: "|")
  }

  private static func formattedMachineCSVList(_ values: [Double]) -> String {
    values.map { formattedMachineDecimalValue($0) }.joined(separator: "|")
  }

  private static func renderImage(
    rooms: [RoomSegments],
    routePoints: [DPoint],
    stairConnections: [FloorplanStairConnection],
    canvasSize: CGSize,
    title: String,
    headerStats: HeaderStats
  ) -> UIImage {
    let renderer = UIGraphicsImageRenderer(size: canvasSize)
    return renderer.image { ctx in
      draw(
        rooms: rooms,
        routePoints: routePoints,
        stairConnections: stairConnections,
        cg: ctx.cgContext,
        rect: CGRect(origin: .zero, size: canvasSize),
        title: title,
        headerStats: headerStats
      )
    }
  }

  private static func draw(
    rooms: [RoomSegments],
    routePoints: [DPoint],
    stairConnections: [FloorplanStairConnection],
    cg: CGContext,
    rect: CGRect,
    title: String,
    headerStats: HeaderStats
  ) {
    let backgroundColor = UIColor.white
    let titleColor = UIColor.black.withAlphaComponent(0.92)
    let headlineColor = UIColor.black.withAlphaComponent(0.62)
    let sublineColor = UIColor.black.withAlphaComponent(0.52)
    let gridColor = UIColor.black.withAlphaComponent(0.06)

    cg.setFillColor(backgroundColor.cgColor)
    cg.fill(rect)

    // Header
    let titleFont = UIFont.systemFont(ofSize: 18, weight: .bold)
    let headlineFont = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
    let sublineFont = UIFont.systemFont(ofSize: 11, weight: .medium)
    let titleAttrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: titleColor]
    let headlineAttrs: [NSAttributedString.Key: Any] = [
      .font: headlineFont,
      .foregroundColor: headlineColor
    ]
    let sublineAttrs: [NSAttributedString.Key: Any] = [
      .font: sublineFont,
      .foregroundColor: sublineColor
    ]

    let margin: CGFloat = 36
    (title as NSString).draw(at: CGPoint(x: margin, y: margin), withAttributes: titleAttrs)
    (headerStats.headlineText as NSString).draw(
      in: CGRect(x: margin, y: margin + 26, width: rect.width - margin * 2, height: 20),
      withAttributes: headlineAttrs
    )
    (headerStats.sublineText as NSString).draw(
      in: CGRect(x: margin, y: margin + 46, width: rect.width - margin * 2, height: 18),
      withAttributes: sublineAttrs
    )

    let contentRect = rect.inset(by: UIEdgeInsets(top: 112, left: margin, bottom: margin, right: margin))
    guard !rooms.isEmpty else { return }

    let renderRooms = rooms.map { room in
      FloorplanPlanRenderer.Room(
        scanId: room.scan.id,
        roomId: room.scan.roomId,
        floorId: room.scan.floorId,
        walls: transformedSegments(room: room),
        doors: transformedSegments(segments: room.doors, t: room.scan.transform),
        openings: transformedSegments(segments: room.openings, t: room.scan.transform),
        windows: transformedSegments(segments: room.windows, t: room.scan.transform),
        doorSwingOverrides: room.doorSwingOverrides
      )
    }
    let planLayout = FloorplanPlanRenderer.layout(for: renderRooms)
    let planCenter = DPoint(x: planLayout.bounds.center.x, y: planLayout.bounds.center.y)
    let mapping = FloorplanPlanRenderer.makeMapping(
      bounds: planLayout.bounds,
      viewport: contentRect,
      minimumScale: 0
    )
    let scale = mapping.scale

    func map(x: Double, y: Double) -> CGPoint {
      mapping.map(x: x, y: y)
    }

    // Grid
    cg.setStrokeColor(gridColor.cgColor)
    cg.setLineWidth(1)
    let gridStepMeters: Double = 1.0
    let stepPx = CGFloat(gridStepMeters) * scale
    if stepPx >= 40 {
      var x = contentRect.minX
      while x <= contentRect.maxX {
        cg.move(to: CGPoint(x: x, y: contentRect.minY))
        cg.addLine(to: CGPoint(x: x, y: contentRect.maxY))
        x += stepPx
      }
      var y = contentRect.minY
      while y <= contentRect.maxY {
        cg.move(to: CGPoint(x: contentRect.minX, y: y))
        cg.addLine(to: CGPoint(x: contentRect.maxX, y: y))
        y += stepPx
      }
      cg.strokePath()
    }

    FloorplanPlanRenderer.drawBasePlan(
      cg: cg,
      rooms: renderRooms,
      layout: planLayout,
      mapping: mapping,
      style: .export,
      labelMode: .roomNameAndFloorIfMultipleFloors
    )

    let mergedWalls = planLayout.mergedWalls.map {
      RenderedWallSegment(seg: $0.seg, isInterior: $0.isInterior)
    }
    drawDimensionAnnotations(
      segments: mergedWalls,
      map: map,
      cg: cg,
      planCenter: planCenter
    )

    drawStairConnections(stairConnections: stairConnections, map: map, cg: cg)
    drawRouteOverlay(routePoints: routePoints, map: map, cg: cg)
  }

  private struct WallSourceSegment {
    let scanId: UUID
    let seg: FloorplanSegment
  }

  private struct RenderedWallSegment {
    let seg: FloorplanSegment
    let isInterior: Bool
  }

  private struct DPoint {
    let x: Double
    let y: Double
  }

  private static func drawStairConnections(
    stairConnections: [FloorplanStairConnection],
    map: (Double, Double) -> CGPoint,
    cg: CGContext
  ) {
    guard !stairConnections.isEmpty else { return }

    let labelAttrs: [NSAttributedString.Key: Any] = [
      .font: UIFont.systemFont(ofSize: 9, weight: .semibold),
      .foregroundColor: UIColor.black.withAlphaComponent(0.78)
    ]

    for stair in stairConnections {
      let center = map(stair.x, stair.y)
      let radius: CGFloat = 9.2
      let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)

      cg.saveGState()
      cg.setFillColor(UIColor.black.withAlphaComponent(0.74).cgColor)
      cg.fillEllipse(in: rect)
      cg.setStrokeColor(UIColor.white.withAlphaComponent(0.92).cgColor)
      cg.setLineWidth(1.2)
      cg.strokeEllipse(in: rect)

      let icon = "⇅"
      let iconAttrs: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 10, weight: .bold),
        .foregroundColor: UIColor.white.withAlphaComponent(0.96)
      ]
      let iconSize = (icon as NSString).size(withAttributes: iconAttrs)
      (icon as NSString).draw(
        at: CGPoint(x: center.x - iconSize.width * 0.5, y: center.y - iconSize.height * 0.5),
        withAttributes: iconAttrs
      )
      cg.restoreGState()

      let fromShort = FloorTaxonomy.floor(id: stair.fromFloorId).shortDisplayName
      let toShort = FloorTaxonomy.floor(id: stair.toFloorId).shortDisplayName
      let label = "\(fromShort) ↔ \(toShort)"
      let labelSize = (label as NSString).size(withAttributes: labelAttrs)
      let bubbleRect = CGRect(
        x: center.x - labelSize.width * 0.5 - 5,
        y: center.y + radius + 3,
        width: labelSize.width + 10,
        height: labelSize.height + 4
      )
      cg.saveGState()
      cg.setFillColor(UIColor.white.withAlphaComponent(0.86).cgColor)
      cg.addPath(UIBezierPath(roundedRect: bubbleRect, cornerRadius: 5).cgPath)
      cg.fillPath()
      cg.setStrokeColor(UIColor.black.withAlphaComponent(0.12).cgColor)
      cg.setLineWidth(1)
      cg.addPath(UIBezierPath(roundedRect: bubbleRect, cornerRadius: 5).cgPath)
      cg.strokePath()
      cg.restoreGState()

      (label as NSString).draw(
        at: CGPoint(
          x: bubbleRect.midX - labelSize.width * 0.5,
          y: bubbleRect.midY - labelSize.height * 0.5
        ),
        withAttributes: labelAttrs
      )
    }
  }

  private static func drawRouteOverlay(
    routePoints: [DPoint],
    map: (Double, Double) -> CGPoint,
    cg: CGContext
  ) {
    guard !routePoints.isEmpty else { return }
    let mapped = routePoints.map { map($0.x, $0.y) }

    // Draw a clear route for the video walkthrough briefing.
    if mapped.count >= 2 {
      cg.saveGState()
      cg.setStrokeColor(UIColor(red: 0.99, green: 0.84, blue: 0.25, alpha: 0.96).cgColor)
      cg.setLineWidth(4.2)
      cg.setLineCap(.round)
      cg.setLineJoin(.round)
      cg.setLineDash(phase: 0, lengths: [13, 8])
      cg.beginPath()
      cg.move(to: mapped[0])
      for point in mapped.dropFirst() {
        cg.addLine(to: point)
      }
      cg.strokePath()
      cg.restoreGState()
    }

    let nodeStroke = UIColor.black.withAlphaComponent(0.55)
    let labelAttrs: [NSAttributedString.Key: Any] = [
      .font: UIFont.systemFont(ofSize: 10, weight: .bold),
      .foregroundColor: UIColor.black.withAlphaComponent(0.85)
    ]

    for (idx, point) in mapped.enumerated() {
      let radius: CGFloat = (idx == 0 || idx == mapped.count - 1) ? 7.2 : 5.2
      let circleRect = CGRect(
        x: point.x - radius,
        y: point.y - radius,
        width: radius * 2,
        height: radius * 2
      )
      let nodeFill: UIColor
      if idx == 0 {
        nodeFill = UIColor(red: 0.38, green: 0.94, blue: 0.44, alpha: 0.98)
      } else if idx == mapped.count - 1 {
        nodeFill = UIColor(red: 1.0, green: 0.47, blue: 0.44, alpha: 0.98)
      } else {
        nodeFill = UIColor(red: 0.99, green: 0.84, blue: 0.25, alpha: 0.96)
      }
      cg.setFillColor(nodeFill.cgColor)
      cg.fillEllipse(in: circleRect)
      cg.setStrokeColor(nodeStroke.cgColor)
      cg.setLineWidth(1.2)
      cg.strokeEllipse(in: circleRect)

      let labelText: String
      if idx == 0 {
        labelText = "S"
      } else if idx == mapped.count - 1 {
        labelText = "Z"
      } else {
        labelText = "\(idx + 1)"
      }
      let size = (labelText as NSString).size(withAttributes: labelAttrs)
      let labelPoint = CGPoint(x: point.x - size.width * 0.5, y: point.y - size.height * 0.5)
      (labelText as NSString).draw(at: labelPoint, withAttributes: labelAttrs)
    }
  }

  private static func drawRoomReportPages(
    entries: [RoomReportEntry],
    headerStats: HeaderStats,
    in context: UIGraphicsPDFRendererContext,
    pageRect: CGRect,
    projectTitle: String
  ) {
    let margin: CGFloat = 38
    let topInset: CGFloat = 94
    let bottomInset: CGFloat = 44
    let contentWidth = pageRect.width - (margin * 2)
    let maxY = pageRect.height - bottomInset

    let titleAttrs: [NSAttributedString.Key: Any] = [
      .font: UIFont.systemFont(ofSize: 18, weight: .bold),
      .foregroundColor: UIColor.black.withAlphaComponent(0.90)
    ]
    let subtitleAttrs: [NSAttributedString.Key: Any] = [
      .font: UIFont.systemFont(ofSize: 11, weight: .medium),
      .foregroundColor: UIColor.black.withAlphaComponent(0.60)
    ]
    let roomTitleAttrs: [NSAttributedString.Key: Any] = [
      .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
      .foregroundColor: UIColor.black.withAlphaComponent(0.86)
    ]
    let sectionTitleAttrs: [NSAttributedString.Key: Any] = [
      .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
      .foregroundColor: UIColor.black.withAlphaComponent(0.86)
    ]
    let bodyAttrs: [NSAttributedString.Key: Any] = [
      .font: UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
      .foregroundColor: UIColor.black.withAlphaComponent(0.80)
    ]
    let noteAttrs: [NSAttributedString.Key: Any] = [
      .font: UIFont.systemFont(ofSize: 10, weight: .regular),
      .foregroundColor: UIColor.black.withAlphaComponent(0.68)
    ]
    let metricTitleAttrs: [NSAttributedString.Key: Any] = [
      .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
      .foregroundColor: UIColor.black.withAlphaComponent(0.55)
    ]
    let metricValueAttrs: [NSAttributedString.Key: Any] = [
      .font: UIFont.monospacedDigitSystemFont(ofSize: 16, weight: .bold),
      .foregroundColor: UIColor.black.withAlphaComponent(0.88)
    ]
    let tableHeaderAttrs: [NSAttributedString.Key: Any] = [
      .font: UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold),
      .foregroundColor: UIColor.black.withAlphaComponent(0.72)
    ]
    let tableCellAttrs: [NSAttributedString.Key: Any] = [
      .font: UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
      .foregroundColor: UIColor.black.withAlphaComponent(0.82)
    ]

    var pageNumber = 0
    var y: CGFloat = .zero

    func beginReportPage(title: String, subtitle: String) {
      context.beginPage()
      pageNumber += 1
      let cg = context.cgContext
      cg.setFillColor(UIColor.white.cgColor)
      cg.fill(pageRect)

      (title as NSString).draw(
        at: CGPoint(x: margin, y: margin),
        withAttributes: titleAttrs
      )
      ("\(subtitle)   |   Seite \(pageNumber)" as NSString).draw(
        at: CGPoint(x: margin, y: margin + 24),
        withAttributes: subtitleAttrs
      )

      cg.setStrokeColor(UIColor.black.withAlphaComponent(0.12).cgColor)
      cg.setLineWidth(1)
      cg.move(to: CGPoint(x: margin, y: margin + 48))
      cg.addLine(to: CGPoint(x: pageRect.width - margin, y: margin + 48))
      cg.strokePath()

      y = topInset
    }

    func drawMetricCard(frame: CGRect, title: String, value: String) {
      let cg = context.cgContext
      cg.saveGState()
      cg.setFillColor(UIColor(white: 0.97, alpha: 1.0).cgColor)
      cg.addPath(UIBezierPath(roundedRect: frame, cornerRadius: 10).cgPath)
      cg.fillPath()
      cg.setStrokeColor(UIColor.black.withAlphaComponent(0.08).cgColor)
      cg.setLineWidth(1)
      cg.addPath(UIBezierPath(roundedRect: frame, cornerRadius: 10).cgPath)
      cg.strokePath()
      cg.restoreGState()

      (title as NSString).draw(
        in: CGRect(x: frame.minX + 12, y: frame.minY + 10, width: frame.width - 24, height: 14),
        withAttributes: metricTitleAttrs
      )
      (value as NSString).draw(
        in: CGRect(x: frame.minX + 12, y: frame.minY + 28, width: frame.width - 24, height: frame.height - 36),
        withAttributes: metricValueAttrs
      )
    }

    func drawSectionTitle(_ title: String) {
      (title as NSString).draw(
        at: CGPoint(x: margin, y: y),
        withAttributes: sectionTitleAttrs
      )
      y += 24
    }

    func drawDistributionTableHeader() {
      let cg = context.cgContext
      let headerRect = CGRect(x: margin, y: y, width: contentWidth, height: 24)
      cg.saveGState()
      cg.setFillColor(UIColor(white: 0.94, alpha: 1.0).cgColor)
      cg.addPath(UIBezierPath(roundedRect: headerRect, cornerRadius: 6).cgPath)
      cg.fillPath()
      cg.restoreGState()

      let roomWidth = contentWidth * 0.42
      let floorWidth = contentWidth * 0.18
      let areaWidth = contentWidth * 0.20
      let shareWidth = contentWidth - roomWidth - floorWidth - areaWidth

      ("Raum" as NSString).draw(
        in: CGRect(x: headerRect.minX + 10, y: headerRect.minY + 6, width: roomWidth - 12, height: 12),
        withAttributes: tableHeaderAttrs
      )
      ("Etage" as NSString).draw(
        in: CGRect(x: headerRect.minX + roomWidth + 4, y: headerRect.minY + 6, width: floorWidth - 8, height: 12),
        withAttributes: tableHeaderAttrs
      )
      ("Flaeche" as NSString).draw(
        in: CGRect(x: headerRect.minX + roomWidth + floorWidth + 4, y: headerRect.minY + 6, width: areaWidth - 8, height: 12),
        withAttributes: tableHeaderAttrs
      )
      ("Anteil" as NSString).draw(
        in: CGRect(x: headerRect.minX + roomWidth + floorWidth + areaWidth + 4, y: headerRect.minY + 6, width: shareWidth - 8, height: 12),
        withAttributes: tableHeaderAttrs
      )
      y = headerRect.maxY + 6
    }

    func drawDistributionRow(index: Int, roomName: String, floorName: String, areaText: String, shareText: String, emphasized: Bool = false) {
      let cg = context.cgContext
      let rowHeight: CGFloat = 24
      let rowRect = CGRect(x: margin, y: y, width: contentWidth, height: rowHeight)
      let roomWidth = contentWidth * 0.42
      let floorWidth = contentWidth * 0.18
      let areaWidth = contentWidth * 0.20
      let shareWidth = contentWidth - roomWidth - floorWidth - areaWidth

      cg.saveGState()
      let fillColor: UIColor
      if emphasized {
        fillColor = UIColor(red: 0.92, green: 0.96, blue: 1.0, alpha: 1.0)
      } else {
        fillColor = index.isMultiple(of: 2) ? UIColor(white: 0.985, alpha: 1.0) : UIColor.white
      }
      cg.setFillColor(fillColor.cgColor)
      cg.addPath(UIBezierPath(roundedRect: rowRect, cornerRadius: 6).cgPath)
      cg.fillPath()
      cg.setStrokeColor(UIColor.black.withAlphaComponent(0.05).cgColor)
      cg.setLineWidth(1)
      cg.addPath(UIBezierPath(roundedRect: rowRect, cornerRadius: 6).cgPath)
      cg.strokePath()
      cg.restoreGState()

      let cellAttrs: [NSAttributedString.Key: Any] = emphasized
        ? [
          .font: UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold),
          .foregroundColor: UIColor.black.withAlphaComponent(0.86)
        ]
        : tableCellAttrs

      (roomName as NSString).draw(
        in: CGRect(x: rowRect.minX + 10, y: rowRect.minY + 6, width: roomWidth - 12, height: 12),
        withAttributes: cellAttrs
      )
      (floorName as NSString).draw(
        in: CGRect(x: rowRect.minX + roomWidth + 4, y: rowRect.minY + 6, width: floorWidth - 8, height: 12),
        withAttributes: cellAttrs
      )
      (areaText as NSString).draw(
        in: CGRect(x: rowRect.minX + roomWidth + floorWidth + 4, y: rowRect.minY + 6, width: areaWidth - 8, height: 12),
        withAttributes: cellAttrs
      )
      (shareText as NSString).draw(
        in: CGRect(x: rowRect.minX + roomWidth + floorWidth + areaWidth + 4, y: rowRect.minY + 6, width: shareWidth - 8, height: 12),
        withAttributes: cellAttrs
      )
      y = rowRect.maxY + 4
    }

    let subtitle = "Projekt: \(projectTitle)"
    beginReportPage(title: "Flaechenuebersicht", subtitle: subtitle)

    if entries.isEmpty {
      ("Keine Raeume im Projekt." as NSString).draw(
        at: CGPoint(x: margin, y: y),
        withAttributes: bodyAttrs
      )
      return
    }

    let summaryEntries = entries.sorted { lhs, rhs in
      if abs(lhs.areaSqm - rhs.areaSqm) > 0.0001 { return lhs.areaSqm > rhs.areaSqm }
      if lhs.floorName != rhs.floorName { return lhs.floorName < rhs.floorName }
      return lhs.roomName < rhs.roomName
    }

    let totalArea = max(headerStats.totalArea, 0)
    let averageArea = summaryEntries.isEmpty ? 0 : totalArea / Double(summaryEntries.count)
    let cardGap: CGFloat = 12
    let cardWidth = (contentWidth - cardGap) * 0.5
    let cardHeight: CGFloat = 66
    drawMetricCard(
      frame: CGRect(x: margin, y: y, width: cardWidth, height: cardHeight),
      title: "Gesamtflaeche",
      value: "\(formattedDecimalValue(totalArea)) m2"
    )
    drawMetricCard(
      frame: CGRect(x: margin + cardWidth + cardGap, y: y, width: cardWidth, height: cardHeight),
      title: "Wohnflaeche (WoFlV ca.)",
      value: "\(formattedDecimalValue(max(headerStats.livingArea, 0))) m2"
    )
    y += cardHeight + cardGap
    drawMetricCard(
      frame: CGRect(x: margin, y: y, width: cardWidth, height: cardHeight),
      title: "Raeume",
      value: "\(summaryEntries.count)"
    )
    drawMetricCard(
      frame: CGRect(x: margin + cardWidth + cardGap, y: y, width: cardWidth, height: cardHeight),
      title: "Ø Raumflaeche",
      value: "\(formattedDecimalValue(averageArea)) m2"
    )
    y += cardHeight + 18

    let note = "Die Flaechenverteilung wird hier als Datenblatt getrennt vom visuellen Grundriss ausgegeben."
    let noteRect = (note as NSString).boundingRect(
      with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      attributes: noteAttrs,
      context: nil
    ).integral
    (note as NSString).draw(
      in: CGRect(x: margin, y: y, width: contentWidth, height: noteRect.height),
      withAttributes: noteAttrs
    )
    y += noteRect.height + 18

    drawSectionTitle("Verteilung nach Raum")
    drawDistributionTableHeader()

    for (index, entry) in summaryEntries.enumerated() {
      if y + 28 > maxY {
        beginReportPage(title: "Flaechenuebersicht", subtitle: subtitle)
        drawSectionTitle("Verteilung nach Raum")
        drawDistributionTableHeader()
      }
      let share = totalArea > 0 ? entry.areaSqm / totalArea : 0
      drawDistributionRow(
        index: index,
        roomName: entry.roomName,
        floorName: entry.floorName,
        areaText: "\(formattedDecimalValue(entry.areaSqm)) m2",
        shareText: formattedPercentValue(share)
      )
    }

    if y + 28 > maxY {
      beginReportPage(title: "Flaechenuebersicht", subtitle: subtitle)
      drawSectionTitle("Verteilung nach Raum")
      drawDistributionTableHeader()
    }
    drawDistributionRow(
      index: summaryEntries.count,
      roomName: "Gesamt",
      floorName: "alle",
      areaText: "\(formattedDecimalValue(totalArea)) m2",
      shareText: formattedPercentValue(totalArea > 0 ? 1.0 : 0.0),
      emphasized: true
    )

    beginReportPage(title: "Raumdaten", subtitle: subtitle)

    for (index, entry) in entries.enumerated() {
      let roomTitle = "\(index + 1). \(entry.roomName) (\(entry.floorName))"
      let bodyText = makeRoomReportBodyText(entry: entry)

      let roomTitleRect = (roomTitle as NSString).boundingRect(
        with: CGSize(width: contentWidth - 24, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: roomTitleAttrs,
        context: nil
      ).integral

      let bodyRect = (bodyText as NSString).boundingRect(
        with: CGSize(width: contentWidth - 24, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: bodyAttrs,
        context: nil
      ).integral

      let blockHeight = roomTitleRect.height + bodyRect.height + 28
      if y + blockHeight > maxY {
        beginReportPage(title: "Raumdaten", subtitle: subtitle)
      }

      let blockRect = CGRect(x: margin, y: y, width: contentWidth, height: blockHeight)
      let cg = context.cgContext
      cg.saveGState()
      cg.setFillColor(UIColor(white: 0.97, alpha: 1.0).cgColor)
      cg.addPath(UIBezierPath(roundedRect: blockRect, cornerRadius: 8).cgPath)
      cg.fillPath()
      cg.setStrokeColor(UIColor.black.withAlphaComponent(0.08).cgColor)
      cg.setLineWidth(1)
      cg.addPath(UIBezierPath(roundedRect: blockRect, cornerRadius: 8).cgPath)
      cg.strokePath()
      cg.restoreGState()

      (roomTitle as NSString).draw(
        in: CGRect(x: blockRect.minX + 12, y: blockRect.minY + 10, width: contentWidth - 24, height: roomTitleRect.height),
        withAttributes: roomTitleAttrs
      )
      (bodyText as NSString).draw(
        in: CGRect(x: blockRect.minX + 12, y: blockRect.minY + 14 + roomTitleRect.height, width: contentWidth - 24, height: bodyRect.height),
        withAttributes: bodyAttrs
      )

      y = blockRect.maxY + 10
    }
  }

  private static func makeRoomReportBodyText(entry: RoomReportEntry) -> String {
    let metricsLine = "Flaeche: \(formattedDecimalValue(entry.areaSqm)) m2 | Umfang: \(formattedDecimalValue(entry.perimeterMeters)) m | Abmessung: \(formattedDecimalValue(entry.widthMeters)) x \(formattedDecimalValue(entry.depthMeters)) m"
    let doorsLine = "Tueren (\(entry.doorWidths.count)): \(formattedOpeningList(entry.doorWidths))"
    let windowsLine = "Fenster (\(entry.windowWidths.count)): \(formattedOpeningList(entry.windowWidths))"
    let openingsLine = "Durchgaenge (\(entry.openingWidths.count)): \(formattedOpeningList(entry.openingWidths))"
    return [metricsLine, doorsLine, windowsLine, openingsLine].joined(separator: "\n")
  }

  private static func formattedOpeningList(_ widths: [Double]) -> String {
    guard !widths.isEmpty else { return "keine" }
    return widths.enumerated()
      .map { idx, value in "#\(idx + 1): \(formattedDecimalValue(value)) m" }
      .joined(separator: ", ")
  }

  private static func drawDimensionAnnotations(
    segments: [RenderedWallSegment],
    map: (Double, Double) -> CGPoint,
    cg: CGContext,
    planCenter: DPoint
  ) {
    guard !segments.isEmpty else { return }
    let centerPx = map(planCenter.x, planCenter.y)
    let valueAttrs: [NSAttributedString.Key: Any] = [
      .font: UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold),
      .foregroundColor: UIColor.black.withAlphaComponent(0.72)
    ]

    for rendered in segments {
      let meters = segmentLength(rendered.seg)
      guard meters >= 0.55 else { continue }

      let a = map(rendered.seg.ax, rendered.seg.ay)
      let b = map(rendered.seg.bx, rendered.seg.by)
      let vx = b.x - a.x
      let vy = b.y - a.y
      let lengthPx = (vx * vx + vy * vy).squareRoot()
      guard lengthPx >= 42 else { continue }

      var nx = -vy / lengthPx
      var ny = vx / lengthPx
      let mid = CGPoint(x: (a.x + b.x) * 0.5, y: (a.y + b.y) * 0.5)
      let towardMidX = mid.x - centerPx.x
      let towardMidY = mid.y - centerPx.y
      if (nx * towardMidX + ny * towardMidY) < 0 {
        nx *= -1
        ny *= -1
      }

      let offset: CGFloat = rendered.isInterior ? 14 : 24
      let extensionLen: CGFloat = rendered.isInterior ? 6 : 8
      let textPad: CGFloat = rendered.isInterior ? 9 : 12
      let dimA = CGPoint(x: a.x + nx * offset, y: a.y + ny * offset)
      let dimB = CGPoint(x: b.x + nx * offset, y: b.y + ny * offset)

      cg.saveGState()
      cg.setStrokeColor(UIColor.black.withAlphaComponent(rendered.isInterior ? 0.28 : 0.42).cgColor)
      cg.setLineWidth(rendered.isInterior ? 1.0 : 1.4)
      cg.setLineCap(.round)
      cg.setLineJoin(.round)

      // Extension lines
      cg.move(to: a)
      cg.addLine(to: CGPoint(x: a.x + nx * (offset + extensionLen), y: a.y + ny * (offset + extensionLen)))
      cg.move(to: b)
      cg.addLine(to: CGPoint(x: b.x + nx * (offset + extensionLen), y: b.y + ny * (offset + extensionLen)))

      // Dimension line
      cg.move(to: dimA)
      cg.addLine(to: dimB)

      // End ticks
      let tx = -ny
      let ty = nx
      let tick: CGFloat = rendered.isInterior ? 3.8 : 4.6
      cg.move(to: CGPoint(x: dimA.x + tx * tick, y: dimA.y + ty * tick))
      cg.addLine(to: CGPoint(x: dimA.x - tx * tick, y: dimA.y - ty * tick))
      cg.move(to: CGPoint(x: dimB.x + tx * tick, y: dimB.y + ty * tick))
      cg.addLine(to: CGPoint(x: dimB.x - tx * tick, y: dimB.y - ty * tick))
      cg.strokePath()
      cg.restoreGState()

      let label = formattedDimensionValue(meters)
      let textSize = (label as NSString).size(withAttributes: valueAttrs)
      let textCenter = CGPoint(
        x: (dimA.x + dimB.x) * 0.5 + nx * textPad,
        y: (dimA.y + dimB.y) * 0.5 + ny * textPad
      )
      let bubbleRect = CGRect(
        x: textCenter.x - textSize.width * 0.5 - 5,
        y: textCenter.y - textSize.height * 0.5 - 2,
        width: textSize.width + 10,
        height: textSize.height + 4
      )
      cg.saveGState()
      cg.setFillColor(UIColor.white.withAlphaComponent(0.96).cgColor)
      cg.addPath(UIBezierPath(roundedRect: bubbleRect, cornerRadius: 4).cgPath)
      cg.fillPath()
      cg.setStrokeColor(UIColor.black.withAlphaComponent(0.10).cgColor)
      cg.setLineWidth(1)
      cg.addPath(UIBezierPath(roundedRect: bubbleRect, cornerRadius: 4).cgPath)
      cg.strokePath()
      cg.restoreGState()
      (label as NSString).draw(
        at: CGPoint(
          x: textCenter.x - textSize.width * 0.5,
          y: textCenter.y - textSize.height * 0.5
        ),
        withAttributes: valueAttrs
      )
    }
  }

  private static func buildRenderedWallSegments(rooms: [RoomSegments]) -> [RenderedWallSegment] {
    var sources: [WallSourceSegment] = []
    for room in rooms {
      let worldSegs = transformedSegments(room: room)
      for seg in worldSegs {
        sources.append(WallSourceSegment(scanId: room.scan.id, seg: seg))
      }
    }

    guard !sources.isEmpty else { return [] }
    let clusters = clusterWallSources(sources)
    var rendered: [RenderedWallSegment] = []
    rendered.reserveCapacity(sources.count)
    for cluster in clusters {
      rendered.append(contentsOf: splitWallCluster(cluster, allSources: sources))
    }
    return rendered
  }

  private static func clusterWallSources(_ sources: [WallSourceSegment]) -> [[WallSourceSegment]] {
    guard !sources.isEmpty else { return [] }
    var remaining = Set(sources.indices)
    var groups: [[WallSourceSegment]] = []

    while let seed = remaining.first {
      remaining.remove(seed)
      var queue: [Int] = [seed]
      var groupIndices: [Int] = [seed]

      while let current = queue.popLast() {
        let neighbors = remaining.filter { shouldClusterAsSameWall(sources[current].seg, sources[$0].seg) }
        for neighbor in neighbors {
          remaining.remove(neighbor)
          queue.append(neighbor)
          groupIndices.append(neighbor)
        }
      }

      groups.append(groupIndices.map { sources[$0] })
    }

    return groups
  }

  private static func splitWallCluster(_ cluster: [WallSourceSegment], allSources: [WallSourceSegment]) -> [RenderedWallSegment] {
    guard !cluster.isEmpty else { return [] }

    let anchor = cluster.max(by: { segmentLength($0.seg) < segmentLength($1.seg) })?.seg ?? cluster[0].seg
    let axis = direction(of: anchor)
    let normal = DPoint(x: -axis.y, y: axis.x)

    let midpoints = cluster.map { midpoint(of: $0.seg) }
    let meanOffset = midpoints.map { dot($0, normal) }.reduce(0, +) / Double(max(midpoints.count, 1))
    let reference = midpoints.first ?? DPoint(x: 0, y: 0)
    let refOffset = dot(reference, normal)
    let lineOrigin = DPoint(
      x: reference.x + normal.x * (meanOffset - refOffset),
      y: reference.y + normal.y * (meanOffset - refOffset)
    )

    var knots: [Double] = []
    for source in cluster {
      let interval = projectionInterval(of: source.seg, origin: lineOrigin, axis: axis)
      knots.append(interval.min)
      knots.append(interval.max)
    }
    knots.sort()

    let knotEpsilon = 0.03
    var uniqueKnots: [Double] = []
    for knot in knots {
      if let last = uniqueKnots.last, abs(last - knot) <= knotEpsilon { continue }
      uniqueKnots.append(knot)
    }
    guard uniqueKnots.count >= 2 else { return [] }

    let segmentMinLength = 0.08
    let projectionPad = 0.03
    let coverDistanceTolerance = 0.12

    var pieces: [RenderedWallSegment] = []
    for idx in 0..<(uniqueKnots.count - 1) {
      let s0 = uniqueKnots[idx]
      let s1 = uniqueKnots[idx + 1]
      guard (s1 - s0) >= segmentMinLength else { continue }

      let midS = (s0 + s1) * 0.5
      let midPoint = DPoint(x: lineOrigin.x + axis.x * midS, y: lineOrigin.y + axis.y * midS)

      var coverageCount = 0
      var coveringRoomIds: Set<UUID> = []
      for source in cluster {
        let interval = projectionInterval(of: source.seg, origin: lineOrigin, axis: axis)
        if midS < interval.min - projectionPad || midS > interval.max + projectionPad { continue }
        if pointSegmentDistance(p: midPoint, seg: source.seg).dist <= coverDistanceTolerance {
          coverageCount += 1
          coveringRoomIds.insert(source.scanId)
        }
      }
      guard coverageCount > 0 else { continue }

      let isLikelySharedWall =
        coveringRoomIds.count >= 2 ||
        hasNearbyParallelWall(
          midpoint: midPoint,
          axis: axis,
          excludedScanIds: coveringRoomIds,
          allSources: allSources
        )

      let a = DPoint(x: lineOrigin.x + axis.x * s0, y: lineOrigin.y + axis.y * s0)
      let b = DPoint(x: lineOrigin.x + axis.x * s1, y: lineOrigin.y + axis.y * s1)
      pieces.append(
        RenderedWallSegment(
          seg: FloorplanSegment(ax: a.x, ay: a.y, bx: b.x, by: b.y),
          isInterior: isLikelySharedWall
        )
      )
    }

    return mergeRenderedWallPieces(pieces)
  }

  private static func hasNearbyParallelWall(
    midpoint: DPoint,
    axis: DPoint,
    excludedScanIds: Set<UUID>,
    allSources: [WallSourceSegment]
  ) -> Bool {
    let axisN = normalized(axis)
    for source in allSources {
      if excludedScanIds.contains(source.scanId) { continue }
      let dir = direction(of: source.seg)
      if abs(dot(axisN, dir)) < 0.90 { continue }
      let interval = projectionInterval(of: source.seg, origin: midpoint, axis: axisN)
      if interval.max < -0.45 || interval.min > 0.45 { continue }
      if pointSegmentDistance(p: midpoint, seg: source.seg).dist <= 0.26 {
        return true
      }
    }
    return false
  }

  private static func mergeRenderedWallPieces(_ pieces: [RenderedWallSegment]) -> [RenderedWallSegment] {
    guard !pieces.isEmpty else { return [] }
    var merged: [RenderedWallSegment] = []

    for piece in pieces {
      guard let last = merged.last else {
        merged.append(piece)
        continue
      }

      let sameType = last.isInterior == piece.isInterior
      let lastEnd = DPoint(x: last.seg.bx, y: last.seg.by)
      let currentStart = DPoint(x: piece.seg.ax, y: piece.seg.ay)
      let touching = distance(lastEnd, currentStart) <= 0.04
      let nearlyCollinear = abs(cross(direction(of: last.seg), direction(of: piece.seg))) <= 0.01

      if sameType && touching && nearlyCollinear {
        let extended = FloorplanSegment(ax: last.seg.ax, ay: last.seg.ay, bx: piece.seg.bx, by: piece.seg.by)
        merged[merged.count - 1] = RenderedWallSegment(seg: extended, isInterior: last.isInterior)
      } else {
        merged.append(piece)
      }
    }

    return merged
  }

  private static func shouldClusterAsSameWall(_ a: FloorplanSegment, _ b: FloorplanSegment) -> Bool {
    let lenA = segmentLength(a)
    let lenB = segmentLength(b)
    guard lenA >= 0.08, lenB >= 0.08 else { return false }

    let dirA = direction(of: a)
    let dirB = direction(of: b)
    guard abs(cross(dirA, dirB)) <= 0.12 else { return false }

    let midA = midpoint(of: a)
    let midB = midpoint(of: b)
    let lineDistance = min(
      distanceToInfiniteLine(point: midA, linePoint: midB, lineDirection: dirB),
      distanceToInfiniteLine(point: midB, linePoint: midA, lineDirection: dirA)
    )
    guard lineDistance <= 0.18 else { return false }

    let intervalA = projectionInterval(of: a, origin: midA, axis: dirA)
    let intervalB = projectionInterval(of: b, origin: midA, axis: dirA)
    let overlap = min(intervalA.max, intervalB.max) - max(intervalA.min, intervalB.min)
    let minOverlap = max(0.10, min(0.30, min(lenA, lenB) * 0.35))
    return overlap >= minOverlap
  }

  private static func projectionInterval(of seg: FloorplanSegment, origin: DPoint, axis: DPoint) -> (min: Double, max: Double) {
    let a = dot(DPoint(x: seg.ax - origin.x, y: seg.ay - origin.y), axis)
    let b = dot(DPoint(x: seg.bx - origin.x, y: seg.by - origin.y), axis)
    return (min(a, b), max(a, b))
  }

  private static func distanceToInfiniteLine(point: DPoint, linePoint: DPoint, lineDirection: DPoint) -> Double {
    let rel = DPoint(x: point.x - linePoint.x, y: point.y - linePoint.y)
    return abs(cross(rel, lineDirection))
  }

  private static func pointSegmentDistance(p: DPoint, seg: FloorplanSegment) -> (dist: Double, t: Double) {
    let vx = seg.bx - seg.ax
    let vy = seg.by - seg.ay
    let wx = p.x - seg.ax
    let wy = p.y - seg.ay
    let vv = vx * vx + vy * vy
    if vv <= 1e-9 {
      let d = ((p.x - seg.ax) * (p.x - seg.ax) + (p.y - seg.ay) * (p.y - seg.ay)).squareRoot()
      return (d, 0)
    }
    var t = (wx * vx + wy * vy) / vv
    t = min(max(t, 0), 1)
    let cx = seg.ax + vx * t
    let cy = seg.ay + vy * t
    let dx = p.x - cx
    let dy = p.y - cy
    let dist = (dx * dx + dy * dy).squareRoot()
    return (dist, t)
  }

  private static func segmentLength(_ seg: FloorplanSegment) -> Double {
    let dx = seg.bx - seg.ax
    let dy = seg.by - seg.ay
    return (dx * dx + dy * dy).squareRoot()
  }

  private static func midpoint(of seg: FloorplanSegment) -> DPoint {
    DPoint(x: (seg.ax + seg.bx) * 0.5, y: (seg.ay + seg.by) * 0.5)
  }

  private static func direction(of seg: FloorplanSegment) -> DPoint {
    normalized(DPoint(x: seg.bx - seg.ax, y: seg.by - seg.ay))
  }

  private static func normalized(_ v: DPoint) -> DPoint {
    let len = (v.x * v.x + v.y * v.y).squareRoot()
    guard len > 1e-9 else { return DPoint(x: 1, y: 0) }
    return DPoint(x: v.x / len, y: v.y / len)
  }

  private static func dot(_ a: DPoint, _ b: DPoint) -> Double {
    a.x * b.x + a.y * b.y
  }

  private static func cross(_ a: DPoint, _ b: DPoint) -> Double {
    a.x * b.y - a.y * b.x
  }

  private static func distance(_ a: DPoint, _ b: DPoint) -> Double {
    let dx = a.x - b.x
    let dy = a.y - b.y
    return (dx * dx + dy * dy).squareRoot()
  }

  private static func centroid(of segments: [FloorplanSegment]) -> DPoint? {
    guard !segments.isEmpty else { return nil }
    var sumX = 0.0
    var sumY = 0.0
    var count = 0.0
    for seg in segments {
      sumX += seg.ax + seg.bx
      sumY += seg.ay + seg.by
      count += 2.0
    }
    return DPoint(x: sumX / count, y: sumY / count)
  }

  private struct HullPoint: Comparable, Hashable {
    let x: Double
    let y: Double

    static func < (lhs: HullPoint, rhs: HullPoint) -> Bool {
      if lhs.x != rhs.x { return lhs.x < rhs.x }
      return lhs.y < rhs.y
    }
  }

  private static func convexHullPoints(segments: [FloorplanSegment]) -> [DPoint] {
    let points = uniqueHullPoints(from: segments).sorted()
    guard points.count >= 3 else { return [] }

    func orient(_ o: HullPoint, _ a: HullPoint, _ b: HullPoint) -> Double {
      (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
    }

    var lower: [HullPoint] = []
    for point in points {
      while lower.count >= 2, orient(lower[lower.count - 2], lower[lower.count - 1], point) <= 0 {
        lower.removeLast()
      }
      lower.append(point)
    }

    var upper: [HullPoint] = []
    for point in points.reversed() {
      while upper.count >= 2, orient(upper[upper.count - 2], upper[upper.count - 1], point) <= 0 {
        upper.removeLast()
      }
      upper.append(point)
    }

    let hull = Array(lower.dropLast() + upper.dropLast())
    return hull.map { DPoint(x: $0.x, y: $0.y) }
  }

  private static func uniqueHullPoints(from segments: [FloorplanSegment]) -> [HullPoint] {
    let tolerance = 0.03
    var out: [HullPoint] = []
    out.reserveCapacity(segments.count * 2)

    func insert(_ candidate: HullPoint) {
      for existing in out {
        let dx = existing.x - candidate.x
        let dy = existing.y - candidate.y
        if (dx * dx + dy * dy).squareRoot() < tolerance {
          return
        }
      }
      out.append(candidate)
    }

    for seg in segments {
      insert(HullPoint(x: seg.ax, y: seg.ay))
      insert(HullPoint(x: seg.bx, y: seg.by))
    }

    return out
  }

  private static func livingAreaFactor(for roomId: String) -> Double {
    if let override = livingAreaFactorOverrides[roomId] {
      return max(0.0, min(1.0, override))
    }
    guard let room = RoomTaxonomy.rooms.first(where: { $0.id == roomId }) else { return 0.0 }
    switch room.category {
    case .interior:
      return 1.0
    case .exterior, .other:
      return 0.0
    }
  }

  private static func formattedDimensionValue(_ meters: Double) -> String {
    "\(formattedDecimalValue(max(0, meters))) m"
  }

  private static func formattedDecimalValue(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale.current
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    return formatter.string(from: NSNumber(value: max(0, value))) ?? String(format: "%.2f", max(0, value))
  }

  private static func formattedPercentNumberValue(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale.current
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 1
    formatter.maximumFractionDigits = 1
    return formatter.string(from: NSNumber(value: max(0, value))) ?? String(format: "%.1f", max(0, value))
  }

  private static func formattedMachineDecimalValue(_ value: Double, fractionDigits: Int = 2) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.decimalSeparator = "."
    formatter.groupingSeparator = ""
    formatter.minimumFractionDigits = fractionDigits
    formatter.maximumFractionDigits = fractionDigits
    return formatter.string(from: NSNumber(value: max(0, value))) ?? String(format: "%.\(fractionDigits)f", max(0, value))
  }

  private static func formattedMachinePercentNumberValue(_ value: Double) -> String {
    formattedMachineDecimalValue(value, fractionDigits: 1)
  }

  private static func formattedPercentValue(_ fraction: Double) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale.current
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 1
    formatter.maximumFractionDigits = 1
    let percentValue = max(0, fraction) * 100
    let number = formatter.string(from: NSNumber(value: percentValue)) ?? String(format: "%.1f", percentValue)
    return "\(number) %"
  }

  private static func iso8601String(from date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }

  private static func openImmoDateString(from date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }

  private static func openImmoDateTimeString(from date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    return formatter.string(from: date)
  }

  private static func parseAddress(_ address: String) -> ParsedAddress? {
    let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let patterns = [
      #"^\s*(.+?)\s+(\d+[A-Za-z\-\/]*)\s*,\s*(\d{5})\s+(.+?)\s*$"#,
      #"^\s*(.+?)\s+(\d+[A-Za-z\-\/]*)\s+(\d{5})\s+(.+?)\s*$"#,
      #"^\s*(.+?)\s*,\s*(\d{5})\s+(.+?)\s*$"#
    ]

    for pattern in patterns {
      guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
      let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
      guard let match = regex.firstMatch(in: trimmed, options: [], range: range) else { continue }

      let values = (1..<match.numberOfRanges).compactMap { index -> String? in
        let groupRange = match.range(at: index)
        guard let range = Range(groupRange, in: trimmed) else { return nil }
        return String(trimmed[range]).trimmingCharacters(in: .whitespacesAndNewlines)
      }

      if values.count == 4 {
        return ParsedAddress(
          street: values[0],
          houseNumber: values[1],
          postalCode: values[2],
          city: values[3]
        )
      }

      if values.count == 3 {
        return ParsedAddress(
          street: values[0],
          houseNumber: nil,
          postalCode: values[1],
          city: values[2]
        )
      }
    }

    return ParsedAddress(street: trimmed, houseNumber: nil, postalCode: nil, city: nil)
  }

  private static func xmlEscapedValue(_ value: String) -> String {
    value
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
  }

  private static func xmlEscapedAttributeValue(_ value: String) -> String {
    xmlEscapedValue(value)
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&apos;")
  }

  private static func uniqueOrderedStrings(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for value in values {
      if seen.insert(value).inserted {
        out.append(value)
      }
    }
    return out
  }

  private static func transformedSegments(room: RoomSegments) -> [FloorplanSegment] {
    transformedSegments(segments: room.segments, t: room.scan.transform)
  }

  private static func transformedSegments(segments: [FloorplanSegment], t: FloorplanRoomTransform) -> [FloorplanSegment] {
    let cosR = cos(t.rotationRadians)
    let sinR = sin(t.rotationRadians)

    func apply(x: Double, y: Double) -> (Double, Double) {
      let rx = x * cosR - y * sinR
      let ry = x * sinR + y * cosR
      return (rx + t.translationX, ry + t.translationY)
    }

    return segments.map { seg in
      let (ax, ay) = apply(x: seg.ax, y: seg.ay)
      let (bx, by) = apply(x: seg.bx, y: seg.by)
      return FloorplanSegment(ax: ax, ay: ay, bx: bx, by: by)
    }
  }
}
