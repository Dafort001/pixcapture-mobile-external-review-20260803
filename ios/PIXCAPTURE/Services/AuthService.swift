import Foundation
import Combine
import CryptoKit

@MainActor
final class AuthService: ObservableObject {
  @Published private(set) var isAuthenticated: Bool = false
  @Published private(set) var accessToken: String? = nil
  @Published private(set) var mobileConnectToken: String? = nil
  @Published private(set) var userId: String? = nil
  @Published private(set) var requiresInteractiveLogin: Bool = false
  @Published var lastError: String? = nil
  @Published var lastInfoMessage: String? = nil
  @Published var availableJobs: [JobInfo] = []

  private let baseURL = URL(string: "https://api.pixcapture.app")!
  private let accessKey = "pixcapture.access"
  private let refreshKey = "pixcapture.refresh"
  private let expiryKey = "pixcapture.expiry"
  private let mobileConnectKey = "pixcapture.mobile.connect.token"
  private let hiddenJobsKeyPrefix = "pixcapture.hiddenJobs"
  private static let installationMarkerKey = "pixcapture.installation.marker.v1"
  private static let legacyOnboardingKey = "pixcapture.hasSeenFirstRunOnboarding"
  static let mobileInboxMotifLimit = 200

  private static func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), arguments: arguments)
  }

  var effectiveAccessToken: String? {
    if let accessToken,
       !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return accessToken
    }
    if let mobileConnectToken,
       !mobileConnectToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return mobileConnectToken
    }
    return nil
  }

  var effectiveUserId: String? {
    if let userId,
       !userId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return userId
    }
    if mobileConnectToken != nil {
      return "mobile"
    }
    return nil
  }

  var recentJobScope: String? {
    if let userId,
       !userId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return "user:\(userId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }
    guard let token = effectiveAccessToken?.trimmingCharacters(in: .whitespacesAndNewlines),
          !token.isEmpty else {
      return nil
    }
    let digest = SHA256.hash(data: Data(token.utf8))
    let fingerprint = digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    return "session:\(fingerprint)"
  }

  func validEffectiveAccessToken() -> String? {
    if let rawAccessToken = accessToken?.trimmingCharacters(in: .whitespacesAndNewlines),
       !rawAccessToken.isEmpty {
      if isTokenExpired(rawAccessToken, fallbackExpiry: storedAccessExpiry()) {
        clearStoredAccessToken()
        if mobileConnectToken == nil {
          requireInteractiveLogin(message: NSLocalizedString("auth.session.expired", comment: ""))
        }
      } else {
        return rawAccessToken
      }
    }

    if let rawMobileConnectToken = mobileConnectToken?.trimmingCharacters(in: .whitespacesAndNewlines),
       !rawMobileConnectToken.isEmpty {
      if isTokenExpired(rawMobileConnectToken, fallbackExpiry: nil) {
        clearMobileConnectToken()
        requireInteractiveLogin(message: NSLocalizedString("auth.session.expired", comment: ""))
        return nil
      }
      return rawMobileConnectToken
    }

    return nil
  }

  init() {
    let shouldClearStoredSession = Self.shouldClearStoredSessionOnLaunch()
      || Self.isFreshInstallationAfterPreviousKeychainSession()
    if shouldClearStoredSession {
      KeychainStore.delete(accessKey)
      KeychainStore.delete(refreshKey)
      KeychainStore.delete(expiryKey)
      KeychainStore.delete(mobileConnectKey)
      UserDefaults.standard.removeObject(forKey: "pixcapture.lastLoginEmail")
    }
    UserDefaults.standard.set(true, forKey: Self.installationMarkerKey)
    loadFromKeychain()
  }

  @discardableResult
  func loginWithPassword(email: String, password: String) async -> Bool {
    lastError = nil
    lastInfoMessage = nil

    let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let normalizedPassword = password

    guard !normalizedEmail.isEmpty else {
      lastError = NSLocalizedString("auth.error.emailMissing", comment: "")
      return false
    }

    guard !normalizedPassword.isEmpty else {
      lastError = NSLocalizedString("auth.error.passwordMissing", comment: "")
      return false
    }

    guard let url = URL(string: "/api/v2/mobile/auth/password", relativeTo: baseURL) else {
      lastError = NSLocalizedString("auth.error.loginPreparation", comment: "")
      return false
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONEncoder().encode(
      PasswordLoginRequest(email: normalizedEmail, password: normalizedPassword)
    )

    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse else {
        lastError = NSLocalizedString("auth.error.invalidResponse", comment: "")
        return false
      }

      guard (200...299).contains(http.statusCode) else {
        lastError = authErrorMessage(from: data)
          ?? Self.localizedFormat("auth.error.loginStatus.format", http.statusCode)
        return false
      }

      let decoded = try JSONDecoder().decode(MobileAuthTokenResponse.self, from: data)
      guard persistAccessToken(decoded.accessToken, expiresIn: decoded.expiresIn) else {
        lastError = NSLocalizedString("auth.error.secureStorageAfterLogin", comment: "")
        return false
      }
      accessToken = decoded.accessToken
      userId = extractUserId(from: decoded.accessToken)
      isAuthenticated = true
      requiresInteractiveLogin = false
      availableJobs = []
      await refreshJobs()
      return true
    } catch {
      lastError = Self.localizedFormat("auth.error.network.format", error.localizedDescription)
      return false
    }
  }

  func refreshJobs() async {
    lastError = nil

    guard let token = effectiveAccessToken else { return }
    guard !isEffectiveTokenExpired(token) else {
      expireCurrentSession()
      return
    }
    guard let url = URL(string: "/api/pixcapture/jobs", relativeTo: baseURL) else { return }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse else {
        return
      }

      if http.statusCode == 401 {
        expireCurrentSession()
        return
      }

      guard (200...299).contains(http.statusCode) else {
        return
      }

      let jobs = try JSONDecoder().decode([PixcaptureJobDTO].self, from: data)
      let hiddenIds = hiddenJobIDs()
      availableJobs = jobs
        .map {
          JobInfo(
            id: $0.id,
            name: $0.title,
            propertyAddress: $0.propertyAddress,
            customerCode: $0.customerCode
          )
        }
        .filter { !hiddenIds.contains($0.id) }
    } catch {
      // Keep current list if refresh fails.
    }
  }

  func createJob(title: String, propertyAddress: String, notes: String? = nil) async -> JobInfo? {
    lastError = nil
    lastInfoMessage = nil

    guard let token = effectiveAccessToken else {
      requireInteractiveLogin(message: NSLocalizedString("auth.signInAgain", comment: ""))
      return nil
    }

    guard !isEffectiveTokenExpired(token) else {
      expireCurrentSession()
      return nil
    }

    guard let url = URL(string: "/api/pixcapture/jobs", relativeTo: baseURL) else { return nil }
    let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanAddress = propertyAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanTitle.isEmpty else {
      lastError = NSLocalizedString("auth.error.jobTitleRequired", comment: "")
      return nil
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.httpBody = try? JSONEncoder().encode(
      CreatePixcaptureJobRequest(title: cleanTitle, propertyAddress: cleanAddress, notes: notes)
    )

    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse else {
        lastError = NSLocalizedString("auth.error.invalidResponse", comment: "")
        return nil
      }

      if http.statusCode == 401 {
        expireCurrentSession()
        return nil
      }

      guard (200...299).contains(http.statusCode) else {
        lastError = authErrorMessage(from: data)
          ?? Self.localizedFormat("auth.error.jobCreateStatus.format", http.statusCode)
        return nil
      }

      let created = try JSONDecoder().decode(PixcaptureJobDTO.self, from: data)
      let info = JobInfo(
        id: created.id,
        name: created.title,
        propertyAddress: created.propertyAddress,
        customerCode: created.customerCode
      )
      availableJobs.removeAll(where: { $0.id == info.id })
      availableJobs.insert(info, at: 0)
      return info
    } catch {
      lastError = Self.localizedFormat("auth.error.network.format", error.localizedDescription)
      return nil
    }
  }

  func updateJob(id: String, title: String, propertyAddress: String, notes: String? = nil) async -> JobInfo? {
    lastError = nil
    lastInfoMessage = nil

    guard let token = effectiveAccessToken else {
      requireInteractiveLogin(message: NSLocalizedString("auth.signInAgain", comment: ""))
      return nil
    }

    guard !isEffectiveTokenExpired(token) else {
      expireCurrentSession()
      return nil
    }

    let cleanId = id.trimmingCharacters(in: .whitespacesAndNewlines)
    let encodedId = cleanId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cleanId
    guard !cleanId.isEmpty,
          let url = URL(string: "/api/pixcapture/jobs/\(encodedId)", relativeTo: baseURL) else {
      lastError = NSLocalizedString("auth.error.jobPreparation", comment: "")
      return nil
    }
    let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanAddress = propertyAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanTitle.isEmpty else {
      lastError = NSLocalizedString("auth.error.jobTitleRequired", comment: "")
      return nil
    }

    var request = URLRequest(url: url)
    request.httpMethod = "PATCH"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.httpBody = try? JSONEncoder().encode(
      UpdatePixcaptureJobRequest(
        title: cleanTitle,
        propertyAddress: cleanAddress.isEmpty ? nil : cleanAddress,
        notes: notes
      )
    )

    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse else {
        lastError = NSLocalizedString("auth.error.invalidResponse", comment: "")
        return nil
      }

      if http.statusCode == 401 {
        expireCurrentSession()
        return nil
      }

      guard (200...299).contains(http.statusCode) else {
        lastError = authErrorMessage(from: data)
          ?? Self.localizedFormat("auth.error.jobUpdateStatus.format", http.statusCode)
        return nil
      }

      let updated = try JSONDecoder().decode(PixcaptureJobDTO.self, from: data)
      let info = JobInfo(
        id: updated.id,
        name: updated.title,
        propertyAddress: updated.propertyAddress,
        customerCode: updated.customerCode
      )
      availableJobs.removeAll(where: { $0.id == info.id })
      availableJobs.insert(info, at: 0)
      return info
    } catch {
      lastError = Self.localizedFormat("auth.error.network.format", error.localizedDescription)
      return nil
    }
  }

  func ensureMobileInboxJob(incomingMotifCount: Int) async -> JobInfo? {
    lastError = nil
    lastInfoMessage = nil

    if let existingInbox = availableJobs.first(where: { job in
      CaptureJobPolicy.isMobileInboxJob(job)
    }) {
      return existingInbox
    }

    guard let token = effectiveAccessToken else {
      requireInteractiveLogin(message: NSLocalizedString("auth.signInAgainForInbox", comment: ""))
      return nil
    }

    guard !isEffectiveTokenExpired(token) else {
      expireCurrentSession()
      return nil
    }

    guard let url = URL(string: "/api/pixcapture/jobs", relativeTo: baseURL) else { return nil }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.httpBody = try? JSONEncoder().encode(
      MobileInboxJobRequest(
        mobileInbox: true,
        incomingMotifCount: max(incomingMotifCount, 0),
        pendingMotifLimit: Self.mobileInboxMotifLimit
      )
    )

    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse else {
        lastError = NSLocalizedString("auth.error.invalidResponse", comment: "")
        return nil
      }

      if http.statusCode == 401 {
        expireCurrentSession()
        return nil
      }

      guard (200...299).contains(http.statusCode) else {
        let serverMessage = authErrorMessage(from: data)
        if http.statusCode == 400,
           serverMessage?.localizedCaseInsensitiveContains("Missing job title") == true {
          return await createJob(
            title: CaptureJobPolicy.mobileInboxJobTitle,
            propertyAddress: "",
            notes: "pixcapture_mobile_inbox_v1"
          )
        }
        lastError = serverMessage
          ?? Self.localizedFormat("auth.error.inboxStatus.format", http.statusCode)
        return nil
      }

      let inbox = try JSONDecoder().decode(PixcaptureJobDTO.self, from: data)
      let info = JobInfo(
        id: inbox.id,
        name: inbox.title,
        propertyAddress: inbox.propertyAddress,
        customerCode: inbox.customerCode
      )
      availableJobs.removeAll(where: { $0.id == info.id })
      availableJobs.insert(info, at: 0)
      removeHiddenJobID(info.id)
      return info
    } catch {
      lastError = Self.localizedFormat("auth.error.network.format", error.localizedDescription)
      return nil
    }
  }

  @discardableResult
  func deleteJob(id: String) async -> Bool {
    lastError = nil
    lastInfoMessage = nil

    guard let token = effectiveAccessToken else {
      requireInteractiveLogin(message: NSLocalizedString("auth.signInAgain", comment: ""))
      return false
    }

    guard !isEffectiveTokenExpired(token) else {
      expireCurrentSession()
      return false
    }

    let cleanId = id.trimmingCharacters(in: .whitespacesAndNewlines)
    let encodedId = cleanId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cleanId
    guard !cleanId.isEmpty,
          let url = URL(string: "/api/pixcapture/jobs/\(encodedId)", relativeTo: baseURL) else {
      lastError = NSLocalizedString("auth.error.jobPreparation", comment: "")
      return false
    }

    var request = URLRequest(url: url)
    request.httpMethod = "DELETE"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

    do {
      let (_, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse else {
        lastError = NSLocalizedString("auth.error.invalidResponse", comment: "")
        return false
      }

      if http.statusCode == 401 {
        expireCurrentSession()
        return false
      }

      guard (200...299).contains(http.statusCode) else {
        hideJobIDFromMobileList(cleanId)
        lastInfoMessage = NSLocalizedString("auth.info.jobHiddenLocally", comment: "")
        return true
      }

      availableJobs.removeAll(where: { $0.id.compare(cleanId, options: [.caseInsensitive]) == .orderedSame })
      removeHiddenJobID(cleanId)
      return true
    } catch {
      lastError = Self.localizedFormat("auth.error.network.format", error.localizedDescription)
      return false
    }
  }

  func hideJobFromMobile(id: String) {
    hideJobIDFromMobileList(id)
  }

  @discardableResult
  func uploadSupportFileList(itemURLs: [URL], localFileCount: Int, queueRecordCount: Int) async -> Bool {
    lastError = nil
    lastInfoMessage = nil

    guard let token = effectiveAccessToken else {
      requireInteractiveLogin(message: NSLocalizedString("auth.signInAgainForSupport", comment: ""))
      return false
    }

    guard !isEffectiveTokenExpired(token) else {
      expireCurrentSession()
      return false
    }

    guard !itemURLs.isEmpty else {
      lastError = NSLocalizedString("auth.error.supportListEmpty", comment: "")
      return false
    }

    guard let url = URL(string: "/api/v2/mobile/support-file-list", relativeTo: baseURL) else {
      lastError = NSLocalizedString("auth.error.supportPreparation", comment: "")
      return false
    }

    do {
      let files = try itemURLs.map { fileURL in
        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        return SupportFileListUploadFile(
          filename: fileURL.lastPathComponent,
          contentType: supportFileListContentType(for: fileURL),
          base64: data.base64EncodedString()
        )
      }

      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      request.httpBody = try JSONEncoder().encode(
        SupportFileListUploadRequest(
          localFileCount: localFileCount,
          queueRecordCount: queueRecordCount,
          files: files
        )
      )

      let (data, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse else {
        lastError = NSLocalizedString("auth.error.invalidResponse", comment: "")
        return false
      }

      if http.statusCode == 401 {
        expireCurrentSession()
        return false
      }

      guard (200...299).contains(http.statusCode) else {
        lastError = authErrorMessage(from: data)
          ?? Self.localizedFormat("auth.error.supportStatus.format", http.statusCode)
        return false
      }

      let decoded = try? JSONDecoder().decode(SupportFileListUploadResponse.self, from: data)
      let count = decoded?.files.count ?? files.count
      lastInfoMessage = Self.localizedFormat("auth.info.supportSaved.format", count)
      return true
    } catch {
      lastError = Self.localizedFormat("auth.error.supportSave.format", error.localizedDescription)
      return false
    }
  }

  func logout() {
    clearStoredAccessToken()
    KeychainStore.delete(mobileConnectKey)
    UserDefaults.standard.removeObject(forKey: "pixcapture.lastLoginEmail")
    mobileConnectToken = nil
    userId = nil
    availableJobs = []
    isAuthenticated = false
    requiresInteractiveLogin = false
    lastError = nil
    lastInfoMessage = nil
  }

  private func supportFileListContentType(for url: URL) -> String {
    switch url.pathExtension.lowercased() {
    case "csv":
      return "text/csv"
    case "txt":
      return "text/plain"
    default:
      return "application/octet-stream"
    }
  }

  func setMobileConnectToken(_ rawToken: String) {
    let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !token.isEmpty else { return }
    guard KeychainStore.set(Data(token.utf8), for: mobileConnectKey) else {
      lastError = NSLocalizedString("auth.error.secureStorage", comment: "")
      return
    }
    mobileConnectToken = token
    if accessToken == nil {
      userId = extractUserId(from: token)
    }
    isAuthenticated = true
    requiresInteractiveLogin = false
    lastError = nil
    lastInfoMessage = nil
  }

  func clearMobileConnectToken() {
    KeychainStore.delete(mobileConnectKey)
    mobileConnectToken = nil
    if accessToken == nil {
      userId = nil
    }
    isAuthenticated = (accessToken != nil)
    requiresInteractiveLogin = false
    lastError = nil
    lastInfoMessage = nil
  }

  private func persistAccessToken(_ token: String, expiresIn: Int) -> Bool {
    let expiry = Date().addingTimeInterval(TimeInterval(expiresIn)).timeIntervalSince1970
    let previousToken = KeychainStore.get(accessKey)
    let previousExpiry = KeychainStore.get(expiryKey)
    guard KeychainStore.set(Data(token.utf8), for: accessKey),
          KeychainStore.set(Data(String(expiry).utf8), for: expiryKey) else {
      restoreKeychainValue(previousToken, for: accessKey)
      restoreKeychainValue(previousExpiry, for: expiryKey)
      return false
    }
    KeychainStore.delete(refreshKey)
    return true
  }

  private func restoreKeychainValue(_ value: Data?, for key: String) {
    if let value {
      _ = KeychainStore.set(value, for: key)
    } else {
      KeychainStore.delete(key)
    }
  }

  private func loadFromKeychain() {
    if let data = KeychainStore.get(accessKey),
       let rawToken = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
       !rawToken.isEmpty {
      if isTokenExpired(rawToken, fallbackExpiry: storedAccessExpiry()) {
        clearStoredAccessToken()
      } else {
        accessToken = rawToken
        userId = extractUserId(from: rawToken)
        Task { [weak self] in
          await self?.refreshJobs()
        }
      }
    }

    if let data = KeychainStore.get(mobileConnectKey),
       let rawToken = String(data: data, encoding: .utf8),
       let token = Self.normalizedMobileTokenValue(rawToken) {
      mobileConnectToken = token
      if accessToken == nil {
        userId = extractUserId(from: token)
      }
    }

    isAuthenticated = (accessToken != nil) || (mobileConnectToken != nil)
  }

  private static func shouldClearStoredSessionOnLaunch() -> Bool {
    let processInfo = ProcessInfo.processInfo
    if processInfo.arguments.contains("--pixcapture-clear-auth") {
      return true
    }
    let value = processInfo.environment["PIXCAPTURE_CLEAR_AUTH"]?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    return value == "1" || value == "true" || value == "yes"
  }

  private static func isFreshInstallationAfterPreviousKeychainSession() -> Bool {
    let defaults = UserDefaults.standard
    if defaults.bool(forKey: installationMarkerKey) {
      return false
    }

    // Existing installations from versions before the marker keep their login
    // during an update. A reinstall has neither marker nor onboarding state,
    // while iOS may still retain the former account tokens in Keychain.
    return defaults.object(forKey: legacyOnboardingKey) == nil
  }

  private func expireStoredAccessToken() {
    clearStoredAccessToken()
    requireInteractiveLogin(message: NSLocalizedString("auth.session.expired", comment: ""))
  }

  private func expireCurrentSession() {
    if accessToken != nil {
      expireStoredAccessToken()
      return
    }

    if mobileConnectToken != nil {
      clearMobileConnectToken()
      requireInteractiveLogin(message: NSLocalizedString("auth.session.expired", comment: ""))
    }
  }

  private func requireInteractiveLogin(message: String) {
    requiresInteractiveLogin = true
    lastError = message
    lastInfoMessage = nil
  }

  private func clearStoredAccessToken() {
    KeychainStore.delete(accessKey)
    KeychainStore.delete(refreshKey)
    KeychainStore.delete(expiryKey)
    accessToken = nil
    availableJobs = []
    if mobileConnectToken == nil {
      userId = nil
      isAuthenticated = false
    }
  }

  private func storedAccessExpiry() -> TimeInterval? {
    guard let data = KeychainStore.get(expiryKey),
          let rawValue = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
          let expiry = TimeInterval(rawValue) else {
      return nil
    }
    return expiry
  }

  private func isTokenExpired(_ jwt: String, fallbackExpiry: TimeInterval?) -> Bool {
    if let expiry = extractTokenExpiry(from: jwt) {
      return expiry <= Date().timeIntervalSince1970
    }
    if let fallbackExpiry {
      return fallbackExpiry <= Date().timeIntervalSince1970
    }
    return false
  }

  private func isEffectiveTokenExpired(_ token: String) -> Bool {
    let fallbackExpiry: TimeInterval?
    if token == accessToken {
      fallbackExpiry = storedAccessExpiry()
    } else {
      fallbackExpiry = nil
    }
    return isTokenExpired(token, fallbackExpiry: fallbackExpiry)
  }

  private func extractUserId(from jwt: String) -> String? {
    guard let object = extractTokenPayload(from: jwt) else {
      return nil
    }
    if let sub = object["sub"] as? String, !sub.isEmpty {
      return sub
    }
    if let userId = object["userId"] as? String, !userId.isEmpty {
      return userId
    }
    if let id = object["id"] as? String, !id.isEmpty {
      return id
    }
    return nil
  }

  private func extractTokenExpiry(from jwt: String) -> TimeInterval? {
    guard let object = extractTokenPayload(from: jwt) else {
      return nil
    }
    if let exp = object["exp"] as? TimeInterval {
      return exp
    }
    if let exp = object["exp"] as? NSNumber {
      return exp.doubleValue
    }
    if let exp = object["exp"] as? String, let doubleValue = TimeInterval(exp) {
      return doubleValue
    }
    return nil
  }

  private func extractTokenPayload(from jwt: String) -> [String: Any]? {
    let parts = jwt.split(separator: ".")
    guard parts.count >= 2 else { return nil }
    var payload = String(parts[1])
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    let remainder = payload.count % 4
    if remainder > 0 {
      payload += String(repeating: "=", count: 4 - remainder)
    }
    guard let data = Data(base64Encoded: payload),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return nil
    }
    return object
  }

  private func authErrorMessage(from data: Data) -> String? {
    guard let apiError = try? JSONDecoder().decode(AuthErrorResponse.self, from: data) else {
      return nil
    }
    return apiError.resolvedMessage
  }

  private func hiddenJobsKey() -> String {
    let scope = effectiveUserId?.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedScope = (scope?.isEmpty == false) ? scope! : "default"
    return "\(hiddenJobsKeyPrefix).\(normalizedScope)"
  }

  private func hiddenJobIDs() -> Set<String> {
    let stored = UserDefaults.standard.stringArray(forKey: hiddenJobsKey()) ?? []
    return Set(stored)
  }

  private func saveHiddenJobIDs(_ ids: Set<String>) {
    UserDefaults.standard.set(Array(ids).sorted(), forKey: hiddenJobsKey())
  }

  private func hideJobIDFromMobileList(_ id: String) {
    let cleanId = id.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanId.isEmpty else { return }
    var hiddenIds = hiddenJobIDs()
    hiddenIds.insert(cleanId)
    saveHiddenJobIDs(hiddenIds)
    availableJobs.removeAll {
      $0.id.compare(cleanId, options: [.caseInsensitive]) == .orderedSame
    }
  }

  private func removeHiddenJobID(_ id: String) {
    var ids = hiddenJobIDs()
    ids = ids.filter { $0.compare(id, options: [.caseInsensitive]) != .orderedSame }
    saveHiddenJobIDs(ids)
  }

  private static let mobileConnectTokenQueryNames: Set<String> = [
    "token", "mobileconnecttoken", "mobile_connect_token"
  ]

  static func parseMobileConnectToken(from raw: String) -> String? {
    let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !token.isEmpty else { return nil }

    if let url = URL(string: token),
       let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
       let queryItems = components.queryItems {
      for item in queryItems {
        if mobileConnectTokenQueryNames.contains(item.name.lowercased()),
           let value = normalizedMobileTokenValue(item.value) {
          return value
        }
      }
    }

    // Fallback for copy-pasted raw token values.
    if !token.contains("://"), !token.contains("{"), !token.contains(" "), token.count >= 8 {
      return normalizedMobileTokenValue(token)
    }

    return nil
  }

  static func looksLikeWebConnectQR(_ raw: String) -> Bool {
    let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !token.isEmpty else { return false }

    if let data = token.data(using: .utf8),
       let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
      let schema = (object["schema"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
      if schema == "pixcapture.connect-qr.v2" {
        return true
      }
      if (object["web_session_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
        return true
      }
      if (object["webSessionId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
        return true
      }
    }

    if let url = URL(string: token),
       let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
      let sessionQueryNames: Set<String> = ["session", "sessionid", "web_session_id", "websessionid", "id"]
      if components.queryItems?.contains(where: { item in
        sessionQueryNames.contains(item.name.lowercased())
          && item.value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
      }) == true {
        return true
      }

      let pathParts = components.path
        .split(separator: "/")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        .filter { !$0.isEmpty }
      if pathParts.count >= 2,
         ["connect", "web-connect", "up"].contains(pathParts[0]),
         pathParts[1].hasPrefix("sess") {
        return true
      }
      if pathParts.count == 1, pathParts[0].hasPrefix("sess") {
        return true
      }
    }

    return token.lowercased().hasPrefix("sess_")
  }

  private static func normalizedMobileTokenValue(_ value: String?) -> String? {
    guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
          !value.isEmpty else {
      return nil
    }
    if value.hasPrefix("\""), value.hasSuffix("\""), value.count > 1 {
      value.removeFirst()
      value.removeLast()
    }
    return value.isEmpty ? nil : value
  }
}

private struct PixcaptureJobDTO: Decodable {
  let id: String
  let title: String
  let propertyAddress: String?
  let customerCode: String?

  private enum CodingKeys: String, CodingKey {
    case id
    case title
    case propertyAddress
    case property_address
    case customerCode
    case customer_code
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    propertyAddress =
      (try? container.decodeIfPresent(String.self, forKey: .propertyAddress))
      ?? (try? container.decodeIfPresent(String.self, forKey: .property_address))
    customerCode =
      (try? container.decodeIfPresent(String.self, forKey: .customerCode))
      ?? (try? container.decodeIfPresent(String.self, forKey: .customer_code))
  }
}

private struct CreatePixcaptureJobRequest: Codable {
  let title: String
  let propertyAddress: String
  let notes: String?
}

private struct UpdatePixcaptureJobRequest: Codable {
  let title: String
  let propertyAddress: String?
  let notes: String?
}

private struct MobileInboxJobRequest: Codable {
  let mobileInbox: Bool
  let incomingMotifCount: Int
  let pendingMotifLimit: Int
}

private struct SupportFileListUploadRequest: Codable {
  let localFileCount: Int
  let queueRecordCount: Int
  let files: [SupportFileListUploadFile]
}

private struct SupportFileListUploadFile: Codable {
  let filename: String
  let contentType: String
  let base64: String
}

private struct SupportFileListUploadResponse: Decodable {
  struct UploadedFile: Decodable {
    let filename: String
  }

  let success: Bool?
  let sessionId: String?
  let files: [UploadedFile]
}
