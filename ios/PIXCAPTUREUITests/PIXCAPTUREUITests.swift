//
//  PIXCAPTUREUITests.swift
//  PIXCAPTUREUITests
//
//  Created by Daniel Fortmann on 05.02.26.
//

import XCTest
import UIKit

final class PIXCAPTUREUITests: XCTestCase {
    private struct E2EConfig: Decodable {
        var email: String?
        var password: String?
        var browserCompanionPayload: String?
        var directCloudPayload: String?
        var cablePackagePayload: String?
        var jobId: String?
    }

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testOfflineCaptureEntryDoesNotRequireLogin() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--pixcapture-clear-auth",
            "-pixcapture.hasSeenFirstRunOnboarding", "false",
        ]
        app.launchEnvironment["PIXCAPTURE_CLEAR_AUTH"] = "1"

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        app.launch()

        let offlineButton = app.buttons["JETZT OHNE ANMELDUNG FOTOGRAFIEREN"]
        XCTAssertTrue(
            offlineButton.waitForExistence(timeout: 10),
            "Offline capture entry did not appear on first launch."
        )
        XCTAssertFalse(
            springboard.alerts.firstMatch.waitForExistence(timeout: 1),
            "Camera permission must not be requested before the user chooses a capture feature."
        )

        let loginButton = app.buttons["BEREITS FREIGESCHALTET? ANMELDEN"]
        var remainingScrollAttempts = 8
        while !loginButton.isHittable && remainingScrollAttempts > 0 {
            app.swipeUp()
            remainingScrollAttempts -= 1
        }

        XCTAssertTrue(
            loginButton.isHittable,
            "The onboarding page could not be scrolled to its final action."
        )
        XCTAssertLessThanOrEqual(
            loginButton.frame.maxY,
            app.frame.maxY - 20,
            "The final onboarding action overlaps the bottom safe area."
        )
        XCTAssertTrue(
            offlineButton.isHittable,
            "The primary offline action is not reachable after scrolling to the bottom."
        )

        offlineButton.tap()

        XCTAssertTrue(
            app.buttons["bottom.camera"].waitForExistence(timeout: 8),
            "The local start screen did not open without authentication."
        )
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    func testE2EMobileLoginCaptureAndDirectUploadSmoke() throws {
        let environment = ProcessInfo.processInfo.environment
        let fileConfig = loadE2EConfig()
        let email = e2eValue(environment["PIXCAPTURE_E2E_EMAIL"], fallback: fileConfig.email)
        let password = e2eValue(environment["PIXCAPTURE_E2E_PASSWORD"], fallback: fileConfig.password)
        let payload = e2eValue(environment["PIXCAPTURE_E2E_DIRECT_CLOUD_PAYLOAD"], fallback: fileConfig.directCloudPayload)
        guard !email.isEmpty, !password.isEmpty, !payload.isEmpty else {
            throw XCTSkip("PIXCAPTURE_E2E_EMAIL, PIXCAPTURE_E2E_PASSWORD, and PIXCAPTURE_E2E_DIRECT_CLOUD_PAYLOAD are required.")
        }

        let app = XCUIApplication()
        app.launchArguments = [
            "--pixcapture-clear-auth",
        ]
        app.launchEnvironment["PIXCAPTURE_CLEAR_AUTH"] = "1"

        addUIInterruptionMonitor(withDescription: "System permissions") { alert in
            for title in ["Allow", "OK", "Erlauben", "Fortfahren", "Continue", "Später", "Nicht jetzt"] {
                if alert.buttons[title].exists {
                    alert.buttons[title].tap()
                    return true
                }
            }
            if alert.buttons.count > 0 {
                alert.buttons.element(boundBy: 0).tap()
                return true
            }
            return false
        }

        app.launch()

        loginIfNeeded(in: app, email: email, password: password)
        openGallery(in: app)
        selectExistingGallerySeriesForUpload(in: app, expectedCount: 2)

        let localWifiMode = app.buttons["upload.mode.localWifi"]
        XCTAssertTrue(localWifiMode.waitForExistence(timeout: 8), "Direkt-in-die-Cloud upload mode did not appear.")
        if !localWifiMode.isSelected {
            localWifiMode.tap()
        }

        let localWifiInput = app.textFields["upload.connect.localWifi.input"]
        XCTAssertTrue(localWifiInput.waitForExistence(timeout: 8), "Direkt-in-die-Cloud QR input did not appear.")
        localWifiInput.tap()
        localWifiInput.typeText(typeableConnectPayload(payload))

        let startUpload = app.buttons["upload.connect.start.primary"].exists ? app.buttons["upload.connect.start.primary"] : (app.buttons["upload.connect.start.toolbar"].exists ? app.buttons["upload.connect.start.toolbar"] : app.buttons["Upload starten"])
        XCTAssertTrue(startUpload.waitForExistence(timeout: 10), "Upload start button did not appear.")
        startUpload.tap()

        let completed = app.staticTexts["Upload abgeschlossen"].waitForExistence(timeout: 240)
        let failed = app.staticTexts["Upload fehlgeschlagen"].exists
        XCTAssertTrue(completed && !failed, "Direkt-in-die-Cloud upload did not complete successfully.")
    }

    @MainActor
    func testE2EBrowserCompanionUploadSmoke() throws {
        let environment = ProcessInfo.processInfo.environment
        let fileConfig = loadE2EConfig()
        let email = e2eValue(environment["PIXCAPTURE_E2E_EMAIL"], fallback: fileConfig.email)
        let password = e2eValue(environment["PIXCAPTURE_E2E_PASSWORD"], fallback: fileConfig.password)
        let payload = e2eValue(environment["PIXCAPTURE_E2E_BROWSER_COMPANION_PAYLOAD"], fallback: fileConfig.browserCompanionPayload)
        guard !email.isEmpty, !password.isEmpty, !payload.isEmpty else {
            throw XCTSkip("PIXCAPTURE_E2E_EMAIL, PIXCAPTURE_E2E_PASSWORD, and PIXCAPTURE_E2E_BROWSER_COMPANION_PAYLOAD are required.")
        }

        let app = XCUIApplication()
        app.launchArguments = [
            "--pixcapture-clear-auth",
            "-photoCaptureMode", "single_shot",
            "-captureDelaySeconds", "0",
            "-bracketCount", "1",
        ]
        app.launchEnvironment["PIXCAPTURE_CLEAR_AUTH"] = "1"

        addUIInterruptionMonitor(withDescription: "System permissions") { alert in
            for title in ["Allow", "OK", "Erlauben", "Fortfahren", "Continue", "Später", "Nicht jetzt"] {
                if alert.buttons[title].exists {
                    alert.buttons[title].tap()
                    return true
                }
            }
            if alert.buttons.count > 0 {
                alert.buttons.element(boundBy: 0).tap()
                return true
            }
            return false
        }

        app.launch()

        let emailField = app.textFields.element(boundBy: 0)
        XCTAssertTrue(emailField.waitForExistence(timeout: 12), "Login email field did not appear.")
        emailField.tap()
        emailField.typeText(email)

        let passwordField = app.secureTextFields.element(boundBy: 0)
        XCTAssertTrue(passwordField.waitForExistence(timeout: 5), "Login password field did not appear.")
        passwordField.tap()
        passwordField.typeText(password)

        let submit = app.buttons["MIT PASSWORT ANMELDEN"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5), "Password login button did not appear.")
        submit.tap()
        dismissPasswordSavePrompt(in: app)

        openGallery(in: app)
        selectExistingGallerySeriesForUpload(in: app, expectedCount: 2)

        let companionMode = app.buttons["upload.mode.companionWifi"]
        if companionMode.waitForExistence(timeout: 8), !companionMode.isSelected {
            companionMode.tap()
        }

        let companionInput = app.textFields["upload.connect.companion.input"]
        if companionInput.waitForExistence(timeout: 8), companionInput.value as? String != payload {
            companionInput.tap()
            companionInput.typeText(typeableConnectPayload(payload))
        }

        let startUpload = app.buttons["upload.connect.start.primary"].exists ? app.buttons["upload.connect.start.primary"] : (app.buttons["upload.connect.start.toolbar"].exists ? app.buttons["upload.connect.start.toolbar"] : app.buttons["Upload starten"])
        XCTAssertTrue(startUpload.waitForExistence(timeout: 10), "Browser Companion upload start button did not appear.")
        startUpload.tap()

        let browserSuccess = app.staticTexts.containing(NSPredicate(
            format: "label CONTAINS %@ OR label CONTAINS %@ OR label CONTAINS %@ OR label == %@",
            "Paket an den Browser",
            "WLAN-Option bereit",
            "Lokaler Eingang bereit",
            "Upload abgeschlossen"
        )).firstMatch
        let completed = app.staticTexts["Upload abgeschlossen"]
        let failed = app.staticTexts["Upload fehlgeschlagen"]
        let success = browserSuccess.waitForExistence(timeout: 240) || completed.waitForExistence(timeout: 5)
        XCTAssertTrue(success && !failed.exists, "Browser Companion upload did not reach browser handoff.")
    }

    @MainActor
    func testE2ECablePackageExistingGallerySmoke() throws {
        throw XCTSkip("Kabel-Option is no longer a customer-visible upload path; keep package handling as support-only legacy behavior.")
    }

    @MainActor
    func testE2EExistingGalleryUploadSheetSmoke() throws {
        let environment = ProcessInfo.processInfo.environment
        let fileConfig = loadE2EConfig()
        let email = e2eValue(environment["PIXCAPTURE_E2E_EMAIL"], fallback: fileConfig.email)
        let password = e2eValue(environment["PIXCAPTURE_E2E_PASSWORD"], fallback: fileConfig.password)

        let app = XCUIApplication()

        addUIInterruptionMonitor(withDescription: "System permissions") { alert in
            for title in ["Allow", "OK", "Erlauben", "Fortfahren", "Continue", "Später", "Nicht jetzt"] {
                if alert.buttons[title].exists {
                    alert.buttons[title].tap()
                    return true
                }
            }
            if alert.buttons.count > 0 {
                alert.buttons.element(boundBy: 0).tap()
                return true
            }
            return false
        }

        app.launch()

        let loginField = app.textFields.element(boundBy: 0)
        if loginField.waitForExistence(timeout: 4), !app.buttons["bottom.gallery"].exists {
            guard !email.isEmpty, !password.isEmpty else {
                throw XCTSkip("Existing app session is not logged in; PIXCAPTURE_E2E_EMAIL and PIXCAPTURE_E2E_PASSWORD are required.")
            }
            loginField.tap()
            loginField.typeText(email)

            let passwordField = app.secureTextFields.element(boundBy: 0)
            XCTAssertTrue(passwordField.waitForExistence(timeout: 5), "Login password field did not appear.")
            passwordField.tap()
            passwordField.typeText(password)

            let submit = app.buttons["MIT PASSWORT ANMELDEN"]
            XCTAssertTrue(submit.waitForExistence(timeout: 5), "Password login button did not appear.")
            submit.tap()
            dismissPasswordSavePrompt(in: app)
        }

        openGallery(in: app)

        let firstSeries = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "gallery.series.")).firstMatch
        XCTAssertTrue(firstSeries.waitForExistence(timeout: 20), "No existing gallery series appeared for upload.")

        let selectButton = app.buttons["gallery.select.toggle"]
        XCTAssertTrue(selectButton.waitForExistence(timeout: 20), "Gallery select button did not appear.")
        selectButton.tap()

        let selectableSeries = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "gallery.series.")).firstMatch
        XCTAssertTrue(selectableSeries.waitForExistence(timeout: 20), "No gallery series appeared for selection upload.")
        selectableSeries.tap()

        let uploadButton = app.buttons["gallery.selection.prepareUpload"]
        XCTAssertTrue(uploadButton.waitForExistence(timeout: 20), "Selected-series upload button did not appear.")
        uploadButton.tap()

        let companionMode = app.buttons["upload.mode.companionWifi"]
        XCTAssertTrue(companionMode.waitForExistence(timeout: 10), "Companion upload mode did not appear.")
        XCTAssertTrue(app.buttons["upload.mode.localWifi"].waitForExistence(timeout: 5), "Cloud upload mode did not appear.")
        XCTAssertFalse(app.buttons["upload.mode.cablePackage"].exists, "Cable package upload mode must not be visible in the customer upload sheet.")
        XCTAssertFalse(app.buttons["upload.mode.direct"].exists, "Internal direct upload mode must not be visible in the customer upload sheet.")
        if !companionMode.isSelected {
            companionMode.tap()
        }

        let startUpload = app.buttons["upload.connect.start.primary"].exists ? app.buttons["upload.connect.start.primary"] : (app.buttons["upload.connect.start.toolbar"].exists ? app.buttons["upload.connect.start.toolbar"] : app.buttons["Upload starten"])
        XCTAssertTrue(startUpload.waitForExistence(timeout: 10), "Upload start button did not appear.")
        startUpload.tap()

        let missingCompanionQR = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "WLAN-Option")).firstMatch
        XCTAssertTrue(missingCompanionQR.waitForExistence(timeout: 5), "Upload sheet should require a browser companion QR before starting.")
    }

    private func loadE2EConfig() -> E2EConfig {
        let url = URL(fileURLWithPath: "/tmp/pixcapture-e2e-browser-companion.json")
        guard let data = try? Data(contentsOf: url) else {
            return E2EConfig()
        }
        return (try? JSONDecoder().decode(E2EConfig.self, from: data)) ?? E2EConfig()
    }

    private func e2eValue(_ value: String?, fallback: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }
        return fallback?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func typeableConnectPayload(_ payload: String) -> String {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") else {
            return trimmed
        }
        return Data(trimmed.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func openGallery(in app: XCUIApplication) {
        let galleryButton = app.buttons["bottom.gallery"].exists
            ? app.buttons["bottom.gallery"]
            : (app.buttons["Galerie"].exists ? app.buttons["Galerie"] : app.buttons["GALERIE"])
        if galleryButton.waitForExistence(timeout: 10), galleryButton.isHittable {
            galleryButton.tap()
            return
        }

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.74, dy: 0.94)).tap()
    }

    private func loginIfNeeded(in app: XCUIApplication, email: String, password: String) {
        let emailField = app.textFields.element(boundBy: 0)
        if emailField.waitForExistence(timeout: 12), !app.buttons["bottom.gallery"].exists {
            emailField.tap()
            emailField.typeText(email)

            let passwordField = app.secureTextFields.element(boundBy: 0)
            XCTAssertTrue(passwordField.waitForExistence(timeout: 5), "Login password field did not appear.")
            passwordField.tap()
            passwordField.typeText(password)

            let submit = app.buttons["MIT PASSWORT ANMELDEN"]
            XCTAssertTrue(submit.waitForExistence(timeout: 5), "Password login button did not appear.")
            submit.tap()
            dismissPasswordSavePrompt(in: app)
        }
    }

    private func selectExistingGallerySeriesForUpload(in app: XCUIApplication, expectedCount: Int) {
        let selectButton = app.buttons["gallery.select.toggle"]
        XCTAssertTrue(selectButton.waitForExistence(timeout: 20), "Gallery select button did not appear.")
        selectButton.tap()

        let series = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "gallery.series."))
        for index in 0..<expectedCount {
            let seriesItem = series.element(boundBy: index)
            XCTAssertTrue(seriesItem.waitForExistence(timeout: 20), "Gallery series \(index + 1) did not appear for scoped upload.")
            seriesItem.tap()
        }

        let uploadSelected = app.buttons["gallery.selection.prepareUpload"]
        XCTAssertTrue(uploadSelected.waitForExistence(timeout: 10), "Selected-series upload button did not appear.")
        uploadSelected.tap()
    }

    private func openCamera(in app: XCUIApplication) {
        let cameraButton = app.buttons["KAMERA"].exists ? app.buttons["KAMERA"] : app.buttons["bottom.camera"]
        if cameraButton.waitForExistence(timeout: 30), cameraButton.isHittable {
            cameraButton.tap()
            return
        }

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.42, dy: 0.94)).tap()
    }

    private func dismissPasswordSavePrompt(in app: XCUIApplication) {
        for title in ["Später", "Nicht jetzt", "Not Now"] {
            let button = app.buttons[title]
            if button.waitForExistence(timeout: 3) {
                button.tap()
                return
            }
        }
    }

    private func resolveJobSelectionIfNeeded(in app: XCUIApplication, preferredJobId: String, allowWithoutJob: Bool = true) {
        if !preferredJobId.isEmpty {
            let jobCard = app.buttons["job.card.\(preferredJobId)"]
            if jobCard.waitForExistence(timeout: 8) {
                jobCard.tap()
                return
            }
        }

        let existingJob = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "job.card.")).firstMatch
        if existingJob.waitForExistence(timeout: 3) {
            existingJob.tap()
            return
        }

        if allowWithoutJob, confirmCaptureWithoutJobIfNeeded(in: app, timeout: 1) {
            return
        }

        let createButton = app.buttons["jobs.create.open"].exists ? app.buttons["jobs.create.open"] : app.buttons["NEUEN JOB ERSTELLEN"]
        guard createButton.waitForExistence(timeout: 8) else { return }
        createButton.tap()

        let nameField = app.textFields["jobs.create.name"].exists ? app.textFields["jobs.create.name"] : app.textFields.element(boundBy: 0)
        guard nameField.waitForExistence(timeout: 8) else { return }
        nameField.tap()
        nameField.typeText("E2E Smoke \(Int(Date().timeIntervalSince1970))")

        let saveButton = app.buttons["jobs.create.save"].exists ? app.buttons["jobs.create.save"] : app.buttons["SPEICHERN"]
        if saveButton.waitForExistence(timeout: 5) {
            saveButton.tap()
        }
    }

    private func confirmCaptureWithoutJobIfNeeded(in app: XCUIApplication, timeout: TimeInterval = 3) -> Bool {
        let clearButton = app.buttons["jobs.clear"].exists
            ? app.buttons["jobs.clear"]
            : (app.buttons["OHNE JOB AUFNEHMEN"].exists ? app.buttons["OHNE JOB AUFNEHMEN"] : app.buttons["Capture without job"])
        guard clearButton.waitForExistence(timeout: timeout) else { return false }
        clearButton.tap()
        return true
    }
}
