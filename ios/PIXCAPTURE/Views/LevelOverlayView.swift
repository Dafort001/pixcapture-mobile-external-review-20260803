import SwiftUI
import UIKit

struct LevelOverlayView: View {
  let roll: Double
  let pitch: Double

  var body: some View {
    let rollNormalized = normalizeAngle(roll)
    let pitchNormalized = normalizeAngle(pitch)
    let rollDegrees = rollNormalized * 180 / .pi
    let pitchDegrees = pitchNormalized * 180 / .pi
    let stateColor = statusColor(rollDegrees: rollDegrees, pitchDegrees: pitchDegrees)
    let rotation = clampedRotation(rollNormalized)

    return GeometryReader { proxy in
      let base = min(max(min(proxy.size.width, proxy.size.height) * 0.28, 120), 180)
      let active = base * 0.78
      let cross = base * 1.45
      let xOffset = clampedOffset(rollNormalized, scale: base * 0.85, limit: base * 0.32)
      let yOffset = clampedOffset(pitchNormalized, scale: base * 0.85, limit: base * 0.32)

      ZStack {
        referenceSquare(size: base)
        activeSquare(color: stateColor, size: active)
          .rotationEffect(.radians(rotation))
          .offset(x: xOffset, y: yOffset)
        crosshair(size: cross)
        angleReadout(roll: rollDegrees, pitch: pitchDegrees, color: stateColor, topPadding: base * 0.85)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func statusColor(rollDegrees: Double, pitchDegrees: Double) -> Color {
    let maxError = max(abs(rollDegrees), abs(pitchDegrees))
    if maxError < 2.0 {
      return .green.opacity(0.9)
    }
    if maxError < 4.5 {
      return Color.yellow.opacity(0.9)
    }
    return Color.red.opacity(0.9)
  }

  private func referenceSquare(size: CGFloat) -> some View {
    let radius = max(8, size * 0.08)
    return RoundedRectangle(cornerRadius: radius)
      .stroke(Color.white.opacity(0.45), lineWidth: 2)
      .frame(width: size, height: size)
      .background(
        RoundedRectangle(cornerRadius: radius)
          .fill(Color.black.opacity(0.12))
          .frame(width: size, height: size)
      )
  }

  private func activeSquare(color: Color, size: CGFloat) -> some View {
    let radius = max(8, size * 0.08)
    return RoundedRectangle(cornerRadius: radius)
      .stroke(color, lineWidth: 3)
      .frame(width: size, height: size)
      .shadow(color: Color.black.opacity(0.35), radius: 3, x: 0, y: 2)
  }

  private func crosshair(size: CGFloat) -> some View {
    return ZStack {
      Rectangle()
        .fill(Color.white.opacity(0.35))
        .frame(width: 2, height: size)
      Rectangle()
        .fill(Color.white.opacity(0.35))
        .frame(width: size, height: 2)
    }
  }

  private func angleReadout(roll: Double, pitch: Double, color: Color, topPadding: CGFloat) -> some View {
    return Text(String(format: "R %.1f°  P %.1f°", roll, pitch))
      .font(.system(size: 12, weight: .semibold, design: .monospaced))
      .foregroundStyle(color)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(Color.black.opacity(0.45))
      .clipShape(Capsule())
      .padding(.top, topPadding)
  }

  private func clampedOffset(_ angle: Double, scale: CGFloat, limit: CGFloat) -> CGFloat {
    let offset = CGFloat(angle) * scale
    return min(max(offset, -limit), limit)
  }

  private func clampedRotation(_ roll: Double) -> Double {
    let maxRotation: Double = 0.45
    return min(max(roll, -maxRotation), maxRotation)
  }

  private func normalizeAngle(_ angle: Double) -> Double {
    var normalized = angle
    if normalized > .pi / 2 {
      normalized = .pi - normalized
    } else if normalized < -.pi / 2 {
      normalized = -.pi - normalized
    }
    return normalized
  }
}

struct KeystoneAlignmentGuide: View {
  let roll: Double
  let pitch: Double
  let viewportOrientation: KeystoneViewportOrientation

  var body: some View {
    let transform = KeystoneOrientationMapper.transform(
      rollRadians: roll,
      pitchRadians: pitch,
      viewportOrientation: viewportOrientation
    )
    let guideColor = color(for: transform.status)

    return GeometryReader { proxy in
      let guideSize = guideSideLength(for: proxy.size)
      let center = guideCenter(for: proxy.size)
      let maxPitchInset = guideSize * 0.16
      let maxRollShear = guideSize * 0.12

      ZStack {
        KeystoneGuideShape(
          pitchInset: 0,
          rollShear: 0
        )
        .stroke(
          Color.white.opacity(0.34),
          style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round, dash: [7, 6])
        )
        .frame(width: guideSize, height: guideSize)
        .position(center)

        KeystoneGuideShape(
          pitchInset: CGFloat(transform.pitchFactor) * maxPitchInset,
          rollShear: CGFloat(transform.rollFactor) * maxRollShear
        )
        .fill(guideColor.opacity(0.13))
        .frame(width: guideSize, height: guideSize)
        .position(center)

        KeystoneGuideShape(
          pitchInset: CGFloat(transform.pitchFactor) * maxPitchInset,
          rollShear: CGFloat(transform.rollFactor) * maxRollShear
        )
        .stroke(guideColor.opacity(0.96), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        .shadow(color: Color.black.opacity(0.34), radius: 3, x: 0, y: 1)
        .frame(width: guideSize, height: guideSize)
        .position(center)
      }
      .animation(.easeOut(duration: 0.18), value: transform.rollFactor)
      .animation(.easeOut(duration: 0.18), value: transform.pitchFactor)
    }
  }

  private func guideSideLength(for viewportSize: CGSize) -> CGFloat {
    let minDimension = min(viewportSize.width, viewportSize.height)
    let multiplier: CGFloat = viewportOrientation.isLandscape ? 0.54 : 0.46
    return min(max(minDimension * multiplier, 150), viewportOrientation.isLandscape ? 280 : 260)
  }

  private func guideCenter(for viewportSize: CGSize) -> CGPoint {
    return CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
  }

  private func color(for status: SingleShotCorrectabilityStatus) -> Color {
    switch status {
    case .good:
      return .green
    case .usable:
      return .yellow
    case .retake:
      return .red
    }
  }
}

enum KeystoneViewportOrientation: Equatable {
  case portrait
  case portraitUpsideDown
  case landscapeLeft
  case landscapeRight

  var isLandscape: Bool {
    switch self {
    case .landscapeLeft, .landscapeRight:
      return true
    case .portrait, .portraitUpsideDown:
      return false
    }
  }

  static func current(viewportSize: CGSize? = nil) -> KeystoneViewportOrientation {
    switch UIDevice.current.orientation {
    case .portrait:
      return .portrait
    case .portraitUpsideDown:
      return .portraitUpsideDown
    case .landscapeLeft:
      return .landscapeLeft
    case .landscapeRight:
      return .landscapeRight
    default:
      guard let viewportSize else { return .portrait }
      return viewportSize.width > viewportSize.height ? .landscapeRight : .portrait
    }
  }
}

struct KeystoneGuideTransform: Equatable {
  let normalizedRollForViewport: Double
  let normalizedPitchForViewport: Double
  let rollFactor: Double
  let pitchFactor: Double
  let status: SingleShotCorrectabilityStatus
}

enum KeystoneOrientationMapper {
  static func transform(
    rollRadians: Double,
    pitchRadians: Double,
    viewportOrientation: KeystoneViewportOrientation
  ) -> KeystoneGuideTransform {
    let rollDegrees = normalizeAngle(rollRadians) * 180 / .pi
    let pitchDegrees = normalizeAngle(pitchRadians) * 180 / .pi
    let mapped = mapToViewport(
      rollDegrees: rollDegrees,
      pitchDegrees: pitchDegrees,
      orientation: viewportOrientation
    )
    let status = SingleShotCorrectionPolicy.assess(
      rollDegrees: mapped.roll,
      pitchDegrees: mapped.pitch
    )

    return KeystoneGuideTransform(
      normalizedRollForViewport: mapped.roll,
      normalizedPitchForViewport: mapped.pitch,
      rollFactor: visualFactor(
        mapped.roll,
        goodLimit: SingleShotCorrectionPolicy.rollGoodDegrees,
        usableLimit: SingleShotCorrectionPolicy.rollUsableDegrees
      ),
      pitchFactor: visualFactor(
        mapped.pitch,
        goodLimit: SingleShotCorrectionPolicy.pitchGoodDegrees,
        usableLimit: SingleShotCorrectionPolicy.pitchUsableDegrees
      ),
      status: status
    )
  }

  private static func mapToViewport(
    rollDegrees: Double,
    pitchDegrees: Double,
    orientation: KeystoneViewportOrientation
  ) -> (roll: Double, pitch: Double) {
    switch orientation {
    case .portrait:
      return (rollDegrees, pitchDegrees)
    case .portraitUpsideDown:
      return (-rollDegrees, -pitchDegrees)
    case .landscapeLeft:
      return (pitchDegrees, -rollDegrees)
    case .landscapeRight:
      return (-pitchDegrees, rollDegrees)
    }
  }

  private static func normalizeAngle(_ angle: Double) -> Double {
    var normalized = angle
    if normalized > .pi / 2 {
      normalized = .pi - normalized
    } else if normalized < -.pi / 2 {
      normalized = -.pi - normalized
    }
    return normalized
  }

  private static func visualFactor(_ degrees: Double, goodLimit: Double, usableLimit: Double) -> Double {
    let magnitude = abs(degrees)
    guard magnitude > goodLimit else { return 0 }
    let range = max(usableLimit - goodLimit, 0.1)
    let normalized = min(max((magnitude - goodLimit) / range, 0), 1)
    return degrees < 0 ? -normalized : normalized
  }
}

private struct KeystoneGuideShape: Shape {
  let pitchInset: CGFloat
  let rollShear: CGFloat

  func path(in rect: CGRect) -> Path {
    let topLeft = CGPoint(
      x: rect.minX + pitchInset + rollShear,
      y: rect.minY
    )
    let topRight = CGPoint(
      x: rect.maxX - pitchInset + rollShear,
      y: rect.minY
    )
    let bottomRight = CGPoint(
      x: rect.maxX + pitchInset - rollShear,
      y: rect.maxY
    )
    let bottomLeft = CGPoint(
      x: rect.minX - pitchInset - rollShear,
      y: rect.maxY
    )

    var path = Path()
    path.move(to: topLeft)
    path.addLine(to: topRight)
    path.addLine(to: bottomRight)
    path.addLine(to: bottomLeft)
    path.closeSubpath()
    return path
  }
}
