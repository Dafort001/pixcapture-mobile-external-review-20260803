import Foundation

enum UploadDebugLog {
  private static let queue = DispatchQueue(label: "app.pixcapture.uploadDebugLog")

  static var fileURL: URL {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("pixupload-debug.log")
  }

  static func write(_ message: String) {
    queue.async {
      let timestamp = ISO8601DateFormatter().string(from: Date())
      let line = "\(timestamp) \(message)\n"
      guard let data = line.data(using: .utf8) else { return }
      let url = fileURL
      if !FileManager.default.fileExists(atPath: url.path) {
        _ = FileManager.default.createFile(atPath: url.path, contents: nil)
      }
      let handle: FileHandle
      do {
        handle = try FileHandle(forWritingTo: url)
      } catch {
        return
      }
      defer {
        do {
          try handle.close()
        } catch {
        }
      }
      do {
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
      } catch {
        return
      }
    }
  }

  static func reset() {
    queue.async {
      do {
        try FileManager.default.removeItem(at: fileURL)
      } catch {
      }
    }
  }
}
