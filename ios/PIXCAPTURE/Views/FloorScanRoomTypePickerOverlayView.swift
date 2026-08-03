import SwiftUI

struct FloorScanRoomTypePickerOverlayView: View {
  @Binding var selectedRoomId: String
  @Binding var selectedFloorId: String
  let topInset: CGFloat
  let bottomReserved: CGFloat
  let onCancel: () -> Void
  let onDone: () -> Void

  var body: some View {
    GeometryReader { proxy in
      let topPadding = resolvedTopPadding(safeTop: proxy.safeAreaInsets.top)
      let bottomPadding = resolvedBottomPadding(safeBottom: proxy.safeAreaInsets.bottom)
      let panelHeight = resolvedPanelHeight(
        containerHeight: proxy.size.height,
        topPadding: topPadding,
        bottomPadding: bottomPadding
      )

      ZStack(alignment: .top) {
        Color.black.opacity(0.38)
          .ignoresSafeArea()

        RoomTypePickerView(
          selectedRoomId: $selectedRoomId,
          selectedFloorId: $selectedFloorId,
          title: "Raumart waehlen · \(FloorTaxonomy.floor(id: selectedFloorId).shortDisplayName)",
          onCancel: onCancel,
          onDone: onDone
        )
        .frame(maxWidth: 430)
        .frame(height: panelHeight)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(Color.white.opacity(0.20), lineWidth: 1)
        )
        .padding(.top, topPadding)
        .padding(.horizontal, 18)
        .shadow(color: Color.black.opacity(0.45), radius: 20, x: 0, y: 10)
      }
    }
  }

  private func resolvedTopPadding(safeTop: CGFloat) -> CGFloat {
    max(topInset, safeTop + 8)
  }

  private func resolvedBottomPadding(safeBottom: CGFloat) -> CGFloat {
    max(bottomReserved, safeBottom + 12)
  }

  private func resolvedPanelHeight(containerHeight: CGFloat, topPadding: CGFloat, bottomPadding: CGFloat) -> CGFloat {
    let available = containerHeight - topPadding - bottomPadding
    return max(220, min(640, available))
  }
}
