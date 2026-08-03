import SwiftUI

struct JobResumeSheet: View {
  private enum Palette {
    static let background = Color.black
    static let darkBlue = Color(red: 42.0 / 255.0, green: 63.0 / 255.0, blue: 104.0 / 255.0)
    static let lightBlue = Color(red: 108.0 / 255.0, green: 168.0 / 255.0, blue: 200.0 / 255.0)
    static let orange = Color(red: 209.0 / 255.0, green: 94.0 / 255.0, blue: 64.0 / 255.0)
    static let pink = Color(red: 227.0 / 255.0, green: 163.0 / 255.0, blue: 174.0 / 255.0)
    static let utilityText = Color.white.opacity(0.56)
    static let bodyText = Color.white.opacity(0.78)
    static let cardText = Color.black.opacity(0.78)
  }

  @Environment(\.dismiss) private var dismiss

  let snapshot: RecentJobSnapshot
  let onContinue: () -> Void
  let onChooseDifferent: () -> Void

  private let relativeFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter
  }()

  var body: some View {
    GeometryReader { geometry in
      let logoWidth = min(geometry.size.width * 0.56, 250.0)
      let cardWidth = min(max(geometry.size.width * 0.78, 260.0), 420.0)

      ZStack {
        Palette.background
          .ignoresSafeArea()

        VStack(spacing: 0) {
          HStack {
            Spacer()
          }
          .padding(.top, max(geometry.safeAreaInsets.top + 12.0, 20.0))
          .padding(.horizontal, 28)

          Spacer(minLength: max(24.0, geometry.size.height * 0.04))

          Image("AppLogo")
            .resizable()
            .renderingMode(.original)
            .scaledToFit()
            .frame(width: logoWidth)
            .accessibilityLabel("PixCapture Logo")

          VStack(spacing: 12) {
            Text("LETZTEN JOB FORTSETZEN")
              .font(inter(size: 22, weight: .light))
              .tracking(1.0)
              .foregroundStyle(.white)

            Text("Du warst kuerzlich noch in diesem Auftrag aktiv. Wenn es derselbe Termin ist, kannst du direkt weiterarbeiten. Sonst wechselst du einfach zu einem anderen oder neuen Job.")
              .font(inter(size: 14, weight: .light))
              .tracking(0.2)
              .multilineTextAlignment(.center)
              .foregroundStyle(Palette.utilityText)
              .frame(maxWidth: min(geometry.size.width - 56.0, 420.0))
          }
          .padding(.top, 34)

          VStack(spacing: 8) {
            Text(snapshot.job.name.uppercased())
              .font(inter(size: 20, weight: .light))
              .tracking(0.9)
              .foregroundStyle(Palette.cardText)
              .multilineTextAlignment(.center)
              .lineLimit(2)

            if let address = snapshot.job.propertyAddress,
               !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
              Text(address)
                .font(inter(size: 12, weight: .light))
                .tracking(0.2)
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.cardText.opacity(0.76))
                .frame(maxWidth: cardWidth - 40.0)
            }

            Text("Letzte Aktivitaet \(lastActivityText)")
              .font(inter(size: 12, weight: .light))
              .tracking(0.2)
              .foregroundStyle(Palette.darkBlue.opacity(0.96))
          }
          .padding(.horizontal, 20)
          .padding(.vertical, 20)
          .frame(width: cardWidth)
          .background(Palette.pink)
          .padding(.top, 38)

          VStack(spacing: 16) {
            Button {
              onContinue()
              dismiss()
            } label: {
              ZStack {
                Rectangle()
                  .fill(Palette.lightBlue)
                  .frame(width: cardWidth, height: 84)

                Text("MIT DIESEM JOB WEITER")
                  .font(inter(size: 19, weight: .light))
                  .tracking(0.9)
                  .foregroundStyle(Palette.darkBlue)
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
              onChooseDifferent()
              dismiss()
            } label: {
              ZStack {
                Rectangle()
                  .fill(Palette.orange)
                  .frame(width: cardWidth, height: 84)

                Text("ANDEREN ODER NEUEN JOB")
                  .font(inter(size: 18, weight: .light))
                  .tracking(0.8)
                  .foregroundStyle(Palette.cardText)
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
          .padding(.top, 24)

          Spacer(minLength: max(24.0, geometry.safeAreaInsets.bottom + 10.0))
        }
        .padding(.horizontal, 28)
      }
    }
    .interactiveDismissDisabled(true)
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }

  private var lastActivityText: String {
    relativeFormatter.localizedString(for: snapshot.lastActivityAt, relativeTo: Date())
  }

  private func inter(size: CGFloat, weight: Font.Weight = .regular) -> Font {
    .pixInter(size: size, weight: weight)
  }
}
