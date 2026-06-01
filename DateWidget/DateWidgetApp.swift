//
//  DateWidgetApp.swift
//  DateWidget
//

import SwiftUI
import WidgetKit

@main
struct DateWidgetApp: App {
    var body: some Scene {
        WindowGroup("Date Widget") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}

private struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("Date Widget")
                .font(.title2.bold())

            Text("Add the widget from Notification Center or your desktop.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(minWidth: 360, minHeight: 280)
    }
}
