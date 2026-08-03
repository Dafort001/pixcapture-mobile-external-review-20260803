import CoreMedia
import Foundation

struct ExposureSample {
  let zone: ExposureZone
  let ev: Double
  let requestedEV: Double
  let perFrameDuration: CMTime
  let effectiveDuration: CMTime
  let perFrameISO: Float
  let frameCount: Int
}

enum ExposureZone: String {
  case highlights = "A"
  case standard = "B"
  case stacking = "C"
}

enum ExposureSeriesShape {
  case balanced
  case highlightPriority
  case highlightAnchor
}

enum ExposureSeriesBuilder {
  static func buildHybridDurations(
    baseDuration: CMTime,
    baseISO: Float,
    stepEV: Double,
    count: Int,
    minDuration: CMTime,
    maxDuration: CMTime,
    minISO: Float,
    maxSafeISO: Float,
    requestedOffsetsEV: [Double]? = nil,
    centerShiftEV: Double = 0,
    seriesShape: ExposureSeriesShape = .highlightPriority
  ) -> [ExposureSample] {
    let normalizedCount = [1, 3, 5, 7].contains(count) ? count : 3
    let offsets = requestedOffsetsEV ?? requestedOffsets(
      for: normalizedCount,
      stepEV: stepEV,
      centerShiftEV: centerShiftEV,
      seriesShape: seriesShape
    )
    let baseSeconds = max(baseDuration.seconds, 0.000_001)
    let minSeconds = max(minDuration.seconds, 0.000_001)
    let maxSeconds = max(maxDuration.seconds, minSeconds)
    let isoFloor = max(minISO, 1.0)
    let isoBase = max(baseISO, isoFloor)
    _ = maxSafeISO

    var samples: [ExposureSample] = []
    for requestedEV in offsets {
      let requestedSeconds = baseSeconds * pow(2.0, requestedEV)
      let sample: ExposureSample

      if requestedSeconds < minSeconds {
        sample = ExposureSample(
          zone: .highlights,
          ev: log2(minSeconds / baseSeconds),
          requestedEV: requestedEV,
          perFrameDuration: CMTimeMakeWithSeconds(minSeconds, preferredTimescale: baseDuration.timescale),
          effectiveDuration: CMTimeMakeWithSeconds(minSeconds, preferredTimescale: baseDuration.timescale),
          perFrameISO: isoBase,
          frameCount: 1
        )
      } else if requestedSeconds > maxSeconds {
        // Keep ISO constant across the bracket. Additional exposure is realized
        // by stacking multiple fixed-ISO frames instead of changing sensor gain.
        let frameCount = max(2, Int(ceil(requestedSeconds / maxSeconds)))
        let perFrameSeconds = min(maxSeconds, max(minSeconds, requestedSeconds / Double(frameCount)))
        let effectiveSeconds = perFrameSeconds * Double(frameCount)
        sample = ExposureSample(
          zone: .stacking,
          ev: log2(max(effectiveSeconds, 0.000_001) / baseSeconds),
          requestedEV: requestedEV,
          perFrameDuration: CMTimeMakeWithSeconds(perFrameSeconds, preferredTimescale: baseDuration.timescale),
          effectiveDuration: CMTimeMakeWithSeconds(effectiveSeconds, preferredTimescale: baseDuration.timescale),
          perFrameISO: isoBase,
          frameCount: max(frameCount, 1)
        )
      } else {
        sample = ExposureSample(
          zone: .standard,
          ev: log2(requestedSeconds / baseSeconds),
          requestedEV: requestedEV,
          perFrameDuration: CMTimeMakeWithSeconds(requestedSeconds, preferredTimescale: baseDuration.timescale),
          effectiveDuration: CMTimeMakeWithSeconds(requestedSeconds, preferredTimescale: baseDuration.timescale),
          perFrameISO: isoBase,
          frameCount: 1
        )
      }

      if let last = samples.last,
         abs(last.perFrameDuration.seconds - sample.perFrameDuration.seconds) < 0.000_001,
         abs(last.perFrameISO - sample.perFrameISO) < 0.5,
         last.frameCount == sample.frameCount {
        continue
      }
      samples.append(sample)
    }

    if samples.isEmpty {
      return [ExposureSample(
        zone: .standard,
        ev: 0,
        requestedEV: 0,
        perFrameDuration: baseDuration,
        effectiveDuration: baseDuration,
        perFrameISO: isoBase,
        frameCount: 1
      )]
    }
    return samples
  }

  static func buildCompressedSingleShotDurations(
    baseDuration: CMTime,
    baseISO: Float,
    stepEV: Double,
    count: Int,
    minDuration: CMTime,
    maxDuration: CMTime,
    minISO: Float,
    maxSafeISO: Float,
    centerShiftEV: Double = 0,
    seriesShape: ExposureSeriesShape = .highlightPriority
  ) -> [ExposureSample] {
    let normalizedCount = [1, 3, 5, 7].contains(count) ? count : 3
    let offsets = requestedOffsets(
      for: normalizedCount,
      stepEV: stepEV,
      centerShiftEV: centerShiftEV,
      seriesShape: seriesShape
    )
    let baseSeconds = max(baseDuration.seconds, 0.000_001)
    let minSeconds = max(minDuration.seconds, 0.000_001)
    let maxSeconds = max(maxDuration.seconds, minSeconds)
    let isoFloor = max(minISO, 1.0)
    let isoBase = max(baseISO, isoFloor)
    _ = maxSafeISO

    var samples: [ExposureSample] = []
    for requestedEV in offsets {
      let requestedSeconds = baseSeconds * pow(2.0, requestedEV)
      let sample: ExposureSample

      if requestedSeconds < minSeconds {
        sample = ExposureSample(
          zone: .highlights,
          ev: log2(minSeconds / baseSeconds),
          requestedEV: requestedEV,
          perFrameDuration: CMTimeMakeWithSeconds(minSeconds, preferredTimescale: baseDuration.timescale),
          effectiveDuration: CMTimeMakeWithSeconds(minSeconds, preferredTimescale: baseDuration.timescale),
          perFrameISO: isoBase,
          frameCount: 1
        )
      } else if requestedSeconds > maxSeconds {
        let clampedSeconds = min(max(requestedSeconds, minSeconds), maxSeconds)
        sample = ExposureSample(
          zone: .standard,
          ev: log2(max(clampedSeconds, 0.000_001) / baseSeconds),
          requestedEV: requestedEV,
          perFrameDuration: CMTimeMakeWithSeconds(clampedSeconds, preferredTimescale: baseDuration.timescale),
          effectiveDuration: CMTimeMakeWithSeconds(clampedSeconds, preferredTimescale: baseDuration.timescale),
          perFrameISO: isoBase,
          frameCount: 1
        )
      } else {
        sample = ExposureSample(
          zone: .standard,
          ev: log2(requestedSeconds / baseSeconds),
          requestedEV: requestedEV,
          perFrameDuration: CMTimeMakeWithSeconds(requestedSeconds, preferredTimescale: baseDuration.timescale),
          effectiveDuration: CMTimeMakeWithSeconds(requestedSeconds, preferredTimescale: baseDuration.timescale),
          perFrameISO: isoBase,
          frameCount: 1
        )
      }

      if let last = samples.last,
         abs(last.perFrameDuration.seconds - sample.perFrameDuration.seconds) < 0.000_001,
         abs(last.perFrameISO - sample.perFrameISO) < 0.5 {
        continue
      }
      samples.append(sample)
    }

    if samples.isEmpty {
      return [ExposureSample(
        zone: .standard,
        ev: 0,
        requestedEV: 0,
        perFrameDuration: baseDuration,
        effectiveDuration: baseDuration,
        perFrameISO: isoBase,
        frameCount: 1
      )]
    }
    return samples
  }

  static func buildDurations(baseDuration: CMTime, stepEV: Double, count: Int, maxSeconds: Double) -> [ExposureSample] {
    let normalizedCount = [1, 3, 5, 7].contains(count) ? count : 3
    let offsets = requestedOffsets(for: normalizedCount, stepEV: stepEV)
    let maxTime = CMTimeMakeWithSeconds(maxSeconds, preferredTimescale: baseDuration.timescale)

    var currentOffsets = offsets
    while true {
      let samples = currentOffsets.map { ev -> ExposureSample in
        let factor = pow(2.0, ev)
        let duration = CMTimeMultiplyByFloat64(baseDuration, multiplier: factor)
        return ExposureSample(
          zone: .standard,
          ev: ev,
          requestedEV: ev,
          perFrameDuration: duration,
          effectiveDuration: duration,
          perFrameISO: 100,
          frameCount: 1
        )
      }

      if samples.allSatisfy({ $0.perFrameDuration <= maxTime }) {
        return samples
      }

      if currentOffsets.count <= 1 {
        let clamped = min(baseDuration.seconds, maxSeconds)
        let duration = CMTimeMakeWithSeconds(clamped, preferredTimescale: baseDuration.timescale)
        return [ExposureSample(
          zone: .standard,
          ev: 0,
          requestedEV: 0,
          perFrameDuration: duration,
          effectiveDuration: duration,
          perFrameISO: 100,
          frameCount: 1
        )]
      }

      currentOffsets = Array(currentOffsets.dropFirst().dropLast())
    }
  }

  static func buildDeviceBoundDurations(
    baseDuration: CMTime,
    stepEV: Double,
    count: Int,
    minDuration: CMTime,
    maxDuration: CMTime
  ) -> [ExposureSample] {
    let normalizedCount = [1, 3, 5, 7].contains(count) ? count : 3
    let offsets = requestedOffsets(for: normalizedCount, stepEV: stepEV)
    let baseSeconds = max(baseDuration.seconds, 0.000_001)
    let minSeconds = max(minDuration.seconds, 0.000_001)
    let maxSeconds = max(maxDuration.seconds, minSeconds)

    var samples: [ExposureSample] = []
    for requestedEV in offsets {
      let requestedSeconds = baseSeconds * pow(2.0, requestedEV)
      let clampedSeconds = min(max(requestedSeconds, minSeconds), maxSeconds)
      let effectiveEV = log2(clampedSeconds / baseSeconds)
      let duration = CMTimeMakeWithSeconds(clampedSeconds, preferredTimescale: baseDuration.timescale)

      if let last = samples.last, abs(last.perFrameDuration.seconds - clampedSeconds) < 0.000_001 {
        continue
      }
      samples.append(ExposureSample(
        zone: .standard,
        ev: effectiveEV,
        requestedEV: requestedEV,
        perFrameDuration: duration,
        effectiveDuration: duration,
        perFrameISO: 100,
        frameCount: 1
      ))
    }

    if samples.isEmpty {
      let fallbackSeconds = min(max(baseSeconds, minSeconds), maxSeconds)
      return [ExposureSample(
        zone: .standard,
        ev: 0,
        requestedEV: 0,
        perFrameDuration: CMTimeMakeWithSeconds(fallbackSeconds, preferredTimescale: baseDuration.timescale),
        effectiveDuration: CMTimeMakeWithSeconds(fallbackSeconds, preferredTimescale: baseDuration.timescale),
        perFrameISO: 100,
        frameCount: 1
      )]
    }
    return samples
  }

  static func needsBrighterExteriorShift(
    samples: [ExposureSample],
    expectedCount: Int,
    minDuration: CMTime,
    minimumDistinctDarkGapEV: Double
  ) -> Bool {
    needsDarkEdgeRecovery(
      samples: samples,
      expectedCount: expectedCount,
      minDuration: minDuration,
      minimumDistinctDarkGapEV: minimumDistinctDarkGapEV
    )
  }

  static func needsDarkEdgeRecovery(
    samples: [ExposureSample],
    expectedCount: Int,
    minDuration: CMTime,
    minimumDistinctDarkGapEV: Double
  ) -> Bool {
    guard expectedCount > 1 else { return false }
    guard !samples.isEmpty else { return false }

    let minSeconds = max(minDuration.seconds, 0.000_001)
    let sorted = samples.sorted { lhs, rhs in
      if lhs.ev == rhs.ev {
        return lhs.requestedEV < rhs.requestedEV
      }
      return lhs.ev < rhs.ev
    }

    let firstHitsMinimum = sorted[0].perFrameDuration.seconds <= (minSeconds + 0.000_001)
    if samples.count < expectedCount, firstHitsMinimum {
      return true
    }

    guard sorted.count >= 2 else { return false }
    let darkGapEV = sorted[1].ev - sorted[0].ev
    return firstHitsMinimum && darkGapEV < minimumDistinctDarkGapEV
  }

  static func brighterCenterShiftForExterior(
    baseDuration: CMTime,
    baseISO: Float,
    stepEV: Double,
    count: Int,
    minDuration: CMTime,
    maxDuration: CMTime,
    minISO: Float,
    maxSafeISO: Float,
    initialCenterShiftEV: Double = 0,
    seriesShape: ExposureSeriesShape = .balanced,
    minimumDistinctDarkGapEV: Double
  ) -> Double {
    let normalizedCount = [1, 3, 5, 7].contains(count) ? count : 3
    guard normalizedCount > 1 else { return initialCenterShiftEV }

    var centerShiftEV = initialCenterShiftEV
    let maxShiftSteps = max(normalizedCount - 1, 1)
    for _ in 0...maxShiftSteps {
      let samples = buildHybridDurations(
        baseDuration: baseDuration,
        baseISO: baseISO,
        stepEV: stepEV,
        count: normalizedCount,
        minDuration: minDuration,
        maxDuration: maxDuration,
        minISO: minISO,
        maxSafeISO: maxSafeISO,
        centerShiftEV: centerShiftEV,
        seriesShape: seriesShape
      )
      if !needsBrighterExteriorShift(
        samples: samples,
        expectedCount: normalizedCount,
        minDuration: minDuration,
        minimumDistinctDarkGapEV: minimumDistinctDarkGapEV
      ) {
        return centerShiftEV
      }
      centerShiftEV += stepEV
    }

    return centerShiftEV
  }

  static func requestedOffsets(
    for count: Int,
    stepEV: Double,
    centerShiftEV: Double = 0,
    seriesShape: ExposureSeriesShape = .highlightPriority
  ) -> [Double] {
    let offsets: [Double]
    switch count {
    case 1:
      offsets = [0]
    case 3:
      switch seriesShape {
      case .highlightAnchor:
        offsets = [-stepEV, 0, stepEV]
      case .balanced, .highlightPriority:
        offsets = [-stepEV, 0, stepEV]
      }
    case 5:
      switch seriesShape {
      case .balanced:
        offsets = [-2 * stepEV, -stepEV, 0, stepEV, 2 * stepEV]
      case .highlightPriority:
        // Prefer an extra highlight-preserving frame over the brightest frame.
        // This makes the 5-shot bracket closer to the useful center/dark half
        // of the 7-shot series for window-heavy interior scenes.
        offsets = [-3 * stepEV, -2 * stepEV, -stepEV, 0, stepEV]
      case .highlightAnchor:
        // Keep regular configured EV spacing. The highlight-aware behavior comes from
        // the anchor measurement, not from compressing the bright side.
        offsets = [-2 * stepEV, -stepEV, 0, stepEV, 2 * stepEV]
      }
    case 7:
      switch seriesShape {
      case .balanced, .highlightPriority:
        offsets = [-3 * stepEV, -2 * stepEV, -stepEV, 0, stepEV, 2 * stepEV, 3 * stepEV]
      case .highlightAnchor:
        offsets = [-3 * stepEV, -2 * stepEV, -stepEV, 0, stepEV, 2 * stepEV, 3 * stepEV]
      }
    default:
      offsets = [-stepEV, 0, stepEV]
    }
    guard centerShiftEV != 0 else { return offsets }
    return offsets.map { $0 + centerShiftEV }
  }

  static func brightestOffsetEV(
    for count: Int,
    stepEV: Double,
    seriesShape: ExposureSeriesShape
  ) -> Double {
    requestedOffsets(for: count, stepEV: stepEV, seriesShape: seriesShape).max() ?? 0
  }
}
