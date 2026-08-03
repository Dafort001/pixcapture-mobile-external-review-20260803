import SwiftUI

struct FocusReticleView: View {
  var color: Color = Color.white.opacity(0.9)

  var body: some View {
    let size: CGFloat = 44
    let line: CGFloat = 20

    ZStack {
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .stroke(color, lineWidth: 1.5)
        .frame(width: size, height: size)

      Rectangle()
        .fill(color)
        .frame(width: line, height: 1.5)

      Rectangle()
        .fill(color)
        .frame(width: 1.5, height: line)
    }
  }
}
