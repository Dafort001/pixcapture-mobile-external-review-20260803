import SwiftUI

struct HistogramOverlayView: View {
  let bins: [CGFloat]
  var showHighlightWarning: Bool = false

  var body: some View {
    GeometryReader { proxy in
      let width = proxy.size.width
      let height = proxy.size.height
      let step = width / CGFloat(max(bins.count, 1))

      Path { path in
        for (index, value) in bins.enumerated() {
          let x = CGFloat(index) * step
          let barHeight = max(1, value * height)
          path.addRect(CGRect(x: x, y: height - barHeight, width: step * 0.9, height: barHeight))
        }
      }
      .fill(LinearGradient(colors: [Color.white.opacity(0.9), Color.white.opacity(0.6)], startPoint: .bottom, endPoint: .top))
    }
    .background(Color.black.opacity(0.2))
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.4), lineWidth: 1))
    .overlay(alignment: .topTrailing) {
      if showHighlightWarning {
        Circle()
          .fill(Color.orange.opacity(0.95))
          .frame(width: 6, height: 6)
          .padding(6)
      }
    }
  }
}
