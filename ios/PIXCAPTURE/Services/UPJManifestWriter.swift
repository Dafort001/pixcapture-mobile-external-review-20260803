import Foundation

enum UPJManifestWriter {
  static func write(
    projectId: UUID,
    outputURL: URL,
    includeLidar: Bool,
    includeVideo: Bool,
    includeMotion: Bool,
    includeIntrinsics: Bool,
    includeAcoustics: Bool,
    lidarPath: String = "scan.usdz",
    mainVideoPath: String = "video/main_scan.mov",
    motionDataPath: String = "sensors.csv",
    intrinsicsPath: String = "intrinsics.json",
    acousticsPath: String = "acoustics.wav"
  ) throws {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    var assets = UPJManifest.Assets()
    if includeLidar { assets.lidar = lidarPath }
    if includeAcoustics { assets.acoustics = acousticsPath }
    if includeMotion { assets.motionData = motionDataPath }
    if includeVideo { assets.mainVideo = mainVideoPath }
    if includeIntrinsics { assets.intrinsics = intrinsicsPath }

    let manifest = UPJManifest(
      version: "2.0",
      projectId: projectId.uuidString,
      uploadTimestamp: formatter.string(from: Date()),
      assets: assets,
      pipelineConfig: UPJManifest.PipelineConfig(
        runSplatting: includeLidar && includeVideo,
        runAcoustics: includeAcoustics,
        stylePreset: nil
      )
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(manifest)
    try data.write(to: outputURL, options: [.atomic])
  }
}
