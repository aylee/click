import AppKit
import ClickCore
import SwiftUI
import UniformTypeIdentifiers

struct GeneralSettingsView: View {
    @EnvironmentObject private var controller: AppController
    @EnvironmentObject private var store: ConfigurationStore
    @StateObject private var loginItem = LoginItem()
    @State private var exportError: String?
    var isPreview = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                SettingsSection(title: "Mouse control", subtitle: "macOS requires these permissions for mouse customization.") {
                    permission("Accessibility", symbol: "hand.raised", granted: controller.hasAccessibility,
                               explanation: "Run your button actions and adjust scrolling.") {
                        controller.requestAccessibility()
                        controller.openPrivacyPane("Privacy_Accessibility")
                    }
                    Divider()
                    permission("Input Monitoring", symbol: "computermouse", granted: controller.hasInputMonitoring,
                               explanation: "Read your mouse’s extra buttons and configure its hardware.") {
                        controller.requestInputMonitoring()
                        controller.openPrivacyPane("Privacy_ListenEvent")
                    }
                    HStack {
                        Text("After granting access, refresh devices. If macOS requests a restart, quit and reopen Click.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Refresh") {
                            controller.refreshPermissions()
                            controller.registry.rescan()
                        }.disabled(isPreview)
                    }
                }
                SettingsSection(title: "General") {
                    Toggle("Start at login", isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) }))
                        .disabled(isPreview)
                    Toggle("Show in menu bar", isOn: Binding(get: { store.configuration.showMenuBarIcon }, set: { enabled in
                        store.update { $0.showMenuBarIcon = enabled }
                    })).disabled(store.isReadOnly)
                    if let error = loginItem.lastError { Text(error).font(.caption).foregroundStyle(.orange) }
                    Text("Closing the window keeps your customizations active.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                SettingsSection(title: "Settings file") {
                    Text("Settings are saved in a JSON file on this Mac.")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button("Show settings file") {
                            store.flush()
                            NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
                        }
                        Button("Export settings…", action: exportSettings)
                    }
                    Text("No network requests or typing history.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let exportError { Text(exportError).font(.caption).foregroundStyle(.red) }
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text("Click \(version)").font(.callout.weight(.semibold))
                    Text("Based on LoLiMouse. MIT License.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(28).frame(maxWidth: 690, alignment: .leading)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                loginItem.refresh()
                if !isPreview { controller.refreshPermissions() }
            }
    }

    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev" }

    private func permission(_ title: String, symbol: String, granted: Bool, explanation: String, request: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.secondary).frame(width: 25)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout.weight(.medium))
                Text(explanation).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
            } else {
                Button("Allow…", action: request).disabled(isPreview)
            }
        }
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Click-settings.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(store.configuration).write(to: url, options: .atomic)
            exportError = nil
        } catch { exportError = "Couldn’t export settings: \(error.localizedDescription)" }
    }
}
