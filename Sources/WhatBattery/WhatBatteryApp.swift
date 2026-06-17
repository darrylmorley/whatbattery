import SwiftUI
import AppKit
import Combine
import WhatBatteryCore
import WhatBatteryAppKit
import WhatBatteryPlugins

@main
struct WhatBatteryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The menu bar status item, its popover, and the main window are all
        // managed in AppKit by the delegate (SwiftUI's MenuBarExtra can't do a
        // right-click menu). The only SwiftUI scene is Settings, which does not
        // auto-open a window at launch, so the app starts as a quiet menu bar app.
        Settings {
            SettingsView()
        }
    }
}

/// Bridges menu/popover actions to the AppKit controllers the delegate owns, so
/// SwiftUI views hosted in the popover (which are outside the scene graph and
/// can't use `openWindow` / `SettingsLink`) can still open the window and
/// settings.
@MainActor
final class MenuActions {
    static let shared = MenuActions()
    var openMainWindow: () -> Void = {}
    var openSettings: () -> Void = {}
    /// Keep the popover open across clicks outside it (so licence-key entry in the
    /// settings pane isn't lost), or restore the default transient behavior.
    var setPopoverSticky: (Bool) -> Void = { _ in }
}

/// Owns the menu bar status item and the main window. Menu-bar-only app
/// (`.accessory`: no Dock icon, no app menu).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let monitor = BatteryMonitor()

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        bootstrapPlugins(registry: .shared)
        Task { @MainActor in
            for hook in PluginRegistry.shared.launchHooks {
                await hook()
            }
        }

        MenuActions.shared.openMainWindow = { [weak self] in self?.showMainWindow() }
        MenuActions.shared.openSettings = { [weak self] in self?.showSettings() }
        MenuActions.shared.setPopoverSticky = { [weak self] sticky in
            // Sticky = stays open until explicitly closed, so the user can switch
            // apps to grab their licence key without the popover dismissing.
            self?.popover.behavior = sticky ? .applicationDefined : .transient
        }

        setUpStatusItem()
        setUpPopover()

        // The icon is static; the charge percentage beside it tracks live state.
        monitor.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in self?.updateStatusTitle(snapshot) }
            .store(in: &cancellables)
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        // A template image so the glyph adapts to the light / dark menu bar.
        let icon = NSImage(systemSymbolName: "battery.100percent.circle", accessibilityDescription: "WhatBattery")
        icon?.isTemplate = true
        button.image = icon
        button.imagePosition = .imageLeading
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .regular)
        updateStatusTitle(monitor.snapshot)
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    /// Show the current charge percentage next to the icon. Empty on a Mac with
    /// no battery, leaving just the glyph.
    private func updateStatusTitle(_ snapshot: BatterySnapshot?) {
        guard let snapshot else {
            statusItem?.button?.title = ""
            return
        }
        statusItem?.button?.title = " \(snapshot.currentChargePercent)%"
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        // A left-click toggles the rich popover; a right-click shows the menu.
        if NSApp.currentEvent?.type == .rightMouseUp {
            showRightClickMenu()
        } else {
            togglePopover(sender)
        }
    }

    // MARK: - Popover (left click)

    private func setUpPopover() {
        popover.behavior = .transient
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        // Recreate the content each open so the popover always starts on the main
        // pane (rather than relying on a SwiftUI lifecycle reset, which an NSPopover
        // does not fire reliably for a reused hosting controller). Start transient;
        // the settings pane flips it sticky while it is open.
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuContentView(monitor: monitor))
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }

    func closePopover() {
        popover.performClose(nil)
    }

    // MARK: - Right click menu

    private func showRightClickMenu() {
        // Don't leave the left-click popover open behind the menu.
        if popover.isShown { closePopover() }
        let menu = NSMenu()
        menu.addItem(withTitle: "About WhatBattery", action: #selector(showAbout), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit WhatBattery", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items where item.action != nil { item.target = self }

        // Attaching the menu makes the next click show it; reset to nil afterward
        // so left-clicks return to toggling the popover.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func showSettings() {
        closePopover()
        settingsWindow = present(settingsWindow, title: "WhatBattery Settings", width: 380, height: 320) {
            SettingsView()
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Windows

    private func showMainWindow() {
        closePopover()
        if mainWindow == nil {
            // Open tall enough to show the full This Mac tab without scrolling;
            // still resizable, and the content scrolls if shrunk or on a short
            // display.
            let window = makeWindow(title: "WhatBattery", width: 480, height: 880, resizable: true) {
                MainWindowView(monitor: monitor)
            }
            mainWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    /// Open (creating if needed) an AppKit window hosting SwiftUI content. We
    /// host these ourselves rather than use the SwiftUI Settings scene because
    /// the `showSettingsWindow:` selector is unreliable for an `.accessory` app.
    private func present<Content: View>(
        _ existing: NSWindow?,
        title: String,
        width: CGFloat,
        height: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> NSWindow {
        let window = existing ?? makeWindow(title: title, width: width, height: height, resizable: false, content: content)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func makeWindow<Content: View>(
        title: String,
        width: CGFloat,
        height: CGFloat,
        resizable: Bool,
        @ViewBuilder content: () -> Content
    ) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable { style.insert(.resizable) }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        let hosting = NSHostingController(rootView: content())
        window.contentViewController = hosting
        // Assigning the hosting controller resizes the window to the SwiftUI
        // fitting size, which collapses a ScrollView to its minimum. Force the
        // size we asked for: the requested rect for a resizable window (so it
        // opens at full height), or the view's own fitting size for a fixed one.
        if resizable {
            // Don't open taller than the screen on a small display; the content
            // scrolls if clamped.
            let maxHeight = (NSScreen.main?.visibleFrame.height ?? height) - 40
            window.setContentSize(NSSize(width: width, height: min(height, maxHeight)))
        } else {
            window.setContentSize(hosting.view.fittingSize)
        }
        window.center()
        return window
    }
}
