import AVFoundation
import SwiftUI
import UIKit

final class PreviewView: UIView {
  var onLayoutOrWindowChange: ((PreviewView) -> Void)?

  override class var layerClass: AnyClass {
    AVCaptureVideoPreviewLayer.self
  }

  var videoPreviewLayer: AVCaptureVideoPreviewLayer {
    layer as! AVCaptureVideoPreviewLayer
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    onLayoutOrWindowChange?(self)
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    onLayoutOrWindowChange?(self)
  }
}

struct CameraPreviewView: UIViewRepresentable {
  let session: AVCaptureSession

  final class Coordinator {
    private weak var previewLayer: AVCaptureVideoPreviewLayer?
    private weak var previewView: PreviewView?

    func configure(previewView: PreviewView) {
      self.previewView = previewView
      self.previewLayer = previewView.videoPreviewLayer
      previewView.onLayoutOrWindowChange = { [weak self] view in
        self?.applyInterfaceRotationAngle(for: view)
      }
      applyInterfaceRotationAngle(for: previewView)
    }

    func tearDown() {
      previewView?.onLayoutOrWindowChange = nil
      previewView = nil
      previewLayer = nil
    }

    private func applyPreviewRotationAngle(_ angle: CGFloat) {
      guard let connection = previewLayer?.connection else { return }
      let normalized = normalizedRotationAngle(angle)
      guard connection.isVideoRotationAngleSupported(normalized) else { return }
      if connection.videoRotationAngle != normalized {
        connection.videoRotationAngle = normalized
      }
    }

    private func applyInterfaceRotationAngle(for view: PreviewView?) {
      let angle = rotationAngle(for: currentInterfaceOrientation(for: view))
      applyPreviewRotationAngle(angle)
    }

    private func normalizedRotationAngle(_ angle: CGFloat) -> CGFloat {
      var normalized = angle.truncatingRemainder(dividingBy: 360)
      if normalized < 0 {
        normalized += 360
      }
      return normalized
    }

    private func currentInterfaceOrientation(for view: PreviewView?) -> UIInterfaceOrientation {
      if let sceneOrientation = view?.window?.windowScene?.effectiveGeometry.interfaceOrientation,
         sceneOrientation != .unknown {
        return sceneOrientation
      }

      if let activeSceneOrientation = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first(where: { $0.activationState == .foregroundActive })?
        .effectiveGeometry.interfaceOrientation,
         activeSceneOrientation != .unknown {
        return activeSceneOrientation
      }

      switch UIDevice.current.orientation {
      case .portrait:
        return .portrait
      case .portraitUpsideDown:
        return .portraitUpsideDown
      case .landscapeLeft:
        // UIDevice orientation is mirrored to UI orientation.
        return .landscapeRight
      case .landscapeRight:
        return .landscapeLeft
      default:
        return .portrait
      }
    }

    private func rotationAngle(for orientation: UIInterfaceOrientation) -> CGFloat {
      switch orientation {
      case .portrait:
        return 90
      case .landscapeRight:
        return 0
      case .portraitUpsideDown:
        return 270
      case .landscapeLeft:
        return 180
      default:
        return 90
      }
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeUIView(context: Context) -> PreviewView {
    let view = PreviewView()
    view.videoPreviewLayer.session = session
    view.videoPreviewLayer.videoGravity = .resizeAspect
    context.coordinator.configure(previewView: view)
    return view
  }

  func updateUIView(_ uiView: PreviewView, context: Context) {
    uiView.videoPreviewLayer.session = session
    context.coordinator.configure(previewView: uiView)
  }

  static func dismantleUIView(_ uiView: PreviewView, coordinator: Coordinator) {
    uiView.videoPreviewLayer.session = nil
    coordinator.tearDown()
  }
}
