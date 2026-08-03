import Foundation
import WebRTC

@MainActor
final class BrowserCompanionWebRTCBridge: NSObject {
  private let factory: RTCPeerConnectionFactory
  private var peerConnection: RTCPeerConnection?
  private var dataChannel: RTCDataChannel?
  private var candidatePollingTask: Task<Void, Never>?
  private var readyContinuation: CheckedContinuation<Void, Error>?
  private var pendingBrowserCandidateCount = 0
  private var endpoint: URL?
  private var webSessionId: String?

  override init() {
    RTCInitializeSSL()
    factory = RTCPeerConnectionFactory(
      encoderFactory: RTCDefaultVideoEncoderFactory(),
      decoderFactory: RTCDefaultVideoDecoderFactory()
    )
    super.init()
  }

  deinit {
    candidatePollingTask?.cancel()
    RTCCleanupSSL()
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
  ) async throws {
    UploadDebugLog.write("[PIXUPLOAD] native webrtc connect endpoint=\(endpoint.absoluteString) session=\(webSessionId)")
    self.endpoint = endpoint
    self.webSessionId = webSessionId
    pendingBrowserCandidateCount = 0
    candidatePollingTask?.cancel()
    candidatePollingTask = nil

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

    var sent = 0
    while true {
      try Task.checkCancellation()
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
    try await sendJSON(["type": "package_done"])
    try await postSignal(endpoint: endpoint, webSessionId: webSessionId, type: "transfer", payload: [
      "status": "sent"
    ])
    UploadDebugLog.write("[PIXUPLOAD] native webrtc sent package_done bytes=\(sent)")
  }

  private func connect(endpoint: URL, webSessionId: String) async throws {
    let configuration = RTCConfiguration()
    configuration.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
    configuration.sdpSemantics = .unifiedPlan

    let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
    guard let peer = factory.peerConnection(with: configuration, constraints: constraints, delegate: self) else {
      throw PixcaptureUploadError.api("Native WebRTC-Verbindung konnte nicht erstellt werden.")
    }
    peerConnection = peer

    let signal = try await pollForBrowserOffer(endpoint: endpoint, webSessionId: webSessionId)
    guard let offer = signal.browserOffer else {
      throw PixcaptureUploadError.api("Browser-Companion lieferte kein Offer.")
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

  private func waitUntilReady(timeoutSeconds: TimeInterval) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask { @MainActor in
        if self.dataChannel?.readyState == .open {
          return
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
          self.readyContinuation = continuation
        }
      }
      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
        throw PixcaptureUploadError.api("Browser-Companion hat den nativen Datenkanal nicht rechtzeitig geoeffnet.")
      }
      try await group.next()
      group.cancelAll()
    }
  }

  private func pollForBrowserOffer(endpoint: URL, webSessionId: String) async throws -> BrowserCompanionSignal {
    let deadline = Date().addingTimeInterval(35)
    while Date() < deadline {
      let signal = try await fetchSignal(endpoint: endpoint, webSessionId: webSessionId)
      if signal.browserOffer != nil {
        return signal
      }
      try await Task.sleep(nanoseconds: 500_000_000)
    }
    throw PixcaptureUploadError.api("Browser-Companion Offer wurde nicht gefunden.")
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
      while let peer = self.peerConnection,
            let endpoint = self.endpoint,
            let webSessionId = self.webSessionId,
            !Task.isCancelled,
            peer.iceConnectionState != .closed {
        do {
          let signal = try await self.fetchSignal(endpoint: endpoint, webSessionId: webSessionId)
          try await self.applyBrowserCandidates(signal.browserCandidates, on: peer)
        } catch {
          UploadDebugLog.write("[PIXUPLOAD] native webrtc candidate poll error=\(error.localizedDescription)")
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
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
          continuation.resume(throwing: PixcaptureUploadError.api("Native WebRTC-Answer fehlte."))
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
      throw PixcaptureUploadError.api("Native WebRTC-Datenkanal ist nicht offen.")
    }
    if !channel.sendData(RTCDataBuffer(data: data, isBinary: false)) {
      throw PixcaptureUploadError.api("Native WebRTC-Textframe konnte nicht gesendet werden.")
    }
  }

  private func sendBinary(_ data: Data) throws {
    guard let channel = dataChannel, channel.readyState == .open else {
      throw PixcaptureUploadError.api("Native WebRTC-Datenkanal ist nicht offen.")
    }
    if !channel.sendData(RTCDataBuffer(data: data, isBinary: true)) {
      throw PixcaptureUploadError.api("Native WebRTC-Datenframe konnte nicht gesendet werden.")
    }
  }

  private func waitForBufferedAmountBelow(_ threshold: UInt64) async throws {
    while let channel = dataChannel, channel.bufferedAmount > threshold {
      try Task.checkCancellation()
      try await Task.sleep(nanoseconds: 10_000_000)
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
      throw PixcaptureUploadError.api("Companion-Signal konnte nicht gelesen werden.")
    }
    let wrapper = try JSONDecoder().decode(BrowserCompanionSignalResponse.self, from: data)
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
      throw PixcaptureUploadError.api("Companion-Signal konnte nicht gesendet werden.")
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
      if dataChannel.readyState == .open {
        self.readyContinuation?.resume()
        self.readyContinuation = nil
      }
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
      if dataChannel.readyState == .open {
        self.readyContinuation?.resume()
        self.readyContinuation = nil
      }
    }
  }

  nonisolated func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {}
}

private struct BrowserCompanionSignalResponse: Decodable {
  let signal: BrowserCompanionSignal
}

private struct BrowserCompanionSignal: Decodable {
  let browserOffer: BrowserCompanionSessionDescription?
  let browserCandidates: [BrowserCompanionIceCandidate]
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
