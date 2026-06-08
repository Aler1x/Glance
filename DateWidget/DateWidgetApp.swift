//
//  DateWidgetApp.swift
//  DateWidget
//
//  Created by Alerix and Claude on 01.06.2026.
//

import AppKit
import SwiftUI

@main
struct DateWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let widgetSize = CGSize(width: 520, height: 230)
    private static let originDefaultsKey = "DesktopWidget.origin"

    private let model = WidgetModel()
    private let settings = WidgetSettings.shared

    private var window: OverlayWindow!
    private var hostingView: ClickThroughHostingView!
    private var backingView: NSVisualEffectView!
    private var settingsWindow: NSWindow?
    private var contextMenu: NSMenu!
    private var moveMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupWindow()
        setupContextMenu()
        applyWindowSettings()
        observeScreenChanges()
        restoreOrigin()
        window.orderFront(nil)
    }

    // MARK: Window

    private func setupWindow() {
        let frame = NSRect(origin: .zero, size: Self.widgetSize)

        window = OverlayWindow(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.isReleasedWhenClosed = false
        window.hasShadow = false
        window.appearance = NSAppearance(named: .darkAqua)

        let container = NSView(frame: frame)
        container.autoresizesSubviews = true

        // Optional opaque-ish frosted base for contrast over busy wallpapers.
        backingView = NSVisualEffectView(frame: frame)
        backingView.material = .hudWindow
        backingView.blendingMode = .behindWindow
        backingView.state = .active
        backingView.wantsLayer = true
        backingView.layer?.cornerRadius = 22
        backingView.layer?.masksToBounds = true
        backingView.autoresizingMask = [.width, .height]
        container.addSubview(backingView)

        hostingView = ClickThroughHostingView(
            rootView: AnyView(
                DesktopWidgetView(model: model) { [weak self] frame in
                    self?.hostingView.interactiveRect = frame
                }
            )
        )
        hostingView.frame = frame
        hostingView.autoresizingMask = [.width, .height]
        hostingView.onDragEnded = { [weak self] in self?.saveOrigin() }
        container.addSubview(hostingView)

        window.contentView = container
    }

    private func applyWindowSettings() {
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        backingView.isHidden = !settings.contrastBacking
        backingView.alphaValue = settings.backingOpacity
    }

    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screensChanged() {
        window.setFrameOrigin(clampedOrigin(window.frame.origin))
    }

    // MARK: Context menu (right-click on the widget)

    private func setupContextMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let refreshItem = NSMenuItem(title: "Refresh Quote", action: #selector(refreshQuote), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(.separator())

        moveMenuItem = NSMenuItem(title: "Move Widget", action: #selector(toggleEditing), keyEquivalent: "")
        moveMenuItem.target = self
        menu.addItem(moveMenuItem)

        let positionItem = NSMenuItem(title: "Position", action: nil, keyEquivalent: "")
        let positionMenu = NSMenu()
        for corner in WidgetCorner.allCases {
            let item = NSMenuItem(title: corner.title, action: #selector(snapToCorner(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = corner
            positionMenu.addItem(item)
        }
        positionItem.submenu = positionMenu
        menu.addItem(positionItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q"))

        contextMenu = menu
        window.onContextClick = { [weak self] event in
            guard let self else { return }
            NSMenu.popUpContextMenu(self.contextMenu, with: event, for: self.hostingView)
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        moveMenuItem.state = model.isEditing ? .on : .off
    }

    @objc private func refreshQuote() {
        Task { await model.refresh() }
    }

    @objc private func toggleEditing() {
        model.isEditing.toggle()
        hostingView.isEditing = model.isEditing
    }

    @objc private func snapToCorner(_ sender: NSMenuItem) {
        guard let corner = sender.representedObject as? WidgetCorner,
              let screen = window.screen ?? NSScreen.main else { return }
        window.setFrameOrigin(corner.origin(in: screen.visibleFrame, size: window.frame.size))
        saveOrigin()
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Date Widget Settings"
            window.contentView = NSHostingView(rootView: SettingsView())
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: Position persistence

    private func saveOrigin() {
        let origin = window.frame.origin
        UserDefaults.standard.set(["x": origin.x, "y": origin.y], forKey: Self.originDefaultsKey)
    }

    private func restoreOrigin() {
        if let saved = UserDefaults.standard.dictionary(forKey: Self.originDefaultsKey),
           let x = saved["x"] as? CGFloat, let y = saved["y"] as? CGFloat {
            window.setFrameOrigin(clampedOrigin(NSPoint(x: x, y: y)))
        } else if let screen = NSScreen.main {
            window.setFrameOrigin(WidgetCorner.bottomRight.origin(in: screen.visibleFrame, size: window.frame.size))
        }
    }

    /// Keeps the widget at least partially on a visible screen.
    private func clampedOrigin(_ origin: NSPoint) -> NSPoint {
        let frame = NSRect(origin: origin, size: window.frame.size)
        if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
            return origin
        }
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        return WidgetCorner.bottomRight.origin(in: visible, size: window.frame.size)
    }
}

// MARK: - Corners

enum WidgetCorner: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight, center

    var title: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        case .center: return "Center"
        }
    }

    func origin(in visibleFrame: NSRect, size: CGSize) -> NSPoint {
        let margin: CGFloat = 24
        switch self {
        case .topLeft:
            return NSPoint(x: visibleFrame.minX + margin, y: visibleFrame.maxY - size.height - margin)
        case .topRight:
            return NSPoint(x: visibleFrame.maxX - size.width - margin, y: visibleFrame.maxY - size.height - margin)
        case .bottomLeft:
            return NSPoint(x: visibleFrame.minX + margin, y: visibleFrame.minY + margin)
        case .bottomRight:
            return NSPoint(x: visibleFrame.maxX - size.width - margin, y: visibleFrame.minY + margin)
        case .center:
            return NSPoint(x: visibleFrame.midX - size.width / 2, y: visibleFrame.midY - size.height / 2)
        }
    }
}

// MARK: - Window

/// A non-activating panel: it can become key to handle clicks and context
/// menus, but clicking it never activates the app or steals focus from the
/// user's foreground window.
final class OverlayWindow: NSPanel {
    var onContextClick: ((NSEvent) -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        let isContextClick =
            event.type == .rightMouseDown
            || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
        // Intercept context-clicks here so they reach our menu instead of being
        // swallowed by the SwiftUI hosting view.
        if isContextClick {
            onContextClick?(event)
            return
        }
        super.sendEvent(event)
    }
}

// MARK: - Click-through hosting view

/// Passes left-clicks through to the desktop except inside `interactiveRect`
/// (the quote button). Right-clicks anywhere surface the context menu, and in
/// edit mode the whole view is grabbable so dragging repositions the window.
final class ClickThroughHostingView: NSHostingView<AnyView> {
    var interactiveRect: CGRect = .zero
    var isEditing = false
    var onDragEnded: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        if isEditing { return self }
        // NSView uses bottom-left origin; flip Y to match SwiftUI's top-left origin.
        let swiftUIPoint = CGPoint(x: point.x, y: bounds.height - point.y)
        return interactiveRect.contains(swiftUIPoint) ? super.hitTest(point) : nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEditing, let window else { return super.mouseDragged(with: event) }
        var origin = window.frame.origin
        origin.x += event.deltaX
        origin.y -= event.deltaY
        window.setFrameOrigin(origin)
    }

    override func mouseUp(with event: NSEvent) {
        if isEditing { onDragEnded?() } else { super.mouseUp(with: event) }
    }
}
