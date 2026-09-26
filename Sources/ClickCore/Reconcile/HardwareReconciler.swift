// MIT License
// Copyright (c) 2026 LoLiMouse contributors

import Combine
import Foundation
import HIDKit
import HIDPP
import os.log

/// Brings each device's hardware into line with its configuration, and keeps it
/// there.
///
/// Three things make this different from just writing settings when the user
/// clicks something:
///
/// 1. **Volatile settings.** SmartShift, DPI, wheel mode and button diversion
///    live in the mouse's RAM. A power cycle — switching the mouse off, letting
///    it sleep, moving it between receivers — silently reverts every one of
///    them. So the desired state is reapplied on every arrival, not just once.
///
/// 2. **The boot race.** A mouse that has just reconnected will accept a HID++
///    write and then finish booting, discarding it. A single confirming reapply
///    a few seconds later costs nothing and closes that window.
///
/// 3. **Restoring on disable.** The first time a setting is written, the value
///    that was there before is remembered. Switching the setting off puts that
///    value back, so Click leaves no trace of features you stopped using.
public final class HardwareReconciler: ObservableObject {
    private static let log = LoLiLog.reconcile

    /// What happened on the last attempt, for the UI to show.
    public enum Status: Equatable {
        case idle
        case applying
        case applied
        case waitingForDevice
        case failed(String)
    }

    @Published public private(set) var statuses: [String: Status] = [:]

    /// Called on the main thread once the mouse has taken a DPI value Click
    /// asked for — written, or found already in force. What the menu bar
    /// announces after a preset change is this, not the configuration, so a
    /// write the mouse never received is never reported as done.
    public var onDPIApplied: ((ManagedDevice, Int) -> Void)?

    private let queue = DispatchQueue(label: "\(LoLiLog.subsystem).reconcile", qos: .utility)
    private let stateLock = NSLock()
    private var baselines: [String: Baseline] = [:]
    private var pendingRetries: [String: DispatchWorkItem] = [:]
    private var attemptCounts: [String: Int] = [:]
    private var generations: [String: Int] = [:]
    /// Set between the system's will-sleep and did-wake notifications. While
    /// the Mac is asleep it still surfaces periodically (DarkWake, for mail
    /// and backups), and any HID traffic we send in that window can promote
    /// the DarkWake into a full wake — lit screen, fans, the lot. So nothing
    /// is written while suspended; the wake handler reapplies everything.
    private var suspended = false

    /// Backoff schedule. The device is usually simply asleep, so the early
    /// retries are quick and the later ones back off to avoid waking it
    /// pointlessly.
    private static let retryDelays: [TimeInterval] = [1, 3, 8, 20]
    /// Delay before the confirming reapply that beats the firmware boot race.
    private static let confirmDelay: TimeInterval = 3

    public init() {}

    /// Values as they were before Click first wrote them.
    private struct Baseline {
        var smartShift: HIDPPSmartShift?
        var wheelMode: HIDPPWheelMode?
        var dpi: UInt16?
        var reportRate: Int?
        var pointerResolution: Double?
        var pointerAcceleration: Double?
        var linearScaling: Int?
        var divertedControls: [HIDPPControlID: HIDPPControlReporting] = [:]
        var rawXYControls: Set<HIDPPControlID> = []
    }

    // MARK: - Entry points

    /// Applies `configuration` to `device`.
    ///
    /// `confirm` schedules the extra pass that guards against the boot race and
    /// should be set when the device has just appeared.
    public func reconcile(
        device: ManagedDevice,
        configuration: DeviceConfiguration,
        globallyEnabled: Bool,
        confirm: Bool = false,
        reason: String
    ) {
        cancelRetry(for: device.key)
        stateLock.lock()
        let generation = (generations[device.key] ?? 0) + 1
        generations[device.key] = generation
        stateLock.unlock()
        guard !isSuspended else {
            os_log("asleep; %{public}@ (%{public}@) deferred until wake",
                   log: Self.log, type: .info, device.displayName, reason)
            return
        }
        setStatus(.applying, for: device.key)

        queue.async { [weak self] in
            guard let self, isCurrent(device.key, generation), !isSuspended else { return }
            os_log("reconciling %{public}@ (%{public}@)",
                   log: Self.log, type: .info, device.displayName, reason)

            let outcome = apply(device: device,
                                configuration: configuration,
                                globallyEnabled: globallyEnabled)

            guard isCurrent(device.key, generation), !isSuspended else { return }
            switch outcome {
            case .success:
                attemptCounts[device.key] = 0
                setStatus(.applied, for: device.key)
                if confirm {
                    scheduleConfirm(device: device,
                                    configuration: configuration,
                                    globallyEnabled: globallyEnabled,
                                    generation: generation)
                }
            case .nothingToDo:
                attemptCounts[device.key] = 0
                setStatus(.idle, for: device.key)
            case let .retryable(message):
                scheduleRetry(device: device,
                              configuration: configuration,
                              globallyEnabled: globallyEnabled,
                              message: message,
                              generation: generation)
            case let .permanent(message):
                attemptCounts[device.key] = 0
                setStatus(.failed(message), for: device.key)
            }
        }
    }

    /// Stops all writes until `resume()`. Pending retries and confirmations
    /// are dropped rather than parked: the wake handler reconciles every
    /// device from scratch, so nothing is lost.
    public func suspend() {
        stateLock.lock()
        suspended = true
        for key in generations.keys { generations[key, default: 0] += 1 }
        let pending = pendingRetries
        pendingRetries.removeAll()
        stateLock.unlock()
        pending.values.forEach { $0.cancel() }
        os_log("suspended for sleep, %{public}d pending write(s) dropped",
               log: Self.log, type: .info, pending.count)
    }

    public func resume() {
        stateLock.lock()
        suspended = false
        stateLock.unlock()
    }

    public var isSuspended: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return suspended
    }

    /// Attempts restoration within one deadline, retaining any failed baseline.
    /// Used when quitting or losing permission.
    ///
    /// Bounded on purpose. This runs from `applicationWillTerminate`, where the
    /// work is blocking HID traffic against a device that may be asleep and
    /// will simply time out. macOS gives a terminating app limited time before
    /// killing it, and being killed mid-teardown is how devices get left in a
    /// bad state — so we give up rather than hang.
    public func restoreAll(devices: [ManagedDevice], timeout: TimeInterval = 2) {
        suspend()
        guard !devices.isEmpty else { return }
        let deadline = ProcessInfo.processInfo.systemUptime + max(0, timeout)
        for device in devices { device.endpoint?.prepareForRestoration(until: deadline) }
        let finished = DispatchSemaphore(value: 0)
        queue.async { [weak self] in
            guard let self else { finished.signal(); return }
            // Recover every device's buttons before spending time on wheel,
            // DPI or polling rate. No ping/probe precedes these writes.
            for stage in RestorationStage.allCases {
                for device in devices {
                    guard ProcessInfo.processInfo.systemUptime < deadline else { break }
                    restore(device: device, stage: stage, deadline: deadline)
                }
            }
            finished.signal()
        }
        let remaining = max(0, deadline - ProcessInfo.processInfo.systemUptime)
        if finished.wait(timeout: .now() + remaining) == .timedOut {
            os_log("device restoration deadline reached; unavailable controls may require a mouse power cycle",
                   log: Self.log, type: .error)
        }
    }

    package enum RestorationStage: CaseIterable, Equatable { case controls, settings }

    // MARK: - Application

    package enum Outcome: Equatable {
        case success
        case nothingToDo
        case retryable(String)
        case permanent(String)
    }

    package static func failureOutcome(_ error: HIDPPError, operation: String) -> Outcome {
        let message = "\(operation): \(error.description)"
        return error.isTransient ? .retryable(message) : .permanent(message)
    }

    private func apply(
        device: ManagedDevice,
        configuration: DeviceConfiguration,
        globallyEnabled: Bool
    ) -> Outcome {
        guard !isSuspended else { return .nothingToDo }
        var didSomething = false
        var transientFailure: String?
        var permanentFailure: String?

        // Pointer settings go through macOS and never fail transiently.
        if let service = device.pointerService {
            applyPointer(service: service,
                         key: device.key,
                         settings: globallyEnabled ? configuration.pointer : PointerSettings())
            didSomething = didSomething || configuration.pointer.managesAnything
        }

        let hardware = globallyEnabled ? configuration.hardware : HardwareSettings()
        let buttons = globallyEnabled ? configuration.buttons : ButtonSettings()
        guard let target = device.target else {
            if hardware.managesAnything || !buttons.divertedControls.isEmpty {
                return .permanent("This device cannot apply the configured HID++ settings.")
            }
            return didSomething ? .success : .nothingToDo
        }

        guard hardware.managesAnything || buttons.divertedControls.isEmpty == false || hasBaseline(device.key)
        else {
            return .nothingToDo
        }

        // A sleeping device answers nothing; there is no point issuing five
        // writes that will each wait out their own timeout.
        guard target.ping() else {
            return .retryable("device is not responding")
        }

        func record(_ result: Result<some Any, HIDPPError>, _ what: String) {
            switch result {
            case .success:
                didSomething = true
            case let .failure(error):
                switch Self.failureOutcome(error, operation: what) {
                case let .retryable(message): transientFailure = message
                case let .permanent(message): permanentFailure = message
                default: break
                }
            }
        }

        guard !isSuspended else { return .nothingToDo }
        record(applyDiversion(target: target, key: device.key, buttons: buttons), "button diversion")
        guard !isSuspended else { return .nothingToDo }
        record(applyWheelRatchet(target: target, key: device.key, setting: hardware.wheelRatchet), "wheel ratchet")
        guard !isSuspended else { return .nothingToDo }
        record(applyWheelMode(target: target,
                              key: device.key,
                              highResolution: hardware.highResolutionWheel,
                              inverted: hardware.invertScrollInFirmware), "wheel mode")
        guard !isSuspended else { return .nothingToDo }
        record(applyDPI(target: target, device: device, hardware: hardware), "DPI")
        guard !isSuspended else { return .nothingToDo }
        record(applyReportRate(target: target, key: device.key, setting: hardware.reportRate), "report rate")
        guard !isSuspended else { return .nothingToDo }

        if let permanentFailure {
            return .permanent(permanentFailure)
        }
        if let transientFailure {
            return .retryable(transientFailure)
        }
        return didSomething ? .success : .nothingToDo
    }

    // MARK: - Individual settings

    private func applyWheelRatchet(
        target: HIDPPTarget,
        key: String,
        setting: Setting<WheelRatchetSetting>
    ) -> Result<Void, HIDPPError> {
        guard setting.enabled || baseline(key)?.smartShift != nil else { return .success(()) }
        guard target.supportsSmartShift else {
            return .failure(.featureUnsupported(.smartShift))
        }

        guard let desired = setting.effective else {
            // Switched off: put back whatever the device had before we started.
            guard let baseline = baseline(key)?.smartShift else { return .success(()) }
            let result = target.setSmartShift(mode: baseline.mode,
                                              autoDisengage: baseline.autoDisengage,
                                              torque: baseline.torque)
            if case .success = result { mutateBaseline(key) { $0.smartShift = nil } }
            return result.map { _ in () }
        }

        let read = target.smartShift()
        guard case let .success(currentState) = read else { return read.map { _ in () } }
        let current: HIDPPSmartShift? = currentState
        captureBaselineIfNeeded(key, current, \.smartShift)

        // Skip the write when the device already holds the desired state. This
        // keeps a reapply on every scan essentially free.
        if let current,
           current.mode == desired.hidppMode,
           current.autoDisengage == desired.hidppAutoDisengage,
           desired.torque == nil || current.torque == desired.torque.map({ UInt8(clamping: $0) }) {
            return .success(())
        }

        return target.setSmartShift(
            mode: desired.hidppMode,
            autoDisengage: desired.hidppAutoDisengage,
            torque: desired.torque.map { UInt8(clamping: $0) }
        ).map { _ in () }
    }

    private func applyWheelMode(
        target: HIDPPTarget,
        key: String,
        highResolution: Setting<Bool>,
        inverted: Setting<Bool>
    ) -> Result<Void, HIDPPError> {
        guard highResolution.enabled || inverted.enabled || baseline(key)?.wheelMode != nil else {
            return .success(())
        }
        guard target.supports(.hiResWheel) else {
            return .failure(.featureUnsupported(.hiResWheel))
        }

        let currentResult = target.wheelMode()
        guard case let .success(current) = currentResult else {
            return currentResult.map { _ in () }
        }
        captureBaselineIfNeeded(key, current, \.wheelMode)

        let baselineMode = baseline(key)?.wheelMode
        let desiredResolution: HIDPPWheelResolution = highResolution.effective.map { $0 ? .high : .low }
            ?? baselineMode?.resolution ?? current.resolution
        let desiredInverted = inverted.effective ?? baselineMode?.inverted ?? current.inverted

        let restoring = !highResolution.enabled && !inverted.enabled
        let desiredTarget: HIDPPWheelTarget = restoring ? (baselineMode?.target ?? .native) : .native
        if current.resolution == desiredResolution,
           current.inverted == desiredInverted,
           current.target == desiredTarget {
            if restoring { mutateBaseline(key) { $0.wheelMode = nil } }
            return .success(())
        }
        let result = target.setWheelMode(target: desiredTarget,
                                         resolution: desiredResolution,
                                         inverted: desiredInverted).map { _ in () }
        if restoring, case .success = result { mutateBaseline(key) { $0.wheelMode = nil } }
        return result
    }

    private func applyDPI(
        target: HIDPPTarget,
        device: ManagedDevice,
        hardware: HardwareSettings
    ) -> Result<Void, HIDPPError> {
        let key = device.key
        // Presets win when enabled: the active preset is the DPI in force.
        let desired: Int? = hardware.dpiPresets.effective?.active ?? hardware.dpi.effective

        guard desired != nil || baseline(key)?.dpi != nil else { return .success(()) }
        guard target.supports(.adjustableDPI) else {
            return .failure(.featureUnsupported(.adjustableDPI))
        }

        let currentResult = target.dpi()
        guard case let .success(current) = currentResult else {
            return currentResult.map { _ in () }
        }
        captureBaselineIfNeeded(key, current.current, \.dpi)
        publishDPI(Int(current.current), on: device, applied: false)

        guard let desired else {
            guard let baselineDPI = baseline(key)?.dpi else { return .success(()) }
            let result = target.setDPI(baselineDPI)
            if case .success = result { mutateBaseline(key) { $0.dpi = nil } }
            if case .success = result { publishDPI(Int(baselineDPI), on: device, applied: false) }
            return result
        }

        let value = UInt16(clamping: desired)
        let result = current.current == value ? .success(()) : target.setDPI(value)
        if case .success = result { publishDPI(Int(value), on: device, applied: true) }
        return result
    }

    private func publishDPI(_ dpi: Int, on device: ManagedDevice, applied: Bool) {
        DispatchQueue.main.async { [weak self] in
            device.dpi = dpi
            if applied { self?.onDPIApplied?(device, dpi) }
        }
    }

    private func applyReportRate(
        target: HIDPPTarget,
        key: String,
        setting: Setting<Int>
    ) -> Result<Void, HIDPPError> {
        guard setting.enabled || baseline(key)?.reportRate != nil else { return .success(()) }
        guard target.supports(.reportRate) else {
            return .failure(.featureUnsupported(.reportRate))
        }

        let currentResult = target.reportRate()
        guard case let .success(current) = currentResult else {
            return currentResult.map { _ in () }
        }
        captureBaselineIfNeeded(key, current, \.reportRate)

        guard let desired = setting.effective else {
            guard let baselineRate = baseline(key)?.reportRate else { return .success(()) }
            let result = target.setReportRate(baselineRate)
            if case .success = result { mutateBaseline(key) { $0.reportRate = nil } }
            return result
        }

        if current == desired { return .success(()) }
        return target.setReportRate(desired)
    }

    /// Diverts exactly the controls the configuration needs, and un-diverts
    /// everything it previously diverted but no longer wants.
    ///
    /// This is what keeps the wheel-mode button toggling SmartShift and the
    /// thumb button opening Mission Control by themselves until the moment the
    /// user asks Click to take them over.
    private func applyDiversion(
        target: HIDPPTarget,
        key: String,
        buttons: ButtonSettings
    ) -> Result<Void, HIDPPError> {
        let desired = buttons.divertedControls
        let previouslyDiverted = Set(baseline(key)?.divertedControls.keys ?? [:].keys)

        guard !desired.isEmpty || !previouslyDiverted.isEmpty else { return .success(()) }
        guard target.supportsReprogrammableControls, target.supportsLongReports else {
            return .failure(.featureUnsupported(.reprogrammableControlsV4))
        }

        let available = target.controlTable().filter(\.isDivertable)
        guard !available.isEmpty else { return .failure(.timeout) }
        var lastError: HIDPPError? = Self.unsupportedButtonConfiguration(buttons, controls: available)
            ? .device(.unsupported) : nil

        for info in available where desired.contains(info.controlID) {
            guard !isSuspended else { return .failure(.timeout) }
            let control = info.controlID
            if baseline(key)?.divertedControls[control] == nil {
                switch target.controlReporting(control) {
                case let .success(reporting):
                    mutateBaseline(key) {
                        $0.divertedControls[control] = reporting
                        if info.supportsRawXY { $0.rawXYControls.insert(control) }
                    }
                case let .failure(error):
                    lastError = error
                    continue
                }
            }
            let change = HIDPPControlReportingChange(diverted: true, rawXY: buttons.rawXY(for: info))
            if case let .failure(error) = target.setControlReporting(control, change) { lastError = error }
        }

        for control in previouslyDiverted.subtracting(desired) {
            guard !isSuspended else { return .failure(.timeout) }
            guard let original = baseline(key)?.divertedControls[control] else { continue }
            let supportsRaw = available.first { $0.controlID == control }?.supportsRawXY == true
            let change = HIDPPControlReportingChange(diverted: original.diverted,
                                                      rawXY: supportsRaw ? original.rawXY : nil)
            if case let .failure(error) = target.setControlReporting(control, change) {
                lastError = error
            } else {
                mutateBaseline(key) { $0.divertedControls.removeValue(forKey: control) }
            }
        }
        if let lastError { return .failure(lastError) }
        return .success(())
    }

    /// Gesture control IDs are alternatives: a device needs one, not all three.
    package static func unsupportedButtonConfiguration(_ buttons: ButtonSettings,
                                                       controls: [HIDPPControlInfo]) -> Bool {
        let available = controls.filter(\.isDivertable)
        let desired = buttons.divertedControls
        if desired.contains(HIDPPControl.wheelModeButton),
           !available.contains(where: { $0.controlID == HIDPPControl.wheelModeButton }) { return true }
        if !desired.isDisjoint(with: HIDPPControl.gestureCapable) {
            let thumb = available.filter { HIDPPControl.gestureCapable.contains($0.controlID) }
            if thumb.isEmpty { return true }
            if !(buttons.thumbButton.gestures.effective ?? [:]).isEmpty,
               !thumb.contains(where: \.supportsRawXY) { return true }
        }
        return false
    }

    private func applyPointer(service: PointerService, key: String, settings: PointerSettings) {
        let original = baseline(key)
        guard settings.managesAnything || original?.pointerResolution != nil
            || original?.pointerAcceleration != nil || original?.linearScaling != nil else { return }
        captureBaselineIfNeeded(key, service.pointerResolution, \.pointerResolution)
        captureBaselineIfNeeded(key, service.pointerAcceleration, \.pointerAcceleration)
        captureBaselineIfNeeded(key, service.linearScalingEnabled, \.linearScaling)

        if let speed = settings.speed.effective {
            // The slider runs 0…1 with 1 as fastest; macOS wants a resolution
            // in counts per inch where *lower* is faster.
            let clamped = min(max(speed, 0), 1)
            service.pointerResolution = 1600 - clamped * 1500
        } else if let original = baseline(key)?.pointerResolution {
            service.pointerResolution = original
            mutateBaseline(key) { $0.pointerResolution = nil }
        }

        if settings.disableAcceleration.effective == true {
            if service.supportsLinearScaling {
                service.linearScalingEnabled = 1
            } else {
                service.pointerAcceleration = -1
            }
        } else {
            if service.supportsLinearScaling, baseline(key)?.linearScaling != nil {
                service.linearScalingEnabled = baseline(key)?.linearScaling ?? 0
                if !settings.disableAcceleration.enabled {
                    mutateBaseline(key) { $0.linearScaling = nil }
                }
            }
            if let acceleration = settings.acceleration.effective {
                service.pointerAcceleration = acceleration
            } else if let original = baseline(key)?.pointerAcceleration {
                service.pointerAcceleration = original
                mutateBaseline(key) { $0.pointerAcceleration = nil }
            }
        }
    }

    private func restore(device: ManagedDevice, stage: RestorationStage, deadline: TimeInterval) {
        guard let baseline = baseline(device.key) else { return }
        func hasTime() -> Bool { ProcessInfo.processInfo.systemUptime < deadline }
        if stage == .controls {
            if let service = device.pointerService {
                if let resolution = baseline.pointerResolution { service.pointerResolution = resolution }
                if let linear = baseline.linearScaling { service.linearScalingEnabled = linear }
                if let acceleration = baseline.pointerAcceleration { service.pointerAcceleration = acceleration }
                mutateBaseline(device.key) {
                    $0.pointerResolution = nil; $0.linearScaling = nil; $0.pointerAcceleration = nil
                }
            }
            guard let target = device.target else { return }
            let controls = baseline.divertedControls.keys.sorted {
                if baseline.rawXYControls.contains($0) != baseline.rawXYControls.contains($1) {
                    return baseline.rawXYControls.contains($0)
                }
                return $0 < $1
            }
            for control in controls {
                guard hasTime(), let reporting = baseline.divertedControls[control] else { return }
                let change = HIDPPControlReportingChange(diverted: reporting.diverted,
                    rawXY: baseline.rawXYControls.contains(control) ? reporting.rawXY : nil)
                if case .success = target.setControlReporting(control, change,
                    timeout: min(0.4, max(0, deadline - ProcessInfo.processInfo.systemUptime))) {
                    mutateBaseline(device.key) {
                        $0.divertedControls.removeValue(forKey: control)
                        $0.rawXYControls.remove(control)
                    }
                }
            }
            return
        }
        guard let target = device.target else { return }
        if let wheel = baseline.smartShift, hasTime(),
           case .success = target.setSmartShift(mode: wheel.mode, autoDisengage: wheel.autoDisengage, torque: wheel.torque) {
            mutateBaseline(device.key) { $0.smartShift = nil }
        }
        if let wheel = baseline.wheelMode, hasTime(),
           case .success = target.setWheelMode(target: wheel.target, resolution: wheel.resolution, inverted: wheel.inverted) {
            mutateBaseline(device.key) { $0.wheelMode = nil }
        }
        if let dpi = baseline.dpi, hasTime(), case .success = target.setDPI(dpi) {
            mutateBaseline(device.key) { $0.dpi = nil }
        }
        if let rate = baseline.reportRate, hasTime(), case .success = target.setReportRate(rate) {
            mutateBaseline(device.key) { $0.reportRate = nil }
        }
    }

    // MARK: - Retry and confirmation

    private func scheduleRetry(
        device: ManagedDevice,
        configuration: DeviceConfiguration,
        globallyEnabled: Bool,
        message: String,
        generation: Int
    ) {
        stateLock.lock()
        let attempt = attemptCounts[device.key] ?? 0
        attemptCounts[device.key] = attempt + 1
        stateLock.unlock()

        guard attempt < Self.retryDelays.count else {
            os_log("giving up on %{public}@ after %{public}d attempts: %{public}@",
                   log: Self.log, type: .error, device.displayName, attempt, message)
            setStatus(.failed(message), for: device.key)
            return
        }

        let delay = Self.retryDelays[attempt]
        setStatus(.waitingForDevice, for: device.key)
        os_log("%{public}@ not ready (%{public}@); retrying in %{public}.0fs",
               log: Self.log, type: .info, device.displayName, message, delay)

        let item = DispatchWorkItem { [weak self] in
            guard let self, isCurrent(device.key, generation), !isSuspended else { return }
            self.reconcile(device: device,
                            configuration: configuration,
                            globallyEnabled: globallyEnabled,
                            reason: "retry \(attempt + 1)")
        }
        stateLock.lock()
        pendingRetries[device.key] = item
        stateLock.unlock()
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func scheduleConfirm(
        device: ManagedDevice,
        configuration: DeviceConfiguration,
        globallyEnabled: Bool,
        generation: Int
    ) {
        let item = DispatchWorkItem { [weak self] in
            guard let self, isCurrent(device.key, generation), !isSuspended else { return }
            os_log("confirming settings on %{public}@", log: Self.log, type: .info, device.displayName)
            _ = apply(device: device, configuration: configuration, globallyEnabled: globallyEnabled)
        }
        stateLock.lock()
        pendingRetries[device.key] = item
        stateLock.unlock()
        queue.asyncAfter(deadline: .now() + Self.confirmDelay, execute: item)
    }

    private func isCurrent(_ key: String, _ generation: Int) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return generations[key] == generation
    }

    private func cancelRetry(for key: String) {
        stateLock.lock()
        pendingRetries.removeValue(forKey: key)?.cancel()
        stateLock.unlock()
    }

    // MARK: - Baseline bookkeeping

    private func baseline(_ key: String) -> Baseline? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return baselines[key]
    }

    private func hasBaseline(_ key: String) -> Bool {
        baseline(key) != nil
    }

    private func mutateBaseline(_ key: String, _ transform: (inout Baseline) -> Void) {
        stateLock.lock()
        var current = baselines[key] ?? Baseline()
        transform(&current)
        baselines[key] = current
        stateLock.unlock()
    }

    /// Records the pre-existing value the first time a setting is written.
    /// Later observations are ignored — by then the value on the device may
    /// already be ours.
    private func captureBaselineIfNeeded<T>(
        _ key: String,
        _ value: T?,
        _ path: WritableKeyPath<Baseline, T?>
    ) {
        guard let value else { return }
        stateLock.lock()
        var current = baselines[key] ?? Baseline()
        if current[keyPath: path] == nil {
            current[keyPath: path] = value
            baselines[key] = current
        }
        stateLock.unlock()
    }

    private func setStatus(_ status: Status, for key: String) {
        DispatchQueue.main.async { [weak self] in
            self?.statuses[key] = status
        }
    }
}
