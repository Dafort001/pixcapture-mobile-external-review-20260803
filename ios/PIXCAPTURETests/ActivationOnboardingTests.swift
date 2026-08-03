import SwiftUI
import Testing
import UIKit
@testable import PIXCAPTURE

struct ActivationOnboardingTests {
  @Test("Greige text exceeds AAA contrast on the black login background")
  func greigeTextHasAccessibleContrast() throws {
    let textColor = UIColor(AppTheme.textOnDark)
    let components = try #require(rgbComponents(of: textColor))
    let contrast = (relativeLuminance(components) + 0.05) / 0.05

    #expect(contrast >= 7.0)
  }

  @Test("German guidance allows offline capture and describes both SMS stages")
  func germanActivationGuidanceUsesOfflineCaptureAndSms() {
    let offline = AppLocalizer.localized(
      "splash.onboarding.step1",
      language: .de
    )
    let registration = AppLocalizer.localized(
      "splash.onboarding.step2",
      language: .de
    )
    let approval = AppLocalizer.localized(
      "splash.onboarding.step3",
      language: .de
    )

    #expect(offline.contains("ohne Anmeldung fotografieren"))
    #expect(registration.contains("SMS-Code"))
    #expect(approval.contains("zweite SMS"))
    #expect(!registration.localizedCaseInsensitiveContains("per E-Mail"))
    #expect(!approval.localizedCaseInsensitiveContains("per E-Mail"))
  }

  @Test("English guidance allows offline capture and describes both SMS stages")
  func englishActivationGuidanceUsesOfflineCaptureAndSms() {
    let offline = AppLocalizer.localized(
      "splash.onboarding.step1",
      language: .en
    )
    let registration = AppLocalizer.localized(
      "splash.onboarding.step2",
      language: .en
    )
    let approval = AppLocalizer.localized(
      "splash.onboarding.step3",
      language: .en
    )

    #expect(offline.localizedCaseInsensitiveContains("capture without signing in"))
    #expect(registration.localizedCaseInsensitiveContains("SMS code"))
    #expect(approval.localizedCaseInsensitiveContains("second SMS"))
    #expect(!registration.localizedCaseInsensitiveContains("by email"))
    #expect(!approval.localizedCaseInsensitiveContains("by email"))
  }

  private func rgbComponents(of color: UIColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat)? {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
      return nil
    }
    return (red, green, blue)
  }

  private func relativeLuminance(
    _ components: (red: CGFloat, green: CGFloat, blue: CGFloat)
  ) -> CGFloat {
    let red = linearized(components.red)
    let green = linearized(components.green)
    let blue = linearized(components.blue)
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue
  }

  private func linearized(_ component: CGFloat) -> CGFloat {
    if component <= 0.04045 {
      return component / 12.92
    }
    return pow((component + 0.055) / 1.055, 2.4)
  }
}
