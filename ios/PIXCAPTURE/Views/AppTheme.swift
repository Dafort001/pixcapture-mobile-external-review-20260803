import SwiftUI

enum AppTheme {
  static let primary = Color(red: 42.0 / 255.0, green: 63.0 / 255.0, blue: 104.0 / 255.0)
  static let secondary = Color(red: 108.0 / 255.0, green: 168.0 / 255.0, blue: 200.0 / 255.0)
  static let accent = Color(red: 209.0 / 255.0, green: 94.0 / 255.0, blue: 64.0 / 255.0)
  static let canvas = Color(red: 238.0 / 255.0, green: 243.0 / 255.0, blue: 247.0 / 255.0)
  static let card = Color.white
  static let stroke = Color.black.opacity(0.08)
  static let textPrimary = Color.black.opacity(0.84)
  static let textSecondary = Color.black.opacity(0.60)
  static let navOverlay = Color(red: 15.0 / 255.0, green: 24.0 / 255.0, blue: 39.0 / 255.0).opacity(0.88)
}

struct PixDonePill: View {
  let title: String

  var body: some View {
    Text(title)
      .font(.pixInter(size: 14, weight: .semibold))
      .lineLimit(1)
      .minimumScaleFactor(0.85)
      .foregroundStyle(Color.white)
      .padding(.horizontal, 18)
      .frame(minHeight: 38)
      .background(AppTheme.primary)
      .clipShape(Capsule())
      .overlay(
        Capsule()
          .stroke(Color.white.opacity(0.18), lineWidth: 1)
      )
      .shadow(color: Color.black.opacity(0.16), radius: 8, x: 0, y: 4)
  }
}
