import ClickCore
import SwiftUI

struct PointScrollView: View {
    @ObservedObject var device: ManagedDevice
    @EnvironmentObject private var store: ConfigurationStore

    var body: some View {
        let model = DeviceSettingsModel(device: device, store: store)
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text("These settings apply to this mouse in every application.")
                    .foregroundStyle(.secondary).font(.callout)
                SettingsSection(title: "Pointer") {
                    ManagedSetting(title: "Custom tracking speed", isManaged: model.enabled(\.pointer.speed)) {
                        LabelledSlider(label: "Speed", value: model.value(\.pointer.speed), range: 0...1,
                                       format: { String(format: "%.0f%%", $0 * 100) })
                    }
                    Divider()
                    Toggle("Disable pointer acceleration", isOn: Binding(
                        get: { model.configuration.pointer.disableAcceleration.effective == true },
                        set: { value in model.binding(\.pointer.disableAcceleration).wrappedValue = value ? .on(true) : .off(false) }
                    ))
                    if device.supportsHardwareSettings && model.supports(\.dpi) {
                        Divider()
                        ManagedSetting(title: "Custom DPI", isManaged: model.enabled(\.hardware.dpi)) {
                            Stepper("\(model.configuration.hardware.dpi.value) DPI", value: model.value(\.hardware.dpi), in: 200...8000, step: 50)
                            Text("The mouse must support the selected DPI; unsupported values are rejected.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                SettingsSection(title: "Scrolling") {
                    Toggle("Reverse vertical scrolling", isOn: reverseBinding(model, horizontal: false))
                    Toggle("Reverse thumb wheel", isOn: reverseBinding(model, horizontal: true))
                    Divider()
                    ManagedSetting(title: "Custom scroll speed", isManaged: model.enabled(\.scrolling.vertical.speed)) {
                        LabelledSlider(label: "Speed", value: model.value(\.scrolling.vertical.speed), range: 0.25...4,
                                       step: 0.05, format: { String(format: "%.2f×", $0) })
                    }
                    Divider()
                    Toggle("One step per wheel click", isOn: Binding(
                        get: { model.configuration.scrolling.normalizeHighResolutionWheel.effective == true },
                        set: { value in model.binding(\.scrolling.normalizeHighResolutionWheel).wrappedValue = value ? .on(true) : .off(true) }
                    ))
                    Text("Useful when a wheel click skips several items in a gallery.").font(.caption).foregroundStyle(.secondary)
                }
                if device.supportsHardwareSettings && model.supports(\.smartShift) {
                    SettingsSection(title: "Scroll wheel") {
                        ManagedSetting(title: "Custom wheel mode", isManaged: model.enabled(\.hardware.wheelRatchet)) {
                            Picker("Mode", selection: model.value(\.hardware.wheelRatchet).mode) {
                                ForEach(WheelRatchetMode.allCases, id: \.self) { mode in Text(mode.displayName).tag(mode) }
                            }
                            if model.configuration.hardware.wheelRatchet.value.mode == .smartShift {
                                Stepper("SmartShift threshold: \(model.configuration.hardware.wheelRatchet.value.threshold)",
                                        value: model.value(\.hardware.wheelRatchet).threshold, in: 8...50)
                            }
                        }
                    }
                }
            }.padding(28).frame(maxWidth: 680)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reverseBinding(_ model: DeviceSettingsModel, horizontal: Bool) -> Binding<Bool> {
        let path: WritableKeyPath<DeviceConfiguration, Setting<Bool>> = horizontal ? \.scrolling.horizontal.reverse : \.scrolling.vertical.reverse
        return Binding(get: { model.configuration[keyPath: path].effective == true },
                       set: { value in model.binding(path).wrappedValue = value ? .on(true) : .off(false) })
    }
}
