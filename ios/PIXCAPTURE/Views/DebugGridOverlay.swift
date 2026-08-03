import SwiftUI

struct DebugGridOverlay: View {
  let columns: Int
  let rows: Int

  var body: some View {
    GeometryReader { proxy in
      let w = proxy.size.width
      let h = proxy.size.height
      let dx = w / CGFloat(columns)
      let dy = h / CGFloat(rows)

      ZStack {
        Path { path in
          for c in 0...columns {
            let x = CGFloat(c) * dx
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: h))
          }
          for r in 0...rows {
            let y = CGFloat(r) * dy
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: w, y: y))
          }
        }
        .stroke(Color.white.opacity(0.2), lineWidth: 1)

        ForEach(0..<columns, id: \.self) { c in
          ForEach(0..<rows, id: \.self) { r in
            let label = "\(c),\(r)"
            Text(label)
              .font(.system(size: 10, weight: .medium))
              .foregroundStyle(Color.white.opacity(0.6))
              .position(x: CGFloat(c) * dx + dx / 2, y: CGFloat(r) * dy + dy / 2)
          }
        }
      }
    }
    .allowsHitTesting(false)
  }
}
