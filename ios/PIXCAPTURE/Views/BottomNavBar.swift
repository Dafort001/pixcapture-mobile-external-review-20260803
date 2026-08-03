import SwiftUI

enum BottomTab {
  case start
  case help
  case sunPlan
  case camera
  case panorama
  case gallery
  case manual
}

struct BottomNavBar: View {
  private enum Palette {
    static let shell = Color.black.opacity(0.92)
    static let fill = Color.white.opacity(0.06)
    static let stroke = Color.white.opacity(0.10)
    static let textPrimary = Color.white.opacity(0.95)
    static let textMuted = Color.white.opacity(0.56)
    static let darkBlue = Color(red: 42.0 / 255.0, green: 63.0 / 255.0, blue: 104.0 / 255.0)
    static let lightBlue = Color(red: 108.0 / 255.0, green: 168.0 / 255.0, blue: 200.0 / 255.0)
    static let orange = Color(red: 209.0 / 255.0, green: 94.0 / 255.0, blue: 64.0 / 255.0)
    static let pink = Color(red: 227.0 / 255.0, green: 163.0 / 255.0, blue: 174.0 / 255.0)
  }

  let selected: BottomTab
  let onSelect: (BottomTab) -> Void
  @EnvironmentObject private var settings: AppSettings

  var body: some View {
    let secondaryIcon = AppFeatureFlags.panoramaEnabled ? "rotate.3d" : "map.fill"
    let secondaryLabel = AppFeatureFlags.panoramaEnabled ? "360°" : l10n("bottom.floorplan")

    HStack(spacing: 7) {
      navItem(tab: .start, icon: "house.fill", label: l10n("bottom.start"), accent: Palette.lightBlue)
      navItem(tab: .sunPlan, icon: "sun.max.fill", label: l10n("bottom.sunPlan"), accent: Palette.pink)
      navItem(tab: .camera, icon: "camera.fill", label: l10n("bottom.camera"), accent: Palette.orange)
      navItem(tab: .panorama, icon: secondaryIcon, label: secondaryLabel, accent: Palette.lightBlue)
      navItem(tab: .gallery, icon: "photo.on.rectangle.angled", label: l10n("bottom.gallery"), accent: Palette.pink)
      navItem(tab: .manual, icon: "ellipsis.circle.fill", label: l10n("bottom.more"), accent: Palette.orange)
    }
    .padding(.horizontal, 10)
    .padding(.top, 10)
    .padding(.bottom, 9)
    .background(
      RoundedRectangle(cornerRadius: 28, style: .continuous)
        .fill(Palette.shell)
        .overlay(
          RoundedRectangle(cornerRadius: 28, style: .continuous)
            .stroke(Palette.stroke, lineWidth: 1)
        )
    )
    .padding(.horizontal, 14)
    .padding(.top, 6)
    .background(Color.clear)
    .safeAreaPadding(.bottom, 0)
  }

  private func navItem(tab: BottomTab, icon: String, label: String, accent: Color) -> some View {
    let isSelected = selected == tab

    return Button {
      onSelect(tab)
    } label: {
      VStack(spacing: 6) {
        Image(systemName: icon)
          .font(.system(size: 17, weight: .semibold))
        Text(label)
          .font(inter(size: 10, weight: .semibold))
          .lineLimit(1)
          .minimumScaleFactor(0.82)
      }
      .foregroundStyle(isSelected ? Palette.textPrimary : accent.opacity(0.82))
      .frame(maxWidth: .infinity)
      .padding(.vertical, 9)
      .background(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(isSelected ? accent.opacity(0.28) : accent.opacity(0.08))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(isSelected ? accent.opacity(0.48) : accent.opacity(0.16), lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("bottom.\(accessibilityIdentifier(for: tab))")
  }

  private func inter(size: CGFloat, weight: Font.Weight = .regular) -> Font {
    .pixInter(size: size, weight: weight)
  }

  private func l10n(_ key: String) -> String {
    settings.localized(key)
  }

  private func accessibilityIdentifier(for tab: BottomTab) -> String {
    switch tab {
    case .start: return "start"
    case .help: return "help"
    case .sunPlan: return "sunPlan"
    case .camera: return "camera"
    case .panorama: return AppFeatureFlags.panoramaEnabled ? "panorama" : "floorplan"
    case .gallery: return "gallery"
    case .manual: return "more"
    }
  }
}
