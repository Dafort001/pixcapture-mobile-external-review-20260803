import Foundation
@preconcurrency import WebRTC

@MainActor
final class BrowserCompanionWebRTCBridge: NSObject {
  private let factory: RTCPeerConnectionFactory
  private var peerConnection: RTCPeerConnection?
  private var dataChannel: RTCDataChannel?
  private var candidatePollingTask: Task<Void, Never>?
  private var pendingBrowserCandidateCount = 0
  private var browserFailureMessage: String?
  private var browserReceipt: BrowserCompanionReceipt?
  private var configuredIceServers: [RTCIceServer] = BrowserCompanionWebRTCBridge.defaultIceServers
  private var hasRelayConfiguration = false
  private var endpoint: URL?
  private var webSessionId: String?

  private static var defaultIceServers: [RTCIceServer] {
    [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
  }

  override init() {
    BrowserCompanionWebRTCRuntime.ensureInitialized()
    factory = RTCPeerConnectionFactory(
      encoderFactory: RTCDefaultVideoEncoderFactory(),
      decoderFactory: RTCDefaultVideoDecoderFactory()
    )
    super.init()
  }

  deinit {
    candidatePollingTask?.cancel()
  }

  func transferPackage(
    endpoint: URL,
    webSessionId: String,
    packageURL: URL,
    filename: String,
    packageId: String,
    keyId: String,
    sha256: String,
    manifest: Any,
    motifCount: Int,
    technicalFileCount: Int,
    sourceTotalBytes: Int,
    sizeBytes: Int,
    progress: @escaping (Int) -> Void
  ) async throws -> BrowserCompanionReceipt {
    UploadDebugLog.write("[PIXUPLOAD] native webrtc connect endpoint=\(endpoint.absoluteString) session=\(webSessionId)")
    self.endpoint = endpoint
    self.webSessionId = webSessionId
    pendingBrowserCandidateCount = 0
    browserFailureMessage = nil
    browserReceipt = nil
    configuredIceServers = Self.defaultIceServers
    hasRelayConfiguration = false
    candidatePollingTask?.cancel()
    candidatePollingTask = nil
    defer {
      closeConnection()
    }

    try await connect(endpoint: endpoint, webSessionId: webSessionId)
    UploadDebugLog.write("[PIXUPLOAD] native webrtc data channel ready")

    try await sendJSON([
      "type": "package_start",
      "filename": filename,
      "packageId": packageId,
      "keyId": keyId,
      "sha256": sha256,
      "sizeBytes": sizeBytes,
      "motifCount": motifCount,
      "technicalFileCount": technicalFileCount,
      "sourceTotalBytes": sourceTotalBytes,
      "manifest": manifest
    ])
    try await postSignal(endpoint: endpoint, webSessionId: webSessionId, type: "transfer", payload: [
      "filename": filename,
      "packageId": packageId,
      "bytesExpected": sizeBytes,
      "bytesReceived": 0,
      "status": "sending"
    ])
    UploadDebugLog.write("[PIXUPLOAD] native webrtc sent package_start filename=\(filename) bytes=\(sizeBytes)")

    let handle = try FileHandle(forReadingFrom: packageURL)
    defer {
      try? handle.close()
    }

    let transferClock = ContinuousClock()
    let transferDeadline = transferClock.now + .seconds(15 * 60)
    var sent = 0
    while true {
      try Task.checkCancellation()
      guard transferClock.now < transferDeadline else {
        throw PixcaptureUploadError.api(
          NSLocalizedString("upload.webrtc.error.totalTimeout", comment: "")
        )
      }
      let data = try autoreleasepool {
        try handle.read(upToCount: 256 * 1024) ?? Data()
      }
      if data.isEmpty { break }
      try await waitForBufferedAmountBelow(8 * 1024 * 1024)
      try sendBinary(data)
      sent += data.count
      progress(sent)
    }

    try await waitForBufferedAmountBelow(512 * 1024)
    guard sent == sizeBytes else {
      throw PixcaptureUploadError.api(
        String(
          format: NSLocalizedString("upload.webrtc.error.incomplete.format", comment: ""),
          sent,
          sizeBytes
        )
      )
    }
    try await sendJSON([
      "type": "package_done",
      "packageId": packageId,
      "sizeBytes": sent,
      "sha256": sha256
    ])
    try await postSignal(endpoint: endpoint, webSessionId: webSessionId, type: "transfer", payload: [
      "status": "sent"
    ])
    UploadDebugLog.write("[PIXUPLOAD] native webrtc sent package_done bytes=\(sent)")
    let receipt = try await waitForBrowserReceipt(
      packageId: packageId,
      sha256: sha256,
      sizeBytes: sizeBytes,
      timeoutSeconds: 180
    )
    UploadDebugLog.write("[PIXUPLOAD] native webrtc browser receipt verified bytes=\(receipt.sizeBytes)")
    return receipt
  }

  private func connect(endpoint: URL, webSessionId: String) async throws {
    let signal = try await pollForBrowserOffer(endpoint: endpoint, webSessionId: webSessionId)
    let configuration = RTCConfiguration()
    configuration.iceServers = configuredIceServers
    configuration.sdpSemantics = .unifiedPlan

    let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
    guard let peer = factory.peerConnection(with: configuration, constraints: constraints, delegate: self) else {
      throw PixcaptureUploadError.api(NSLocalizedString("upload.webrtc.error.peerCreation", comment: ""))
    }
    peerConnection = peer

    guard let offer = signal.browserOffer else {
      throw PixcaptureUploadError.api(NSLocalizedString("upload.webrtc.error.browserOfferMissing", comment: ""))
    }

    let remoteDescription = RTCSessionDescription(type: .offer, sdp: offer.sdp)
    try await setRemoteDescription(remoteDescription, on: peer)
    try await applyBrowserCandidates(signal.browserCandidates, on: peer)

    let answer = try await createAnswer(on: peer)
    try await setLocalDescription(answer, on: peer)
    try await postSignal(endpoint: endpoint, webSessionId: webSessionId, type: "answer", payload: [
      "type": "answer",
      "sdp": answer.sdp
    ])
    startCandidatePolling()
    try await postSignal(endpoint: endpoint, webSessionId: webSessionId, type: "state", payload: "answer_created")

    try await waitUntilReady(timeoutSeconds: 35)
  }

  private func waitUntilReady(timeoutSeconds: Int) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(timeoutSeconds)
    while clock.now < deadline {
      try Task.checkCancellation()
      if let browserFailureMessage {
        throw PixcaptureUploadError.api(browserFailureMessage)
      }
      if dataChannel?.readyState == .open {
        return
      }
      switch peerConnection?.iceConnectionState {
      case .failed:
        let key = hasRelayConfiguration
          ? "upload.webrtc.error.noNetworkPath"
          : "upload.webrtc.error.noNetworkPathWithoutRelay"
        throw PixcaptureUploadError.api(NSLocalizedString(key, comment: ""))
      case .closed:
        throw PixcaptureUploadError.api(NSLocalizedString("upload.webrtc.error.closedBeforeUpload", comment: ""))
      default:
        break
      }
      try await clock.sleep(for: .milliseconds(100))
    }
    throw PixcaptureUploadError.api(
      NSLocalizedString("upload.webrtc.error.connectionTimeout", comment: "")
    )
  }

  private func waitForBrowserReceipt(
    packageId: String,
    sha256: String,
    sizeBytes: Int,
    timeoutSeconds: Int
  ) async throws -> BrowserCompanionReceipt {
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(timeoutSeconds)
    while clock.now < deadline {
      try Task.checkCancellation()
      try throwIfTransferFailed()
      if let receipt = browserReceipt {
        guard receipt.packageId == packageId else {
          throw PixcaptureUploadError.api(NSLocalizedString("upload.webrtc.error.wrongPackageId", comment: ""))
        }
        guard receipt.sizeBytes == sizeBytes else {
          throw PixcaptureUploadError.api(
            String(
              format: NSLocalizedString("upload.webrtc.error.wrongSize.format", comment: ""),
              receipt.sizeBytes,
              sizeBytes
            )
          )
        }
        guard receipt.sha256.caseInsensitiveCompare(sha256) == .orderedSame else {
          throw PixcaptureUploadError.api(NSLocalizedString("upload.webrtc.error.wrongChecksum", comment: ""))
        }
        return receipt
      }
      guard dataChannel?.readyState == .open else {
        throw PixcaptureUploadError.api(NSLocalizedString("upload.webrtc.error.closedBeforeReceipt", comment: ""))
      }
      try await clock.sleep(for: .milliseconds(100))
    }
    throw PixcaptureUploadError.api(
      NSLocalizedString("upload.webrtc.error.receiptTimeout", comment: "")
    )
  }

  private func closeConnection() {
    candidatePollingTask?.cancel()
    candidatePollingTask = nil
    dataChannel?.close()
    dataChannel = nil
    peerConnection?.close()
    peerConnection = nil
    endpoint = nil
    webSessionId = nil
    pendingBrowserCandidateCount = 0
    browserFailureMessage = nil
    browserReceipt = nil
    configuredIceServers = Self.defaultIceServers
    hasRelayConfiguration = false
  }

  private func pollForBrowserOffer(endpoint: URL, webSessionId: String) async throws -> BrowserCompanionSignal {
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(35)
    while clock.now < deadline {
      let signal = try await fetchSignal(endpoint: endpoint, webSessionId: webSessionId)
      if let failureMessage = signal.browserFailureMessage {
        throw PixcaptureUploadError.api(failureMessage)
      }
      if signal.browserOffer != nil {
        return signal
      }
      try await clock.sleep(for: .milliseconds(500))
    }
      throw PixcaptureUploadError.api(NSLocalizedString("upload.webrtc.error.offerMissing", comment: ""))
  }

  private func applyBrowserCandidates(_ candidates: [BrowserCompanionIceCandidate], on peer: RTCPeerConnection) async throws {
    guard pendingBrowserCandidateCount < candidates.count else { return }
    let previousCandidateCount = pendingBrowserCandidateCount
    pendingBrowserCandidateCount = candidates.count
    for candidate in candidates.dropFirst(previousCandidateCount) {
      guard !candidate.candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        continue
      }
      let rtcCandidate = RTCIceCandidate(
        sdp: candidate.candidate,
        sdpMLineIndex: candidate.sdpMLineIndex,
        sdpMid: candidate.sdpMid
      )
      do {
        try await addIceCandidate(rtcCandidate, on: peer)
      } catch {
        UploadDebugLog.write("[PIXUPLOAD] native webrtc ignored browser candidate error=\(error.localizedDescription)")
      }
    }
  }

  private func startCandidatePolling() {
    guard candidatePollingTask == nil else { return }
    candidatePollingTask = Task { @MainActor [weak self] in
      guard let self else { return }
      defer { self.candidatePollingTask = nil }
      while let peer = self.peerConnection,
            let endpoint = self.endpoint,
            let webSessionId = self.webSessionId,
            !Task.isCancelled,
            peer.iceConnectionState != .closed {
        do {
          let signal = try await self.fetchSignal(endpoint: endpoint, webSessionId: webSessionId)
          if let failureMessage = signal.browserFailureMessage {
            self.browserFailureMessage = failureMessage
            UploadDebugLog.write("[PIXUPLOAD] native webrtc browser failure=\(failureMessage)")
            return
          }
          if let receipt = signal.verifiedReceipt {
            self.browserReceipt = receipt
          }
          try await self.applyBrowserCandidates(signal.browserCandidates, on: peer)
        } catch {
          UploadDebugLog.write("[PIXUPLOAD] native webrtc candidate poll error=\(error.localizedDescription)")
        }
        try? await ContinuousClock().sleep(for: .milliseconds(500))
      }
    }
  }

  private func createAnswer(on peer: RTCPeerConnection) async throws -> RTCSessionDescription {
    try await withCheckedThrowingContinuation { continuation in
      let constraints = RTCMediaConstraints(
        mandatoryConstraints: nil,
        optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]
      )
      peer.answer(for: constraints) { description, error in
        if let error {
          continuation.resume(throwing: error)
        } else if let description {
          continuation.resume(returning: description)
        } else {
          continuation.resume(
            throwing: PixcaptureUploadError.api(
              NSLocalizedString("upload.webrtc.error.answerMissing", comment: "")
            )
          )
        }
      }
    }
  }

  private func setRemoteDescription(_ description: RTCSessionDescription, on peer: RTCPeerConnection) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      peer.setRemoteDescription(description) { error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume()
        }
      }
    }
  }

  private func setLocalDescription(_ description: RTCSessionDescription, on peer: RTCPeerConnection) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      peer.setLocalDescription(description) { error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume()
        }
      }
    }
  }

  private func addIceCandidate(_ candidate: RTCIceCandidate, on peer: RTCPeerConnection) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      peer.add(candidate) { error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume()
        }
      }
    }
  }

  private func sendJSON(_ value: [String: Any]) async throws {
    let data = try JSONSerialization.data(withJSONObject: value)
    try sendTextData(data)
  }

  private func sendTextData(_ data: Data) throws {
    guard let channel = dataChannel, channel.readyState == .open else {
      throw PixcaptureUploadError.api(NSLocalizedString("upload.webrtc.error.channelNotOpen", comment: ""))
    }
    if !channel.sendData(RTCDataBuffer(data: data, isBinary: false)) {
      throw PixcaptureUploadError.api(NSLocalizedString("upload.webrtc.error.textFrame", comment: ""))
    }
  }

  private func sendBinary(_ data: Data) throws {
    guard let channel = dataChannel, channel.readyState == .open else {
      throw PixcaptureUploadError.api(NSLocalizedString("upload.webrtc.error.channelNotOpen", comment: ""))
    }
    if !channel.sendData(RTCDataBuffer(data: data, isBinary: true)) {
      throw PixcaptureUploadError.api(NSLocalizedString("upload.webrtc.error.dataFrame", comment: ""))
    }
  }

  private func waitForBufferedAmountBelow(_ threshold: UInt64) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(45)
    while true {
      try Task.checkCancellation()
      try throwIfTransferFailed()
      guard let channel = dataChannel, channel.readyState == .open else {
        throw PixcaptureUploadError.api(NSLocalizedString("upload.webrtc.error.closedDuringTransfer", comment: ""))
      }
      if channel.bufferedAmount <= threshold {
        return
      }
      if clock.now >= deadline {
        throw PixcaptureUploadError.api(
          NSLocalizedString("upload.webrtc.error.progressTimeout", comment: "")
        )
      }
      try await clock.sleep(for: .milliseconds(10))
    }
  }

  private func throwIfTransferFailed() throws {
    if let browserFailureMessage {
      throw PixcaptureUploadError.api(browserFailureMessage)
    }
    switch peerConnection?.iceConnectionState {
    case .failed, .closed:
      throw PixcaptureUploadError.api(NSLocalizedString("upload.webrtc.error.connectionEnded", comment: ""))
    default:
      break
    }
  }

  private func receiveDataChannelMessage(_ buffer: RTCDataBuffer) {
    guard !buffer.isBinary,
          let object = try? JSONSerialization.jsonObject(with: buffer.data) as? [String: Any],
          let type = object["type"] as? String else {
      return
    }
    if type == "package_ack" {
      guard let packageId = object["packageId"] as? String,
            let sha256 = object["sha256"] as? String,
            let sizeBytes = object["sizeBytes"] as? Int else {
        browserFailureMessage = NSLocalizedString("upload.webrtc.error.receiptIncomplete", comment: "")
        return
      }
      browserReceipt = BrowserCompanionReceipt(
        packageId: packageId,
        sha256: sha256,
        sizeBytes: sizeBytes
      )
    } else if type == "package_error" {
      let detail = (object["error"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
      browserFailureMessage = detail?.isEmpty == false
        ? detail
        : NSLocalizedString("upload.webrtc.error.browserAborted", comment: "")
    }
  }

  private func fetchSignal(endpoint: URL, webSessionId: String) async throws -> BrowserCompanionSignal {
    let url = endpoint
      .appendingPathComponent("api")
      .appendingPathComponent("v2")
      .appendingPathComponent("web-connect")
      .appendingPathComponent("sessions")
      .appendingPathComponent(webSessionId)
      .appendingPathComponent("companion-signal")
    let (data, response) = try await URLSession.shared.data(from: url)
    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
      throw PixcaptureUploadError.api(NSLocalizedString("upload.webrtc.error.signalRead", comment: ""))
    }
    let wrapper = try JSONDecoder().decode(BrowserCompanionSignalResponse.self, from: data)
    if let serverConfigurations = wrapper.iceServers, !serverConfigurations.isEmpty {
      let resolved = serverConfigurations.compactMap { configuration -> RTCIceServer? in
        guard !configuration.urls.isEmpty else { return nil }
        if let username = configuration.username,
           let credential = configuration.credential {
          return RTCIceServer(
            urlStrings: configuration.urls,
            username: username,
            credential: credential
          )
        }
        return RTCIceServer(urlStrings: configuration.urls)
      }
      if !resolved.isEmpty {
        configuredIceServers = resolved
        hasRelayConfiguration = resolved.contains { server in
          server.urlStrings.contains { $0.lowercased().hasPrefix("turn:") || $0.lowercased().hasPrefix("turns:") }
        }
      }
    }
    return wrapper.signal
  }

  private func postSignal(endpoint: URL, webSessionId: String, type: String, payload: Any) async throws {
    let url = endpoint
      .appendingPathComponent("api")
      .appendingPathComponent("v2")
      .appendingPathComponent("web-connect")
      .appendingPathComponent("sessions")
      .appendingPathComponent(webSessionId)
      .appendingPathComponent("companion-signal")
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: [
      "role": "mobile",
      "type": type,
      "payload": payload
    ])
    let (_, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
      throw PixcaptureUploadError.api(NSLocalizedString("upload.webrtc.error.signalSend", comment: ""))
    }
  }
}

extension BrowserCompanionWebRTCBridge: RTCPeerConnectionDelegate {
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
  nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
    Task { @MainActor in
      self.dataChannel = dataChannel
      dataChannel.delegate = self
      UploadDebugLog.write("[PIXUPLOAD] native webrtc didOpen dataChannel state=\(dataChannel.readyState.rawValue)")
    }
  }
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
    Task { @MainActor in
      UploadDebugLog.write("[PIXUPLOAD] native webrtc ice state=\(newState.rawValue)")
    }
  }
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
    Task { @MainActor in
      guard let endpoint = self.endpoint, let webSessionId = self.webSessionId else { return }
      do {
        try await self.postSignal(endpoint: endpoint, webSessionId: webSessionId, type: "candidate", payload: [
          "candidate": candidate.sdp,
          "sdpMid": candidate.sdpMid as Any,
          "sdpMLineIndex": candidate.sdpMLineIndex
        ])
      } catch {
        UploadDebugLog.write("[PIXUPLOAD] native webrtc candidate post error=\(error.localizedDescription)")
      }
    }
  }
}

extension BrowserCompanionWebRTCBridge: RTCDataChannelDelegate {
  nonisolated func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
    Task { @MainActor in
      UploadDebugLog.write("[PIXUPLOAD] native webrtc dataChannel state=\(dataChannel.readyState.rawValue)")
    }
  }

  nonisolated func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
    Task { @MainActor in
      self.receiveDataChannelMessage(buffer)
    }
  }
}

struct BrowserCompanionReceipt: Equatable {
  let packageId: String
  let sha256: String
  let sizeBytes: Int
}

@MainActor
private enum BrowserCompanionWebRTCRuntime {
  private static var isInitialized = false

  static func ensureInitialized() {
    guard !isInitialized else { return }
    RTCInitializeSSL()
    isInitialized = true
  }
}

private struct BrowserCompanionSignalResponse: Decodable {
  let signal: BrowserCompanionSignal
  let iceServers: [BrowserCompanionIceServer]?

  enum CodingKeys: String, CodingKey {
    case signal
    case iceServers = "ice_servers"
  }
}

private struct BrowserCompanionIceServer: Decodable {
  let urls: [String]
  let username: String?
  let credential: String?
}

private struct BrowserCompanionSignal: Decodable {
  let browserOffer: BrowserCompanionSessionDescription?
  let browserCandidates: [BrowserCompanionIceCandidate]
  let transfer: BrowserCompanionTransfer?

  var browserFailureMessage: String? {
    guard transfer?.status == "failed" else { return nil }
    let detail = transfer?.error?.trimmingCharacters(in: .whitespacesAndNewlines)
    return detail?.isEmpty == false
      ? detail
      : NSLocalizedString("upload.webrtc.error.browserEnded", comment: "")
  }

  var verifiedReceipt: BrowserCompanionReceipt? {
    guard transfer?.status == "received",
          let packageId = transfer?.packageId,
          let sha256 = transfer?.sha256,
          let sizeBytes = transfer?.bytesReceived else {
      return nil
    }
    return BrowserCompanionReceipt(packageId: packageId, sha256: sha256, sizeBytes: sizeBytes)
  }
}

private struct BrowserCompanionTransfer: Decodable {
  let status: String?
  let error: String?
  let packageId: String?
  let sha256: String?
  let bytesReceived: Int?
}

private struct BrowserCompanionSessionDescription: Decodable {
  let type: String
  let sdp: String
}

private struct BrowserCompanionIceCandidate: Decodable {
  let candidate: String
  let sdpMid: String?
  let sdpMLineIndex: Int32
}
