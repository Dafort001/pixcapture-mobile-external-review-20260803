import Testing
@testable import PIXCAPTURE

struct RoomTaxonomyTests {

  @Test("Room taxonomy exposes the full 37-room upload taxonomy")
  func roomIdsMatchCanonicalUploadSet() {
    #expect(RoomTaxonomy.rooms.map(\.id) == [
      "living_room",
      "living_kitchen",
      "studio",
      "kitchen",
      "dining_room",
      "bedroom",
      "children_room",
      "guest_room",
      "bathroom",
      "guest_wc",
      "office",
      "fitness_room",
      "hallway",
      "corridor",
      "stairs",
      "storage",
      "pantry",
      "utility_room",
      "laundry_room",
      "built_in_closet",
      "closet",
      "walk_in_closet",
      "basement",
      "attic",
      "conservatory",
      "balcony",
      "terrace",
      "roof_terrace",
      "courtyard",
      "garden",
      "driveway",
      "garage",
      "carport",
      "outbuilding",
      "exterior",
      "street",
      "unknown",
    ])
  }
}
