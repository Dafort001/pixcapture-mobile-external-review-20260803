import Foundation

struct PasswordLoginRequest: Codable {
  let email: String
  let password: String
}

struct MobileAuthTokenResponse: Codable {
  let accessToken: String
  let expiresIn: Int
}

struct AuthErrorResponse: Codable {
  let error: String?
  let message: String?
  let needNewCode: Bool?

  var resolvedMessage: String? {
    let candidates = [message, error]
    for candidate in candidates {
      let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if !trimmed.isEmpty {
        return trimmed
      }
    }
    return nil
  }
}

struct JobInfo: Codable, Identifiable, Equatable {
  let id: String
  let name: String
  let propertyAddress: String?
  let customerCode: String?

  init(id: String, name: String, propertyAddress: String?, customerCode: String? = nil) {
    self.id = id
    self.name = name
    self.propertyAddress = propertyAddress
    self.customerCode = customerCode
  }
}
