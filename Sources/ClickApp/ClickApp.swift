// MIT License
// Copyright (c) 2026 LoLiMouse contributors

import AppKit
import Carbon
import ClickCore
import SwiftUI

/// The app runs a plain AppKit lifecycle, not a SwiftUI `App`.
///
/// SwiftUI's scene machinery has bitten this project twice. A `MenuBarExtra`
/// ties the app's lifetime to the icon's visibility — hide the icon and the
/// app is terminated. A `Window` scene with `.defaultLaunchBehavior(.suppressed)`
/// can only ever be opened through the `openWindow` environment action, which
/// exists solely inside a live SwiftUI view — with the menu bar item in AppKit
/// there is no such view left, so nothing could open the settings window at
/// all. Owning the window and the status item directly makes both paths
/// boringly deterministic. The UI itself is still SwiftUI, hosted with
/// `NSHostingController`.
@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    /// `NSApplication.delegate` is unowned; something has to keep the
    /// delegate alive for the lifetime of the process.
    private static var shared: AppDelegate!

    static func main() {
        if CommandLine.arguments.contains("--diagnose") {
            Diagnostics.printReport()
            return
        }
        let delegate = AppDelegate()
        shared = delegate
        let app = NSApplication.shared
        app.delegate = delegate
        app.mainMenu = makeMainMenu()
        app.run()
    }

    private var controller: AppController!
    private var previewDevice: ManagedDevice?
    private var previewDirectory: URL?

    private var statusItemController: StatusItemController?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_: Notification) {
        let preview = CommandLine.arguments.contains("--preview")
        if !preview, let bundleID = Bundle.main.bundleIdentifier,
           let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            if let url = running.bundleURL { NSWorkspace.shared.open(url) }
            NSApp.terminate(nil)
            return
        }
        if preview {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Click-preview-" + UUID().uuidString)
            previewDirectory = directory
            controller = AppController(store: ConfigurationStore(directory: directory))
            let mouse = ManagedDevice(key: "preview-mx-master", displayName: "MX Master 3 for Mac",
                                      target: nil, endpoint: nil, pointerService: nil, isOnline: false)
            previewDevice = mouse
            controller.store.updateDevice(mouse.key) { configuration in
                configuration.displayName = mouse.displayName
                configuration.buttons.mappings = .on([
                    ButtonMapping(button: 3, action: .back), ButtonMapping(button: 4, action: .forward)])
                configuration.buttons.thumbButton.tap = .on(.missionControl)
            }
        } else {
            controller = .shared
            controller.start()
        }

        if !preview {
            statusItemController = StatusItemController(controller: controller) { [weak self] in
                self?.showSettingsWindow()
            }
        }

        // The Dock icon follows the settings window. Click lives in the
        // menu bar; a Dock entry with no window behind it is just clutter, so
        // the activation policy flips to `.accessory` whenever the last real
        // window closes and back to `.regular` when one appears. Launch is
        // quiet: no window, no Dock icon — that is what makes "start at
        // login" unobtrusive.
        NSApp.setActivationPolicy(.accessory)
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(windowBecameKey(_:)),
                           name: NSWindow.didBecomeKeyNotification, object: nil)
        center.addObserver(self, selector: #selector(windowWillClose(_:)),
                           name: NSWindow.willCloseNotification, object: nil)
        let loginLaunch = NSAppleEventManager.shared().currentAppleEvent?
            .paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if !loginLaunch && !CommandLine.arguments.contains("--background") { showSettingsWindow() }

    }

    func applicationWillTerminate(_: Notification) {
        // Put every hardware setting back the way it was found. Leaving a mouse
        // in a state the user never chose, with the app no longer running to
        // explain it, is exactly the kind of thing this project exists to stop.
        controller?.stop()
        if let previewDirectory {
            controller?.store.flush()
            try? FileManager.default.removeItem(at: previewDirectory)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }

    /// Launching the app while it is already running as a menu-bar resident
    /// should bring the settings window up rather than appearing to do
    /// nothing. This is also the only way in when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        showSettingsWindow()
        return false
    }

    // MARK: - Settings window

    /// Menu bar Settings…, a Finder relaunch, and ⌘, all land here.
    @objc func showSettingsWindow() {
        let window = settingsWindow ?? makeSettingsWindow()
        settingsWindow = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeSettingsWindow() -> NSWindow {
        let controller = self.controller!
        let root = RootView(previewDevice: previewDevice)
            .environmentObject(controller)
            .environmentObject(controller.store)
            .environmentObject(controller.registry)
            .environmentObject(controller.reconciler)
            .frame(minWidth: 1080, minHeight: 680)
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = previewDevice == nil ? "Click" : "Click — Preview"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.contentMinSize = NSSize(width: 1080, height: 680)
        // Closing the window only hides it; the instance is reused so the
        // sidebar selection and tab survive a close/reopen.
        window.isReleasedWhenClosed = false
        // A saved frame can be taller than the screen — older builds let the
        // content inflate the window past the display's edge. Shrinking such a
        // frame in place leaves the hosting view laid out at the old giant
        // size, showing an empty mid-slice of the interface, so a frame that
        // does not fit is discarded outright and the window starts afresh.
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame
        let restored = window.setFrameUsingName("main")
            && visible.map { $0.contains(window.frame) } != false
        if !restored {
            window.setContentSize(NSSize(width: 1160, height: 740))
            window.center()
        }
        window.setFrameAutosaveName("main")
        return window
    }

    /// The windows that should hold a place in the Dock. The status item's
    /// window and other borderless helpers are not titled, so this filters
    /// them out.
    private static func isSettingsWindow(_ window: NSWindow) -> Bool {
        window.styleMask.contains(.titled) && !(window is NSPanel)
    }

    @objc private func windowBecameKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, Self.isSettingsWindow(window) else { return }
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, Self.isSettingsWindow(window) else { return }
        // The window still counts as visible while this notification is being
        // delivered; re-check once the close has actually happened.
        DispatchQueue.main.async { [weak self] in
            self?.updateDockVisibility()
        }
    }

    private func updateDockVisibility() {
        let hasWindow = NSApp.windows.contains { $0.isVisible && Self.isSettingsWindow($0) }
        let policy: NSApplication.ActivationPolicy = hasWindow ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }

    @objc private func toggleCustomizations() {
        guard let controller, !controller.store.isReadOnly else { return }
        controller.store.update { $0.enabled.toggle() }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(toggleCustomizations) {
            guard let controller else { return false }
            item.title = controller.store.configuration.enabled ? "Pause customizations" : "Resume customizations"
            return !controller.store.isReadOnly
        }
        return true
    }

    // MARK: - Main menu

    /// A SwiftUI `App` builds this for free; with an AppKit lifecycle it has
    /// to be spelled out. Without an Edit menu, ⌘C/⌘V/⌘A stop working in
    /// every text field of the settings window.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Click",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(AppDelegate.showSettingsWindow), keyEquivalent: ",")
        let pause = appMenu.addItem(withTitle: "Pause customizations", action: #selector(toggleCustomizations), keyEquivalent: "")
        pause.target = shared
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Click", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others",
                                         action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Click", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu(appMenu, title: ""))

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenu(editMenu, title: "Edit"))

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimise", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        main.addItem(submenu(windowMenu, title: "Window"))
        NSApp.windowsMenu = windowMenu

        return main
    }

    private static func submenu(_ menu: NSMenu, title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
