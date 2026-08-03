import SwiftUI
import SceneKit
import UIKit

struct RoomPlanReviewScreen: View {
  let usdzURL: URL
  let onRescan: () -> Void
  let onContinue: () -> Void

  private enum ReviewMode: String, CaseIterable, Identifiable {
    case model3D = "3D"
    case floorplan = "Grundriss"

    var id: String { rawValue }
  }

  @State private var scene: SCNScene? = nil
  @State private var floorplanImage: UIImage? = nil
  @State private var segmentsSummary: SegmentsSummary? = nil
  @State private var mode: ReviewMode = .model3D
  @State private var hasLoadedAssets = false

  var body: some View {
    ZStack {
      Color(.systemGray6).ignoresSafeArea()

      VStack(spacing: 14) {
        HStack {
          Text("Scan prüfen")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.85))
          Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)

        VStack(spacing: 12) {
          Picker("", selection: $mode) {
            ForEach(ReviewMode.allCases) { mode in
              Text(mode.rawValue).tag(mode)
            }
          }
          .pickerStyle(.segmented)
          .padding(.horizontal, 2)

          Group {
            switch mode {
            case .model3D:
              ZStack {
                modelPreviewBackground
                SceneView(
                  scene: scene,
                  options: [.allowsCameraControl, .autoenablesDefaultLighting]
                )
                .padding(6)
              }
            case .floorplan:
              ZStack {
                Color.white
                floorplanView()
              }
            }
          }
          .frame(maxWidth: .infinity)
          .frame(height: 320)
          .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
          .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.06), lineWidth: 1))
          .onAppear {
            loadAssetsIfNeeded()
          }

          VStack(alignment: .leading, spacing: 8) {
            Text("Was prüfen?")
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(Color.black.opacity(0.82))
            Text(mode == .model3D
                 ? "• Sind alle Wände sichtbar?\n• Gibt es große Löcher/fehlende Bereiche?\n• Wenn etwas fehlt: Scan wiederholen."
                 : "• Sind die Wände geschlossen (keine großen Lücken)?\n• Stimmen grobe Proportionen?\n• Wenn etwas fehlt: Scan wiederholen.")
              .font(.system(size: 12))
              .foregroundStyle(Color.black.opacity(0.62))
              .fixedSize(horizontal: false, vertical: true)
          }
          .padding(14)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color.white)
          .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
          .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.06), lineWidth: 1))

          if let segmentsSummary {
            VStack(alignment: .leading, spacing: 8) {
              Text("Erkannte Maße")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.82))

              Text(
                "Fläche ca.: \(formatted(segmentsSummary.areaSqmApprox)) m² · Umfang: \(formatted(segmentsSummary.perimeterMeters)) m\nBreite: \(formatted(segmentsSummary.widthMeters)) m · Tiefe: \(formatted(segmentsSummary.depthMeters)) m\nTüren: \(segmentsSummary.doorCount) · Öffnungen: \(segmentsSummary.openingCount) · Fenster: \(segmentsSummary.windowCount)"
              )
              .font(.system(size: 12))
              .foregroundStyle(Color.black.opacity(0.62))
              .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.06), lineWidth: 1))
          }
        }
        .padding(.horizontal, 18)

        Spacer()

        HStack(spacing: 12) {
          Button(action: onRescan) {
            Text("Scan wiederholen")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(Color.black.opacity(0.75))
              .frame(maxWidth: .infinity)
              .padding(.vertical, 12)
              .background(Color.white)
              .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
              .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.08), lineWidth: 1))
          }

          Button(action: onContinue) {
            Text("Weiter")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(.white)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 12)
              .background(Color(red: 0.29, green: 0.35, blue: 0.29))
              .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
          }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 24)
      }
    }
  }

  private func floorplanView() -> some View {
    Group {
      if let floorplanImage {
        Image(uiImage: floorplanImage)
          .resizable()
          .scaledToFit()
          .padding(10)
      } else {
        VStack(spacing: 8) {
          Image(systemName: "square.dashed")
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.25))
          Text("Grundriss nicht verfügbar")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.55))
          Text("Falls du gerade gescannt hast: bitte kurz warten oder erneut scannen.")
            .font(.system(size: 12))
            .foregroundStyle(Color.black.opacity(0.45))
            .multilineTextAlignment(.center)
        }
        .padding(16)
      }
    }
  }

  private var modelPreviewBackground: some View {
    LinearGradient(
      colors: [
        Color(red: 0.92, green: 0.95, blue: 0.99),
        Color(red: 0.86, green: 0.90, blue: 0.95)
      ],
      startPoint: .top,
      endPoint: .bottom
    )
  }

  private func loadAssetsIfNeeded() {
    guard !hasLoadedAssets else { return }
    hasLoadedAssets = true

    let loaded = (try? SCNScene(url: usdzURL, options: nil))
    if let loaded {
      loaded.background.contents = UIColor(red: 0.90, green: 0.93, blue: 0.97, alpha: 1.0)
    }
    scene = loaded
    loadFloorplanIfPresent()
  }

  private func loadFloorplanIfPresent() {
    let url = usdzURL.deletingLastPathComponent().appendingPathComponent("floorplan.png")
    let segmentsURL = usdzURL.deletingLastPathComponent().appendingPathComponent("segments.json")

    if FileManager.default.fileExists(atPath: segmentsURL.path),
       let data = try? Data(contentsOf: segmentsURL),
       let decoded = try? JSONDecoder().decode(FloorplanSegmentsFile.self, from: data) {
      let normalized = decoded.normalizedForDisplay()
      segmentsSummary = SegmentsSummary(
        areaSqmApprox: normalized.metrics.areaSqmApprox,
        perimeterMeters: normalized.metrics.perimeterMeters,
        widthMeters: normalized.metrics.widthMeters,
        depthMeters: normalized.metrics.depthMeters,
        doorCount: normalized.doors?.count ?? 0,
        openingCount: normalized.openings?.count ?? 0,
        windowCount: normalized.windows?.count ?? 0
      )
    } else {
      segmentsSummary = nil
    }

    guard FileManager.default.fileExists(atPath: url.path) else {
      floorplanImage = nil
      return
    }
    let img = UIImage(contentsOfFile: url.path)

    // Legacy compatibility: older exports were mirrored vs. the 3D USDZ preview.
    // New exports (segments.json v4+) are already fixed at the source.
    if FileManager.default.fileExists(atPath: segmentsURL.path),
       let data = try? Data(contentsOf: segmentsURL),
       let decoded = try? JSONDecoder().decode(FloorplanSegmentsFile.self, from: data),
       decoded.version <= 3,
       let img {
      floorplanImage = img.flippedHorizontally()
      return
    }

    floorplanImage = img
  }

  private func formatted(_ value: Double) -> String {
    String(format: "%.1f", value)
  }

  private struct SegmentsSummary {
    let areaSqmApprox: Double
    let perimeterMeters: Double
    let widthMeters: Double
    let depthMeters: Double
    let doorCount: Int
    let openingCount: Int
    let windowCount: Int
  }
}

private extension UIImage {
  func flippedHorizontally() -> UIImage? {
    UIGraphicsBeginImageContextWithOptions(size, false, scale)
    defer { UIGraphicsEndImageContext() }
    guard let ctx = UIGraphicsGetCurrentContext(), let cg = cgImage else { return nil }

    ctx.translateBy(x: size.width, y: 0)
    ctx.scaleBy(x: -1, y: 1)
    ctx.draw(cg, in: CGRect(origin: .zero, size: size))
    return UIGraphicsGetImageFromCurrentImageContext()
  }
}
