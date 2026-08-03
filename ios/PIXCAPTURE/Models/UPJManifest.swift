import Foundation

struct UPJManifest: Codable {
  let version: String
  let projectId: String
  let uploadTimestamp: String
  let assets: Assets
  let pipelineConfig: PipelineConfig

  struct Assets: Codable {
    var lidar: String?
    var acoustics: String?
    var motionData: String?
    var mainVideo: String?
    var intrinsics: String?
    var livingPortraits: [LivingPortrait]?

    enum CodingKeys: String, CodingKey {
      case lidar
      case acoustics
      case motionData = "motion_data"
      case mainVideo = "main_video"
      case intrinsics
      case livingPortraits = "living_portraits"
    }
  }

  struct LivingPortrait: Codable {
    var filename: String
    var focusObject: String?
    var effect: String?

    enum CodingKeys: String, CodingKey {
      case filename
      case focusObject = "focus_object"
      case effect
    }
  }

  struct PipelineConfig: Codable {
    var runSplatting: Bool
    var runAcoustics: Bool
    var stylePreset: String?

    enum CodingKeys: String, CodingKey {
      case runSplatting = "run_splatting"
      case runAcoustics = "run_acoustics"
      case stylePreset = "style_preset"
    }
  }

  enum CodingKeys: String, CodingKey {
    case version
    case projectId = "project_id"
    case uploadTimestamp = "upload_timestamp"
    case assets
    case pipelineConfig = "pipeline_config"
  }
}

