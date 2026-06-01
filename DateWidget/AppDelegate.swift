//
//  AppDelegate.swift
//  DateWidget
//
//  Created by Alerix and Claude on 26.05.2026.
//

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
