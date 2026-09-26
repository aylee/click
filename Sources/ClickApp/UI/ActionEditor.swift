import AppKit
import ClickCore
import SwiftUI
import UniformTypeIdentifiers

struct ActionEditor: View {
    @Binding var action: Action?
    var defaultLabel = "Default behavior"
    @State private var recording = false
    @State private var selectionError: String?

    private let navigation: [Action] = [.back, .forward, .missionControl, .applicationWindows, .showDesktop, .spaceLeft, .spaceRight]
    private let editing: [(String, Action)] = [
        ("Copy", .keyPress(KeyCombo(keyCode: 8, command: true))),
        ("Paste", .keyPress(KeyCombo(keyCode: 9, command: true))),
        ("Cut", .keyPress(KeyCombo(keyCode: 7, command: true))),
        ("Undo", .keyPress(KeyCombo(keyCode: 6, command: true))),
        ("Redo", .keyPress(KeyCombo(keyCode: 6, command: true, shift: true))),
        ("Select all", .keyPress(KeyCombo(keyCode: 0, command: true))),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Menu {
                Button(defaultLabel) { action = nil }
                Divider()
                Button("Keyboard shortcut…") { recording = true }
                Button("Open application…", action: chooseApplication)
                Menu("Navigation") {
                    ForEach(navigation, id: \.self) { choice in
                        Button(choice.displayName) { action = choice }
                    }
                }
                Menu("Editing") {
                    ForEach(editing, id: \.0) { title, choice in
                        Button(title) { action = choice }
                    }
                }
                Menu("Media & volume") {
                    ForEach([Action.playPause, .mediaNext, .mediaPrevious, .volumeUp, .volumeDown, .mute], id: \.self) { choice in
                        Button(choice.displayName) { action = choice }
                    }
                }
                Menu("Mouse & zoom") {
                    Button("Middle click") { action = .mouseButton(2) }
                    Button("Zoom in") { action = .zoomIn }
                    Button("Zoom out") { action = .zoomOut }
                }
                Divider()
                Button("Do nothing") { action = Action.none }
            } label: {
                HStack {
                    Text(actionLabel).lineLimit(2).multilineTextAlignment(.leading)
                    Spacer(minLength: 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .menuStyle(.borderedButton)
            .controlSize(.large)
            .accessibilityLabel("Button action")
            .accessibilityValue(actionLabel)

            if case .keyPress = action {
                Button("Record another shortcut…") { recording = true }
                    .buttonStyle(.link).font(.caption)
            }
            if let selectionError {
                Text(selectionError).font(.caption).foregroundStyle(.red)
            }
        }
        .sheet(isPresented: $recording) {
            ShortcutSheet { combo in
                action = .keyPress(combo)
                recording = false
            } cancel: { recording = false }
        }
    }

    private var actionLabel: String {
        guard let action else { return defaultLabel }
        if case let .launchApp(bundleID) = action,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return "Open \(url.deletingPathExtension().lastPathComponent)"
        }
        if case .mouseButton(2) = action { return "Middle click" }
        return action.displayName
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = "Choose an application"
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let identifier = Bundle(url: url)?.bundleIdentifier else {
            selectionError = "This application has no bundle identifier."
            return
        }
        selectionError = nil
        action = .launchApp(identifier)
    }
}

private struct ShortcutSheet: View {
    let onRecord: (KeyCombo) -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "keyboard").font(.system(size: 32)).foregroundStyle(.secondary)
            Text("Press your shortcut").font(.title2.weight(.semibold))
            Text("Hold any modifiers, then press a key.\nEscape cancels. Nothing is recorded outside this window.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            ShortcutCapture(onRecord: onRecord, cancel: cancel).frame(width: 1, height: 1)
            Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
        }
        .padding(32).frame(width: 360)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in cancel() }
    }
}

private struct ShortcutCapture: NSViewRepresentable {
    let onRecord: (KeyCombo) -> Void
    let cancel: () -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onRecord = onRecord
        view.cancel = cancel
        return view
    }
    func updateNSView(_ nsView: CaptureView, context: Context) {}

    final class CaptureView: NSView {
        var onRecord: ((KeyCombo) -> Void)?
        var cancel: (() -> Void)?
        private var captured = false
        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                window?.makeFirstResponder(self)
            }
        }
        override func keyDown(with event: NSEvent) { capture(event) }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard window?.firstResponder === self else { return false }
            capture(event)
            return true
        }
        private func capture(_ event: NSEvent) {
            guard !captured, !event.isARepeat else { return }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            captured = true
            if event.keyCode == 53 && flags.intersection([.command, .option, .control, .shift]).isEmpty {
                cancel?()
            } else {
                onRecord?(KeyCombo(keyCode: event.keyCode,
                    command: flags.contains(.command), option: flags.contains(.option),
                    control: flags.contains(.control), shift: flags.contains(.shift), fn: flags.contains(.function)))
            }
        }
    }
}
