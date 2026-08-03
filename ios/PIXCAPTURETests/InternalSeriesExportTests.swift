import Foundation
import Testing
@testable import PIXCAPTURE

struct InternalSeriesExportTests {

  @Test("Internal series export stages JSON and capture files together")
  func prepareInternalSeriesExport() throws {
    let fm = FileManager.default
    let sourceRoot = fm.temporaryDirectory.appendingPathComponent(
      "pixcapture-internal-export-source-\(UUID().uuidString)",
      isDirectory: true
    )
    try fm.createDirectory(at: sourceRoot, withIntermediateDirectories: true)

    var exportDirectoryURL: URL?
    defer {
      if let exportDirectoryURL {
        try? fm.removeItem(at: exportDirectoryURL)
      }
      try? fm.removeItem(at: sourceRoot)
    }

    let exifURL = sourceRoot.appendingPathComponent("exif-series.json")
    let photoOneURL = sourceRoot.appendingPathComponent("living_room_eg_motif-1_01.dng")
    let photoTwoURL = sourceRoot.appendingPathComponent("living_room_eg_motif-1_02.dng")

    try Data("[]".utf8).write(to: exifURL, options: [.atomic])
    try Data("raw-one".utf8).write(to: photoOneURL, options: [.atomic])
    try Data("raw-two".utf8).write(to: photoTwoURL, options: [.atomic])

    let recordOne = UploadRecord(
      id: UUID(),
      seriesId: UUID(uuidString: "4D3DA4B7-7478-4D21-9AFA-0730D030887A")!,
      localShootId: "shoot-1",
      fileURL: photoOneURL,
      originalFileURL: nil,
      exifLogURL: exifURL,
      roomId: "living_room",
      floorId: "eg",
      jobLabel: "Test Job",
      jobId: nil,
      seriesIndex: 1,
      exposureEV: -1.0,
      exposureSeconds: 0.02,
      iso: 100,
      captureMode: .standardBracket,
      captureOrientation: "portrait",
      metadataReady: true,
      createdAt: Date(timeIntervalSince1970: 1_731_000_000),
      status: .pending,
      remoteKey: nil
    )

    let recordTwo = UploadRecord(
      id: UUID(),
      seriesId: recordOne.seriesId,
      localShootId: "shoot-1",
      fileURL: photoTwoURL,
      originalFileURL: nil,
      exifLogURL: exifURL,
      roomId: "living_room",
      floorId: "eg",
      jobLabel: "Test Job",
      jobId: nil,
      seriesIndex: 1,
      exposureEV: 1.0,
      exposureSeconds: 0.08,
      iso: 200,
      captureMode: .standardBracket,
      captureOrientation: "portrait",
      metadataReady: true,
      createdAt: Date(timeIntervalSince1970: 1_731_000_001),
      status: .pending,
      remoteKey: nil
    )

    let prepared = try FileStore.prepareInternalSeriesExport(
      records: [recordOne, recordTwo],
      exifLogURL: exifURL
    )
    exportDirectoryURL = prepared.directoryURL

    #expect(fm.fileExists(atPath: prepared.directoryURL.path))
    #expect(prepared.itemURLs.count == 3)
    #expect(
      Set(prepared.itemURLs.map(\.lastPathComponent)) == Set([
        "exif-series.json",
        "living_room_eg_motif-1_01.dng",
        "living_room_eg_motif-1_02.dng"
      ])
    )

    let exportedPhotoOneURL = try #require(
      prepared.itemURLs.first(where: { $0.lastPathComponent == "living_room_eg_motif-1_01.dng" })
    )
    let exportedExifURL = try #require(
      prepared.itemURLs.first(where: { $0.lastPathComponent == "exif-series.json" })
    )

    #expect(try Data(contentsOf: exportedPhotoOneURL) == Data("raw-one".utf8))
    #expect(try Data(contentsOf: exportedExifURL) == Data("[]".utf8))
  }

  @Test("Internal series ZIP export creates one archive with JSON and capture files")
  func prepareInternalSeriesZipExport() throws {
    let fm = FileManager.default
    let sourceRoot = fm.temporaryDirectory.appendingPathComponent(
      "pixcapture-internal-zip-source-\(UUID().uuidString)",
      isDirectory: true
    )
    try fm.createDirectory(at: sourceRoot, withIntermediateDirectories: true)

    var exportDirectoryURL: URL?
    defer {
      if let exportDirectoryURL {
        try? fm.removeItem(at: exportDirectoryURL)
      }
      try? fm.removeItem(at: sourceRoot)
    }

    let exifURL = sourceRoot.appendingPathComponent("exif-series.json")
    let photoOneURL = sourceRoot.appendingPathComponent("living_room_eg_motif-1_01.dng")
    let photoTwoURL = sourceRoot.appendingPathComponent("living_room_eg_motif-1_02.dng")

    try Data("[]".utf8).write(to: exifURL, options: [.atomic])
    try Data("raw-one".utf8).write(to: photoOneURL, options: [.atomic])
    try Data("raw-two".utf8).write(to: photoTwoURL, options: [.atomic])

    let recordOne = UploadRecord(
      id: UUID(),
      seriesId: UUID(uuidString: "81D46C52-7B5B-4C53-8FE4-0ED4232EA4B5")!,
      localShootId: "shoot-1",
      fileURL: photoOneURL,
      originalFileURL: nil,
      exifLogURL: exifURL,
      roomId: "living_room",
      floorId: "eg",
      jobLabel: "Test Job",
      jobId: nil,
      seriesIndex: 1,
      exposureEV: -1.0,
      exposureSeconds: 0.02,
      iso: 100,
      captureMode: .standardBracket,
      captureOrientation: "portrait",
      metadataReady: true,
      createdAt: Date(timeIntervalSince1970: 1_731_000_000),
      status: .pending,
      remoteKey: nil
    )

    let recordTwo = UploadRecord(
      id: UUID(),
      seriesId: recordOne.seriesId,
      localShootId: "shoot-1",
      fileURL: photoTwoURL,
      originalFileURL: nil,
      exifLogURL: exifURL,
      roomId: "living_room",
      floorId: "eg",
      jobLabel: "Test Job",
      jobId: nil,
      seriesIndex: 1,
      exposureEV: 1.0,
      exposureSeconds: 0.08,
      iso: 200,
      captureMode: .standardBracket,
      captureOrientation: "portrait",
      metadataReady: true,
      createdAt: Date(timeIntervalSince1970: 1_731_000_001),
      status: .pending,
      remoteKey: nil
    )

    let prepared = try FileStore.prepareInternalSeriesZipExport(
      records: [recordOne, recordTwo],
      exifLogURL: exifURL
    )
    exportDirectoryURL = prepared.directoryURL

    #expect(fm.fileExists(atPath: prepared.directoryURL.path))
    #expect(prepared.itemURLs.count == 1)

    let archiveURL = try #require(prepared.itemURLs.first)
    #expect(archiveURL.pathExtension.lowercased() == "zip")

    let archiveEntries = try storedZipEntries(at: archiveURL)
    #expect(Set(archiveEntries.keys) == Set([
      "exif-series.json",
      "living_room_eg_motif-1_01.dng",
      "living_room_eg_motif-1_02.dng"
    ]))
    #expect(archiveEntries["exif-series.json"] == Data("[]".utf8))
    #expect(archiveEntries["living_room_eg_motif-1_01.dng"] == Data("raw-one".utf8))
    #expect(archiveEntries["living_room_eg_motif-1_02.dng"] == Data("raw-two".utf8))
  }
}

private func storedZipEntries(at archiveURL: URL) throws -> [String: Data] {
  let data = try Data(contentsOf: archiveURL)
  var offset = 0
  var entries: [String: Data] = [:]

  while offset + 4 <= data.count {
    let signature = try readUInt32(from: data, at: offset)

    if signature == 0x04034b50 {
      let compressionMethod = try readUInt16(from: data, at: offset + 8)
      if compressionMethod != 0 {
        throw StoredZipParseError.unsupportedCompressionMethod(compressionMethod)
      }

      let compressedSize = Int(try readUInt32(from: data, at: offset + 18))
      let uncompressedSize = Int(try readUInt32(from: data, at: offset + 22))
      let fileNameLength = Int(try readUInt16(from: data, at: offset + 26))
      let extraFieldLength = Int(try readUInt16(from: data, at: offset + 28))
      let nameStart = offset + 30
      let nameEnd = nameStart + fileNameLength
      let dataStart = nameEnd + extraFieldLength
      let dataEnd = dataStart + compressedSize

      guard nameEnd <= data.count, dataEnd <= data.count else {
        throw StoredZipParseError.truncatedArchive
      }

      let nameData = data.subdata(in: nameStart..<nameEnd)
      guard let fileName = String(data: nameData, encoding: .utf8) else {
        throw StoredZipParseError.invalidFileNameEncoding
      }

      if compressedSize != uncompressedSize {
        throw StoredZipParseError.sizeMismatch(fileName)
      }

      entries[fileName] = data.subdata(in: dataStart..<dataEnd)
      offset = dataEnd
      continue
    }

    if signature == 0x02014b50 || signature == 0x06054b50 {
      break
    }

    throw StoredZipParseError.invalidSignature(signature)
  }

  return entries
}

private func readUInt16(from data: Data, at offset: Int) throws -> UInt16 {
  guard offset + 2 <= data.count else {
    throw StoredZipParseError.truncatedArchive
  }

  return UInt16(data[offset])
    | (UInt16(data[offset + 1]) << 8)
}

private func readUInt32(from data: Data, at offset: Int) throws -> UInt32 {
  guard offset + 4 <= data.count else {
    throw StoredZipParseError.truncatedArchive
  }

  return UInt32(data[offset])
    | (UInt32(data[offset + 1]) << 8)
    | (UInt32(data[offset + 2]) << 16)
    | (UInt32(data[offset + 3]) << 24)
}

private enum StoredZipParseError: Error {
  case invalidSignature(UInt32)
  case invalidFileNameEncoding
  case sizeMismatch(String)
  case truncatedArchive
  case unsupportedCompressionMethod(UInt16)
}
