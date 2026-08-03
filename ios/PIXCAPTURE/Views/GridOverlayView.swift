import SwiftUI

struct GridOverlayView: View {
  var body: some View {
    GeometryReader { proxy in
      let w = proxy.size.width
      let h = proxy.size.height
      Path { path in
        path.move(to: CGPoint(x: w / 3, y: 0))
        path.addLine(to: CGPoint(x: w / 3, y: h))
        path.move(to: CGPoint(x: 2 * w / 3, y: 0))
        path.addLine(to: CGPoint(x: 2 * w / 3, y: h))
        path.move(to: CGPoint(x: 0, y: h / 3))
        path.addLine(to: CGPoint(x: w, y: h / 3))
        path.move(to: CGPoint(x: 0, y: 2 * h / 3))
        path.addLine(to: CGPoint(x: w, y: 2 * h / 3))
      }
      .stroke(Color.white.opacity(0.4), lineWidth: 1)
    }
  }
}
