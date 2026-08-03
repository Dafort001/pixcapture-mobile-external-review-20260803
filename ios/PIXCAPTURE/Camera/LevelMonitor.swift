import CoreMotion
import Foundation
import UIKit

enum CameraStabilityState: String, Equatable {
  case stable
  case marginal
  case unstable
}

struct CameraMotionSample {
  let roll: Double
  let pitch: Double
  let deviceOrientation: UIDeviceOrientation
  let stabilityScore: Double
  let stabilityState: CameraStabilityState
  let gyroMagnitude: Double
  let accelerationMagnitude: Double
}

final class LevelMonitor {
  private let motionManager = CMMotionManager()
  var onLevelUpdate: ((Double, Double) -> Void)?
  var onMotionSample: ((CameraMotionSample) -> Void)?
  private var smoothedRoll: Double?
  private var smoothedPitch: Double?
  private var smoothedGyroMagnitude: Double?
  private var smoothedAccelerationMagnitude: Double?
  private var recentStabilityScores: [Double] = []
  private var stabilityCandidateSince: Date?
  private var isStabilityLatched = false
  private let smoothingAlpha = 0.18
  private let motionSmoothingAlpha = 0.2
  private let stabilityWindowSize = 15
  private let stableEntryThreshold = 0.18
  private let stableExitThreshold = 0.24
  private let warningThreshold = 0.52
  private let minimumStableDuration: TimeInterval = 0.42
  private var isRunning = false
  private var lastResolvedOrientation: UIDeviceOrientation = .portrait

  init() {}

  func start() {
    guard !isRunning else { return }
    guard motionManager.isDeviceMotionAvailable else { return }
    isRunning = true
    UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    lastResolvedOrientation = Self.resolveLevelDeviceOrientation(
      deviceOrientation: UIDevice.current.orientation,
      sceneOrientation: Self.preferredForegroundWindowScene()?.effectiveGeometry.interfaceOrientation
    )
    motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
    motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
      guard let self, let motion else { return }
      let orientation = self.resolveCurrentOrientation(gravity: motion.gravity)
      let mapped = Self.map(gravity: motion.gravity, for: orientation)
      let gyroMagnitude = Self.magnitude(
        x: motion.rotationRate.x,
        y: motion.rotationRate.y,
        z: motion.rotationRate.z
      )
      let accelerationMagnitude = Self.magnitude(
        x: motion.userAcceleration.x,
        y: motion.userAcceleration.y,
        z: motion.userAcceleration.z
      )
      self.emitSample(
        roll: mapped.roll,
        pitch: mapped.pitch,
        deviceOrientation: orientation,
        gyroMagnitude: gyroMagnitude,
        accelerationMagnitude: accelerationMagnitude
      )
    }
  }

  func stop() {
    guard isRunning else { return }
    isRunning = false
    motionManager.stopDeviceMotionUpdates()
    UIDevice.current.endGeneratingDeviceOrientationNotifications()
    resetMotionState()
  }

  deinit {
    stop()
  }

  private func emitSample(
    roll: Double,
    pitch: Double,
    deviceOrientation: UIDeviceOrientation,
    gyroMagnitude: Double,
    accelerationMagnitude: Double
  ) {
    smoothedRoll = smooth(previous: smoothedRoll, current: roll, alpha: smoothingAlpha)
    smoothedPitch = smooth(previous: smoothedPitch, current: pitch, alpha: smoothingAlpha)
    smoothedGyroMagnitude = smooth(
      previous: smoothedGyroMagnitude,
      current: gyroMagnitude,
      alpha: motionSmoothingAlpha
    )
    smoothedAccelerationMagnitude = smooth(
      previous: smoothedAccelerationMagnitude,
      current: accelerationMagnitude,
      alpha: motionSmoothingAlpha
    )

    let rollOut = applyDeadband(smoothedRoll ?? roll)
    let pitchOut = applyDeadband(smoothedPitch ?? pitch)
    let resolvedGyroMagnitude = smoothedGyroMagnitude ?? gyroMagnitude
    let resolvedAccelerationMagnitude = smoothedAccelerationMagnitude ?? accelerationMagnitude
    let stabilityScore = combinedStabilityScore(
      gyroMagnitude: resolvedGyroMagnitude,
      accelerationMagnitude: resolvedAccelerationMagnitude
    )
    let stabilityState = resolveStabilityState(for: stabilityScore, now: Date())

    onLevelUpdate?(rollOut, pitchOut)
    onMotionSample?(
      CameraMotionSample(
        roll: rollOut,
        pitch: pitchOut,
        deviceOrientation: deviceOrientation,
        stabilityScore: stabilityScore,
        stabilityState: stabilityState,
        gyroMagnitude: resolvedGyroMagnitude,
        accelerationMagnitude: resolvedAccelerationMagnitude
      )
    )
  }

  private func smooth(previous: Double?, current: Double, alpha: Double) -> Double {
    guard let previous else { return current }
    return (alpha * current) + ((1.0 - alpha) * previous)
  }

  private func applyDeadband(_ angle: Double) -> Double {
    let deadband = 0.15 * .pi / 180.0
    return abs(angle) < deadband ? 0 : angle
  }

  private func combinedStabilityScore(
    gyroMagnitude: Double,
    accelerationMagnitude: Double
  ) -> Double {
    let normalizedGyro = min(max(gyroMagnitude / 0.45, 0), 1)
    let normalizedAcceleration = min(max(accelerationMagnitude / 0.18, 0), 1)
    let instantScore = min(1.0, (normalizedGyro * 0.82) + (normalizedAcceleration * 0.18))
    recentStabilityScores.append(instantScore)
    if recentStabilityScores.count > stabilityWindowSize {
      recentStabilityScores.removeFirst(recentStabilityScores.count - stabilityWindowSize)
    }
    let total = recentStabilityScores.reduce(0, +)
    return total / Double(max(recentStabilityScores.count, 1))
  }

  private func resolveStabilityState(
    for score: Double,
    now: Date
  ) -> CameraStabilityState {
    let stableThreshold = isStabilityLatched ? stableExitThreshold : stableEntryThreshold

    if score <= stableThreshold {
      if stabilityCandidateSince == nil {
        stabilityCandidateSince = now
      }
      if isStabilityLatched || now.timeIntervalSince(stabilityCandidateSince ?? now) >= minimumStableDuration {
        isStabilityLatched = true
        return .stable
      }
      return .marginal
    }

    stabilityCandidateSince = nil
    isStabilityLatched = false
    if score <= warningThreshold {
      return .marginal
    }
    return .unstable
  }

  private func resetMotionState() {
    smoothedRoll = nil
    smoothedPitch = nil
    smoothedGyroMagnitude = nil
    smoothedAccelerationMagnitude = nil
    recentStabilityScores.removeAll(keepingCapacity: false)
    stabilityCandidateSince = nil
    isStabilityLatched = false
  }

  private static func magnitude(x: Double, y: Double, z: Double) -> Double {
    sqrt((x * x) + (y * y) + (z * z))
  }

  private func resolveCurrentOrientation(gravity: CMAcceleration) -> UIDeviceOrientation {
    lastResolvedOrientation = Self.resolveLevelDeviceOrientation(
      gravity: gravity,
      reportedDeviceOrientation: UIDevice.current.orientation,
      sceneOrientation: Self.preferredForegroundWindowScene()?.effectiveGeometry.interfaceOrientation,
      previousOrientation: lastResolvedOrientation
    )
    return lastResolvedOrientation
  }

  static func resolveLevelDeviceOrientation(
    gravity: CMAcceleration,
    reportedDeviceOrientation: UIDeviceOrientation,
    sceneOrientation: UIInterfaceOrientation?,
    previousOrientation: UIDeviceOrientation
  ) -> UIDeviceOrientation {
    let absoluteX = abs(gravity.x)
    let absoluteY = abs(gravity.y)
    let planarMagnitude = hypot(absoluteX, absoluteY)

    // When the camera points almost straight up/down, x/y gravity cannot
    // determine the viewport rotation. Retain the last useful physical axis.
    guard planarMagnitude >= 0.35 else {
      return isUsableLevelOrientation(previousOrientation)
        ? previousOrientation
        : resolveLevelDeviceOrientation(
          deviceOrientation: reportedDeviceOrientation,
          sceneOrientation: sceneOrientation
        )
    }

    // Use gravity as the primary source. UIDevice.current.orientation can stay
    // portrait while the camera UI remains portrait-locked; that produced the
    // real-device R -87 degree screenshot in physical landscape. A small
    // dominance margin prevents rapid axis changes around the 45-degree point.
    let dominanceMargin = 0.10
    if absoluteX > absoluteY + dominanceMargin {
      return gravity.x < 0 ? .landscapeLeft : .landscapeRight
    }
    if absoluteY > absoluteX + dominanceMargin {
      return gravity.y < 0 ? .portrait : .portraitUpsideDown
    }

    if isUsableLevelOrientation(previousOrientation) {
      return previousOrientation
    }
    return resolveLevelDeviceOrientation(
      deviceOrientation: reportedDeviceOrientation,
      sceneOrientation: sceneOrientation
    )
  }

  private static func isUsableLevelOrientation(_ orientation: UIDeviceOrientation) -> Bool {
    switch orientation {
    case .portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight:
      return true
    case .faceUp, .faceDown, .unknown:
      return false
    @unknown default:
      return false
    }
  }

  static func resolveLevelDeviceOrientation(
    deviceOrientation: UIDeviceOrientation,
    sceneOrientation: UIInterfaceOrientation?
  ) -> UIDeviceOrientation {
    // Gravity is expressed in physical device coordinates. Keep the physical
    // UIDevice orientation here; mirroring it into UIInterfaceOrientation
    // swaps the two landscape gravity transforms and makes a level device read
    // as 180 degrees off on real hardware.
    switch deviceOrientation {
    case .portrait:
      return .portrait
    case .portraitUpsideDown:
      return .portraitUpsideDown
    case .landscapeLeft:
      return .landscapeLeft
    case .landscapeRight:
      return .landscapeRight
    default:
      break
    }

    // Interface and device landscape names are inverse. Convert the scene
    // fallback back into the physical device coordinate system before mapping
    // gravity.
    switch sceneOrientation {
    case .portrait:
      return .portrait
    case .portraitUpsideDown:
      return .portraitUpsideDown
    case .landscapeLeft:
      return .landscapeRight
    case .landscapeRight:
      return .landscapeLeft
    case .unknown, .none:
      return .portrait
    @unknown default:
      return .portrait
    }
  }

  static func resolveInterfaceOrientation(
    deviceOrientation: UIDeviceOrientation,
    sceneOrientation: UIInterfaceOrientation?
  ) -> UIInterfaceOrientation {
    switch deviceOrientation {
    case .portrait:
      return .portrait
    case .portraitUpsideDown:
      return .portraitUpsideDown
    case .landscapeLeft:
      return .landscapeRight
    case .landscapeRight:
      return .landscapeLeft
    default:
      break
    }
    if let sceneOrientation, sceneOrientation != .unknown {
      return sceneOrientation
    }
    return .portrait
  }

  static func map(gravity: CMAcceleration, for orientation: UIDeviceOrientation) -> (roll: Double, pitch: Double) {
    let gx = gravity.x
    let gy = gravity.y
    let gz = gravity.z

    let screenX: Double
    let screenY: Double
    switch orientation {
    case .landscapeLeft:
      // rotate +90 from portrait axes
      screenX = -gy
      screenY = gx
    case .landscapeRight:
      // rotate -90 from portrait axes
      screenX = gy
      screenY = -gx
    case .portraitUpsideDown:
      screenX = -gx
      screenY = -gy
    case .portrait, .faceUp, .faceDown, .unknown:
      screenX = gx
      screenY = gy
    @unknown default:
      screenX = gx
      screenY = gy
    }

    let roll = atan2(screenX, -screenY)
    let planar = sqrt(max(0.000_001, (screenX * screenX) + (screenY * screenY)))
    let pitch = atan2(gz, planar)
    return (roll: roll, pitch: pitch)
  }

  private static func preferredForegroundWindowScene() -> UIWindowScene? {
    let scenes = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .filter { $0.activationState == .foregroundActive }
    return scenes.first(where: { $0.windows.contains(where: \.isKeyWindow) }) ?? scenes.first
  }
}
