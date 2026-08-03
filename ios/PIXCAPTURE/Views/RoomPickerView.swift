import SwiftUI

struct RoomPickerView: View {
  @Binding var selectedRoomId: String
  @Binding var selectedFloorId: String
  @EnvironmentObject private var settings: AppSettings
  @Environment(\.dismiss) private var dismiss
  var onDone: (() -> Void)? = nil

  var body: some View {
    let interior = RoomTaxonomy.rooms.filter { $0.category == .interior }
    let exterior = RoomTaxonomy.rooms.filter { $0.category == .exterior }
    let other = RoomTaxonomy.rooms.filter { $0.category == .other }

    NavigationStack {
      List {
        Section(header: Text("rooms.floor")) {
          ForEach(FloorTaxonomy.floors, id: \.id) { floor in
            floorRow(floor)
          }
        }

        Section(header: Text("rooms.interior")) {
          ForEach(interior, id: \.id) { room in
            roomRow(room)
          }
        }

        Section(header: Text("rooms.exterior")) {
          ForEach(exterior, id: \.id) { room in
            roomRow(room)
          }
        }

        Section(header: Text("rooms.other")) {
          ForEach(other, id: \.id) { room in
            roomRow(room)
          }
        }
      }
      .scrollIndicators(.visible)
      .scrollContentBackground(.hidden)
      .background(Color(.systemBackground))
      .tint(AppTheme.primary)
      .navigationTitle(Text("rooms.title"))
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button {
            onDone?()
            dismiss()
          } label: {
            PixDonePill(title: settings.localized("common.done"))
          }
          .buttonStyle(.plain)
          .accessibilityLabel(settings.localized("common.done"))
        }
      }
    }
  }

  private func roomRow(_ room: Room) -> some View {
    let isSelected = RoomTaxonomy.normalizedRoomId(selectedRoomId) == room.id

    return Button {
      selectedRoomId = room.id
    } label: {
      HStack(spacing: 12) {
        Text(room.displayName(language: settings.appLanguage))
          .foregroundStyle(Color(.label))
        Spacer()
        selectionAccessory(isSelected: isSelected)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .listRowBackground(isSelected ? AppTheme.primary.opacity(0.08) : Color(.systemBackground))
    .accessibilityValue(Text(isSelected ? settings.localized("common.selected") : ""))
  }

  private func floorRow(_ floor: FloorOption) -> some View {
    let isSelected = FloorTaxonomy.normalizedFloorId(selectedFloorId) == floor.id

    return Button {
      selectedFloorId = floor.id
    } label: {
      HStack(spacing: 12) {
        Text(floor.displayName(language: settings.appLanguage))
          .foregroundStyle(Color(.label))
        Spacer()
        selectionAccessory(isSelected: isSelected)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .listRowBackground(isSelected ? AppTheme.primary.opacity(0.08) : Color(.systemBackground))
    .accessibilityValue(Text(isSelected ? settings.localized("common.selected") : ""))
  }

  private func selectionAccessory(isSelected: Bool) -> some View {
    ZStack {
      Circle()
        .fill(isSelected ? Color.white.opacity(0.14) : Color.clear)
      Circle()
        .stroke(isSelected ? Color.white : Color(.label).opacity(0.72), lineWidth: isSelected ? 2 : 1.5)
      if isSelected {
        Image(systemName: "checkmark")
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(Color.white)
      }
    }
      .frame(width: 24, height: 24)
      .accessibilityHidden(true)
  }
}
