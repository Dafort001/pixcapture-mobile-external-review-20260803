import Foundation
import Combine
import AVFoundation

@MainActor
final class VolumeShutterListener: ObservableObject {
  // Emits whenever the system volume changes (e.g. volume buttons / BT remotes).
  let didTrigger = PassthroughSubject<Void, Never>()

  var keepVolumeStable: Bool = true
  var volumeReset: ((Float) -> Void)?

  private var observation: NSKeyValueObservation?
  private var lastVolume: Float?
  private var baselineVolume: Float?
  private var lastTriggerAt: Date = .distantPast
  private var suppressEventsUntil: Date = .distantPast
  private let minimumIntervalSeconds: TimeInterval

  init(minimumIntervalSeconds: TimeInterval = 0.45) {
    self.minimumIntervalSeconds = minimumIntervalSeconds
  }

  func start() {
    guard observation == nil else { return }

    let session = AVAudioSession.sharedInstance()
    do {
      // Keep other audio (e.g. Music) playing; we only need volume change notifications.
      try session.setCategory(.playback, options: [.mixWithOthers])
      try session.setActive(true)
    } catch {
      // If this fails we simply won't receive volume changes reliably.
    }

    lastVolume = session.outputVolume
    baselineVolume = safeBaseline(for: session.outputVolume)
    if keepVolumeStable, let baselineVolume, let volumeReset {
      // Ensure we start away from 0/100 so presses always generate volume changes.
      suppressEventsUntil = Date().addingTimeInterval(0.5)
      Task { @MainActor in
        try? await Task.sleep(nanoseconds: 120_000_000)
        volumeReset(baselineVolume)
      }
    }
    observation = session.observe(\.outputVolume, options: [.new]) { [weak self] session, change in
      guard let self else { return }
      let newValue = change.newValue ?? session.outputVolume
      Task { @MainActor in
        self.handle(volume: newValue)
      }
    }
  }

  func stop() {
    observation?.invalidate()
    observation = nil
    lastVolume = nil
    baselineVolume = nil
    suppressEventsUntil = .distantPast

    do {
      try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    } catch {
      // Ignore.
    }
  }

  private func handle(volume newValue: Float) {
    let now = Date()
    if now < suppressEventsUntil {
      lastVolume = newValue
      return
    }

    if let lastVolume, abs(newValue - lastVolume) < 0.0001 {
      return
    }
    lastVolume = newValue

    guard now.timeIntervalSince(lastTriggerAt) >= minimumIntervalSeconds else { return }
    lastTriggerAt = now

    didTrigger.send(())

    guard keepVolumeStable, let baselineVolume, let volumeReset else { return }
    suppressEventsUntil = now.addingTimeInterval(0.6)
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 100_000_000)
      volumeReset(baselineVolume)
    }
  }

  private func safeBaseline(for current: Float) -> Float {
    // outputVolume: 0.0 ... 1.0. Keep away from extremes so +/- always produces a change.
    if current <= 0.05 || current >= 0.95 {
      return 0.5
    }
    return min(max(current, 0.15), 0.85)
  }
}
