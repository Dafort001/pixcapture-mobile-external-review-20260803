//
//  PIXCAPTURETests.swift
//  PIXCAPTURETests
//
//  Created by Daniel Fortmann on 05.02.26.
//

import CoreMedia
import CoreGraphics
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import PIXCAPTURE

struct PIXCAPTURETests {

  @Test("Five-shot bracketing favors darker window-preserving exposures")
  func fiveShotBracketUsesDarkerOffsets() {
    let samples = ExposureSeriesBuilder.buildHybridDurations(
      baseDuration: CMTimeMake(value: 100, timescale: 6_000),
      baseISO: 100,
      stepEV: 2.0,
      count: 5,
      minDuration: CMTimeMake(value: 1, timescale: 8_000),
      maxDuration: CMTimeMake(value: 24_000, timescale: 6_000),
      minISO: 25,
      maxSafeISO: 800,
      seriesShape: .highlightPriority
    )

    #expect(samples.map(\.requestedEV) == [-6.0, -4.0, -2.0, 0.0, 2.0])
  }

  @Test("Five-shot exterior bracketing keeps the balanced range")
  func fiveShotExteriorBracketUsesBalancedOffsets() {
    let samples = ExposureSeriesBuilder.buildHybridDurations(
      baseDuration: CMTimeMake(value: 100, timescale: 6_000),
      baseISO: 100,
      stepEV: 2.0,
      count: 5,
      minDuration: CMTimeMake(value: 1, timescale: 8_000),
      maxDuration: CMTimeMake(value: 24_000, timescale: 6_000),
      minISO: 25,
      maxSafeISO: 800,
      seriesShape: .balanced
    )

    #expect(samples.map(\.requestedEV) == [-4.0, -2.0, 0.0, 2.0, 4.0])
  }

  @Test("Seven-shot bracketing keeps the full symmetric range")
  func sevenShotBracketRemainsSymmetric() {
    let samples = ExposureSeriesBuilder.buildHybridDurations(
      baseDuration: CMTimeMake(value: 100, timescale: 6_000),
      baseISO: 100,
      stepEV: 2.0,
      count: 7,
      minDuration: CMTimeMake(value: 1, timescale: 8_000),
      maxDuration: CMTimeMake(value: 48_000, timescale: 6_000),
      minISO: 25,
      maxSafeISO: 800
    )

    #expect(samples.map(\.requestedEV) == [-6.0, -4.0, -2.0, 0.0, 2.0, 4.0, 6.0])
  }

  @Test("Highlight-anchor planning keeps symmetric two-stop spacing for three shots")
  func highlightAnchorThreeShotOffsetsRunDownward() {
    #expect(
      ExposureSeriesBuilder.requestedOffsets(
        for: 3,
        stepEV: 2.0,
        seriesShape: .highlightAnchor
      ) == [-2.0, 0.0, 2.0]
    )
  }

  @Test("Highlight-anchor planning keeps symmetric two-stop spacing for five shots")
  func highlightAnchorFiveShotOffsetsRunDownward() {
    #expect(
      ExposureSeriesBuilder.requestedOffsets(
        for: 5,
        stepEV: 2.0,
        seriesShape: .highlightAnchor
      ) == [-4.0, -2.0, 0.0, 2.0, 4.0]
    )
  }

  @Test("Highlight-anchor planning keeps symmetric two-stop spacing for seven shots")
  func highlightAnchorSevenShotOffsetsRunDownward() {
    #expect(
      ExposureSeriesBuilder.requestedOffsets(
        for: 7,
        stepEV: 2.0,
        seriesShape: .highlightAnchor
      ) == [-6.0, -4.0, -2.0, 0.0, 2.0, 4.0, 6.0]
    )
  }

  @Test("Lower exterior ISO restores distinct dark five-shot exposures")
  func lowerExteriorISORestoresFullBracketCount() {
    let compressedAtHigherISO = ExposureSeriesBuilder.buildHybridDurations(
      baseDuration: CMTimeMake(value: 3, timescale: 6_000),
      baseISO: 100,
      stepEV: 2.0,
      count: 5,
      minDuration: CMTimeMake(value: 1, timescale: 8_000),
      maxDuration: CMTimeMake(value: 24_000, timescale: 6_000),
      minISO: 25,
      maxSafeISO: 800,
      seriesShape: .balanced
    )

    let recoveredAtLowerISO = ExposureSeriesBuilder.buildHybridDurations(
      baseDuration: CMTimeMake(value: 6, timescale: 6_000),
      baseISO: 50,
      stepEV: 2.0,
      count: 5,
      minDuration: CMTimeMake(value: 1, timescale: 8_000),
      maxDuration: CMTimeMake(value: 24_000, timescale: 6_000),
      minISO: 25,
      maxSafeISO: 800,
      seriesShape: .balanced
    )

    #expect(compressedAtHigherISO.count == 4)
    #expect(recoveredAtLowerISO.count == 5)
  }

  @Test("Exterior helper shifts the bracket brighter when the dark edge collapses")
  func exteriorHelperShiftsBracketBrighter() {
    let baseDuration = CMTimeMake(value: 3, timescale: 6_000)
    let minDuration = CMTimeMake(value: 1, timescale: 8_000)
    let maxDuration = CMTimeMake(value: 24_000, timescale: 6_000)
    let initialSamples = ExposureSeriesBuilder.buildHybridDurations(
      baseDuration: baseDuration,
      baseISO: 50,
      stepEV: 2.0,
      count: 5,
      minDuration: minDuration,
      maxDuration: maxDuration,
      minISO: 25,
      maxSafeISO: 800,
      seriesShape: .balanced
    )

    #expect(
      ExposureSeriesBuilder.needsBrighterExteriorShift(
        samples: initialSamples,
        expectedCount: 5,
        minDuration: minDuration,
        minimumDistinctDarkGapEV: 1.0
      )
    )

    let shiftedCenterEV = ExposureSeriesBuilder.brighterCenterShiftForExterior(
      baseDuration: baseDuration,
      baseISO: 50,
      stepEV: 2.0,
      count: 5,
      minDuration: minDuration,
      maxDuration: maxDuration,
      minISO: 25,
      maxSafeISO: 800,
      seriesShape: .balanced,
      minimumDistinctDarkGapEV: 1.0
    )
    let shiftedSamples = ExposureSeriesBuilder.buildHybridDurations(
      baseDuration: baseDuration,
      baseISO: 50,
      stepEV: 2.0,
      count: 5,
      minDuration: minDuration,
      maxDuration: maxDuration,
      minISO: 25,
      maxSafeISO: 800,
      centerShiftEV: shiftedCenterEV,
      seriesShape: .balanced
    )

    #expect(shiftedCenterEV == 2.0)
    #expect(shiftedSamples.map(\.requestedEV) == [-2.0, 0.0, 2.0, 4.0, 6.0])
    #expect(
      !ExposureSeriesBuilder.needsBrighterExteriorShift(
        samples: shiftedSamples,
        expectedCount: 5,
        minDuration: minDuration,
        minimumDistinctDarkGapEV: 1.0
      )
    )
  }

  @Test("Interior shadow recovery keeps a five-shot highlight-priority bracket distinct")
  func interiorShadowRecoveryPreservesFiveShotBracket() {
    let baseDuration = CMTimeMake(value: 100, timescale: 600_000)
    let minDuration = CMTimeMake(value: 20, timescale: 1_000_000)
    let maxDuration = CMTimeMake(value: 1_000_000, timescale: 1_000_000)
    let initialSamples = ExposureSeriesBuilder.buildHybridDurations(
      baseDuration: baseDuration,
      baseISO: 25,
      stepEV: 2.0,
      count: 5,
      minDuration: minDuration,
      maxDuration: maxDuration,
      minISO: 25,
      maxSafeISO: 800,
      seriesShape: .highlightPriority
    )

    #expect(initialSamples.count == 4)

    let shiftedCenterEV = ExposureSeriesBuilder.brighterCenterShiftForExterior(
      baseDuration: baseDuration,
      baseISO: 25,
      stepEV: 2.0,
      count: 5,
      minDuration: minDuration,
      maxDuration: maxDuration,
      minISO: 25,
      maxSafeISO: 800,
      seriesShape: .highlightPriority,
      minimumDistinctDarkGapEV: 1.0
    )
    let shiftedSamples = ExposureSeriesBuilder.buildHybridDurations(
      baseDuration: baseDuration,
      baseISO: 25,
      stepEV: 2.0,
      count: 5,
      minDuration: minDuration,
      maxDuration: maxDuration,
      minISO: 25,
      maxSafeISO: 800,
      centerShiftEV: shiftedCenterEV,
      seriesShape: .highlightPriority
    )

    #expect(shiftedCenterEV == 2.0)
    #expect(shiftedSamples.count == 5)
    #expect(shiftedSamples.map(\.requestedEV) == [-4.0, -2.0, 0.0, 2.0, 4.0])
  }

  @Test("High-contrast clamp expands a five-shot request to a strict seven-shot plan")
  func highContrastClampExpandsToSevenShotPlan() {
    let expandedCount = HighContrastBracketExpansionPolicy.expandedCount(
      requestedCount: 5,
      needsDarkEdgeRecovery: true
    )

    let shiftedCenterEV = ExposureSeriesBuilder.brighterCenterShiftForExterior(
      baseDuration: CMTimeMake(value: 100, timescale: 600_000),
      baseISO: 25,
      stepEV: 2.0,
      count: expandedCount,
      minDuration: CMTimeMake(value: 20, timescale: 1_000_000),
      maxDuration: CMTimeMake(value: 1_000_000, timescale: 1_000_000),
      minISO: 25,
      maxSafeISO: 800,
      seriesShape: .highlightPriority,
      minimumDistinctDarkGapEV: 1.0
    )
    let shiftedSamples = ExposureSeriesBuilder.buildHybridDurations(
      baseDuration: CMTimeMake(value: 100, timescale: 600_000),
      baseISO: 25,
      stepEV: 2.0,
      count: expandedCount,
      minDuration: CMTimeMake(value: 20, timescale: 1_000_000),
      maxDuration: CMTimeMake(value: 1_000_000, timescale: 1_000_000),
      minISO: 25,
      maxSafeISO: 800,
      centerShiftEV: shiftedCenterEV,
      seriesShape: .highlightPriority
    )

    #expect(expandedCount == 7)
    #expect(shiftedCenterEV == 2.0)
    #expect(shiftedSamples.count == 7)
    #expect(shiftedSamples.map(\.requestedEV) == [-4.0, -2.0, 0.0, 2.0, 4.0, 6.0, 8.0])
  }

  @Test("High-contrast expansion leaves an existing seven-shot request unchanged")
  func highContrastClampKeepsExistingSevenShotPlan() {
    let expandedCount = HighContrastBracketExpansionPolicy.expandedCount(
      requestedCount: 7,
      needsDarkEdgeRecovery: true
    )

    #expect(expandedCount == 7)
  }

  @Test("Stacked five-shot brackets keep all requested frames")
  func stackedFiveShotBracketKeepsFrameCount() {
    let samples = ExposureSeriesBuilder.buildHybridDurations(
      baseDuration: CMTimeMake(value: 500_000, timescale: 1_000_000),
      baseISO: 25,
      stepEV: 2.0,
      count: 5,
      minDuration: CMTimeMake(value: 20, timescale: 1_000_000),
      maxDuration: CMTimeMake(value: 1_000_000, timescale: 1_000_000),
      minISO: 25,
      maxSafeISO: 800,
      seriesShape: .highlightPriority
    )

    #expect(samples.count == 5)
    #expect(samples.contains(where: { $0.frameCount > 1 }))
  }

  @Test("Interior helper detects a collapsed dark edge in strong backlight")
  func darkEdgeRecoveryDetectsCollapsedHighlightFrame() {
    let baseDuration = CMTimeMake(value: 3, timescale: 6_000)
    let minDuration = CMTimeMake(value: 1, timescale: 8_000)
    let samples = ExposureSeriesBuilder.buildHybridDurations(
      baseDuration: baseDuration,
      baseISO: 100,
      stepEV: 2.0,
      count: 5,
      minDuration: minDuration,
      maxDuration: CMTimeMake(value: 24_000, timescale: 6_000),
      minISO: 25,
      maxSafeISO: 800,
      seriesShape: .highlightPriority
    )

    #expect(
      ExposureSeriesBuilder.needsDarkEdgeRecovery(
        samples: samples,
        expectedCount: 5,
        minDuration: minDuration,
        minimumDistinctDarkGapEV: 1.0
      )
    )
  }

  @Test("Temporary RAW fallback uses JPEG and restores RAW when the lens supports it again")
  func temporaryProRAWFallbackRestoresPreferredFormat() {
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: "photoFormat")
    defaults.removeObject(forKey: "preferredPhotoFormat")
    defer {
      defaults.removeObject(forKey: "photoFormat")
      defaults.removeObject(forKey: "preferredPhotoFormat")
    }

    let settings = AppSettings()
    settings.photoFormat = .proRaw

    let fallback = settings.syncPhotoFormatAvailability(isProRAWAvailable: false)
    #expect(fallback == .fellBackToJPEG)
    #expect(settings.photoFormat == .jpeg)
    #expect(settings.preferredPhotoFormat == .proRaw)

    let restored = settings.syncPhotoFormatAvailability(isProRAWAvailable: true)
    #expect(restored == .restored(.proRaw))
    #expect(settings.photoFormat == .proRaw)
  }

  @Test("Exposure bias reset returns the slider to neutral")
  func exposureBiasResetReturnsSliderToNeutral() {
    let settings = AppSettings()
    settings.exposureBiasEV = 1.4

    settings.resetExposureBiasToNeutral()

    #expect(settings.exposureBiasEV == 0)
  }

  @Test("Photo format selector prefers the shortest shutter among photo-capable formats")
  func activePhotoFormatSelectorPrefersShortestPhotoFormat() {
    let selected = ActivePhotoFormatSelector.preferredCandidateIndex(
      in: [
        ActivePhotoFormatCandidate(
          highestPhotoQualitySupported: false,
          maxPhotoArea: 0,
          streamingArea: 12_000_000,
          minExposureSeconds: 1.0 / 80_000.0,
          minISO: 32,
          maxExposureSeconds: 1
        ),
        ActivePhotoFormatCandidate(
          highestPhotoQualitySupported: true,
          maxPhotoArea: 12_000_000,
          streamingArea: 12_000_000,
          minExposureSeconds: 1.0 / 50_000.0,
          minISO: 32,
          maxExposureSeconds: 1
        ),
        ActivePhotoFormatCandidate(
          highestPhotoQualitySupported: true,
          maxPhotoArea: 24_000_000,
          streamingArea: 12_000_000,
          minExposureSeconds: 1.0 / 24_000.0,
          minISO: 32,
          maxExposureSeconds: 1
        )
      ]
    )

    #expect(selected == 1)
  }

  @Test("Preferred max photo dimensions pick the largest supported photo size")
  func preferredMaxPhotoDimensionsUseLargestArea() {
    let selected = CameraManager.preferredMaxPhotoDimensions(
      from: [
        CMVideoDimensions(width: 4032, height: 3024),
        CMVideoDimensions(width: 5712, height: 4284),
        CMVideoDimensions(width: 3024, height: 4032)
      ]
    )

    #expect(selected?.width == 5712)
    #expect(selected?.height == 4284)
  }

  @Test("RAW selector keeps the original first DNG pixel type")
  func rawPixelFormatSelectorChoosesFirstDNGType() {
    let selected = RawPixelFormatSelector.preferredSensorRawPixelFormatType(in: [111, 222, 333])

    #expect(selected == 111)
  }

  @Test("RAW selector reports an empty DNG list")
  func rawPixelFormatSelectorRejectsEmptyList() {
    let selected = RawPixelFormatSelector.preferredSensorRawPixelFormatType(in: [])

    #expect(selected == nil)
  }

  @Test("Extreme backlight heuristic prefers a brighter interior fallback when only tiny highlights clip")
  func extremeBacklightHeuristicPrefersBrighterFallback() {
    #expect(
      ExtremeBacklightShadowRecoveryHeuristics.shouldPreferBrighterShift(
        brightClipRatio: 0.03,
        darkClipRatio: 0.24,
        meanLuma: 0.18
      )
    )
  }

  @Test("Extreme backlight heuristic stays off for broader highlight pressure")
  func extremeBacklightHeuristicIgnoresNormalHighlightScenes() {
    #expect(
      !ExtremeBacklightShadowRecoveryHeuristics.shouldPreferBrighterShift(
        brightClipRatio: 0.14,
        darkClipRatio: 0.08,
        meanLuma: 0.42
      )
    )
  }

  @Test("Compression warning stays quiet when five photos remain despite a slight highlight clamp")
  func compressedBracketWarningIgnoresMinorHighlightClamp() {
    let samples = ExposureSeriesBuilder.buildHybridDurations(
      baseDuration: CMTimeMake(value: 5, timescale: 6_000),
      baseISO: 50,
      stepEV: 1.0,
      count: 5,
      minDuration: CMTimeMake(value: 1, timescale: 8_000),
      maxDuration: CMTimeMake(value: 24_000, timescale: 6_000),
      minISO: 25,
      maxSafeISO: 800,
      seriesShape: .highlightPriority
    )

    #expect(samples.count == 5)
    #expect(!BracketCompressionWarningEvaluator.shouldWarn(samples: samples, requestedCount: 5, stepEV: 1.0, trimmedFromCount: 0))
  }

  @Test("Compression warning still appears for strongly squeezed full-length brackets")
  func compressedBracketWarningDetectsMeaningfulRangeLoss() {
    let samples = [
      ExposureSample(
        zone: .highlights,
        ev: -3.0,
        requestedEV: -3.0,
        perFrameDuration: CMTimeMake(value: 1, timescale: 8_000),
        effectiveDuration: CMTimeMake(value: 1, timescale: 8_000),
        perFrameISO: 50,
        frameCount: 1
      ),
      ExposureSample(
        zone: .standard,
        ev: -2.2,
        requestedEV: -2.0,
        perFrameDuration: CMTimeMake(value: 1, timescale: 6_000),
        effectiveDuration: CMTimeMake(value: 1, timescale: 6_000),
        perFrameISO: 50,
        frameCount: 1
      ),
      ExposureSample(
        zone: .standard,
        ev: -1.0,
        requestedEV: -1.0,
        perFrameDuration: CMTimeMake(value: 1, timescale: 4_000),
        effectiveDuration: CMTimeMake(value: 1, timescale: 4_000),
        perFrameISO: 50,
        frameCount: 1
      ),
      ExposureSample(
        zone: .standard,
        ev: 0.0,
        requestedEV: 0.0,
        perFrameDuration: CMTimeMake(value: 1, timescale: 2_000),
        effectiveDuration: CMTimeMake(value: 1, timescale: 2_000),
        perFrameISO: 50,
        frameCount: 1
      ),
      ExposureSample(
        zone: .standard,
        ev: 1.0,
        requestedEV: 1.0,
        perFrameDuration: CMTimeMake(value: 1, timescale: 1_000),
        effectiveDuration: CMTimeMake(value: 1, timescale: 1_000),
        perFrameISO: 50,
        frameCount: 1
      )
    ]

    #expect(BracketCompressionWarningEvaluator.shouldWarn(samples: samples, requestedCount: 5, stepEV: 1.0, trimmedFromCount: 0))
    #expect(!BracketCompressionWarningEvaluator.shouldWarn(samples: samples, requestedCount: 5, stepEV: 1.0, trimmedFromCount: 1))
  }

  @Test("Capture metadata rewriter stores the actual exposure time in EXIF")
  func captureMetadataRewriterUpdatesExposureTime() throws {
    let original = try makeJPEGWithExif(exposureTime: 0.5, iso: 200)
    let rewritten = CaptureMetadataRewriter.rewriteExposureMetadata(
      data: original,
      outputFormat: .jpeg,
      exposureSeconds: 0.125,
      iso: 64
    )

    let exif = try #require(exifDictionary(from: rewritten))
    let exposureTime = try #require(exif[kCGImagePropertyExifExposureTime as String] as? Double)
    let shutterSpeedValue = try #require(exif[kCGImagePropertyExifShutterSpeedValue as String] as? Double)
    let iso = try #require(firstISO(from: exif))

    #expect(abs(exposureTime - 0.125) < 0.000_001)
    #expect(abs(shutterSpeedValue - 3.0) < 0.000_001)
    #expect(iso == 64)
  }

  @Test("Companion XMP stores the absolute bracket bias for Adobe-side inspection")
  func companionXMPStoresAbsoluteBracketBias() throws {
    let metadata = CompanionXMPMetadata(
      exposureBiasValue: -3.0,
      bracketExposureEV: -1.6,
      requestedBracketExposureEV: -2.0,
      absoluteRequestedExposureBiasEV: -3.4,
      baseExposureBiasEV: -1.4,
      exposureSeconds: 1.0 / 56_000.0,
      effectiveExposureSeconds: 1.0 / 56_000.0,
      iso: 100,
      bracketIndex: 1,
      bracketTotal: 7,
      frameCount: 1,
      captureMode: "standardBracket",
      singleShotTriggeredAt: nil,
      singleShotRollDegrees: nil,
      singleShotPitchDegrees: nil,
      singleShotStabilityScore: nil,
      singleShotStabilityState: nil,
      singleShotCorrectability: nil,
      intendedProcessing: nil
    )

    let data = FileStore.companionXMPData(for: metadata)
    let xml = try #require(String(data: data, encoding: .utf8))

    #expect(xml.contains("<exif:ExposureBiasValue>-3</exif:ExposureBiasValue>"))
    #expect(xml.contains("<pixcapture:BracketExposureEV>-1.6</pixcapture:BracketExposureEV>"))
    #expect(xml.contains("<pixcapture:RequestedBracketExposureEV>-2</pixcapture:RequestedBracketExposureEV>"))
    #expect(xml.contains("<pixcapture:BaseExposureBiasEV>-1.4</pixcapture:BaseExposureBiasEV>"))
    #expect(xml.contains("<pixcapture:BracketTotal>7</pixcapture:BracketTotal>"))
  }

  private func makeJPEGWithExif(exposureTime: Double, iso: Int) throws -> Data {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue
    let context = try #require(
      CGContext(
        data: nil,
        width: 2,
        height: 2,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo
      )
    )
    let image = try #require(context.makeImage())
    let output = NSMutableData()
    let destination = try #require(
      CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
    )
    let properties: [CFString: Any] = [
      kCGImagePropertyExifDictionary: [
        kCGImagePropertyExifExposureTime: exposureTime,
        kCGImagePropertyExifShutterSpeedValue: -log2(exposureTime),
        kCGImagePropertyExifISOSpeedRatings: [iso]
      ]
    ]

    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    return output as Data
  }

  private func exifDictionary(from data: Data) -> [String: Any]? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
      return nil
    }

    return properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
  }

  private func firstISO(from exif: [String: Any]) -> Int? {
    if let values = exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Int] {
      return values.first
    }
    if let values = exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Double] {
      return values.first.map { Int($0.rounded()) }
    }
    if let value = exif[kCGImagePropertyExifISOSpeedRatings as String] as? Double {
      return Int(value.rounded())
    }
    return nil
  }
}
