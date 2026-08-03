import SwiftUI

struct DraggableOverlay<Content: View>: View {
  @Binding var normalizedPosition: CGPoint
  let overlaySize: CGSize
  let safeInsets: EdgeInsets
  let minimumPadding: CGFloat
  let content: Content

  init(
    normalizedPosition: Binding<CGPoint>,
    overlaySize: CGSize,
    safeInsets: EdgeInsets = EdgeInsets(),
    minimumPadding: CGFloat = 12,
    @ViewBuilder content: () -> Content
  ) {
    _normalizedPosition = normalizedPosition
    self.overlaySize = overlaySize
    self.safeInsets = safeInsets
    self.minimumPadding = minimumPadding
    self.content = content()
  }

  var body: some View {
    GeometryReader { proxy in
      let horizontalInset = (overlaySize.width / 2) + minimumPadding
      let verticalInset = (overlaySize.height / 2) + minimumPadding
      let minX = min(max(horizontalInset, safeInsets.leading + horizontalInset), proxy.size.width - horizontalInset)
      let maxX = max(minX, proxy.size.width - max(horizontalInset, safeInsets.trailing + horizontalInset))
      let minY = min(max(verticalInset, safeInsets.top + verticalInset), proxy.size.height - verticalInset)
      let maxY = max(minY, proxy.size.height - max(verticalInset, safeInsets.bottom + verticalInset))
      let clampedX = min(max(normalizedPosition.x * proxy.size.width, minX), maxX)
      let clampedY = min(max(normalizedPosition.y * proxy.size.height, minY), maxY)

      content
        .position(x: clampedX, y: clampedY)
        .gesture(
          DragGesture()
            .onChanged { value in
              let nextX = min(max(value.location.x, minX), maxX)
              let nextY = min(max(value.location.y, minY), maxY)
              normalizedPosition = CGPoint(
                x: nextX / max(proxy.size.width, 1),
                y: nextY / max(proxy.size.height, 1)
              )
            }
        )
    }
  }
}
