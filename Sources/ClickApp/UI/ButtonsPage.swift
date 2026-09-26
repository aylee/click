import AppKit
import ClickCore
import SwiftUI
import UniformTypeIdentifiers

struct ButtonsPage: View {
    @ObservedObject var device: ManagedDevice
    @EnvironmentObject private var store: ConfigurationStore
    @State private var selection: MouseControl = .back
    @State private var profileID: String?
    @State private var profileError: String?
    var isPreview = false

    private var configuration: DeviceConfiguration { store.configuration.device(device.key) }
    private var buttons: ButtonSettings { configuration.effectiveButtons(for: profileID) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: profileID == nil ? "square.grid.2x2" : "app").foregroundStyle(.secondary)
                Picker("Bindings for", selection: $profileID) {
                    Text("All applications").tag(nil as String?)
                    ForEach(configuration.applicationBindings.keys.sorted(), id: \.self) { id in
                        Text(configuration.applicationBindings[id]?.displayName ?? id).tag(id as String?)
                    }
                }
                .labelsHidden().frame(maxWidth: 230)
                if profileID != nil {
                    Button("Remove profile", systemImage: "minus.circle", action: removeProfile)
                        .labelStyle(.iconOnly).buttonStyle(.borderless)
                }
                Spacer()
                Button("Add application", systemImage: "plus", action: addApplication)
                    .buttonStyle(.borderless)
            }.padding(.horizontal, 28).padding(.vertical, 16)
            Divider()
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    MouseDiagram(selected: $selection, caption: caption)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(minWidth: 420)
                Divider().padding(.vertical, 28)
                ScrollView {
                    inspector.padding(24)
                }.frame(width: 286)
            }
            if let profileError {
                Text(profileError).font(.caption).foregroundStyle(.red).padding(12)
            }
        }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: selection.symbol).font(.title).foregroundStyle(Color.accentColor)
                .frame(width: 48, height: 48).background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 7) {
                Text(selection.title).font(.title3.weight(.semibold))
                Text(selection.detail).font(.callout).foregroundStyle(.secondary)
            }
            if selection == .thumbwheel {
                Text("Horizontal scrolling").font(.headline)
                Toggle("Reverse direction", isOn: Binding(
                    get: { configuration.scrolling.horizontal.reverse.effective == true },
                    set: { value in store.updateDevice(device.key) { $0.scrolling.horizontal.reverse = value ? .on(true) : .off(false) } }
                ))
                Text("Wheel settings apply in every application. More controls are in Point & Scroll.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ON CLICK").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ActionEditor(action: actionBinding(selection), defaultLabel: selection.defaultLabel)
                        .disabled(!canEdit(selection))
                }
                if selection.needsHID && !canEdit(selection) {
                    Label("Connect your mouse and allow Input Monitoring to configure this button.", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if selection == .thumb && canEdit(selection) {
                    Divider()
                    Toggle("Hold & move gestures", isOn: Binding(get: { buttons.thumbButton.gestures.enabled }, set: { enabled in
                        updateButtons { settings in
                            settings.thumbButton.gestures.enabled = enabled
                            if enabled && !settings.thumbButton.tap.enabled { settings.thumbButton.tap = .on(.missionControl) }
                        }
                    }))
                        .disabled(!isPreview && device.capabilities?.thumbGestures != true)
                        .toggleStyle(.switch).font(.callout)
                    if buttons.thumbButton.gestures.enabled {
                        ForEach(GestureDirection.allCases, id: \.self) { direction in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(direction.displayName).font(.caption).foregroundStyle(.secondary)
                                ActionEditor(action: gestureBinding(direction), defaultLabel: "Do nothing")
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Gesture distance").font(.caption)
                            Slider(value: buttonBinding(\.thumbButton.threshold), in: 20...200, step: 5)
                                .accessibilityLabel("Gesture distance")
                        }
                    }
                }
                Divider()
                Text(profileID == nil
                     ? "Used in applications without a profile."
                     : "Used when this app is active. This profile has its own button bindings.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if action(for: selection) != nil {
                    Button("Restore default") { setAction(nil, for: selection) }
                        .buttonStyle(.link).font(.caption)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(selection)
    }

    private func canEdit(_ control: MouseControl) -> Bool {
        if !control.needsHID || isPreview { return true }
        guard device.supportsHardwareSettings, let capabilities = device.capabilities else { return false }
        return control == .thumb ? capabilities.thumbButton : capabilities.wheelModeButton
    }

    private func action(for control: MouseControl) -> Action? {
        if let number = control.buttonNumber {
            return buttons.mappings.effective?.first { $0.button == number && $0.modifiers.isEmpty }?.action
        }
        if control == .wheelMode { return buttons.wheelModeButton.effective }
        if control == .thumb { return buttons.thumbButton.tap.effective ?? (buttons.thumbButton.gestures.enabled ? Action.none : nil) }
        return nil
    }

    private func caption(_ control: MouseControl) -> String {
        if control == .thumb && buttons.thumbButton.gestures.enabled { return "Click + gestures" }
        if control == .thumbwheel && configuration.scrolling.horizontal.reverse.effective == true { return "Reversed scroll" }
        return action(for: control)?.displayName ?? control.defaultLabel
    }

    private func actionBinding(_ control: MouseControl) -> Binding<Action?> {
        Binding(get: { action(for: control) }, set: { setAction($0, for: control) })
    }

    private func setAction(_ action: Action?, for control: MouseControl) {
        updateButtons { settings in
            if let number = control.buttonNumber {
                settings.mappings.value.removeAll { $0.button == number && $0.modifiers.isEmpty }
                if let action { settings.mappings.value.append(ButtonMapping(button: number, action: action)) }
                settings.mappings.enabled = !settings.mappings.value.isEmpty
            } else if control == .wheelMode {
                settings.wheelModeButton = action.map { .on($0) } ?? .off(.toggleWheelRatchet)
            } else if control == .thumb {
                if let action { settings.thumbButton.tap = .on(action) } else { settings.thumbButton = GestureButtonSettings() }
            }
        }
    }

    private func buttonBinding<Value>(_ path: WritableKeyPath<ButtonSettings, Value>) -> Binding<Value> {
        Binding(get: { buttons[keyPath: path] }, set: { value in updateButtons { $0[keyPath: path] = value } })
    }

    private func gestureBinding(_ direction: GestureDirection) -> Binding<Action?> {
        Binding(get: { buttons.thumbButton.gestures.value[direction] }, set: { value in
            updateButtons { $0.thumbButton.gestures.value[direction] = value ?? Action.none }
        })
    }

    private func updateButtons(_ update: (inout ButtonSettings) -> Void) {
        store.updateDevice(device.key) { configuration in
            configuration.displayName = device.displayName
            if let profileID, var profile = configuration.applicationBindings[profileID] {
                update(&profile.buttons)
                configuration.applicationBindings[profileID] = profile
            } else {
                update(&configuration.buttons)
            }
        }
    }

    private func addApplication() {
        let panel = NSOpenPanel()
        panel.title = "Add application bindings"
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let identifier = Bundle(url: url)?.bundleIdentifier else {
            profileError = "This application has no bundle identifier."
            return
        }
        store.updateDevice(device.key) { configuration in
            if configuration.applicationBindings[identifier] == nil {
                configuration.applicationBindings[identifier] = ApplicationButtonBindings(
                    displayName: url.deletingPathExtension().lastPathComponent, buttons: configuration.buttons)
            }
        }
        profileError = nil
        profileID = identifier
    }

    private func removeProfile() {
        guard let identifier = profileID else { return }
        profileID = nil
        store.updateDevice(device.key) { $0.applicationBindings.removeValue(forKey: identifier) }
    }
}
