import SwiftUI

struct AspectGridOverlay: View {
  let baseAspectRatio: CGFloat
  let targetAspectRatio: CGFloat

  var body: some View {
    GeometryReader { proxy in
      let size = proxy.size
      let previewRect = centeredRect(in: size, aspectRatio: baseAspectRatio)
      let targetRectLocal = centeredRect(in: previewRect.size, aspectRatio: targetAspectRatio)
      let rect = targetRectLocal.offsetBy(dx: previewRect.minX, dy: previewRect.minY)

      Path { path in
        // Vertical thirds
        let x1 = rect.minX + rect.width / 3
        let x2 = rect.minX + rect.width * 2 / 3
        path.move(to: CGPoint(x: x1, y: rect.minY))
        path.addLine(to: CGPoint(x: x1, y: rect.maxY))
        path.move(to: CGPoint(x: x2, y: rect.minY))
        path.addLine(to: CGPoint(x: x2, y: rect.maxY))

        // Horizontal thirds
        let y1 = rect.minY + rect.height / 3
        let y2 = rect.minY + rect.height * 2 / 3
        path.move(to: CGPoint(x: rect.minX, y: y1))
        path.addLine(to: CGPoint(x: rect.maxX, y: y1))
        path.move(to: CGPoint(x: rect.minX, y: y2))
        path.addLine(to: CGPoint(x: rect.maxX, y: y2))
      }
      .stroke(Color.white.opacity(0.45), lineWidth: 1.5)
    }
    .allowsHitTesting(false)
  }

  private func centeredRect(in size: CGSize, aspectRatio: CGFloat) -> CGRect {
    let viewRatio = size.width / max(size.height, 1)
    var targetSize = size

    if viewRatio > aspectRatio {
      let width = size.height * aspectRatio
      targetSize = CGSize(width: width, height: size.height)
    } else {
      let height = size.width / aspectRatio
      targetSize = CGSize(width: size.width, height: height)
    }

    let origin = CGPoint(
      x: (size.width - targetSize.width) / 2,
      y: (size.height - targetSize.height) / 2
    )
    return CGRect(origin: origin, size: targetSize)
  }
}
