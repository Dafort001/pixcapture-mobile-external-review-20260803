import SwiftUI

struct HelpView: View {
  private enum Palette {
    static let background = PixBrand.background
    static let panel = PixBrand.panel
    static let panelSecondary = PixBrand.panelSecondary
    static let title = PixBrand.textOnDark
    static let body = PixBrand.textOnDarkSecondary
    static let border = PixBrand.borderOnDark
  }

  var onBack: () -> Void
  var backButtonTitle: String = "Zurück"
  @State private var selectedTopic: HelpTopic? = nil
  @EnvironmentObject private var settings: AppSettings

  var body: some View {
    ZStack {
      Palette.background
        .ignoresSafeArea()

      VStack(spacing: 18) {
        HStack(spacing: 12) {
          Button(action: {
            if selectedTopic != nil {
              selectedTopic = nil
            } else {
              onBack()
            }
          }) {
            Image(systemName: "chevron.left")
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(Palette.title)
              .frame(width: 36, height: 36)
              .background(Palette.panel)
              .clipShape(Circle())
              .overlay(Circle().stroke(Palette.border, lineWidth: 1))
              .frame(width: 44, height: 44)
          }
          .accessibilityLabel(selectedTopic == nil ? backButtonTitle : "Zurück zur Hilfe")
          Text(selectedTopic.map { title(for: $0) } ?? l10n("help.title"))
            .font(.pixInter(size: 18, weight: .light))
            .tracking(0.6)
            .foregroundStyle(Palette.title)
          Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)

        ScrollView {
          VStack(spacing: 14) {
            if let selectedTopic {
              if selectedTopic == .glossary {
                GlossaryListView()
              } else {
                HelpDetailCard(topic: selectedTopic)
              }
            } else {
              HelpCard(
                icon: "book.closed",
                title: l10n("help.card.glossary.title"),
                subtitle: l10n("help.card.glossary.subtitle")
              ) {
                selectedTopic = .glossary
              }

              HelpCard(
                icon: "envelope",
                title: l10n("help.card.forgotPassword.title"),
                subtitle: l10n("help.card.forgotPassword.subtitle")
              ) {
                selectedTopic = .forgotPassword
              }

              HelpCard(
                icon: "person.badge.plus",
                title: l10n("help.card.register.title"),
                subtitle: l10n("help.card.register.subtitle")
              ) {
                selectedTopic = .register
              }
            }

            ForEach(helpInfoItems) { item in
              HelpInfoCard(
                icon: item.icon,
                title: l10n(item.titleKey),
                text: l10n(item.textKey)
              )
            }
          }
          .padding(.horizontal, 20)
          .padding(.bottom, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnTap()

        Button(action: onBack) {
          Text(backButtonTitle)
            .font(.pixInter(size: 14, weight: .regular))
            .foregroundStyle(Palette.title)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Palette.panel)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.border, lineWidth: 1))
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 24)
      }
    }
    .keyboardDoneToolbar()
  }

  private var helpInfoItems: [HelpInfoItem] {
    [
      HelpInfoItem(icon: "info.circle", titleKey: "help.info.scope.title", textKey: "help.info.scope.text"),
      HelpInfoItem(icon: "square.grid.2x2", titleKey: "help.info.navigation.title", textKey: "help.info.navigation.text"),
      HelpInfoItem(icon: "line.3.horizontal", titleKey: "help.info.cameraTopbar.title", textKey: "help.info.cameraTopbar.text"),
      HelpInfoItem(icon: "checkmark.seal", titleKey: "help.info.cameraStatus.title", textKey: "help.info.cameraStatus.text"),
      HelpInfoItem(icon: "slider.horizontal.3", titleKey: "help.info.manual.title", textKey: "help.info.manual.text"),
      HelpInfoItem(icon: "square.stack.3d.up", titleKey: "help.info.bracketing.title", textKey: "help.info.bracketing.text"),
      HelpInfoItem(icon: "camera.aperture", titleKey: "help.info.raw.title", textKey: "help.info.raw.text"),
      HelpInfoItem(icon: "door.left.hand.open", titleKey: "help.info.roomPicker.title", textKey: "help.info.roomPicker.text"),
      HelpInfoItem(icon: "key.fill", titleKey: "help.info.login.title", textKey: "help.info.login.text"),
      HelpInfoItem(icon: "briefcase", titleKey: "help.info.jobs.title", textKey: "help.info.jobs.text"),
      HelpInfoItem(icon: "arrow.up.circle", titleKey: "help.info.upload.title", textKey: "help.info.upload.text"),
      HelpInfoItem(icon: "dial.low", titleKey: "help.info.iso.title", textKey: "help.info.iso.text"),
      HelpInfoItem(icon: "slider.horizontal.3", titleKey: "help.info.ev.title", textKey: "help.info.ev.text"),
      HelpInfoItem(icon: "chart.bar.xaxis", titleKey: "help.info.histogram.title", textKey: "help.info.histogram.text"),
      HelpInfoItem(icon: "level", titleKey: "help.info.level.title", textKey: "help.info.level.text"),
      HelpInfoItem(icon: "viewfinder", titleKey: "help.info.focus.title", textKey: "help.info.focus.text"),
      HelpInfoItem(icon: "textformat.abc", titleKey: "help.info.taxonomy.title", textKey: "help.info.taxonomy.text"),
      HelpInfoItem(icon: "photo.stack", titleKey: "help.info.formats.title", textKey: "help.info.formats.text")
    ]
  }

  private func title(for topic: HelpTopic) -> String {
    settings.localized(topic.titleKey)
  }

  private func l10n(_ key: String) -> String {
    settings.localized(key)
  }
}

private struct HelpInfoItem: Identifiable {
  let icon: String
  let titleKey: String
  let textKey: String

  var id: String { titleKey }
}

private struct HelpInfoCard: View {
  let icon: String
  let title: String
  let text: String

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: icon)
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(PixBrand.pink)
        .frame(width: 28, height: 28)
        .background(PixBrand.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(PixBrand.borderOnDark, lineWidth: 1)
        )

      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(PixBrand.textOnDark)
        Text(text)
          .font(.system(size: 12))
          .foregroundStyle(PixBrand.textOnDarkSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .padding(12)
    .background(PixBrand.panelSecondary)
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(PixBrand.borderOnDark, lineWidth: 1)
    )
  }
}

private struct HelpCard: View {
  let icon: String
  let title: String
  let subtitle: String
  let action: () -> Void

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: icon)
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(PixBrand.orange)
        .frame(width: 44, height: 44)
        .background(PixBrand.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(PixBrand.borderOnDark, lineWidth: 1))

      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(PixBrand.textOnDark)
        Text(subtitle)
          .font(.system(size: 12))
          .foregroundStyle(PixBrand.textOnDarkSecondary)
      }
      Spacer()
    }
    .padding(14)
    .background(PixBrand.panelSecondary)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 16).stroke(PixBrand.borderOnDark, lineWidth: 1))
    .contentShape(Rectangle())
    .onTapGesture(perform: action)
  }
}

private enum HelpTopic {
  case glossary
  case forgotPassword
  case register

  var titleKey: String {
    switch self {
    case .glossary:
      return "help.card.glossary.title"
    case .forgotPassword:
      return "help.card.forgotPassword.title"
    case .register:
      return "help.card.register.title"
    }
  }
}

private struct GlossaryListView: View {
  @EnvironmentObject private var settings: AppSettings
  @State private var query: String = ""
  @State private var expanded: Set<GlossaryCategory> = Set(GlossaryCategory.allCases)

  private var visibleCategories: [GlossaryCategory] {
    GlossaryCategory.allCases.filter(\.isVisibleInCurrentBuild)
  }

  private var searchHint: String {
    if AppFeatureFlags.videoEnabled {
      return l10n("help.glossary.searchHint.video")
    }
    return l10n("help.glossary.searchHint")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 10) {
        Text(l10n("help.glossary.heading"))
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(PixBrand.textOnDark)

        searchField

        Text(searchHint)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(PixBrand.textOnDarkSecondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(16)
      .background(PixBrand.panelSecondary)
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 16).stroke(PixBrand.borderOnDark, lineWidth: 1))

      ForEach(visibleCategories, id: \.self) { category in
        let items = itemsForCategory(category)
        if !items.isEmpty {
          DisclosureGroup(
            isExpanded: Binding(
              get: { expanded.contains(category) },
              set: { newValue in
                if newValue {
                  expanded.insert(category)
                } else {
                  expanded.remove(category)
                }
              }
            )
          ) {
            VStack(spacing: 10) {
              ForEach(items) { item in
                HelpInfoCard(icon: item.icon, title: l10n(item.termKey), text: l10n(item.descriptionKey))
              }
            }
            .padding(.top, 10)
          } label: {
            HStack {
              Text(l10n(category.titleKey))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PixBrand.textOnDark)
              Spacer()
              Text("\(items.count)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(PixBrand.textOnDarkSecondary)
            }
          }
          .padding(14)
          .background(PixBrand.panel)
          .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
          .overlay(RoundedRectangle(cornerRadius: 16).stroke(PixBrand.borderOnDark, lineWidth: 1))
        }
      }
    }
    .dismissKeyboardOnTap()
  }

  private var searchField: some View {
    HStack(spacing: 10) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(PixBrand.textOnDarkSecondary)
      TextField(l10n("help.glossary.searchPlaceholder"), text: $query)
        .textInputAutocapitalization(.never)
        .disableAutocorrection(true)
        .submitLabel(.done)
        .onSubmit {
          hideSystemKeyboard()
        }
        .foregroundStyle(PixBrand.textOnDark)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(PixBrand.panel)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(PixBrand.borderOnDark, lineWidth: 1))
  }

  private func itemsForCategory(_ category: GlossaryCategory) -> [GlossaryItem] {
    let q = normalizedForSearch(query)
    let all = GlossaryItem.all.filter { $0.category == category }
    guard !q.isEmpty else { return all }
    return all.filter { item in
      let hay = normalizedForSearch([l10n(item.termKey), l10n(item.descriptionKey), item.keywords.joined(separator: " ")].joined(separator: " "))
      return hay.contains(q)
    }
  }

  private func normalizedForSearch(_ value: String) -> String {
    value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
  }

  private enum GlossaryCategory: String, CaseIterable, Hashable {
    case camera
    case galleryUpload
    case floorplan
    case video
    case backend

    var titleKey: String {
      switch self {
      case .camera: return "help.glossary.category.camera"
      case .galleryUpload: return "help.glossary.category.galleryUpload"
      case .floorplan: return "help.glossary.category.floorplan"
      case .video: return "help.glossary.category.video"
      case .backend: return "help.glossary.category.backend"
      }
    }

    var isVisibleInCurrentBuild: Bool {
      switch self {
      case .video:
        return AppFeatureFlags.videoEnabled
      default:
        return true
      }
    }
  }

  private struct GlossaryItem: Identifiable, Hashable {
    let id: String
    let category: GlossaryCategory
    let icon: String
    let termKey: String
    let descriptionKey: String
    let keywords: [String]

    static let all: [GlossaryItem] = [
      // Kamera (Foto)
      GlossaryItem(
        id: "camera:bracketing",
        category: .camera,
        icon: "square.stack.3d.up",
        termKey: "help.glossary.item.camera.bracketing.term",
        descriptionKey: "help.glossary.item.camera.bracketing.desc",
        keywords: ["hdr", "ev", "serie", "reihe"]
      ),
      GlossaryItem(
        id: "camera:ev",
        category: .camera,
        icon: "slider.horizontal.3",
        termKey: "help.glossary.item.camera.ev.term",
        descriptionKey: "help.glossary.item.camera.ev.desc",
        keywords: ["exposure", "belichtung"]
      ),
      GlossaryItem(
        id: "camera:raw",
        category: .camera,
        icon: "camera.aperture",
        termKey: "help.glossary.item.camera.raw.term",
        descriptionKey: "help.glossary.item.camera.raw.desc",
        keywords: ["dng", "jpeg", "heif", "format"]
      ),
      GlossaryItem(
        id: "camera:locks",
        category: .camera,
        icon: "viewfinder",
        termKey: "help.glossary.item.camera.locks.term",
        descriptionKey: "help.glossary.item.camera.locks.desc",
        keywords: ["af", "focus", "lock"]
      ),
      GlossaryItem(
        id: "camera:wblevin",
        category: .camera,
        icon: "thermometer.medium",
        termKey: "help.glossary.item.camera.wb.term",
        descriptionKey: "help.glossary.item.camera.wb.desc",
        keywords: ["wb", "kelvin", "farbe"]
      ),
      GlossaryItem(
        id: "camera:overlays",
        category: .camera,
        icon: "level",
        termKey: "help.glossary.item.camera.overlays.term",
        descriptionKey: "help.glossary.item.camera.overlays.desc",
        keywords: ["grid", "histogram", "level"]
      ),
      GlossaryItem(
        id: "camera:eq",
        category: .camera,
        icon: "checkmark.seal",
        termKey: "help.glossary.item.camera.eq.term",
        descriptionKey: "help.glossary.item.camera.eq.desc",
        keywords: ["quality", "belichtung", "indikator"]
      ),
      GlossaryItem(
        id: "camera:remote",
        category: .camera,
        icon: "dot.radiowaves.left.and.right",
        termKey: "help.glossary.item.camera.remote.term",
        descriptionKey: "help.glossary.item.camera.remote.desc",
        keywords: ["bluetooth", "ausloeser", "volume"]
      ),

      // Galerie & Upload
      GlossaryItem(
        id: "gallery:series",
        category: .galleryUpload,
        icon: "photo.stack",
        termKey: "help.glossary.item.gallery.series.term",
        descriptionKey: "help.glossary.item.gallery.series.desc",
        keywords: ["bracketing", "reihe"]
      ),
      GlossaryItem(
        id: "gallery:roomfloor",
        category: .galleryUpload,
        icon: "door.left.hand.open",
        termKey: "help.glossary.item.gallery.roomFloor.term",
        descriptionKey: "help.glossary.item.gallery.roomFloor.desc",
        keywords: ["taxonomy", "roompicker", "etage"]
      ),
      GlossaryItem(
        id: "gallery:job",
        category: .galleryUpload,
        icon: "briefcase",
        termKey: "help.glossary.item.gallery.job.term",
        descriptionKey: "help.glossary.item.gallery.job.desc",
        keywords: ["auftrag", "projekt"]
      ),
      GlossaryItem(
        id: "gallery:upload",
        category: .galleryUpload,
        icon: "arrow.up.circle",
        termKey: "help.glossary.item.gallery.upload.term",
        descriptionKey: "help.glossary.item.gallery.upload.desc",
        keywords: ["queue", "status"]
      ),

      // Grundriss
      GlossaryItem(
        id: "floorplan:scan",
        category: .floorplan,
        icon: "cube.transparent",
        termKey: "help.glossary.item.floorplan.scan.term",
        descriptionKey: "help.glossary.item.floorplan.scan.desc",
        keywords: ["lidar", "usdz", "mesh", "segments"]
      ),
      GlossaryItem(
        id: "floorplan:review",
        category: .floorplan,
        icon: "checkmark.circle",
        termKey: "help.glossary.item.floorplan.review.term",
        descriptionKey: "help.glossary.item.floorplan.review.desc",
        keywords: ["confirm", "rescan"]
      ),
      GlossaryItem(
        id: "floorplan:composer",
        category: .floorplan,
        icon: "rectangle.3.group",
        termKey: "help.glossary.item.floorplan.composer.term",
        descriptionKey: "help.glossary.item.floorplan.composer.desc",
        keywords: ["editor", "dock", "snap", "tuer"]
      ),
      GlossaryItem(
        id: "floorplan:doors",
        category: .floorplan,
        icon: "door.left.hand.open",
        termKey: "help.glossary.item.floorplan.doors.term",
        descriptionKey: "help.glossary.item.floorplan.doors.desc",
        keywords: ["door", "opening"]
      ),
      GlossaryItem(
        id: "floorplan:route",
        category: .floorplan,
        icon: "figure.walk",
        termKey: "help.glossary.item.floorplan.route.term",
        descriptionKey: "help.glossary.item.floorplan.route.desc",
        keywords: ["route", "path"]
      ),
      GlossaryItem(
        id: "floorplan:export",
        category: .floorplan,
        icon: "square.and.arrow.up",
        termKey: "help.glossary.item.floorplan.export.term",
        descriptionKey: "help.glossary.item.floorplan.export.desc",
        keywords: ["pdf", "png", "share"]
      ),

      // Video
      GlossaryItem(
        id: "video:main",
        category: .video,
        icon: "video",
        termKey: "help.glossary.item.video.main.term",
        descriptionKey: "help.glossary.item.video.main.desc",
        keywords: ["4k", "30fps", "hevc", "mov"]
      ),
      GlossaryItem(
        id: "video:lock",
        category: .video,
        icon: "lock.fill",
        termKey: "help.glossary.item.video.lock.term",
        descriptionKey: "help.glossary.item.video.lock.desc",
        keywords: ["exposure", "wb", "focus", "fix"]
      ),
      GlossaryItem(
        id: "video:framing",
        category: .video,
        icon: "aspectratio",
        termKey: "help.glossary.item.video.framing.term",
        descriptionKey: "help.glossary.item.video.framing.desc",
        keywords: ["crop", "portrait", "social", "9:16", "16:9"]
      ),
      GlossaryItem(
        id: "video:zoom",
        category: .video,
        icon: "plus.magnifyingglass",
        termKey: "help.glossary.item.video.zoom.term",
        descriptionKey: "help.glossary.item.video.zoom.desc",
        keywords: ["ultraweit", "tele", "brennweite"]
      ),
      GlossaryItem(
        id: "video:review",
        category: .video,
        icon: "play.rectangle",
        termKey: "help.glossary.item.video.review.term",
        descriptionKey: "help.glossary.item.video.review.desc",
        keywords: ["review", "approve"]
      ),

      // Backend / Paket
      GlossaryItem(
        id: "backend:upj",
        category: .backend,
        icon: "doc.badge.gearshape",
        termKey: "help.glossary.item.backend.upj.term",
        descriptionKey: "help.glossary.item.backend.upj.desc",
        keywords: ["json", "protocol", "pipeline"]
      ),
      GlossaryItem(
        id: "backend:storage",
        category: .backend,
        icon: "internaldrive",
        termKey: "help.glossary.item.backend.storage.term",
        descriptionKey: "help.glossary.item.backend.storage.desc",
        keywords: ["application support", "storage", "files"]
      )
    ]
  }

  private func l10n(_ key: String) -> String {
    settings.localized(key)
  }
}

private struct HelpDetailCard: View {
  let topic: HelpTopic
  @EnvironmentObject private var settings: AppSettings

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(l10n(topic.titleKey))
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(PixBrand.textOnDark)

      Text(detailText)
        .font(.system(size: 13))
        .foregroundStyle(PixBrand.textOnDarkSecondary)
        .fixedSize(horizontal: false, vertical: true)

      Text(l10n("help.detail.status"))
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(PixBrand.textOnDarkSecondary)
        .padding(.top, 4)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(PixBrand.panelSecondary)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 16).stroke(PixBrand.borderOnDark, lineWidth: 1))
  }

  private var detailText: String {
    switch topic {
    case .glossary:
      return l10n("help.detail.glossary")
    case .forgotPassword:
      return l10n("help.detail.forgotPassword")
    case .register:
      return l10n("help.detail.register")
    }
  }

  private func l10n(_ key: String) -> String {
    settings.localized(key)
  }
}
