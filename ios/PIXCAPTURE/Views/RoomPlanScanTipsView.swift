import SwiftUI

struct RoomPlanScanTipsView: View {
  let roomName: String
  let floorName: String
  let onCancel: () -> Void
  let onStart: () -> Void

  private struct Tip: Identifiable {
    let id = UUID()
    let symbol: String
    let text: String
  }

  private var tips: [Tip] {
    [
      Tip(symbol: "lightbulb", text: "Lichter einschalten (mindestens ca. 50 Lux)."),
      Tip(symbol: "pause.fill", text: "Scan nach jedem Raum stoppen und auf derselben Etage bleiben."),
      Tip(symbol: "door.left.hand.closed", text: "Türen schließen, wenn möglich, damit der Raum eine geschlossene Form ergibt."),
      Tip(symbol: "arrow.uturn.left", text: "Wenn Tracking instabil ist: kurz langsamer werden, auf Ecken/Wände richten, dann neu ausrichten."),
      Tip(symbol: "exclamationmark.triangle.fill", text: "Sehr große Flächen lieber in mehreren Scans aufnehmen (Performance / Genauigkeit)."),
    ]
  }

  var body: some View {
    ZStack {
      Color(red: 0.20, green: 0.20, blue: 0.20)
        .ignoresSafeArea()

      VStack(spacing: 0) {
        HStack {
          Button(action: onCancel) {
            Image(systemName: "chevron.left")
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(.white.opacity(0.9))
              .frame(width: 42, height: 42)
              .background(Color.white.opacity(0.10))
              .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
          }
          Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)

        Spacer()

        VStack(alignment: .leading, spacing: 22) {
          VStack(alignment: .leading, spacing: 8) {
            Text("Für beste Ergebnisse…")
              .font(.system(size: 34, weight: .semibold))
              .foregroundStyle(.white)
              .fixedSize(horizontal: false, vertical: true)

            Text("\(roomName) · \(floorName)")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(.white.opacity(0.7))
              .lineLimit(1)
          }

          VStack(alignment: .leading, spacing: 18) {
            ForEach(tips) { tip in
              HStack(alignment: .top, spacing: 14) {
                Image(systemName: tip.symbol)
                  .font(.system(size: 18, weight: .semibold))
                  .foregroundStyle(.white.opacity(0.85))
                  .frame(width: 26)
                  .padding(.top, 2)

                Text(tip.text)
                  .font(.system(size: 17, weight: .medium))
                  .foregroundStyle(.white.opacity(0.9))
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
          }
        }
        .padding(.horizontal, 26)

        Spacer()

        Button(action: onStart) {
          Text("Starten")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.black.opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
              RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 28)
      }
    }
  }
}
