import Foundation

nonisolated struct Room: Identifiable, Hashable {
  let id: String
  let nameDE: String
  let nameEN: String
  let category: RoomCategory

  var displayName: String {
    let lang = Locale.current.language.languageCode?.identifier ?? "en"
    return lang == "de" ? nameDE : nameEN
  }

  func displayName(language: AppLanguage) -> String {
    switch language {
    case .de:
      return nameDE
    case .en:
      return nameEN
    case .system:
      return displayName
    }
  }
}

nonisolated enum RoomCategory: String, CaseIterable {
  case interior
  case exterior
  case other
}

nonisolated struct FloorOption: Identifiable, Hashable {
  let id: String
  let nameDE: String
  let nameEN: String
  let shortDE: String
  let shortEN: String
  let fileToken: String

  var displayName: String {
    let lang = Locale.current.language.languageCode?.identifier ?? "en"
    return lang == "de" ? nameDE : nameEN
  }

  var shortDisplayName: String {
    let lang = Locale.current.language.languageCode?.identifier ?? "en"
    return lang == "de" ? shortDE : shortEN
  }

  func displayName(language: AppLanguage) -> String {
    switch language {
    case .de:
      return nameDE
    case .en:
      return nameEN
    case .system:
      return displayName
    }
  }

  func shortDisplayName(language: AppLanguage) -> String {
    switch language {
    case .de:
      return shortDE
    case .en:
      return shortEN
    case .system:
      return shortDisplayName
    }
  }
}

nonisolated enum RoomTaxonomy {
  static let defaultRoomId = "unknown"

  static let rooms: [Room] = [
    Room(id: "living_room", nameDE: "Wohnzimmer", nameEN: "Living Room", category: .interior),
    Room(id: "living_kitchen", nameDE: "Wohnküche", nameEN: "Open-plan Living Kitchen", category: .interior),
    Room(id: "studio", nameDE: "Studio (Wohn-/Schlafraum)", nameEN: "Studio (Living/Sleeping)", category: .interior),
    Room(id: "kitchen", nameDE: "Küche", nameEN: "Kitchen", category: .interior),
    Room(id: "dining_room", nameDE: "Esszimmer", nameEN: "Dining Room", category: .interior),
    Room(id: "bedroom", nameDE: "Schlafzimmer", nameEN: "Bedroom", category: .interior),
    Room(id: "children_room", nameDE: "Kinderzimmer", nameEN: "Children's Room", category: .interior),
    Room(id: "guest_room", nameDE: "Gästezimmer", nameEN: "Guest Room", category: .interior),
    Room(id: "bathroom", nameDE: "Badezimmer", nameEN: "Bathroom", category: .interior),
    Room(id: "guest_wc", nameDE: "WC", nameEN: "WC", category: .interior),
    Room(id: "office", nameDE: "Büro / Arbeitszimmer", nameEN: "Office", category: .interior),
    Room(id: "fitness_room", nameDE: "Fitnessraum", nameEN: "Fitness Room", category: .interior),
    Room(id: "hallway", nameDE: "Flur / Diele", nameEN: "Hallway", category: .interior),
    Room(id: "corridor", nameDE: "Gang / Korridor", nameEN: "Corridor", category: .interior),
    Room(id: "stairs", nameDE: "Treppe / Treppenhaus", nameEN: "Stairs / Stairwell", category: .interior),
    Room(id: "storage", nameDE: "Abstellraum", nameEN: "Storage Room", category: .interior),
    Room(id: "pantry", nameDE: "Speisekammer", nameEN: "Pantry", category: .interior),
    Room(id: "utility_room", nameDE: "Hauswirtschaft / Technik (HWR)", nameEN: "Utility Room", category: .interior),
    Room(id: "laundry_room", nameDE: "Waschküche", nameEN: "Laundry Room", category: .interior),
    Room(id: "built_in_closet", nameDE: "Einbauschrank", nameEN: "Built-in Closet", category: .interior),
    Room(id: "closet", nameDE: "Garderobe / Schrankraum", nameEN: "Closet", category: .interior),
    Room(id: "walk_in_closet", nameDE: "Ankleidezimmer", nameEN: "Walk-in Closet", category: .interior),
    Room(id: "basement", nameDE: "Keller", nameEN: "Basement", category: .interior),
    Room(id: "attic", nameDE: "Dachboden", nameEN: "Attic", category: .interior),
    Room(id: "conservatory", nameDE: "Wintergarten", nameEN: "Conservatory / Sunroom", category: .interior),

    Room(id: "balcony", nameDE: "Balkon", nameEN: "Balcony", category: .exterior),
    Room(id: "terrace", nameDE: "Terrasse", nameEN: "Terrace", category: .exterior),
    Room(id: "roof_terrace", nameDE: "Dachterrasse", nameEN: "Roof Terrace", category: .exterior),
    Room(id: "courtyard", nameDE: "Innenhof", nameEN: "Courtyard", category: .exterior),
    Room(id: "garden", nameDE: "Garten", nameEN: "Garden", category: .exterior),
    Room(id: "driveway", nameDE: "Einfahrt / Zufahrt", nameEN: "Driveway", category: .exterior),
    Room(id: "garage", nameDE: "Garage", nameEN: "Garage", category: .exterior),
    Room(id: "carport", nameDE: "Carport", nameEN: "Carport", category: .exterior),
    Room(id: "outbuilding", nameDE: "Nebengebäude / Schuppen", nameEN: "Outbuilding / Shed", category: .exterior),
    Room(id: "exterior", nameDE: "Außenbereich (allgemein)", nameEN: "Exterior (general)", category: .exterior),
    Room(id: "street", nameDE: "Straße", nameEN: "Street", category: .exterior),

    Room(id: "unknown", nameDE: "Sonstiges / Unbestimmt", nameEN: "Other / Unknown", category: .other)
  ]

  static func room(id: String) -> Room {
    rooms.first(where: { $0.id == id }) ?? rooms.first(where: { $0.id == defaultRoomId })!
  }

  static func normalizedRoomId(_ id: String) -> String {
    rooms.contains(where: { $0.id == id }) ? id : defaultRoomId
  }
}

nonisolated enum FloorTaxonomy {
  static let defaultFloorId = "undefined"

  static let floors: [FloorOption] = [
    FloorOption(
      id: "kg",
      nameDE: "Kellergeschoss",
      nameEN: "Basement Level",
      shortDE: "KG",
      shortEN: "B1",
      fileToken: "kg"
    ),
    FloorOption(
      id: "eg",
      nameDE: "Erdgeschoss",
      nameEN: "Ground Floor",
      shortDE: "EG",
      shortEN: "GF",
      fileToken: "eg"
    ),
    FloorOption(
      id: "1og",
      nameDE: "1. Obergeschoss",
      nameEN: "1st Floor",
      shortDE: "1. OG",
      shortEN: "1F",
      fileToken: "1og"
    ),
    FloorOption(
      id: "2og",
      nameDE: "2. Obergeschoss",
      nameEN: "2nd Floor",
      shortDE: "2. OG",
      shortEN: "2F",
      fileToken: "2og"
    ),
    FloorOption(
      id: "3og",
      nameDE: "3. Obergeschoss",
      nameEN: "3rd Floor",
      shortDE: "3. OG",
      shortEN: "3F",
      fileToken: "3og"
    ),
    FloorOption(
      id: "4og",
      nameDE: "4. Obergeschoss",
      nameEN: "4th Floor",
      shortDE: "4. OG",
      shortEN: "4F",
      fileToken: "4og"
    ),
    FloorOption(
      id: defaultFloorId,
      nameDE: "Undefiniert (Hochhaus/variabel)",
      nameEN: "Undefined (high-rise/variable)",
      shortDE: "undef.",
      shortEN: "undef.",
      fileToken: "--"
    )
  ]

  static func floor(id: String) -> FloorOption {
    floors.first(where: { $0.id == id }) ?? floors.first(where: { $0.id == defaultFloorId })!
  }

  static func normalizedFloorId(_ id: String) -> String {
    floors.contains(where: { $0.id == id }) ? id : defaultFloorId
  }
}
