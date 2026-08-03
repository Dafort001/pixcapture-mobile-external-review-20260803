import Testing
@testable import PIXCAPTURE

struct CompanionPackageReceiptTests {
  private let packageID = "pkg_test"
  private let sizeBytes = 12_345
  private let sha256 = String(repeating: "a", count: 64)

  @Test("Companion receipt accepts only the exact package identity, size and checksum")
  func exactReceiptIsAccepted() throws {
    try CompanionPackageReceiptValidator.validate(
      receipt(),
      expectedPackageId: packageID,
      expectedSizeBytes: sizeBytes,
      expectedSHA256: sha256.uppercased()
    )
  }

  @Test("Companion receipt rejects a checksum mismatch")
  func checksumMismatchIsRejected() {
    #expect(throws: CompanionPackageReceiptValidationError.wrongChecksum) {
      try CompanionPackageReceiptValidator.validate(
        receipt(sha256: String(repeating: "b", count: 64)),
        expectedPackageId: packageID,
        expectedSizeBytes: sizeBytes,
        expectedSHA256: sha256
      )
    }
  }

  @Test("Companion receipt rejects an incorrect byte count")
  func sizeMismatchIsRejected() {
    #expect(
      throws: CompanionPackageReceiptValidationError.wrongSize(
        received: sizeBytes - 1,
        expected: sizeBytes
      )
    ) {
      try CompanionPackageReceiptValidator.validate(
        receipt(sizeBytes: sizeBytes - 1),
        expectedPackageId: packageID,
        expectedSizeBytes: sizeBytes,
        expectedSHA256: sha256
      )
    }
  }

  @Test("Companion receipt rejects receiver warnings")
  func warningsAreRejected() {
    #expect(
      throws: CompanionPackageReceiptValidationError.warnings(["sha256_mismatch"])
    ) {
      try CompanionPackageReceiptValidator.validate(
        receipt(warnings: ["sha256_mismatch"]),
        expectedPackageId: packageID,
        expectedSizeBytes: sizeBytes,
        expectedSHA256: sha256
      )
    }
  }

  private func receipt(
    sizeBytes: Int? = nil,
    sha256: String? = nil,
    warnings: [String] = []
  ) -> CompanionPackageReceiveResponse {
    CompanionPackageReceiveResponse(
      accepted: true,
      packageId: packageID,
      filename: "test.pixcapturepkg",
      sizeBytes: sizeBytes ?? self.sizeBytes,
      sha256: sha256 ?? self.sha256,
      storedPath: "/tmp/test.pixcapturepkg",
      warnings: warnings
    )
  }
}
