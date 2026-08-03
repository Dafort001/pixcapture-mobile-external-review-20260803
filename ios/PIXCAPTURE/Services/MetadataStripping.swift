import Foundation
import ImageIO

enum MetadataStripping {
  static func stripGPS(from data: Data) throws -> Data {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let type = CGImageSourceGetType(source) else {
      return data
    }
    let writableTypes = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
    guard writableTypes.contains(type as String) else {
      return data
    }

    let count = CGImageSourceGetCount(source)
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, type, count, nil) else {
      return data
    }

    for index in 0..<count {
      var properties = (CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]) ?? [:]
      properties[kCGImagePropertyGPSDictionary] = nil
      CGImageDestinationAddImageFromSource(destination, source, index, properties as CFDictionary)
    }

    CGImageDestinationFinalize(destination)
    return output as Data
  }
}
