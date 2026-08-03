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
}
