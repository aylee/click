import AppKit
import IOKit.hid

enum Diagnostics {
    /// Inventory only: does not open or seize HID devices, send reports, or request grants.
    static func printReport() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x046d] as CFDictionary)
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        var seen = Set<String>()
        var result: [[String: Any]] = []
        for device in devices {
            let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Logitech device"
            let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
            let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? "Unknown"
            guard seen.insert("\(product):\(pid):\(transport)").inserted else { continue }
            result.append(["name": product, "productID": String(format: "0x%04X", pid), "transport": transport])
        }
        let report: [String: Any] = [
            "app": "Click", "accessibility": AXIsProcessTrusted(),
            "inputMonitoring": IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted,
            "devices": result.sorted { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") },
            "hardwareWrites": false,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) { print(text) }
    }
}
