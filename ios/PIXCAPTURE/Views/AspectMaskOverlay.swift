import SwiftUI

struct AspectMaskOverlay: View {
  let baseAspectRatio: CGFloat
  let targetAspectRatio: CGFloat

  var body: some View {
    GeometryReader { proxy in
      let size = proxy.size
      let previewRect = centeredRect(in: size, aspectRatio: baseAspectRatio)
      let targetRectLocal = centeredRect(in: previewRect.size, aspectRatio: targetAspectRatio)
      let rect = targetRectLocal.offsetBy(dx: previewRect.minX, dy: previewRect.minY)
      let isSixteenNine = abs(targetAspectRatio - (16.0 / 9.0)) < 0.01

      ZStack {
        if isSixteenNine {
          Path { path in
            // Left
            path.addRect(CGRect(x: 0, y: 0, width: rect.minX, height: size.height))
            // Right
            path.addRect(CGRect(x: rect.maxX, y: 0, width: size.width - rect.maxX, height: size.height))
            // Bottom
            path.addRect(CGRect(x: rect.minX, y: rect.maxY, width: rect.width, height: size.height - rect.maxY))
          }
          .fill(Color.black.opacity(0.25))
        } else {
          Path { path in
            path.addRect(CGRect(origin: .zero, size: size))
            path.addRect(rect)
          }
          .fill(Color.black.opacity(0.25), style: FillStyle(eoFill: true))
        }

        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(Color.white.opacity(0.4), lineWidth: 1)
          .frame(width: rect.width, height: rect.height)
          .position(x: rect.midX, y: rect.midY)

        CornerMarks(rect: rect)
      }
      .allowsHitTesting(false)
    }
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

private struct CornerMarks: View {
  let rect: CGRect

  var body: some View {
    Path { path in
      let len: CGFloat = 18

      // Top-left
      path.move(to: CGPoint(x: rect.minX, y: rect.minY + len))
      path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.minX + len, y: rect.minY))

      // Top-right
      path.move(to: CGPoint(x: rect.maxX - len, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + len))

      // Bottom-left
      path.move(to: CGPoint(x: rect.minX, y: rect.maxY - len))
      path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.minX + len, y: rect.maxY))

      // Bottom-right
      path.move(to: CGPoint(x: rect.maxX - len, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - len))
    }
    .stroke(Color.white.opacity(0.9), lineWidth: 2)
  }
}
