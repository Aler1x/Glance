//
//  DateWidgetApp.swift
//  DateWidget
//
//  Created by Alerix and Claude on 26.05.2026.
//

import SwiftUI

@main
struct DateWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            DateWidgetView()
                .background(.clear)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
