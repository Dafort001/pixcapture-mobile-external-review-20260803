//
//  PIXCAPTUREApp.swift
//  PIXCAPTURE
//
//  Created by Daniel Fortmann on 05.02.26.
//

import SwiftUI

@main
struct PIXCAPTUREApp: App {
    init() {
        #if DEBUG
        let processInfo = ProcessInfo.processInfo
        let shouldResetStorage = processInfo.arguments.contains("--pixcapture-reset-local-capture-storage")
            || processInfo.environment["PIXCAPTURE_RESET_LOCAL_CAPTURE_STORAGE"] == "1"
        if shouldResetStorage {
            FileStore.resetLocalPixCaptureStorageForDebugLaunch()
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                ContentView()
            } else {
                RootView()
            }
        }
    }
}
