import SwiftUI
import UIKit

enum PixBrand {
  static let background = Color.black
  static let darkBlue = Color(red: 42.0 / 255.0, green: 63.0 / 255.0, blue: 104.0 / 255.0)
  static let lightBlue = Color(red: 108.0 / 255.0, green: 168.0 / 255.0, blue: 200.0 / 255.0)
  static let orange = Color(red: 209.0 / 255.0, green: 94.0 / 255.0, blue: 64.0 / 255.0)
  static let pink = Color(red: 227.0 / 255.0, green: 163.0 / 255.0, blue: 174.0 / 255.0)
  static let indigo = Color(red: 58.0 / 255.0, green: 70.0 / 255.0, blue: 124.0 / 255.0)

  static let utilityText = Color.white.opacity(0.56)
  static let textOnDark = Color.white.opacity(0.86)
  static let textOnDarkSecondary = Color.white.opacity(0.66)
  static let borderOnDark = Color.white.opacity(0.12)
  static let panel = Color(red: 17.0 / 255.0, green: 23.0 / 255.0, blue: 34.0 / 255.0)
  static let panelSecondary = Color(red: 24.0 / 255.0, green: 32.0 / 255.0, blue: 49.0 / 255.0)
  static let danger = Color(red: 1.0, green: 111.0 / 255.0, blue: 97.0 / 255.0)
  static let tileCornerRadius: CGFloat = 0

  static let cardCycle: [Color] = [lightBlue, orange, pink, indigo]

  static func cardFill(_ index: Int) -> Color {
    cardCycle[index % cardCycle.count]
  }

  static func cardText(_ index: Int) -> Color {
    switch index % cardCycle.count {
    case 0:
      return darkBlue
    case 1:
      return Color.black.opacity(0.8)
    case 2:
      return darkBlue
    default:
      return pink
    }
  }

  static func tileShape(_ radius: CGFloat = tileCornerRadius) -> RoundedRectangle {
    RoundedRectangle(cornerRadius: radius, style: .continuous)
  }

  static func interFontName(for weight: Font.Weight) -> String {
    if weight == .ultraLight {
      return "Inter-ExtraLight"
    }
    if weight == .thin {
      return "Inter-Thin"
    }
    if weight == .light {
      return "Inter-Light"
    }
    if weight == .medium {
      return "Inter-Medium"
    }
    if weight == .semibold {
      return "Inter-SemiBold"
    }
    if weight == .bold {
      return "Inter-Bold"
    }
    if weight == .heavy {
      return "Inter-ExtraBold"
    }
    if weight == .black {
      return "Inter-Black"
    }
    return "Inter-Regular"
  }
}

extension Font {
  static func pixInter(size: CGFloat, weight: Weight = .regular) -> Font {
    let fontName = PixBrand.interFontName(for: weight)
    if UIFont(name: fontName, size: size) != nil {
      return Font.custom(fontName, size: size)
    }
    return .system(size: size, weight: weight)
  }
}
