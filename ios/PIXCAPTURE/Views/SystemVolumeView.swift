import SwiftUI
import MediaPlayer
import Combine

final class SystemVolumeController: ObservableObject {
  let objectWillChange = ObservableObjectPublisher()

  fileprivate var slider: UISlider? {
    didSet {
      if let value = pendingVolume {
        pendingVolume = nil
        setVolume(value)
      }
    }
  }

  private var pendingVolume: Float?

  func setVolume(_ value: Float) {
    let clamped = min(max(value, 0.0), 1.0)
    guard let slider else {
      pendingVolume = clamped
      return
    }
    slider.setValue(clamped, animated: false)
    slider.sendActions(for: .touchUpInside)
  }
}

struct SystemVolumeView: UIViewRepresentable {
  @ObservedObject var controller: SystemVolumeController

  func makeUIView(context: Context) -> MPVolumeView {
    let view = MPVolumeView(frame: .zero)
    view.showsVolumeSlider = true
    view.isUserInteractionEnabled = false
    return view
  }

  func updateUIView(_ uiView: MPVolumeView, context: Context) {
    // MPVolumeView contains an internal UISlider which allows us to set system volume.
    if let slider = uiView.subviews.compactMap({ $0 as? UISlider }).first {
      controller.slider = slider
    }
  }
}
