import Testing
@testable import PIXCAPTURE

struct AuthQRClassifierTests {

  @Test("Upload connection QR JSON is not treated as an invalid login QR")
  @MainActor
  func detectsWebConnectJSONPayload() {
    let payload = #"{"schema":"pixcapture.connect-qr.v2","web_session_id":"sess_test_123"}"#

    #expect(AuthService.looksLikeWebConnectQR(payload))
    #expect(AuthService.parseMobileConnectToken(from: payload) == nil)
  }

  @Test("Upload connection QR URL is recognized by session query")
  @MainActor
  func detectsWebConnectURLSessionQuery() {
    let payload = "https://pixcapture.app/dashboard/app-connect?session=sess_test_123"

    #expect(AuthService.looksLikeWebConnectQR(payload))
    #expect(AuthService.parseMobileConnectToken(from: payload) == nil)
  }

  @Test("Mobile connect token URL remains a login pairing token")
  @MainActor
  func keepsMobileConnectURLAsPairingToken() {
    let payload = "pixcapture://connect?token=mobile_token_12345"

    #expect(!AuthService.looksLikeWebConnectQR(payload))
    #expect(AuthService.parseMobileConnectToken(from: payload) == "mobile_token_12345")
  }
}
