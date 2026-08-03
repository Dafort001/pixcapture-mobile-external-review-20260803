import CoreGraphics
import ImageIO
import UIKit

enum ImageCropper {
  static func centerCrop(data: Data, aspectRatio: CGFloat) -> Data? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let type = CGImageSourceGetType(source),
          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
      return nil
    }

    let properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
    let orientationValue = properties[kCGImagePropertyOrientation] as? UInt32
    let isRotated = orientationValue == 6 || orientationValue == 8 || orientationValue == 5 || orientationValue == 7
    let targetAspect = isRotated ? (1.0 / aspectRatio) : aspectRatio

    let width = CGFloat(cgImage.width)
    let height = CGFloat(cgImage.height)
    let currentRatio = width / max(height, 1)

    var targetWidth = width
    var targetHeight = height

    if currentRatio > targetAspect {
      targetWidth = height * targetAspect
      targetHeight = height
    } else {
      targetHeight = width / targetAspect
      targetWidth = width
    }

    let originX = (width - targetWidth) / 2
    let originY = (height - targetHeight) / 2
    let cropRect = CGRect(x: originX, y: originY, width: targetWidth, height: targetHeight)

    guard let cropped = cgImage.cropping(to: cropRect) else { return nil }

    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, type, 1, nil) else { return nil }
    var updatedProperties = properties
    updatedProperties[kCGImagePropertyPixelWidth] = Int(targetWidth.rounded())
    updatedProperties[kCGImagePropertyPixelHeight] = Int(targetHeight.rounded())
    if var exif = updatedProperties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
      exif[kCGImagePropertyExifPixelXDimension] = Int(targetWidth.rounded())
      exif[kCGImagePropertyExifPixelYDimension] = Int(targetHeight.rounded())
      updatedProperties[kCGImagePropertyExifDictionary] = exif
    }
    CGImageDestinationAddImage(destination, cropped, updatedProperties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return output as Data
  }
}
