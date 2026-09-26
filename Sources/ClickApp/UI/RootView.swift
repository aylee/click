import AppKit
import ClickCore
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var controller: AppController
    @EnvironmentObject private var store: ConfigurationStore
    @EnvironmentObject private var registry: DeviceRegistry
    @EnvironmentObject private var reconciler: HardwareReconciler
    @State private var selectedKey: String?
    @State private var page: Page = .buttons
    var previewDevice: ManagedDevice?

    private enum Page: String, CaseIterable {
        case buttons = "Buttons", scrolling = "Point & Scroll", settings = "Settings"
        var symbol: String {
            switch self {
            case .buttons: return "computermouse"
            case .scrolling: return "arrow.up.and.down"
            case .settings: return "gearshape"
            }
        }
    }

    private var devices: [ManagedDevice] {
        if let previewDevice { return [previewDevice] }
        let live = registry.devices.filter { !$0.isTrackpad }
        let liveKeys = Set(live.map(\.key))
        let saved = store.configuration.devices.keys.sorted().filter { !liveKeys.contains($0) }.map { key in
            ManagedDevice(key: key, displayName: store.configuration.device(key).displayName ?? "Saved mouse",
                          target: nil, endpoint: nil, pointerService: nil, isOnline: false)
        }
        return live + saved
    }
    private var selectedDevice: ManagedDevice? { devices.first { $0.key == selectedKey } ?? devices.first }
    private var permissionsOK: Bool { controller.hasAccessibility && controller.hasInputMonitoring }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 190)
            Divider()
            VStack(spacing: 0) {
                header
                if let error = store.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                        .background(Color.red.opacity(0.06))
                }
                if !permissionsOK && previewDevice == nil && page != .settings {
                    HStack(spacing: 12) {
                        Image(systemName: "hand.raised").foregroundStyle(.orange)
                        Text("Allow mouse control to enable your bindings.").font(.callout)
                        Spacer()
                        Button("Set up permissions") { page = .settings }
                    }.padding(.horizontal, 28).padding(.vertical, 12)
                        .background(Color.orange.opacity(0.06))
                }
                if previewDevice == nil, permissionsOK, let error = controller.inputError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 28).padding(.vertical, 12)
                        .background(Color.orange.opacity(0.06))
                }
                if !store.configuration.enabled {
                    HStack {
                        Label("Customizations paused", systemImage: "pause.circle")
                        Spacer()
                        Button("Resume") { store.update { $0.enabled = true } }
                            .disabled(store.isReadOnly)
                    }
                    .font(.callout).padding(.horizontal, 28).padding(.vertical, 12)
                    .background(Color.orange.opacity(0.06))
                }
                Divider()
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .tint(.indigo)
        .onAppear { selectedKey = devices.first?.key }
        .onChange(of: registry.devices.map(\.key)) { _, _ in
            if selectedKey == nil { selectedKey = devices.first?.key }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 9) {
                Image(systemName: "cursorarrow.click.2").font(.title2).foregroundStyle(Color.accentColor)
                Text("Click").font(.system(size: 23, weight: .semibold, design: .rounded))
            }.padding(.top, 16)
            VStack(alignment: .leading, spacing: 10) {
                Text("MOUSE").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                if let device = selectedDevice {
                    Menu {
                        ForEach(devices) { candidate in
                            Button(candidate.displayName) { selectedKey = candidate.key }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(device.displayName).font(.callout.weight(.medium)).lineLimit(2).multilineTextAlignment(.leading)
                            HStack(spacing: 5) {
                                Circle().fill(previewDevice != nil ? Color.secondary : device.isOnline ? .green : .orange)
                                    .frame(width: 5, height: 5)
                                Text(previewDevice != nil ? "Preview" : device.isOnline ? "Connected" : "Disconnected")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.menuStyle(.borderlessButton)
                } else {
                    Text("No mouse connected").font(.callout).foregroundStyle(.secondary)
                }
            }
            VStack(spacing: 5) {
                ForEach(Page.allCases, id: \.self) { item in
                    Button { page = item } label: {
                        Label(item.rawValue, systemImage: item.symbol)
                            .font(.callout.weight(page == item ? .semibold : .regular))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).padding(.vertical, 11)
                            .foregroundStyle(page == item ? Color.accentColor : Color.primary)
                            .background(page == item ? Color.accentColor.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain)
                        .accessibilityAddTraits(page == item ? .isSelected : [])
                }
            }
            Spacer()
        }
        .padding(18).padding(.bottom, 4)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(page == .settings ? "Settings" : selectedDevice?.displayName ?? "Mouse")
                .font(.system(size: 25, weight: .semibold))
            Spacer()
            if previewDevice != nil {
                Text("PREVIEW · HARDWARE OFF").font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary).padding(8)
                    .background(.quaternary, in: Capsule())
            } else if let device = selectedDevice {
                DeviceStatus(device: device)
            }
        }.padding(.horizontal, 28).padding(.vertical, 24)
    }

    @ViewBuilder private var content: some View {
        if page == .settings {
            GeneralSettingsView(isPreview: previewDevice != nil)
        } else if let device = selectedDevice {
            if page == .buttons {
                ButtonsPage(device: device, isPreview: previewDevice != nil)
                    .id(device.key).disabled(store.isReadOnly)
            } else {
                PointScrollView(device: device).id(device.key).disabled(store.isReadOnly)
            }
        } else {
            VStack(spacing: 18) {
                Image(systemName: "computermouse").font(.system(size: 54, weight: .ultraLight)).foregroundStyle(.secondary)
                Text("Connect your mouse").font(.title2.weight(.semibold))
                Text("Pair it in macOS Bluetooth settings, or plug in its receiver.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                HStack {
                    Button("Refresh devices") { registry.rescan() }
                    Button("Open Bluetooth settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") { NSWorkspace.shared.open(url) }
                    }
                }
            }.padding(30)
        }
    }
}

private struct DeviceStatus: View {
    @ObservedObject var device: ManagedDevice
    @EnvironmentObject private var reconciler: HardwareReconciler

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if let battery = device.battery?.percentage {
                Label("\(battery)%", systemImage: "battery.75percent").font(.callout).foregroundStyle(.secondary)
            }
            if let transport = device.endpoint?.transport {
                Text(transport.contains("Bluetooth") ? "Bluetooth" : transport).font(.caption).foregroundStyle(.secondary)
            }
            switch reconciler.statuses[device.key] ?? .idle {
            case .idle: EmptyView()
            case .applying: Text("Applying…").font(.caption).foregroundStyle(.secondary)
            case .applied: Label("Applied", systemImage: "checkmark").font(.caption).foregroundStyle(.green)
            case .waitingForDevice: Text("Waiting for mouse").font(.caption).foregroundStyle(.orange)
            case let .failed(message): Text("Couldn’t apply settings").font(.caption).foregroundStyle(.orange).help(message)
            }
        }
    }
}
