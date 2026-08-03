import Foundation
import CoreMedia

enum PhotoCaptureMode: String, CaseIterable, Codable {
  case standardBracket = "standardBracket"
  case darkRoom = "darkRoom"
  case singleShot = "single_shot"

  var manifestSubtype: String? {
    switch self {
    case .standardBracket:
      return nil
    case .darkRoom:
      return "dark_room_single"
    case .singleShot:
      return "single_shot"
    }
  }
}

enum SingleShotCorrectabilityStatus: String, Codable {
  case good
  case usable
  case retake

  var manifestToken: String { rawValue }

  var feedbackText: String {
    switch self {
    case .good:
      return "Aufnahme ok"
    case .usable:
      return "Noch korrigierbar"
    case .retake:
      return "Bitte neu aufnehmen - zu stark gekippt"
    }
  }
}

struct SingleShotCorrectionPolicy {
  static let rollGoodDegrees = 2.0
  static let rollUsableDegrees = 6.0
  static let pitchGoodDegrees = 2.0
  static let pitchUsableDegrees = 6.0
  static let intendedProcessing = "single_image_external_or_standard_pipeline"

  static func assess(
    rollDegrees: Double,
    pitchDegrees: Double
  ) -> SingleShotCorrectabilityStatus {
    let roll = abs(rollDegrees)
    let pitch = abs(pitchDegrees)

    if roll <= rollGoodDegrees, pitch <= pitchGoodDegrees {
      return .good
    }
    if roll <= rollUsableDegrees, pitch <= pitchUsableDegrees {
      return .usable
    }
    return .retake
  }
}

struct SingleShotCaptureAssessment: Codable, Equatable {
  let triggeredAt: Date
  let rollDegrees: Double
  let pitchDegrees: Double
  let stabilityScore: Double?
  let stabilityState: String?
  let status: SingleShotCorrectabilityStatus
  let intendedProcessing: String

  init(
    triggeredAt: Date,
    rollDegrees: Double,
    pitchDegrees: Double,
    stabilityScore: Double?,
    stabilityState: String?
  ) {
    self.triggeredAt = triggeredAt
    self.rollDegrees = rollDegrees
    self.pitchDegrees = pitchDegrees
    self.stabilityScore = stabilityScore
    self.stabilityState = stabilityState
    self.status = SingleShotCorrectionPolicy.assess(
      rollDegrees: rollDegrees,
      pitchDegrees: pitchDegrees
    )
    self.intendedProcessing = SingleShotCorrectionPolicy.intendedProcessing
  }
}

enum BracketMeteringMode: String, CaseIterable, Codable {
  case previewBalanced
  case highlightAnchor
}

struct CaptureSeriesConfig {
  let bracketCount: Int
  let stepEV: Double
  let maxExposureSeconds: Double
  let exposureBiasEV: Double
  let bracketMeteringMode: BracketMeteringMode
  let captureDelaySeconds: Double
  let photoFormat: PhotoFormat
  let isoOverride: Float?
  let baseShutterSeconds: Double
  let roomId: String
  let floorId: String
  let outputAspectRatio: Double
  let captureMode: PhotoCaptureMode
  let singleShotAssessment: SingleShotCaptureAssessment?
}

enum BracketStepPolicy {
  static let denseBracketStepEV = 1.5

  static func effectiveStepEV(
    configuredStepEV: Double,
    bracketCount: Int,
    photoFormat: PhotoFormat
  ) -> Double {
    let normalizedCount = max(1, bracketCount)
    let denseAdjustedStepEV = normalizedCount >= 5
      ? min(configuredStepEV, denseBracketStepEV)
      : configuredStepEV

    if photoFormat == .proRaw {
      return denseAdjustedStepEV
    }

    return min(denseAdjustedStepEV, 1.0)
  }
}

struct CapturedPhoto: Identifiable {
  let id: UUID
  let fileURL: URL
  let originalFileURL: URL?
  let exposureEV: Double
  let exposureDuration: CMTime
  let iso: Float
  let captureOrientation: String?
  let sensorPitchDegrees: Double?
  let sensorRollDegrees: Double?
  let sensorHeadingDegrees: Double?
  let captureMode: PhotoCaptureMode
  let singleShotAssessment: SingleShotCaptureAssessment?
}

struct CaptureSeriesSummary {
  let seriesId: UUID
  let roomId: String
  let floorId: String
  let photos: [CapturedPhoto]
  let trimmedFromCount: Int
  let exifLogURL: URL?
  let metadataReady: Bool
  let captureMode: PhotoCaptureMode
  let singleShotAssessment: SingleShotCaptureAssessment?
}
