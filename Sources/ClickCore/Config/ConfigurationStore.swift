// MIT License
// Copyright (c) 2026 LoLiMouse contributors

import Combine
import Foundation
import HIDKit
import os.log

/// Atomic local JSON persistence. An unreadable or newer file is never replaced.
public final class ConfigurationStore: ObservableObject {
    @Published public private(set) var configuration: Configuration
    @Published public private(set) var lastError: String?
    public private(set) var isReadOnly = false
    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("config.json") }

    private let saveQueue = DispatchQueue(label: "\(LoLiLog.subsystem).config", qos: .utility)
    private var saveWorkItem: DispatchWorkItem?

    public init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory()
        configuration = Configuration()
        let url = self.directory.appendingPathComponent("config.json")
        do {
            let data = try Data(contentsOf: url)
            let loaded = try JSONDecoder().decode(Configuration.self, from: data)
            guard loaded.schemaVersion <= Configuration.currentSchemaVersion else {
                throw CocoaError(.coderReadCorrupt, userInfo: [NSLocalizedDescriptionKey:
                    "This settings file requires a newer version of Click."])
            }
            if let message = loaded.validationError {
                throw CocoaError(.coderReadCorrupt, userInfo: [NSLocalizedDescriptionKey: message])
            }
            configuration = loaded
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // First launch.
        } catch {
            configuration.enabled = false
            isReadOnly = true
            lastError = "Settings could not be loaded. The original file is unchanged at \(url.path). \(error.localizedDescription)"
        }
    }

    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Click", isDirectory: true)
    }

    public func update(_ transform: (inout Configuration) -> Void) {
        guard !isReadOnly else { return }
        var next = configuration
        transform(&next)
        guard next != configuration else { return }
        if let error = next.validationError { lastError = error; return }
        configuration = next
        scheduleSave(next)
    }

    public func updateDevice(_ key: String, _ transform: (inout DeviceConfiguration) -> Void) {
        update { $0.update(key, transform) }
    }

    public func replace(with configuration: Configuration) {
        guard !isReadOnly, configuration != self.configuration else { return }
        if let error = configuration.validationError { lastError = error; return }
        self.configuration = configuration
        scheduleSave(configuration)
    }

    private func scheduleSave(_ configuration: Configuration) {
        saveWorkItem?.cancel()
        let url = fileURL
        let item = DispatchWorkItem { [weak self] in
            let error = Self.write(configuration, to: url)
            DispatchQueue.main.async { self?.lastError = error }
        }
        saveWorkItem = item
        saveQueue.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    public func flush() {
        guard !isReadOnly else { return }
        saveWorkItem?.cancel()
        saveWorkItem = nil
        let configuration = self.configuration
        let url = fileURL
        lastError = saveQueue.sync { Self.write(configuration, to: url) }
    }

    private static func write(_ configuration: Configuration, to url: URL) -> String? {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(configuration).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return nil
        } catch {
            os_log("could not save configuration: %{public}@", log: LoLiLog.config,
                   type: .error, error.localizedDescription)
            return "Settings could not be saved: \(error.localizedDescription)"
        }
    }
}
