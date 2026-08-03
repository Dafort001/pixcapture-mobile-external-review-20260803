import SwiftUI

struct ExposureSliderView: View {
  @Binding var value: Double
  var range: ClosedRange<Double> = -2...2
  var step: Double = 0.1
  var orientation: SliderOrientation

  enum SliderOrientation {
    case vertical
    case horizontal
  }

  var body: some View {
    Group {
      if orientation == .vertical {
        VStack(spacing: 8) {
          Text(evLabel(value))
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.45))
            .clipShape(Capsule())

          Slider(value: $value, in: range, step: step)
            .rotationEffect(.degrees(-90))
            .frame(height: 200)
            .scaleEffect(x: 1.0, y: 0.5, anchor: .center)
        }
      } else {
        VStack(spacing: 8) {
          Text(evLabel(value))
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.45))
            .clipShape(Capsule())

          Slider(value: $value, in: range, step: step)
            .frame(width: 200)
            .scaleEffect(x: 0.5, y: 1.0, anchor: .center)
        }
      }
    }
  }

  private func evLabel(_ ev: Double) -> String {
    let rounded = (ev * 10).rounded() / 10
    return String(format: "%+.1f EV", rounded)
  }
}
