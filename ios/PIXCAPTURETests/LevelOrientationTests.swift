import CoreMotion
import Testing
import UIKit
@testable import PIXCAPTURE

struct LevelOrientationTests {
  private let tolerance = 0.000_001

  @Test("Portrait gravity maps to a level viewport")
  func portraitGravityIsLevel() {
    let mapped = LevelMonitor.map(
      gravity: CMAcceleration(x: 0, y: -1, z: 0),
      for: .portrait
    )

    #expect(abs(mapped.roll) < tolerance)
    #expect(abs(mapped.pitch) < tolerance)
  }

  @Test("Landscape-left gravity maps to a level viewport")
  func landscapeLeftGravityIsLevel() {
    let mapped = LevelMonitor.map(
      gravity: CMAcceleration(x: -1, y: 0, z: 0),
      for: .landscapeLeft
    )

    #expect(abs(mapped.roll) < tolerance)
    #expect(abs(mapped.pitch) < tolerance)
  }

  @Test("Landscape-right gravity maps to a level viewport")
  func landscapeRightGravityIsLevel() {
    let mapped = LevelMonitor.map(
      gravity: CMAcceleration(x: 1, y: 0, z: 0),
      for: .landscapeRight
    )

    #expect(abs(mapped.roll) < tolerance)
    #expect(abs(mapped.pitch) < tolerance)
  }

  @Test("Portrait mapping reproduces the reported 90-degree landscape error")
  func portraitMappingOfLandscapeGravityIsNinetyDegreesWrong() {
    let mapped = LevelMonitor.map(
      gravity: CMAcceleration(x: -1, y: 0, z: 0),
      for: .portrait
    )

    #expect(abs((mapped.roll * 180 / .pi) + 90) < tolerance)
    #expect(abs(mapped.pitch) < tolerance)
  }

  @Test("Keystone guide keeps viewport-normalized level values unchanged")
  func keystoneDoesNotRotateViewportValuesTwice() {
    let transform = KeystoneOrientationMapper.transform(
      rollRadians: 1.25 * .pi / 180,
      pitchRadians: -2.5 * .pi / 180
    )

    #expect(abs(transform.normalizedRollForViewport - 1.25) < tolerance)
    #expect(abs(transform.normalizedPitchForViewport + 2.5) < tolerance)
  }

  @Test("Level mapping keeps physical landscape-left axes")
  func levelMappingKeepsPhysicalLandscapeLeft() {
    #expect(
      LevelMonitor.resolveLevelDeviceOrientation(
        deviceOrientation: .landscapeLeft,
        sceneOrientation: .portrait
      ) == .landscapeLeft
    )
  }

  @Test("Physical landscape-right overrides a portrait-locked scene for gravity")
  func physicalLandscapeRightOverridesPortraitLockedSceneForGravity() {
    let orientation = LevelMonitor.resolveLevelDeviceOrientation(
      deviceOrientation: .landscapeRight,
      sceneOrientation: .portrait
    )
    #expect(orientation == .landscapeRight)
    let mapped = LevelMonitor.map(
      gravity: CMAcceleration(x: 1, y: 0, z: 0),
      for: orientation
    )
    #expect(abs(mapped.roll) < tolerance)
  }

  @Test("Scene fallback is converted back to physical landscape axes")
  func sceneOrientationFallbackUsesPhysicalAxes() {
    #expect(
      LevelMonitor.resolveLevelDeviceOrientation(
        deviceOrientation: .faceUp,
        sceneOrientation: .landscapeRight
      ) == .landscapeLeft
    )
  }

  @Test("Camera interface orientation mirrors physical landscape names")
  func cameraInterfaceOrientationMirrorsPhysicalLandscape() {
    #expect(
      LevelMonitor.resolveInterfaceOrientation(
        deviceOrientation: .landscapeLeft,
        sceneOrientation: .portrait
      ) == .landscapeRight
    )
    #expect(
      LevelMonitor.resolveInterfaceOrientation(
        deviceOrientation: .landscapeRight,
        sceneOrientation: .portrait
      ) == .landscapeLeft
    )
  }

  @Test("Screenshot gravity overrides stale portrait device and scene orientation")
  func screenshotGravityOverridesStalePortraitOrientation() {
    let gravity = CMAcceleration(x: -0.996, y: -0.052, z: -0.075)
    let orientation = LevelMonitor.resolveLevelDeviceOrientation(
      gravity: gravity,
      reportedDeviceOrientation: .portrait,
      sceneOrientation: .portrait,
      previousOrientation: .portrait
    )

    #expect(orientation == .landscapeLeft)
    let corrected = LevelMonitor.map(gravity: gravity, for: orientation)
    #expect(abs((corrected.roll * 180 / .pi) - 2.99) < 0.1)
    #expect(abs((corrected.pitch * 180 / .pi) + 4.29) < 0.1)
  }

  @Test("Opposite landscape gravity overrides stale portrait orientation")
  func oppositeLandscapeGravityOverridesStalePortraitOrientation() {
    let orientation = LevelMonitor.resolveLevelDeviceOrientation(
      gravity: CMAcceleration(x: 0.998, y: -0.035, z: 0),
      reportedDeviceOrientation: .portrait,
      sceneOrientation: .portrait,
      previousOrientation: .portrait
    )

    #expect(orientation == .landscapeRight)
  }

  @Test("Face-up gravity retains the previous physical viewport axis")
  func faceUpGravityRetainsPreviousAxis() {
    let orientation = LevelMonitor.resolveLevelDeviceOrientation(
      gravity: CMAcceleration(x: 0.02, y: -0.01, z: -0.999),
      reportedDeviceOrientation: .faceUp,
      sceneOrientation: .portrait,
      previousOrientation: .landscapeLeft
    )

    #expect(orientation == .landscapeLeft)
  }
}
