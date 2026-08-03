import SwiftUI

struct OnboardingView: View {
  var onDone: () -> Void
  var onLogin: () -> Void

  private enum Palette {
    static let background = Color.black
    static let primary = Color(red: 42.0 / 255.0, green: 63.0 / 255.0, blue: 104.0 / 255.0)
    static let blue = Color(red: 108.0 / 255.0, green: 168.0 / 255.0, blue: 200.0 / 255.0)
    static let orange = Color(red: 209.0 / 255.0, green: 94.0 / 255.0, blue: 64.0 / 255.0)
    static let pink = Color(red: 227.0 / 255.0, green: 163.0 / 255.0, blue: 174.0 / 255.0)
    static let panel = Color.white.opacity(0.07)
    static let border = Color.white.opacity(0.13)
  }

  var body: some View {
    GeometryReader { geometry in
      let contentWidth = min(max(geometry.size.width - 40, 0), 460)

      ZStack {
        Palette.background
          .ignoresSafeArea()

        ScrollView(showsIndicators: false) {
          VStack(alignment: .leading, spacing: 18) {
            Image("AppLogo")
              .resizable()
              .renderingMode(.original)
              .scaledToFit()
              .frame(width: min(contentWidth * 0.62, 250))
              .frame(maxWidth: .infinity, alignment: .center)
              .padding(.bottom, 6)

            Text("PixCapture zuerst im Web einrichten")
              .font(.pixInter(size: 23, weight: .semibold))
              .foregroundStyle(Color.white.opacity(0.94))

            Text("Diese App funktioniert zusammen mit PIXCAPTURE.APP. Registriere dich zuerst auf der Webseite, warte auf die Freischaltung und melde dich danach hier mit derselben E-Mail und deinem selbst vergebenen Passwort an.")
              .font(.pixInter(size: 14, weight: .regular))
              .foregroundStyle(Color.white.opacity(0.72))
              .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
              onboardingRow(
                number: "1",
                title: "Auf der Webseite registrieren",
                body: "Gehe zuerst auf PIXCAPTURE.APP und erstelle dort dein Benutzerkonto. E-Mail und Passwort legst du in der Web-Anwendung selbst fest.",
                color: Palette.blue
              )
              onboardingRow(
                number: "2",
                title: "Freischaltung abwarten",
                body: "Dein Web-Konto muss fuer PixCapture freigeschaltet sein. Erst danach kann die App deine Auftraege und Uploads korrekt zuordnen.",
                color: Palette.orange
              )
              onboardingRow(
                number: "3",
                title: "Auf dem iPhone anmelden",
                body: "Melde dich in dieser App mit derselben E-Mail und demselben Passwort an, das du auf PIXCAPTURE.APP erstellt hast.",
                color: Palette.pink
              )
              onboardingRow(
                number: "4",
                title: "Upload am Rechner verbinden",
                body: "Wenn du Aufnahmen übertragen möchtest, öffnest du den gewünschten Upload-Weg in der Web-App und scannst dessen QR-Code. Dieser QR-Code verbindet nur diese eine Übertragung.",
                color: Palette.blue
              )
              onboardingRow(
                number: "5",
                title: "Dann aufnehmen",
                body: "Danach fotografierst oder erstellst du Grundrisse. Die Daten koennen dann dem richtigen Kundenauftrag zugeordnet und hochgeladen werden.",
                color: Palette.orange
              )
            }

            VStack(spacing: 10) {
              Link(destination: URL(string: "https://pixcapture.app")!) {
                Text("PIXCAPTURE.APP öffnen")
                  .font(.pixInter(size: 16, weight: .semibold))
                  .foregroundStyle(Color.black.opacity(0.82))
                  .frame(maxWidth: .infinity, minHeight: 50)
                  .background(Palette.orange)
                  .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
              }
              .buttonStyle(.plain)

              Button {
                onLogin()
              } label: {
                Text("Mit Web-Konto anmelden")
                  .font(.pixInter(size: 16, weight: .semibold))
                  .foregroundStyle(Palette.blue)
                  .frame(maxWidth: .infinity, minHeight: 46)
                  .background(Palette.blue.opacity(0.10))
                  .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
              }
              .buttonStyle(.plain)

              Button {
                onDone()
              } label: {
                Text("Einrichtung verstanden")
                  .font(.pixInter(size: 14, weight: .semibold))
                  .foregroundStyle(Color.white.opacity(0.62))
                  .frame(maxWidth: .infinity, minHeight: 44)
              }
              .buttonStyle(.plain)
            }
            .padding(.top, 6)
          }
          .frame(width: contentWidth, alignment: .leading)
          .frame(maxWidth: .infinity)
          .padding(.top, max(geometry.safeAreaInsets.top + 28, 44))
          .padding(.bottom, max(geometry.safeAreaInsets.bottom + 28, 40))
          .padding(.horizontal, 20)
        }
      }
    }
  }

  private func onboardingRow(number: String, title: String, body: String, color: Color) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Text(number)
        .font(.pixInter(size: 13, weight: .semibold))
        .foregroundStyle(Color.black.opacity(0.82))
        .frame(width: 28, height: 28)
        .background(color)
        .clipShape(Circle())

      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.pixInter(size: 14, weight: .semibold))
          .foregroundStyle(Color.white.opacity(0.92))
        Text(body)
          .font(.pixInter(size: 12, weight: .regular))
          .foregroundStyle(Color.white.opacity(0.66))
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(13)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Palette.panel)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Palette.border, lineWidth: 1)
    )
  }
}
