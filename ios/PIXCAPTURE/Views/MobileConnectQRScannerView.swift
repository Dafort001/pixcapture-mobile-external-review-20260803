import SwiftUI
import AVFoundation

struct MobileConnectQRScannerView: UIViewControllerRepresentable {
  let onCode: (String) -> Void
  let onError: (String) -> Void

  func makeUIViewController(context: Context) -> MobileConnectQRScannerController {
    MobileConnectQRScannerController(onCode: onCode, onError: onError)
  }

  func updateUIViewController(_ uiViewController: MobileConnectQRScannerController, context: Context) {}
}

final class MobileConnectQRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
  private let onCode: (String) -> Void
  private let onError: (String) -> Void
  private let session = AVCaptureSession()
  private var previewLayer: AVCaptureVideoPreviewLayer?
  private var didEmitResult = false

  init(onCode: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
    self.onCode = onCode
    self.onError = onError
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    return nil
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    configureCaptureSession()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    previewLayer?.frame = view.bounds
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    if session.isRunning {
      session.stopRunning()
    }
  }

  private func configureCaptureSession() {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      setupSession()
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        DispatchQueue.main.async {
          guard let self else { return }
          if granted {
            self.setupSession()
          } else {
            self.emitError("Kamerazugriff wurde nicht erlaubt.")
          }
        }
      }
    case .denied, .restricted:
      emitError("Kein Kamerazugriff. Bitte in den iOS-Einstellungen aktivieren.")
    @unknown default:
      emitError("Kamera konnte nicht initialisiert werden.")
    }
  }

  private func setupSession() {
    guard let videoDevice = AVCaptureDevice.default(for: .video) else {
      emitError("Keine Kamera gefunden.")
      return
    }

    do {
      let input = try AVCaptureDeviceInput(device: videoDevice)
      guard session.canAddInput(input) else {
        emitError("Kamera-Input konnte nicht hinzugefuegt werden.")
        return
      }
      session.addInput(input)
    } catch {
      emitError("Kamera konnte nicht gestartet werden.")
      return
    }

    let output = AVCaptureMetadataOutput()
    guard session.canAddOutput(output) else {
      emitError("QR-Scanner konnte nicht initialisiert werden.")
      return
    }
    session.addOutput(output)
    output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
    output.metadataObjectTypes = [.qr]

    let preview = AVCaptureVideoPreviewLayer(session: session)
    preview.videoGravity = .resizeAspectFill
    preview.frame = view.bounds
    view.layer.insertSublayer(preview, at: 0)
    previewLayer = preview

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      self?.session.startRunning()
    }
  }

  func metadataOutput(
    _ output: AVCaptureMetadataOutput,
    didOutput metadataObjects: [AVMetadataObject],
    from connection: AVCaptureConnection
  ) {
    guard !didEmitResult else { return }
    guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
          object.type == .qr,
          let value = object.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
          !value.isEmpty else {
      return
    }

    didEmitResult = true
    session.stopRunning()
    onCode(value)
  }

  private func emitError(_ message: String) {
    guard !didEmitResult else { return }
    didEmitResult = true
    onError(message)
  }
}
