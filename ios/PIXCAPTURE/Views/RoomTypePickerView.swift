import SwiftUI

struct RoomTypePickerView: View {
  @Binding var selectedRoomId: String
  @Binding var selectedFloorId: String
  @EnvironmentObject private var settings: AppSettings
  let title: String
  let onCancel: () -> Void
  let onDone: () -> Void

  private var grouped: [(title: String, rooms: [Room])] {
    let interiors = RoomTaxonomy.rooms.filter { $0.category == .interior }
    let exteriors = RoomTaxonomy.rooms.filter { $0.category == .exterior }
    let other = RoomTaxonomy.rooms.filter { $0.category == .other }
    return [
      ("Innen", interiors),
      ("Außen", exteriors),
      ("Sonstiges", other)
    ]
  }

  var body: some View {
    NavigationView {
      List {
        Section("Etage") {
          ForEach(FloorTaxonomy.floors, id: \.id) { floor in
            Button {
              selectedFloorId = floor.id
            } label: {
              HStack {
                Text(floor.displayName(language: settings.appLanguage))
                  .foregroundStyle(Color(.label))
                Spacer()
                if selectedFloorId == floor.id {
                  Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.primary)
                }
              }
            }
            .buttonStyle(.plain)
          }
        }

        ForEach(grouped, id: \.title) { group in
          Section(group.title) {
            ForEach(group.rooms) { room in
              Button {
                selectedRoomId = room.id
              } label: {
                HStack {
                  Text(room.displayName(language: settings.appLanguage))
                    .foregroundStyle(Color(.label))
                  Spacer()
                  if selectedRoomId == room.id {
                    Image(systemName: "checkmark.circle.fill")
                      .foregroundStyle(AppTheme.primary)
                  }
                }
              }
              .buttonStyle(.plain)
            }
          }
        }
      }
      .scrollContentBackground(.hidden)
      .background(Color(.systemBackground))
      .tint(AppTheme.primary)
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Abbrechen", action: onCancel)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(action: onDone) {
            PixDonePill(title: settings.localized("common.done"))
          }
          .buttonStyle(.plain)
          .accessibilityLabel(settings.localized("common.done"))
        }
      }
    }
  }
}
