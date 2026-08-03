import SwiftUI

struct HighlightWarningOverlayView: View {
  let mask: HighlightWarningMask

  var body: some View {
    GeometryReader { proxy in
      if mask.columns > 0, mask.rows > 0 {
        let cellWidth = proxy.size.width / CGFloat(mask.columns)
        let cellHeight = proxy.size.height / CGFloat(mask.rows)

        ForEach(Array(mask.cells.enumerated()), id: \.offset) { index, intensity in
          if intensity > 0.01 {
            let column = index % mask.columns
            let row = index / mask.columns

            RoundedRectangle(cornerRadius: 2)
              .fill(Color(red: 1.0, green: 0.9, blue: 0.42).opacity(0.08 + (0.18 * intensity)))
              .overlay(
                RoundedRectangle(cornerRadius: 2)
                  .stroke(Color.white.opacity(0.06 + (0.10 * intensity)), lineWidth: 0.5)
              )
              .frame(width: cellWidth, height: cellHeight)
              .position(
                x: (CGFloat(column) + 0.5) * cellWidth,
                y: (CGFloat(row) + 0.5) * cellHeight
              )
          }
        }
      }
    }
    .allowsHitTesting(false)
  }
}
