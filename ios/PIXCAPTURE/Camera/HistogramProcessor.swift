import CoreVideo
import Foundation
import SwiftUI

struct HighlightWarningMask {
  let columns: Int
  let rows: Int
  let cells: [CGFloat]

  static let empty = HighlightWarningMask(columns: 0, rows: 0, cells: [])
}

struct FrameQualityMetrics {
  let bins: [CGFloat]
  let meanLuminance: Double
  let darkClipRatio: Double
  let brightClipRatio: Double
  let sharpnessScore: Double
  let highlightWarningMask: HighlightWarningMask
}

final class HistogramProcessor {
  private let binsCount = 32
  private let highlightColumns = 12
  private let highlightRows = 20

  func process(pixelBuffer: CVPixelBuffer) -> [CGFloat] {
    analyze(pixelBuffer: pixelBuffer).bins
  }

  func analyze(pixelBuffer: CVPixelBuffer) -> FrameQualityMetrics {
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
      return FrameQualityMetrics(
        bins: Array(repeating: 0, count: binsCount),
        meanLuminance: 0,
        darkClipRatio: 0,
        brightClipRatio: 0,
        sharpnessScore: 0,
        highlightWarningMask: .empty
      )
    }

    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

    var bins = Array(repeating: 0, count: binsCount)
    let step = max(2, min(width, height) / 80)

    var sampleCount = 0
    var luminanceSum = 0.0
    var darkClipCount = 0
    var brightClipCount = 0
    var sharpnessSum = 0.0
    var sharpnessSamples = 0
    var highlightCellHits = Array(repeating: 0, count: highlightColumns * highlightRows)
    var highlightCellSamples = Array(repeating: 0, count: highlightColumns * highlightRows)

    let centerMinX = Int(Double(width) * 0.3)
    let centerMaxX = Int(Double(width) * 0.7)
    let centerMinY = Int(Double(height) * 0.3)
    let centerMaxY = Int(Double(height) * 0.7)

    for y in stride(from: 0, to: height, by: step) {
      let row = baseAddress.advanced(by: y * bytesPerRow)
      let nextRow = y + step < height ? baseAddress.advanced(by: (y + step) * bytesPerRow) : nil
      for x in stride(from: 0, to: width, by: step) {
        let pixel = row.advanced(by: x * 4)
        let b = pixel.load(fromByteOffset: 0, as: UInt8.self)
        let g = pixel.load(fromByteOffset: 1, as: UInt8.self)
        let r = pixel.load(fromByteOffset: 2, as: UInt8.self)

        let luminance = (0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)) / 255.0
        let index = min(binsCount - 1, max(0, Int(luminance * Double(binsCount))))
        bins[index] += 1
        sampleCount += 1
        luminanceSum += luminance
        if luminance <= 0.03 { darkClipCount += 1 }
        if luminance >= 0.97 { brightClipCount += 1 }

        let column = min(highlightColumns - 1, max(0, (x * highlightColumns) / max(width, 1)))
        let rowIndex = min(highlightRows - 1, max(0, (y * highlightRows) / max(height, 1)))
        let highlightIndex = (rowIndex * highlightColumns) + column
        highlightCellSamples[highlightIndex] += 1
        if luminance >= 0.97 {
          highlightCellHits[highlightIndex] += 1
        }

        if x >= centerMinX, x <= centerMaxX, y >= centerMinY, y <= centerMaxY {
          if x + step < width {
            let rightPixel = row.advanced(by: (x + step) * 4)
            let rb = rightPixel.load(fromByteOffset: 0, as: UInt8.self)
            let rg = rightPixel.load(fromByteOffset: 1, as: UInt8.self)
            let rr = rightPixel.load(fromByteOffset: 2, as: UInt8.self)
            let rightLuma = (0.2126 * Double(rr) + 0.7152 * Double(rg) + 0.0722 * Double(rb)) / 255.0
            sharpnessSum += abs(luminance - rightLuma)
            sharpnessSamples += 1
          }
          if let nextRow, y + step < height {
            let downPixel = nextRow.advanced(by: x * 4)
            let db = downPixel.load(fromByteOffset: 0, as: UInt8.self)
            let dg = downPixel.load(fromByteOffset: 1, as: UInt8.self)
            let dr = downPixel.load(fromByteOffset: 2, as: UInt8.self)
            let downLuma = (0.2126 * Double(dr) + 0.7152 * Double(dg) + 0.0722 * Double(db)) / 255.0
            sharpnessSum += abs(luminance - downLuma)
            sharpnessSamples += 1
          }
        }
      }
    }

    let maxValue = bins.max() ?? 1
    let normalizedBins = bins.map { CGFloat($0) / CGFloat(maxValue) }
    let safeSamples = max(sampleCount, 1)
    let mean = luminanceSum / Double(safeSamples)
    let darkClip = Double(darkClipCount) / Double(safeSamples)
    let brightClip = Double(brightClipCount) / Double(safeSamples)
    let sharpness = sharpnessSamples > 0 ? sharpnessSum / Double(sharpnessSamples) : 0
    let highlightCells: [CGFloat] = highlightCellSamples.enumerated().map { index, samples in
      guard samples > 0 else { return 0 }
      let ratio = CGFloat(highlightCellHits[index]) / CGFloat(samples)
      guard ratio >= 0.22 else { return 0 }
      return min(1, max(0, (ratio - 0.22) / 0.58))
    }

    return FrameQualityMetrics(
      bins: normalizedBins,
      meanLuminance: mean,
      darkClipRatio: darkClip,
      brightClipRatio: brightClip,
      sharpnessScore: sharpness,
      highlightWarningMask: HighlightWarningMask(
        columns: highlightColumns,
        rows: highlightRows,
        cells: highlightCells
      )
    )
  }
}
