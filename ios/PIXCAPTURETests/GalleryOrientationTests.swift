import Testing
import UIKit
@testable import PIXCAPTURE

struct GalleryOrientationTests {

  @Test("Portrait capture on landscape pixels rotates right")
  func portraitCaptureLandscapePixels() {
    let orientation = manualGalleryOrientation(
      captureOrientation: "portrait",
      pixelWidth: 4032,
      pixelHeight: 3024
    )
    #expect(orientation == .right)
  }

  @Test("Portrait upside down capture on landscape pixels rotates left")
  func portraitUpsideDownCaptureLandscapePixels() {
    let orientation = manualGalleryOrientation(
      captureOrientation: "portraitUpsideDown",
      pixelWidth: 4032,
      pixelHeight: 3024
    )
    #expect(orientation == .left)
  }

  @Test("Landscape right capture on portrait pixels rotates right")
  func landscapeRightCapturePortraitPixels() {
    let orientation = manualGalleryOrientation(
      captureOrientation: "landscapeRight",
      pixelWidth: 3024,
      pixelHeight: 4032
    )
    #expect(orientation == .right)
  }

  @Test("Landscape left capture on portrait pixels rotates left")
  func landscapeLeftCapturePortraitPixels() {
    let orientation = manualGalleryOrientation(
      captureOrientation: "landscapeLeft",
      pixelWidth: 3024,
      pixelHeight: 4032
    )
    #expect(orientation == .left)
  }

  @Test("Matching portrait pixels keep up orientation")
  func portraitCapturePortraitPixelsUnchanged() {
    let orientation = manualGalleryOrientation(
      captureOrientation: "portrait",
      pixelWidth: 3024,
      pixelHeight: 4032
    )
    #expect(orientation == .up)
  }

  @Test("Matching landscape pixels keep up orientation")
  func landscapeCaptureLandscapePixelsUnchanged() {
    let right = manualGalleryOrientation(
      captureOrientation: "landscapeRight",
      pixelWidth: 4032,
      pixelHeight: 3024
    )
    let left = manualGalleryOrientation(
      captureOrientation: "landscapeLeft",
      pixelWidth: 4032,
      pixelHeight: 3024
    )
    #expect(right == .up)
    #expect(left == .up)
  }

  @Test("Matching upside-down portrait pixels stay up")
  func portraitUpsideDownCapturePortraitPixelsStayUp() {
    let orientation = manualGalleryOrientation(
      captureOrientation: "portraitUpsideDown",
      pixelWidth: 3024,
      pixelHeight: 4032
    )
    #expect(orientation == .up)
  }

  @Test("EXIF fallback returns down for orientation=3")
  func exifFallbackDownOrientation() {
    let orientation = manualGalleryOrientation(
      captureOrientation: nil,
      metadataOrientation: 3,
      pixelWidth: 4032,
      pixelHeight: 3024
    )
    #expect(orientation == .down)
  }
}
