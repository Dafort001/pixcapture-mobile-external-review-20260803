import Foundation
import Security

enum KeychainStore {
  private static let service = Bundle.main.bundleIdentifier ?? "app.pixcapture.PIXCAPTURE"

  static func set(_ value: Data, for key: String) -> Bool {
    let lookup = itemLookup(for: key)
    let attributes: [String: Any] = [
      kSecValueData as String: value,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    ]
    let updateStatus = SecItemUpdate(lookup as CFDictionary, attributes as CFDictionary)
    if updateStatus == errSecSuccess {
      deleteLegacyItem(key)
      return true
    }
    guard updateStatus == errSecItemNotFound else { return false }

    var item = lookup
    attributes.forEach { item[$0.key] = $0.value }
    let addStatus = SecItemAdd(item as CFDictionary, nil)
    guard addStatus == errSecSuccess else { return false }
    deleteLegacyItem(key)
    return true
  }

  static func get(_ key: String) -> Data? {
    if let data = copyData(matching: itemLookup(for: key)) {
      return data
    }

    // One-time migration from versions that stored all generic passwords in
    // the empty service bucket. The legacy item is removed only after the new
    // protected item was written successfully.
    guard let legacyData = copyData(matching: legacyLookup(for: key)) else { return nil }
    guard set(legacyData, for: key) else { return legacyData }
    return legacyData
  }

  static func delete(_ key: String) {
    SecItemDelete(itemLookup(for: key) as CFDictionary)
    deleteLegacyItem(key)
  }

  private static func itemLookup(for key: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key
    ]
  }

  private static func legacyLookup(for key: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "",
      kSecAttrAccount as String: key
    ]
  }

  private static func copyData(matching lookup: [String: Any]) -> Data? {
    var query = lookup
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess else { return nil }
    return item as? Data
  }

  private static func deleteLegacyItem(_ key: String) {
    SecItemDelete(legacyLookup(for: key) as CFDictionary)
  }
}
