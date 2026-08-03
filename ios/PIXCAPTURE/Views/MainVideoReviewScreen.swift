import AVKit
import SwiftUI
import UIKit

struct MainVideoReviewScreen: View {
  let videoURL: URL
  let onDiscard: () -> Void
  let onContinue: () -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var player: AVPlayer

  private var isPad: Bool {
    UIDevice.current.userInterfaceIdiom == .pad
  }

  init(
    videoURL: URL,
    onDiscard: @escaping () -> Void,
    onContinue: @escaping () -> Void
  ) {
    self.videoURL = videoURL
    self.onDiscard = onDiscard
    self.onContinue = onContinue
    _player = State(initialValue: AVPlayer(url: videoURL))
  }

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      VideoPlayer(player: player)
        .ignoresSafeArea()

      VStack(spacing: isPad ? 14 : 10) {
        topBar
          .frame(maxWidth: isPad ? 920 : .infinity, alignment: .leading)
        Spacer()
        bottomBar
          .frame(maxWidth: isPad ? 700 : .infinity)
      }
      .frame(maxWidth: .infinity)
      .padding(.horizontal, isPad ? 28 : 16)
      .padding(.top, isPad ? 20 : 14)
      .padding(.bottom, isPad ? 32 : 24)
    }
    .onAppear {
      player.play()
    }
    .onDisappear {
      player.pause()
    }
  }

  private var topBar: some View {
    HStack(spacing: isPad ? 14 : 12) {
      Button {
        dismiss()
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: isPad ? 18 : 14, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: isPad ? 44 : 36, height: isPad ? 44 : 36)
          .background(Color.black.opacity(0.45))
          .clipShape(Circle())
      }

      VStack(alignment: .leading, spacing: isPad ? 3 : 2) {
        Text("Video prüfen")
          .font(.system(size: isPad ? 18 : 15, weight: .semibold))
          .foregroundStyle(.white)
        Text(videoURL.lastPathComponent)
          .font(.system(size: isPad ? 14 : 12, weight: .medium))
          .foregroundStyle(.white.opacity(0.7))
          .lineLimit(1)
      }

      Spacer()
    }
  }

  private var bottomBar: some View {
    VStack(spacing: isPad ? 16 : 12) {
      Button {
        onContinue()
      } label: {
        Text("Übernehmen")
          .font(.system(size: isPad ? 18 : 15, weight: .semibold))
          .foregroundStyle(.black)
          .frame(maxWidth: .infinity)
          .padding(.vertical, isPad ? 18 : 14)
          .background(Color.white)
          .clipShape(RoundedRectangle(cornerRadius: isPad ? 18 : 14, style: .continuous))
      }

      Button(role: .destructive) {
        onDiscard()
      } label: {
        Text("Verwerfen und neu aufnehmen")
          .font(.system(size: isPad ? 15 : 13, weight: .semibold))
          .foregroundStyle(Color.red.opacity(0.95))
          .frame(maxWidth: .infinity)
          .padding(.vertical, isPad ? 15 : 12)
          .background(Color.black.opacity(0.35))
          .clipShape(RoundedRectangle(cornerRadius: isPad ? 18 : 14, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: isPad ? 18 : 14, style: .continuous)
              .stroke(Color.red.opacity(0.35), lineWidth: 1)
          )
      }
    }
  }
}
