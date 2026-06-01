//
//  DateWingetApp.swift
//  DateWinget
//
//  Created by Alerix and Claude on 26.05.2026.
//

import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            for window in NSApplication.shared.windows {
                window.isOpaque = false
                window.backgroundColor = .clear
            }
        }
    }
}

@main
struct DateWingetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(.clear)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
