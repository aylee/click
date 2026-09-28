// MIT License
// Copyright (c) 2026 LoLiMouse contributors

import AppKit
import Combine
import CoreGraphics
import Foundation
import HIDKit
import HIDPP
import os.log

/// Ties everything together: configuration, devices, hardware reconciliation
/// and the event pipeline.
public final class AppController: ObservableObject {
    private static let log = LoLiLog.app

    public static let shared = AppController()

    public let store: ConfigurationStore
    public let registry = DeviceRegistry()
    public let reconciler = HardwareReconciler()
    public let actions = ActionRunner()

    @Published public private(set) var hasAccessibility = false
    @Published public private(set) var hasInputMonitoring = false
    @Published public private(set) var isRunning = false
    @Published public private(set) var inputError: String?

    /// A DPI value the mouse has just taken because the user switched preset
    /// with a button. The menu bar shows it briefly.
    public let dpiAnnouncements = PassthroughSubject<Int, Never>()
    /// Devices whose next applied DPI should be announced: the value expected,
    /// so a pass already under way with the old one is not taken for it, and
    /// the moment the request stops counting, so a write that failed is not
    /// announced much later by an unrelated reconnect.
    private var pendingDPIAnnouncements: [String: (dpi: Int, deadline: Date)] = [:]
    private static let dpiAnnouncementWindow: TimeInterval = 5

    private lazy var router = DivertedButtonRouter(actions: actions)
    private var eventTap: EventTap?

    /// The event thread's view of the world. Guarded by `snapshotLock`;
    /// everything else in this class stays on the main thread.
    private let snapshotLock = NSLock()
    private var snapshot = EventSnapshot()

    /// One scroll processor per device, so accumulator state is not shared
    /// between a mouse and a trackball plugged in at the same time.
    private var scrollProcessors: [String: ScrollProcessor] = [:]
    /// One modifier transformer per device, for the same reason — pinch state
    /// must not leak between devices.
    private var modifierTransformers: [String: ModifierKeyTransformer] = [:]
    /// Only ever touched from the event thread.
    private var swallowedButtons = ButtonPressTracker()
    /// When the last rescan was requested because an event carried a sender
    /// ID nobody in the registry owns. Only ever touched from the event thread.
    private var lastUnknownSenderRescan: TimeInterval = 0

    private var subscriptions = Set<AnyCancellable>()
    private var permissionTimer: Timer?
    private var batteryTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var activeBundleID: String?
    private var canHandleInput: Bool { hasAccessibility && hasInputMonitoring }

    public init(store: ConfigurationStore = ConfigurationStore()) {
        self.store = store
        actions.onDeviceAction = { [weak self] action, device in
            self?.performDeviceAction(action, device: device)
        }
        reconciler.onDPIApplied = { [weak self] device, dpi in
            guard let self, let pending = pendingDPIAnnouncements[device.key], pending.dpi == dpi else { return }
            pendingDPIAnnouncements.removeValue(forKey: device.key)
            if pending.deadline > Date() { dpiAnnouncements.send(dpi) }
        }
        router.configurationProvider = { [weak self] key in
            guard let self, isRunning, store.configuration.enabled, canHandleInput else { return nil }
            return activeConfiguration(for: key)
        }
    }

    // MARK: - Lifecycle

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        reconciler.resume()
        activeBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        refreshPermissions()

        registry.onDevicesChanged = { [weak self] devices, arrived in
            self?.devicesChanged(devices, arrived: arrived)
        }
        if hasInputMonitoring { registry.start() }

        store.$configuration
            .removeDuplicates()
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] configuration in
                self?.configurationChanged(configuration)
            }
            .store(in: &subscriptions)

        updateEventTap()

        // Permissions are granted outside the app, so poll for the moment they
        // appear rather than making the user restart.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.refreshPermissions()
            // A failed tap creation can coexist with unchanged TCC grants.
            // Retry that failure without reopening HID endpoints or requiring
            // another settings edit to restart ordinary button handling.
            if self.inputError != nil { self.updateEventTap() }
        }

        startBatteryTimer()

        // A sleeping Mac still wakes briefly on its own (DarkWake) and any HID
        // request we make then can turn that into a full wake. So the battery
        // poll and the reconciler are both parked until the real wake. Learned
        // from OpenLogi, which hit exactly this.
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isRunning else { return }
            os_log("going to sleep; pausing HID traffic", log: Self.log, type: .info)
            batteryTimer?.invalidate()
            batteryTimer = nil
            reconciler.suspend()
        })
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isRunning else { return }
            // Waking from sleep is the single most reliable way to lose every
            // volatile hardware setting at once.
            os_log("woke from sleep; reapplying everything", log: Self.log, type: .info)
            reconciler.resume()
            reconcileAll(confirm: true, reason: "system wake")
            registry.refreshBatteries()
            startBatteryTimer()
            // A Bluetooth mouse comes back from sleep with a freshly created
            // event service, and the sender ID stamped on its scroll events
            // changes with it. The IDs the registry remembers are from the
            // last scan, so scan again or the tap will not recognise the
            // mouse. Cost the reverse-scroll setting one morning.
            registry.rescan()
        })
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self, self.isRunning else { return }
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            guard bundleID != activeBundleID else { return }
            activeBundleID = bundleID
            router.resetPresses()
            configurationChanged(store.configuration)
        })
    }

    /// Battery drains over hours; ten minutes keeps the reading honest without
    /// waking the mouse's radio for nothing.
    private func startBatteryTimer() {
        batteryTimer?.invalidate()
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            self?.registry.refreshBatteries()
        }
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        inputError = nil

        subscriptions.removeAll()
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        workspaceObservers.removeAll()
        registry.onDevicesChanged = nil
        permissionTimer?.invalidate()
        permissionTimer = nil
        batteryTimer?.invalidate()
        batteryTimer = nil
        removeEventTap()
        router.detachAll()
        // Quitting while asleep is rare but must still put the mouse back.
        reconciler.resume()
        reconciler.restoreAll(devices: registry.devices)
        registry.stop()
        store.flush()
    }

    // MARK: - Permissions

    public func refreshPermissions() {
        let accessibility = EventTap.hasAccessibilityPermission
        let hidAccess = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        let inputMonitoring = Self.inputMonitoringGranted(
            hidAccess, hasOpenEndpoint: registry.devices.contains { $0.endpoint?.isOpen == true })

        if !hasLoggedPermissions || accessibility != hasAccessibility || inputMonitoring != hasInputMonitoring {
            hasLoggedPermissions = true
            os_log("""
            permissions: accessibility=%{public}@ inputMonitoring=%{public}@ \
            (IOHIDCheckAccess=%{public}d) bundle=%{public}@ path=%{public}@
            """,
            log: Self.log, type: .info,
            accessibility ? "granted" : "denied",
            inputMonitoring ? "granted" : "denied",
            hidAccess.rawValue,
            Bundle.main.bundleIdentifier ?? "(none)",
            Bundle.main.bundlePath)
        }

        if accessibility != hasAccessibility || inputMonitoring != hasInputMonitoring {
            let revoked = (hasAccessibility && !accessibility) || (hasInputMonitoring && !inputMonitoring)
            hasAccessibility = accessibility
            hasInputMonitoring = inputMonitoring
            guard isRunning else { return }
            if revoked {
                // Publish disabled routing before draining callbacks or touching
                // hardware; cached handles never grant continued input access.
                rebuildProcessors(registry.devices)
                removeEventTap()
                router.detachAll()
                reconciler.restoreAll(devices: registry.devices, timeout: 1)
                registry.stop()
            }
            if canHandleInput {
                reconciler.resume()
                registry.start()
            }
            configurationChanged(store.configuration)
            if canHandleInput { registry.rescan() }
        }
    }

    package static func inputMonitoringGranted(_ access: IOHIDAccessType, hasOpenEndpoint: Bool) -> Bool {
        switch access {
        case kIOHIDAccessTypeGranted: return true
        case kIOHIDAccessTypeDenied: return false
        default: return hasOpenEndpoint
        }
    }

    /// Ensures the permission state is logged at least once per launch, even
    /// when nothing changes — otherwise a permanently denied grant is silent.
    private var hasLoggedPermissions = false

    public func requestAccessibility() {
        EventTap.requestAccessibilityPermission()
    }

    public func requestInputMonitoring() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    public func openPrivacyPane(_ anchor: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
        if let url { NSWorkspace.shared.open(url) }
    }

    // MARK: - Events

    /// Installs or removes the event tap to match what the configuration
    /// actually needs.
    ///
    /// An active tap at the HID level sits in the path of every input event on
    /// the machine, so Click only installs one while at least one device
    /// has scrolling or button settings switched on. With nothing configured
    /// the app has no presence in the input path at all — which is both the
    /// safe default and the honest one.
    private func updateEventTap() {
        guard isRunning else { return }
        let configuration = store.configuration
        let needed = configuration.enabled && canHandleInput && registry.devices.contains {
            configuration.device($0.key).usesEventTap
        }

        if !needed {
            inputError = nil
            snapshotLock.lock()
            let hasPendingRelease = !swallowedButtons.isEmpty
            snapshotLock.unlock()
            if hasPendingRelease { return }
            if eventTap != nil {
                os_log("no scrolling or button settings are active; removing the event tap",
                       log: Self.log, type: .info)
                removeEventTap()
            }
            return
        }

        // `flagsChanged` is watched only while some device binds a modifier to
        // pinch zoom — it is what ends the synthesised gesture. Every other
        // configuration keeps the narrower mask.
        var watched = EventTap.defaultWatchedEvents
        let wantsFlags = configuration.enabled && registry.devices.contains {
            configuration.device($0.key).scrolling.wantsFlagsChanged
        }
        if wantsFlags { watched.append(.flagsChanged) }

        if let eventTap, eventTap.watchedEvents != watched {
            os_log("the set of watched events changed; replacing the event tap",
                   log: Self.log, type: .info)
            removeEventTap()
        }

        guard eventTap == nil, EventTap.hasAccessibilityPermission else { return }

        let tap = EventTap(watchedEvents: watched) { [weak self] event, type in
            guard let self else { return event }
            return self.handle(event: event, type: type)
        }
        tap.onPermissionLost = { [weak self] in
            self?.removeEventTap()
            self?.refreshPermissions()
        }
        let started = tap.start(reportFailure: inputError == nil)
        if started { eventTap = tap }
        inputError = Self.inputStartError(needed: canHandleInput, started: started)
    }

    package static func inputStartError(needed: Bool, started: Bool) -> String? {
        needed && !started ? "Couldn’t start button and scroll control. Retrying…" : nil
    }

    /// Stops the tap and ends any synthesised gesture still in flight, so an
    /// application never sees a pinch that began and never ended.
    private func removeEventTap() {
        eventTap?.stop()
        eventTap = nil
        snapshotLock.lock()
        swallowedButtons = ButtonPressTracker()
        snapshotLock.unlock()
        for transformer in modifierTransformers.values {
            transformer.deactivate()
        }
    }

    /// Runs on the event thread for every input event in the system. Anything
    /// slow here is felt as input lag, so the fast path is kept short.
    ///
    /// The tap callback runs on its own thread while devices and configuration
    /// live on the main thread, so it never reads either directly. Instead it
    /// takes one lock, copies out an immutable snapshot, and works from that.
    private func handle(event: CGEvent, type: CGEventType) -> CGEvent? {
        guard !event.isSynthetic else { return event }

        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        let snapshot = self.snapshot
        if type == .otherMouseUp {
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            if swallowedButtons.release(
                button: button, senderID: event.senderID,
                sourcePID: event.getIntegerValueField(.eventSourceUnixProcessID)
            ) {
                if swallowedButtons.isEmpty {
                    DispatchQueue.main.async { [weak self] in self?.updateEventTap() }
                }
                return nil
            }
            return event
        }
        guard snapshot.enabled else { return event }

        switch type {
        case .scrollWheel:
            return handleScroll(event, snapshot: snapshot)
        case .flagsChanged:
            // A modifier was pressed or released. Devices cannot be told apart
            // here (the event comes from the keyboard), so every transformer
            // gets the chance to end its pinch. Never swallowed.
            for transformer in snapshot.modifierTransformers.values {
                _ = transformer.process(event, type: type)
            }
            return event
        case .otherMouseDown, .otherMouseUp:
            return handleButton(event, snapshot: snapshot)
        default:
            return event
        }
    }

    private func handleScroll(_ event: CGEvent, snapshot: EventSnapshot) -> CGEvent? {
        guard !ScrollWheelEvent(event).looksLikeTrackpad else { return event }
        guard let key = snapshot.deviceKey(for: event) else {
            noteUnknownSender(of: event)
            return event
        }

        var current = event
        if let transformer = snapshot.modifierTransformers[key] {
            guard let transformed = transformer.process(current, type: .scrollWheel) else { return nil }
            current = transformed
        }
        guard let processor = snapshot.processors[key] else { return current }
        return processor.process(current)
    }

    private func handleButton(_ event: CGEvent, snapshot: EventSnapshot) -> CGEvent? {
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))

        let senderID = event.senderID
        let sourcePID = event.getIntegerValueField(.eventSourceUnixProcessID)
        guard let key = Self.buttonDeviceKey(
            senderID: senderID, sourcePID: sourcePID,
            senderToKey: snapshot.senderToKey, connectedMouseKeys: Array(snapshot.devices.keys),
            mouseServiceCount: snapshot.mouseServiceCount
        ) else {
            noteUnknownSender(of: event)
            return event
        }
        guard let mapping = ButtonMapping.bestMatch(
                  in: snapshot.buttonMappings[key] ?? [],
                  button: button,
                  held: ModifierKey.held(in: event.flags)
              )
        else {
            return event
        }

        guard actions.run(mapping.action, device: snapshot.devices[key]) else { return event }
        swallowedButtons.swallow(button: button, senderID: senderID, sourcePID: sourcePID)
        return nil
    }

    /// Some Bluetooth button events carry no HID sender. Only attribute those
    /// to a mouse when exactly one device and one non-trackpad service are live.
    /// Multiple services fail closed, even when they may belong to one mouse.
    package static func buttonDeviceKey(
        senderID: UInt64?, sourcePID: Int64,
        senderToKey: [UInt64: String], connectedMouseKeys: [String], mouseServiceCount: Int
    ) -> String? {
        if let senderID { return senderToKey[senderID] }
        guard sourcePID == 0, connectedMouseKeys.count == 1, mouseServiceCount == 1 else { return nil }
        return connectedMouseKeys.first
    }

    /// An event arrived from a sender the registry does not know. That is
    /// what a Bluetooth mouse looks like after a reconnect the HID monitor
    /// did not report (its event service was recreated with a new registry
    /// ID), so ask for a rescan — at most once every few seconds, because a
    /// wheel produces hundreds of events and one scan is enough.
    ///
    /// Runs on the event thread; the registry is poked from the main queue.
    private func noteUnknownSender(of event: CGEvent) {
        guard event.senderID != nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastUnknownSenderRescan > 5 else { return }
        lastUnknownSenderRescan = now
        os_log("event from unknown sender 0x%llX; rescanning devices",
               log: Self.log, type: .info, event.senderID ?? 0)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRunning else { return }
            registry.rescan()
        }
    }

    /// An immutable view of everything the event thread needs, published from
    /// the main thread whenever devices or configuration change.
    private struct EventSnapshot {
        var enabled = false
        var senderToKey: [UInt64: String] = [:]
        var processors: [String: ScrollProcessor] = [:]
        var modifierTransformers: [String: ModifierKeyTransformer] = [:]
        var buttonMappings: [String: [ButtonMapping]] = [:]
        var devices: [String: ManagedDevice] = [:]
        var mouseServiceCount = 0

        func deviceKey(for event: CGEvent) -> String? {
            if let senderID = event.senderID, let key = senderToKey[senderID] {
                return key
            }
            return nil
        }
    }

    // MARK: - Reacting to change

    private func devicesChanged(_ devices: [ManagedDevice], arrived: [ManagedDevice]) {
        guard isRunning else { return }
        for device in arrived { multiplierCache.removeValue(forKey: device.key) }
        router.retain(devices)
        rebuildProcessors(devices)
        updateEventTap()

        for device in devices {
            let configuration = activeConfiguration(for: device.key)
            if !configuration.buttons.divertedControls.isEmpty {
                router.attach(device)
            }
            // Remember the name so an unplugged device still has a label.
            if store.configuration.devices[device.key] != nil,
               store.configuration.device(device.key).displayName != device.displayName {
                store.updateDevice(device.key) { $0.displayName = device.displayName }
            }
        }

        // A device that has just appeared gets the confirming second pass; the
        // rest only need reconciling if something actually changed.
        for device in arrived {
            reconciler.reconcile(
                device: device,
                configuration: activeConfiguration(for: device.key),
                globallyEnabled: store.configuration.enabled && canHandleInput,
                confirm: true,
                reason: "device arrived"
            )
        }

        refreshPermissions()
    }

    private func configurationChanged(_ configuration: Configuration) {
        guard isRunning else { return }
        rebuildProcessors(registry.devices)
        updateEventTap()

        for device in registry.devices {
            let deviceConfiguration = activeConfiguration(for: device.key)
            if deviceConfiguration.buttons.divertedControls.isEmpty {
                router.detach(device.key)
            } else {
                router.attach(device)
            }
            reconciler.reconcile(
                device: device,
                configuration: deviceConfiguration,
                globallyEnabled: configuration.enabled && canHandleInput,
                reason: "configuration changed"
            )
        }
    }

    /// Rebuilds the event thread's snapshot. Main thread only.
    private func rebuildProcessors(_ devices: [ManagedDevice]) {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        let configuration = store.configuration

        var processors: [String: ScrollProcessor] = [:]
        var transformers: [String: ModifierKeyTransformer] = [:]
        var senderToKey: [UInt64: String] = [:]
        var buttonMappings: [String: [ButtonMapping]] = [:]
        var deviceMap: [String: ManagedDevice] = [:]

        for device in devices where !device.isTrackpad {
            let deviceConfiguration = activeConfiguration(for: device.key)

            // Reuse the existing processor so accumulator state survives a
            // settings change made in the middle of a scroll.
            let processor = scrollProcessors[device.key] ?? ScrollProcessor()
            processor.settings = deviceConfiguration.scrolling
            processor.highResolutionMultiplier = multiplier(for: device)
            processors[device.key] = processor

            // Same for the modifier transformer: replacing it mid-pinch would
            // strand the gesture without its "ended" event.
            if let actions = deviceConfiguration.scrolling.modifiers.effective, !actions.isEmpty {
                let transformer = modifierTransformers[device.key] ?? ModifierKeyTransformer()
                transformer.actions = actions
                transformers[device.key] = transformer
            } else if let existing = modifierTransformers[device.key] {
                existing.deactivate()
            }

            for senderID in device.senderIDs {
                senderToKey[senderID] = device.key
            }
            if let mappings = deviceConfiguration.buttons.mappings.effective, !mappings.isEmpty {
                buttonMappings[device.key] = mappings
            }
            deviceMap[device.key] = device
        }

        for (key, transformer) in modifierTransformers where transformers[key] == nil {
            transformer.deactivate()
        }
        scrollProcessors = processors
        modifierTransformers = transformers
        snapshot = EventSnapshot(
            enabled: configuration.enabled && canHandleInput,
            senderToKey: senderToKey,
            processors: processors,
            modifierTransformers: transformers,
            buttonMappings: buttonMappings,
            devices: deviceMap,
            mouseServiceCount: registry.mouseServiceCount
        )
    }

    private func activeConfiguration(for key: String) -> DeviceConfiguration {
        var configuration = store.configuration.device(key).applyingApplication(activeBundleID)
        if !canHandleInput || !store.configuration.enabled { configuration.buttons = ButtonSettings() }
        return configuration
    }

    /// The wheel's high-resolution multiplier, needed to fold increments back
    /// into detents. Cached on the device so this stays off the event path.
    private var multiplierCache: [String: Int] = [:]

    private func multiplier(for device: ManagedDevice) -> Int {
        if let cached = multiplierCache[device.key] { return cached }
        guard let target = device.target else { return 1 }

        // Reading the wheel costs a round trip, so do it once, off the main
        // thread, and cache the answer.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let capabilities = try? target.wheelCapabilities().get() else { return }
            let mode = try? target.wheelMode().get()
            let value = (mode?.resolution == .high) ? Int(capabilities.multiplier) : 1
            DispatchQueue.main.async {
                guard let self, self.isRunning else { return }
                self.multiplierCache[device.key] = max(value, 1)
                self.rebuildProcessors(self.registry.devices)
            }
        }
        return 1
    }

    public func invalidateMultiplier(for key: String) {
        multiplierCache.removeValue(forKey: key)
        rebuildProcessors(registry.devices)
    }

    private func reconcileAll(confirm: Bool, reason: String) {
        guard canHandleInput else { return }
        multiplierCache.removeAll()
        for device in registry.devices {
            reconciler.reconcile(
                device: device,
                configuration: activeConfiguration(for: device.key),
                globallyEnabled: store.configuration.enabled && canHandleInput,
                confirm: confirm,
                reason: reason
            )
        }
    }

    // MARK: - Device-level actions

    private func performDeviceAction(_ action: Action, device: ManagedDevice?) {
        guard let device else { return }
        let key = device.key

        switch action {
        case .cycleDPIPresets:
            var configuration = store.configuration.device(key)
            guard configuration.hardware.dpiPresets.enabled else {
                os_log("DPI presets are switched off for %{public}@; ignoring",
                       log: Self.log, type: .info, device.displayName)
                return
            }
            configuration.hardware.dpiPresets.value = configuration.hardware.dpiPresets.value.next()
            announceNextDPI(configuration.hardware.dpiPresets.value.active, for: key)
            store.updateDevice(key) { $0 = configuration }

        case let .dpiPreset(index):
            var presets = store.configuration.device(key).hardware.dpiPresets
            guard presets.enabled else { return }
            presets.value.activeIndex = index
            announceNextDPI(presets.value.active, for: key)
            store.updateDevice(key) { $0.hardware.dpiPresets = presets }

        case .toggleWheelRatchet:
            var configuration = store.configuration.device(key)
            guard configuration.hardware.wheelRatchet.enabled else {
                os_log("wheel ratchet control is switched off for %{public}@; ignoring",
                       log: Self.log, type: .info, device.displayName)
                return
            }
            let current = configuration.hardware.wheelRatchet.value
            configuration.hardware.wheelRatchet.value.mode = current.mode == .freeSpin
                ? .alwaysRatchet
                : .freeSpin
            store.updateDevice(key) { $0 = configuration }

        default:
            break
        }
    }

    /// Set before the configuration changes, because that change is what
    /// sends the reconciler off to write the new value.
    private func announceNextDPI(_ dpi: Int?, for key: String) {
        guard let dpi else { return }
        pendingDPIAnnouncements[key] = (dpi, Date().addingTimeInterval(Self.dpiAnnouncementWindow))
    }
}

/// Called only after a routed action consumes the down. Remember an untagged
/// hardware press through configuration changes so its matching up is consumed.
/// Tagged releases and events posted by other processes cannot consume it.
package struct ButtonPressTracker {
    package init() {}
    private struct Press: Hashable { let sender: UInt64?; let button: Int }
    private var pressed: Set<Press> = []
    package var isEmpty: Bool { pressed.isEmpty }
    package mutating func swallow(button: Int, senderID: UInt64?, sourcePID: Int64) {
        guard senderID != nil || sourcePID == 0 else { return }
        pressed.insert(Press(sender: senderID, button: button))
    }
    package mutating func release(button: Int, senderID: UInt64?, sourcePID: Int64) -> Bool {
        guard senderID != nil || sourcePID == 0 else { return false }
        return pressed.remove(Press(sender: senderID, button: button)) != nil
    }
}
