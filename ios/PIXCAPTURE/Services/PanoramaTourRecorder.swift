@preconcurrency import AVFoundation
import Combine
import CoreImage
import CoreMedia
import Foundation
import simd
import UIKit
import VideoToolbox
import Vision
#if canImport(ARKit)
import ARKit
#endif

final class PanoramaTourRecorder: NSObject, ObservableObject {
  struct MarkerOverlay: Identifiable {
    let id: String
    let markerId: String
    let boundingBox: CGRect // normalized [0...1], origin bottom-left
    let isAnchored: Bool
  }

  struct ExportBundle {
    let takeId: UUID
    let bundleURL: URL
    let videoURL: URL
    let metadataURL: URL
  }

  enum RecorderError: LocalizedError {
    case arKitUnavailable
    case writerSetupFailed(String)
    case recordingNotStarted
    case noFramesWritten
    case finalizeFailed(String)

    var errorDescription: String? {
      switch self {
      case .arKitUnavailable:
        return "ARKit ist auf diesem Gerät nicht verfügbar."
      case .writerSetupFailed(let reason):
        return "Video-Setup fehlgeschlagen: \(reason)"
      case .recordingNotStarted:
        return "Es läuft keine Aufnahme."
      case .noFramesWritten:
        return "Es wurden keine Frames geschrieben."
      case .finalizeFailed(let reason):
        return "Export fehlgeschlagen: \(reason)"
      }
    }
  }

  @Published var isSessionRunning = false
  @Published var isRecording = false
  @Published var durationSeconds: Double = 0
  @Published var warningMessage: String?
  @Published var previewImage: CGImage?
  @Published var markerOverlays: [MarkerOverlay] = []
  @Published var lastTriggerMarkerId: String?
  @Published var lastTriggerTimestamp: Double?
  @Published var writerProfileLabel: String = "HEVC_Main"

  // Optional Z-offset placeholder for hardware calibration.
  var hardwareOffsetZ: Double? = nil

#if canImport(ARKit)
  private let arSession = ARSession()
  private var arSessionDelegate: ARSessionDelegateProxy?
#endif
  private let sessionQueue = DispatchQueue(label: "pixcapture.panorama.session")
  private let ciContext = CIContext(options: [CIContextOption.cacheIntermediates: false])

  private let targetFPS = 30
  private let targetBitrate = 24_000_000
  private let warmupFrameTarget = 20

  private var viewportSize: CGSize = .zero
  private var lastPreviewTimestamp: TimeInterval = -.greatestFiniteMagnitude

  private var writer: AVAssetWriter?
  private var writerInput: AVAssetWriterInput?
  private var writerAdaptor: AVAssetWriterInputPixelBufferAdaptor?
  private var recordingPaths: RecordingPaths?

  private var recordingActive = false
  private var startFrameTimestamp: TimeInterval?
  private var warmupFramesDiscarded = 0
  private var nextFrameIndex = 0
  private var lastFrameTimestamp: TimeInterval?

  private var frameRecords: [FrameRecord] = []
  private var markerRecords: [MarkerRecord] = []
  private var triggerEvents: [TriggerEventRecord] = []

  private var anchoredMarkerTransforms: [String: simd_float4x4] = [:]
  private var lastSeenMarkerTimestamp: [String: Double] = [:]
  private var lastLinkedMarkerId: String?
  private var floorplanProjectKey: String? = nil
  private let openCVDetector = OpenCVArUcoDetector()
  private let isOpenCVDetectorAvailable = OpenCVArUcoDetector.isOpenCVAvailable

  override init() {
    super.init()
#if canImport(ARKit)
    let proxy = ARSessionDelegateProxy()
    proxy.recorder = self
    arSessionDelegate = proxy
    arSession.delegate = proxy
#endif
  }

  func updateViewportSize(_ size: CGSize) {
    guard size.width > 0, size.height > 0 else { return }
    sessionQueue.async {
      self.viewportSize = size
    }
  }

  func setFloorplanProjectKey(_ projectKey: String?) {
    let normalized = Self.normalizedProjectKey(projectKey)
    sessionQueue.async {
      self.floorplanProjectKey = normalized
    }
  }

  func startSession() {
#if canImport(ARKit)
    guard ARWorldTrackingConfiguration.isSupported else {
      DispatchQueue.main.async {
        self.warningMessage = RecorderError.arKitUnavailable.localizedDescription
      }
      return
    }

    sessionQueue.async {
      let config = ARWorldTrackingConfiguration()
      config.worldAlignment = .gravity
      config.planeDetection = [.horizontal, .vertical]
      config.environmentTexturing = .none
      config.isAutoFocusEnabled = true

      if #available(iOS 13.4, *), ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
        config.sceneReconstruction = .mesh
      }

      if let format = Self.selectPreferredVideoFormat() {
        config.videoFormat = format
      }

      self.arSession.run(config, options: [.resetTracking, .removeExistingAnchors])
      DispatchQueue.main.async {
        self.warningMessage = self.isOpenCVDetectorAvailable
          ? nil
          : "OpenCV ArUco ist nicht aktiv. Für 4x4_100 bitte opencv2.xcframework einbinden."
        self.isSessionRunning = true
      }
    }
#else
    DispatchQueue.main.async {
      self.warningMessage = RecorderError.arKitUnavailable.localizedDescription
    }
#endif
  }

  func stopSession() {
    sessionQueue.async {
#if canImport(ARKit)
      self.arSession.pause()
#endif
      self.resetRecordingState(clearPreview: false)
      DispatchQueue.main.async {
        self.isSessionRunning = false
      }
    }
  }

  func startRecording() {
    sessionQueue.async {
      guard !self.recordingActive else { return }

      do {
        let paths = try Self.createRecordingPaths()
        let writer = try AVAssetWriter(outputURL: paths.videoURL, fileType: .mp4)

        let (videoSettings, profileLabel) = self.makeVideoSettings()
        guard writer.canApply(outputSettings: videoSettings, forMediaType: .video) else {
          throw RecorderError.writerSetupFailed("HEVC-Profile wird auf diesem Gerät nicht unterstützt.")
        }

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true

        guard writer.canAdd(input) else {
          throw RecorderError.writerSetupFailed("AVAssetWriterInput konnte nicht hinzugefügt werden.")
        }
        writer.add(input)

        let attributes: [String: Any] = [
          kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
          kCVPixelBufferWidthKey as String: Int(Self.selectedResolution().width),
          kCVPixelBufferHeightKey as String: Int(Self.selectedResolution().height),
          kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
          assetWriterInput: input,
          sourcePixelBufferAttributes: attributes
        )

        guard writer.startWriting() else {
          throw RecorderError.writerSetupFailed(writer.error?.localizedDescription ?? "startWriting fehlgeschlagen")
        }

        self.writer = writer
        self.writerInput = input
        self.writerAdaptor = adaptor
        self.recordingPaths = paths
        self.recordingActive = true
        self.startFrameTimestamp = nil
        self.warmupFramesDiscarded = 0
        self.nextFrameIndex = 0
        self.frameRecords = []
        self.markerRecords = []
        self.triggerEvents = []
        self.lastLinkedMarkerId = nil
        self.lastTriggerMarkerId = nil
        self.lastTriggerTimestamp = nil
        self.durationSeconds = 0
        self.writerProfileLabel = profileLabel

        self.lockCameraExposureAndFocus()

        DispatchQueue.main.async {
          self.warningMessage = nil
          self.isRecording = true
          self.durationSeconds = 0
        }
      } catch {
        DispatchQueue.main.async {
          self.warningMessage = error.localizedDescription
          self.isRecording = false
        }
      }
    }
  }

  func stopRecording(completion: @escaping (Result<ExportBundle, Error>) -> Void) {
    sessionQueue.async {
      guard self.recordingActive else {
        DispatchQueue.main.async {
          completion(.failure(RecorderError.recordingNotStarted))
        }
        return
      }

      self.recordingActive = false
      self.restoreCameraAutoModes()

      guard self.writer != nil,
            let input = self.writerInput,
            let paths = self.recordingPaths else {
        self.resetRecordingState(clearPreview: false)
        DispatchQueue.main.async {
          completion(.failure(RecorderError.finalizeFailed("Interner Writer-Status fehlt.")))
        }
        return
      }

      guard !self.frameRecords.isEmpty else {
        self.writer?.cancelWriting()
        self.resetRecordingState(clearPreview: false)
        DispatchQueue.main.async {
          self.isRecording = false
          self.durationSeconds = 0
          completion(.failure(RecorderError.noFramesWritten))
        }
        return
      }

      input.markAsFinished()
      self.writer?.finishWriting { [weak self] in
        guard let self else { return }
        self.sessionQueue.async {
          let writerStatus = self.writer?.status ?? .unknown
          let writerErrorDescription = self.writer?.error?.localizedDescription
          defer {
            self.resetRecordingState(clearPreview: false)
          }

          guard writerStatus == .completed else {
            DispatchQueue.main.async {
              self.isRecording = false
              self.durationSeconds = 0
              completion(.failure(RecorderError.finalizeFailed(writerErrorDescription ?? "finishWriting fehlgeschlagen")))
            }
            return
          }

          do {
            let linkedFloorplan = self.collectLinkedFloorplanBundle(in: paths.bundleURL)
            let jsonObject = self.makeMetadataJSONObject(linkedFloorplan: linkedFloorplan)
            let data = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: paths.metadataURL, options: [.atomic])

            let bundle = ExportBundle(
              takeId: paths.takeId,
              bundleURL: paths.bundleURL,
              videoURL: paths.videoURL,
              metadataURL: paths.metadataURL
            )

            DispatchQueue.main.async {
              self.isRecording = false
              self.durationSeconds = 0
              completion(.success(bundle))
            }
          } catch {
            DispatchQueue.main.async {
              self.isRecording = false
              self.durationSeconds = 0
              completion(.failure(error))
            }
          }
        }
      }
    }
  }

  func markHighResSpot() {
    sessionQueue.async {
      guard self.recordingActive else { return }
      let timestamp = max(0, self.durationSecondsLocked)
      let linkedMarkerId = self.resolveLinkedMarkerId()

      self.triggerEvents.append(
        TriggerEventRecord(
          timestamp: timestamp,
          markerId: linkedMarkerId,
          eventType: "high_res_spot"
        )
      )

      DispatchQueue.main.async {
        self.lastTriggerTimestamp = timestamp
        self.lastTriggerMarkerId = linkedMarkerId
      }
    }
  }

#if canImport(ARKit)
  private func handleARFrame(_ frame: ARFrame) {
    sessionQueue.async {
      self.lastFrameTimestamp = frame.timestamp
      self.publishPreviewImageIfNeeded(frame)
      self.processMarkers(from: frame)
      self.appendRecordingFrameIfNeeded(frame)
    }
  }
#endif

  private var durationSecondsLocked: Double {
    if let startFrameTimestamp, let lastFrameTimestamp {
      return max(0, lastFrameTimestamp - startFrameTimestamp)
    }
    return 0
  }

#if canImport(ARKit)
  private func appendRecordingFrameIfNeeded(_ frame: ARFrame) {
    guard recordingActive,
          let writer,
          let input = writerInput,
          let adaptor = writerAdaptor,
          writer.status == .writing else {
      return
    }

    if startFrameTimestamp == nil {
      warmupFramesDiscarded += 1
      if warmupFramesDiscarded < warmupFrameTarget {
        return
      }
      startFrameTimestamp = frame.timestamp
      writer.startSession(atSourceTime: .zero)
    }

    guard let startFrameTimestamp else { return }

    let relativeSeconds = max(0, frame.timestamp - startFrameTimestamp)
    let pts = CMTime(seconds: relativeSeconds, preferredTimescale: 600)

    guard input.isReadyForMoreMediaData else { return }
    guard adaptor.append(frame.capturedImage, withPresentationTime: pts) else {
      if let error = writer.error {
        DispatchQueue.main.async {
          self.warningMessage = "Frame konnte nicht geschrieben werden: \(error.localizedDescription)"
        }
      }
      return
    }

    let intrinsics = Self.matrix3x3ToArray(frame.camera.intrinsics)
    let transform = Self.matrix4x4ToArray(frame.camera.transform)

    frameRecords.append(
      FrameRecord(
        frameIndex: nextFrameIndex,
        timestamp: relativeSeconds,
        intrinsics: intrinsics,
        transform: transform,
        trackingState: Self.trackingStateString(frame.camera.trackingState)
      )
    )

    nextFrameIndex += 1

    DispatchQueue.main.async {
      self.durationSeconds = relativeSeconds
    }
  }

  private func processMarkers(from frame: ARFrame) {
    let detections = detectMarkers(in: frame.capturedImage)
    guard !detections.isEmpty else {
      DispatchQueue.main.async {
        self.markerOverlays = []
      }
      return
    }

    var overlays: [MarkerOverlay] = []
    var linkedMarkerId: String?

    for (index, detection) in detections.enumerated() {
      let markerId = detection.markerId
      let boundingBox = detection.boundingBox

      if linkedMarkerId == nil {
        linkedMarkerId = markerId
      }

      if let relativeTimestamp = recordingRelativeTimestamp(for: frame.timestamp) {
        lastSeenMarkerTimestamp[markerId] = relativeTimestamp
      }

      let wasAnchored = anchoredMarkerTransforms[markerId] != nil
      if !wasAnchored,
         let anchorTransform = raycastTransform(for: boundingBox, frame: frame) {
        anchoredMarkerTransforms[markerId] = anchorTransform

        let anchor = ARAnchor(name: "marker_\(markerId)", transform: anchorTransform)
        arSession.add(anchor: anchor)

        if let relativeTimestamp = recordingRelativeTimestamp(for: frame.timestamp) {
          markerRecords.append(
            MarkerRecord(
              markerId: markerId,
              timestamp: relativeTimestamp,
              transform: Self.matrix4x4ToArray(anchorTransform),
              imageBoundingBox: [
                Double(boundingBox.minX),
                Double(boundingBox.minY),
                Double(boundingBox.width),
                Double(boundingBox.height)
              ]
            )
          )
        }
      }

      overlays.append(
        MarkerOverlay(
          id: "\(markerId)-\(index)",
          markerId: markerId,
          boundingBox: boundingBox,
          isAnchored: anchoredMarkerTransforms[markerId] != nil
        )
      )
    }

    lastLinkedMarkerId = linkedMarkerId

    DispatchQueue.main.async {
      self.markerOverlays = overlays
    }
  }

  private struct DetectedMarker {
    let markerId: String
    let boundingBox: CGRect
  }

  private var markerDictionaryType: String {
    isOpenCVDetectorAvailable
      ? "aruco_4x4_100"
      : "vision_barcodes_qr_aztec_datamatrix_pdf417"
  }

  private func detectMarkers(in pixelBuffer: CVPixelBuffer) -> [DetectedMarker] {
    let arucoMarkers = openCVDetector.detect(pixelBuffer: pixelBuffer)
    if !arucoMarkers.isEmpty {
      return arucoMarkers.map { detection in
        DetectedMarker(
          markerId: String(detection.markerId),
          boundingBox: normalizeBoundingBox(detection.normalizedBoundingBox)
        )
      }
    }

    if isOpenCVDetectorAvailable {
      return []
    }

    let request = VNDetectBarcodesRequest()
    request.symbologies = [.qr, .aztec, .dataMatrix, .pdf417]
    let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])

    do {
      try handler.perform([request])
      let observations = request.results ?? []
      return observations.enumerated().map { index, observation in
        DetectedMarker(
          markerId: markerIdentifier(for: observation, fallbackIndex: index),
          boundingBox: normalizeBoundingBox(observation.boundingBox)
        )
      }
    } catch {
      DispatchQueue.main.async {
        self.warningMessage = "Marker-Erkennung fehlgeschlagen: \(error.localizedDescription)"
      }
      return []
    }
  }

  private func markerIdentifier(for observation: VNBarcodeObservation, fallbackIndex: Int) -> String {
    if let payload = observation.payloadStringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
       !payload.isEmpty {
      return payload
    }

    let c = observation.boundingBox
    let cx = Int((c.midX * 1000).rounded())
    let cy = Int((c.midY * 1000).rounded())
    return "\(observation.symbology.rawValue)_\(fallbackIndex)_\(cx)_\(cy)"
  }

  private func normalizeBoundingBox(_ raw: CGRect) -> CGRect {
    let minX = max(0, min(1, raw.minX))
    let minY = max(0, min(1, raw.minY))
    let maxX = max(0, min(1, raw.maxX))
    let maxY = max(0, min(1, raw.maxY))
    return CGRect(
      x: minX,
      y: minY,
      width: max(0, maxX - minX),
      height: max(0, maxY - minY)
    )
  }

  private func raycastTransform(for normalizedBoundingBox: CGRect, frame: ARFrame) -> simd_float4x4? {
    let viewport = viewportSize.width > 0 && viewportSize.height > 0
      ? viewportSize
      : CGSize(width: CGFloat(frame.camera.imageResolution.width), height: CGFloat(frame.camera.imageResolution.height))

    let center = CGPoint(
      x: normalizedBoundingBox.midX * viewport.width,
      y: (1 - normalizedBoundingBox.midY) * viewport.height
    )

    let query = frame.raycastQuery(from: center, allowing: .estimatedPlane, alignment: .any)
    return arSession.raycast(query).first?.worldTransform
  }

  private func recordingRelativeTimestamp(for frameTimestamp: TimeInterval) -> Double? {
    guard let startFrameTimestamp else { return nil }
    return max(0, frameTimestamp - startFrameTimestamp)
  }

  private func publishPreviewImageIfNeeded(_ frame: ARFrame) {
    let previewInterval = 1.0 / 15.0
    guard frame.timestamp - lastPreviewTimestamp >= previewInterval else { return }
    lastPreviewTimestamp = frame.timestamp

    let image = CIImage(cvPixelBuffer: frame.capturedImage).oriented(.right)
    guard let cg = ciContext.createCGImage(image, from: image.extent) else { return }

    DispatchQueue.main.async {
      self.previewImage = cg
    }
  }
#endif

  private func makeVideoSettings() -> ([String: Any], String) {
    let size = Self.selectedResolution()

    let main10Compression: [String: Any] = [
      AVVideoAverageBitRateKey: targetBitrate,
      AVVideoExpectedSourceFrameRateKey: targetFPS,
      AVVideoMaxKeyFrameIntervalKey: targetFPS,
      AVVideoAllowFrameReorderingKey: false,
      AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel as String
    ]

    let settings: [String: Any] = [
      AVVideoCodecKey: AVVideoCodecType.hevc,
      AVVideoWidthKey: Int(size.width),
      AVVideoHeightKey: Int(size.height),
      AVVideoCompressionPropertiesKey: main10Compression
    ]

    return (settings, "HEVC_Main10_AutoLevel")
  }

  private func resolveLinkedMarkerId() -> String? {
    if let lastLinkedMarkerId,
       anchoredMarkerTransforms[lastLinkedMarkerId] != nil {
      return lastLinkedMarkerId
    }

    return lastSeenMarkerTimestamp
      .filter { anchoredMarkerTransforms[$0.key] != nil }
      .sorted { $0.value > $1.value }
      .first?
      .key
  }

  private func makeMetadataJSONObject(linkedFloorplan: [String: Any]?) -> [String: Any] {
    let encoderTimestamp = ISO8601DateFormatter().string(from: Date())

    let framesPayload = frameRecords.map { record in
      [
        "frame_index": record.frameIndex,
        "timestamp": record.timestamp,
        "intrinsics": record.intrinsics.map { $0.map(Double.init) },
        "transform": record.transform.map { $0.map(Double.init) },
        "tracking_state": record.trackingState
      ] as [String: Any]
    }

    let markersPayload = markerRecords.map { marker in
      [
        "marker_id": marker.markerId,
        "timestamp": marker.timestamp,
        "transform": marker.transform.map { $0.map(Double.init) },
        "image_bounding_box": marker.imageBoundingBox
      ] as [String: Any]
    }

    let eventsPayload = triggerEvents.map { event in
      [
        "timestamp": event.timestamp,
        "marker_id": event.markerId ?? NSNull(),
        "event_type": event.eventType
      ] as [String: Any]
    }

    return [
      "schema_version": 1,
      "created_at": encoderTimestamp,
      "fps": targetFPS,
      "codec": "hevc",
      "codec_profile": writerProfileLabel,
      "bitrate": targetBitrate,
      "hardware_offset_z": hardwareOffsetZ ?? NSNull(),
      "marker_dictionary": markerDictionaryType,
      "opencv_enabled": isOpenCVDetectorAvailable,
      "linked_floorplan": linkedFloorplan ?? NSNull(),
      "frame_count": frameRecords.count,
      "marker_count": markerRecords.count,
      "event_count": triggerEvents.count,
      "frames": framesPayload,
      "markers": markersPayload,
      "events": eventsPayload
    ]
  }

  private func lockCameraExposureAndFocus() {
    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }

    do {
      try device.lockForConfiguration()
      if device.isFocusModeSupported(.locked) {
        let lens = device.lensPosition
        device.setFocusModeLocked(lensPosition: lens, completionHandler: nil)
      }
      if device.isExposureModeSupported(.custom) {
        let duration = device.exposureDuration
        let iso = min(max(device.iso, device.activeFormat.minISO), device.activeFormat.maxISO)
        device.setExposureModeCustom(duration: duration, iso: iso, completionHandler: nil)
      } else if device.isExposureModeSupported(.locked) {
        device.exposureMode = .locked
      }
      device.unlockForConfiguration()
    } catch {
      DispatchQueue.main.async {
        self.warningMessage = "AF/AE-Lock fehlgeschlagen: \(error.localizedDescription)"
      }
    }
  }

  private func restoreCameraAutoModes() {
    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }

    do {
      try device.lockForConfiguration()
      if device.isFocusModeSupported(.continuousAutoFocus) {
        device.focusMode = .continuousAutoFocus
      }
      if device.isExposureModeSupported(.continuousAutoExposure) {
        device.exposureMode = .continuousAutoExposure
      }
      device.unlockForConfiguration()
    } catch {
      // ignore - non-critical on teardown
    }
  }

  private func resetRecordingState(clearPreview: Bool) {
    writer = nil
    writerInput = nil
    writerAdaptor = nil
    recordingPaths = nil
    recordingActive = false
    startFrameTimestamp = nil
    warmupFramesDiscarded = 0
    nextFrameIndex = 0
    frameRecords = []
    markerRecords = []
    triggerEvents = []
    anchoredMarkerTransforms = [:]
    lastSeenMarkerTimestamp = [:]
    lastLinkedMarkerId = nil

    DispatchQueue.main.async {
      self.isRecording = false
      self.durationSeconds = 0
      self.markerOverlays = []
      self.lastTriggerMarkerId = nil
      self.lastTriggerTimestamp = nil
      if clearPreview {
        self.previewImage = nil
      }
    }
  }

  private func collectLinkedFloorplanBundle(in bundleURL: URL) -> [String: Any] {
    guard let projectKey = floorplanProjectKey else {
      return [
        "linked": false,
        "reason": "no_project_key"
      ]
    }
    var payload: [String: Any] = [
      "project_key": projectKey,
      "linked": false
    ]

    do {
      let sourcePaths = try FloorplanProjectStore.projectPaths(projectKey: projectKey)
      let fileManager = FileManager.default
      guard fileManager.fileExists(atPath: sourcePaths.projectJSON.path) else {
        payload["reason"] = "project_json_missing"
        return payload
      }

      let projectData = try Data(contentsOf: sourcePaths.projectJSON)
      let project = try JSONDecoder().decode(FloorplanProject.self, from: projectData)

      let floorplanRootRelative = "floorplan"
      let floorplanRootURL = bundleURL.appendingPathComponent(floorplanRootRelative, isDirectory: true)
      try fileManager.createDirectory(at: floorplanRootURL, withIntermediateDirectories: true)

      var copiedFilesCount = 0

      @discardableResult
      func copyIfExists(sourceURL: URL, relativeDestination: String) -> String? {
        guard fileManager.fileExists(atPath: sourceURL.path),
              let safeRelativePath = Self.sanitizedRelativePath(relativeDestination) else {
          return nil
        }

        let destinationURL = bundleURL.appendingPathComponent(safeRelativePath)
        let parentDirectory = destinationURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDirectory.path) {
          try? fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
        }
        if fileManager.fileExists(atPath: destinationURL.path) {
          try? fileManager.removeItem(at: destinationURL)
        }

        do {
          try fileManager.copyItem(at: sourceURL, to: destinationURL)
          copiedFilesCount += 1
          return safeRelativePath
        } catch {
          return nil
        }
      }

      let projectJSONRelative = "\(floorplanRootRelative)/project.json"
      let projectJSONPath = copyIfExists(sourceURL: sourcePaths.projectJSON, relativeDestination: projectJSONRelative)
      let combinedPNGPath = copyIfExists(sourceURL: sourcePaths.combinedPNG, relativeDestination: "\(floorplanRootRelative)/floorplan.png")
      let combinedPDFPath = copyIfExists(sourceURL: sourcePaths.combinedPDF, relativeDestination: "\(floorplanRootRelative)/floorplan.pdf")

      let roomScansPayload: [[String: Any]] = project.roomScans.map { roomScan in
        var item: [String: Any] = [
          "scan_id": roomScan.id.uuidString,
          "room_id": roomScan.roomId,
          "floor_id": roomScan.floorId
        ]

        if let segmentsSource = try? FloorplanProjectStore.resolve(projectKey: projectKey, relativePath: roomScan.segmentsJSONPath),
           let copied = copyIfExists(sourceURL: segmentsSource, relativeDestination: "\(floorplanRootRelative)/\(roomScan.segmentsJSONPath)") {
          item["segments_json"] = copied
        }

        if let floorplanPNGSource = try? FloorplanProjectStore.resolve(projectKey: projectKey, relativePath: roomScan.floorplanPNGPath),
           let copied = copyIfExists(sourceURL: floorplanPNGSource, relativeDestination: "\(floorplanRootRelative)/\(roomScan.floorplanPNGPath)") {
          item["floorplan_png"] = copied
        }

        if let usdzSource = try? FloorplanProjectStore.resolve(projectKey: projectKey, relativePath: roomScan.usdzPath),
           let copied = copyIfExists(sourceURL: usdzSource, relativeDestination: "\(floorplanRootRelative)/\(roomScan.usdzPath)") {
          item["usdz"] = copied
        }

        return item
      }

      payload["linked"] = true
      payload["floorplan_root"] = floorplanRootRelative
      payload["project_json"] = projectJSONPath ?? NSNull()
      payload["combined_png"] = combinedPNGPath ?? NSNull()
      payload["combined_pdf"] = combinedPDFPath ?? NSNull()
      payload["room_scan_count"] = project.roomScans.count
      payload["connections_count"] = project.connections.count
      payload["route_point_count"] = project.routePoints.count
      payload["copied_files_count"] = copiedFilesCount
      payload["room_scans"] = roomScansPayload
      return payload
    } catch {
      payload["reason"] = "link_error"
      payload["error"] = error.localizedDescription
      return payload
    }
  }

  private struct RecordingPaths {
    let takeId: UUID
    let bundleURL: URL
    let videoURL: URL
    let metadataURL: URL
  }

  private static func createRecordingPaths() throws -> RecordingPaths {
    let root = try FileStore.ensureUserFilesDirectory()
      .appendingPathComponent("PanoramaTours", isDirectory: true)

    if !FileManager.default.fileExists(atPath: root.path) {
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    let takeId = UUID()
    let bundleURL = root.appendingPathComponent(takeId.uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)

    let videoURL = bundleURL.appendingPathComponent("\(takeId.uuidString).mp4")
    let metadataURL = bundleURL.appendingPathComponent("metadata.json")

    return RecordingPaths(
      takeId: takeId,
      bundleURL: bundleURL,
      videoURL: videoURL,
      metadataURL: metadataURL
    )
  }

#if canImport(ARKit)
  private static func selectPreferredVideoFormat() -> ARConfiguration.VideoFormat? {
    let formats = ARWorldTrackingConfiguration.supportedVideoFormats

    if let exact4K30 = formats.first(where: { format in
      format.framesPerSecond == 30 &&
      format.imageResolution.width == 3840
    }) {
      return exact4K30
    }

    let fps30 = formats.filter { $0.framesPerSecond == 30 }
    if let best30 = fps30.max(by: { lhs, rhs in
      let lArea = Int(lhs.imageResolution.width) * Int(lhs.imageResolution.height)
      let rArea = Int(rhs.imageResolution.width) * Int(rhs.imageResolution.height)
      return lArea < rArea
    }) {
      return best30
    }

    return formats.max(by: { lhs, rhs in
      let lArea = Int(lhs.imageResolution.width) * Int(lhs.imageResolution.height)
      let rArea = Int(rhs.imageResolution.width) * Int(rhs.imageResolution.height)
      return lArea < rArea
    })
  }
#endif

  private static func selectedResolution() -> (width: Int32, height: Int32) {
#if canImport(ARKit)
    if let format = selectPreferredVideoFormat() {
      let size = format.imageResolution
      return (Int32(size.width.rounded()), Int32(size.height.rounded()))
    }
#endif
    return (1920, 1080)
  }

  private static func normalizedProjectKey(_ raw: String?) -> String? {
    let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func sanitizedRelativePath(_ rawPath: String) -> String? {
    let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let replacedSlashes = trimmed.replacingOccurrences(of: "\\", with: "/")
    let withoutLeading = replacedSlashes.drop(while: { $0 == "/" })
    let normalized = String(withoutLeading)
    guard !normalized.isEmpty, !normalized.contains("..") else {
      return nil
    }
    return normalized
  }

  private static func matrix3x3ToArray(_ matrix: simd_float3x3) -> [[Float]] {
    [
      [matrix.columns.0.x, matrix.columns.1.x, matrix.columns.2.x],
      [matrix.columns.0.y, matrix.columns.1.y, matrix.columns.2.y],
      [matrix.columns.0.z, matrix.columns.1.z, matrix.columns.2.z]
    ]
  }

  private static func matrix4x4ToArray(_ matrix: simd_float4x4) -> [[Float]] {
    [
      [matrix.columns.0.x, matrix.columns.1.x, matrix.columns.2.x, matrix.columns.3.x],
      [matrix.columns.0.y, matrix.columns.1.y, matrix.columns.2.y, matrix.columns.3.y],
      [matrix.columns.0.z, matrix.columns.1.z, matrix.columns.2.z, matrix.columns.3.z],
      [matrix.columns.0.w, matrix.columns.1.w, matrix.columns.2.w, matrix.columns.3.w]
    ]
  }

#if canImport(ARKit)
  private static func trackingStateString(_ state: ARCamera.TrackingState) -> String {
    switch state {
    case .normal:
      return "normal"
    case .notAvailable:
      return "not_available"
    case .limited(let reason):
      switch reason {
      case .initializing:
        return "limited_initializing"
      case .excessiveMotion:
        return "limited_excessive_motion"
      case .insufficientFeatures:
        return "limited_insufficient_features"
      case .relocalizing:
        return "limited_relocalizing"
      @unknown default:
        return "limited_unknown"
      }
    }
  }
#endif

  private struct FrameRecord {
    let frameIndex: Int
    let timestamp: Double
    let intrinsics: [[Float]]
    let transform: [[Float]]
    let trackingState: String
  }

  private struct MarkerRecord {
    let markerId: String
    let timestamp: Double
    let transform: [[Float]]
    let imageBoundingBox: [Double]
  }

  private struct TriggerEventRecord {
    let timestamp: Double
    let markerId: String?
    let eventType: String
  }

#if canImport(ARKit)
  private final class ARSessionDelegateProxy: NSObject, ARSessionDelegate {
    weak var recorder: PanoramaTourRecorder?

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
      recorder?.handleARFrame(frame)
    }
  }
#endif
}
