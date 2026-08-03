import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
  case system
  case de
  case en

  var id: String { rawValue }

  var bundleLanguageCode: String? {
    switch self {
    case .system:
      return nil
    case .de:
      return "de"
    case .en:
      return "en"
    }
  }

  var localeIdentifier: String {
    switch self {
    case .system:
      return Locale.current.identifier
    case .de:
      return "de"
    case .en:
      return "en"
    }
  }
}

enum AppLocalizer {
  static func localized(_ key: String, language: AppLanguage, comment: String = "") -> String {
    NSLocalizedString(key, bundle: bundle(for: language), comment: comment)
  }

  static func localizedFormat(_ key: String, language: AppLanguage, _ arguments: CVarArg...) -> String {
    localizedFormat(key, language: language, arguments: arguments)
  }

  static func localizedFormat(_ key: String, language: AppLanguage, arguments: [CVarArg]) -> String {
    let format = localized(key, language: language)
    return String(format: format, locale: Locale(identifier: language.localeIdentifier), arguments: arguments)
  }

  private static func bundle(for language: AppLanguage) -> Bundle {
    guard let code = language.bundleLanguageCode,
          let path = Bundle.main.path(forResource: code, ofType: "lproj"),
          let bundle = Bundle(path: path) else {
      return .main
    }
    return bundle
  }
}
