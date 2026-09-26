// MIT License
// Copyright (c) 2026 LoLiMouse contributors

import AppKit
import Foundation

/// A keyboard shortcut, described the way a user would type it.
public struct KeyCombo: Codable, Equatable, Hashable, Sendable {
    /// Virtual key code, as used by `CGEvent(keyboardEventSource:)`.
    public var keyCode: UInt16
    public var command: Bool
    public var option: Bool
    public var control: Bool
    public var shift: Bool
    public var fn: Bool

    public init(
        keyCode: UInt16,
        command: Bool = false,
        option: Bool = false,
        control: Bool = false,
        shift: Bool = false,
        fn: Bool = false
    ) {
        self.keyCode = keyCode
        self.command = command
        self.option = option
        self.control = control
        self.shift = shift
        self.fn = fn
    }

    public var flags: CGEventFlags {
        var flags: CGEventFlags = []
        if command { flags.insert(.maskCommand) }
        if option { flags.insert(.maskAlternate) }
        if control { flags.insert(.maskControl) }
        if shift { flags.insert(.maskShift) }
        if fn { flags.insert(.maskSecondaryFn) }
        return flags
    }

    public var displayString: String {
        var parts = ""
        if fn { parts += "fn " }
        if control { parts += "⌃" }
        if option { parts += "⌥" }
        if shift { parts += "⇧" }
        if command { parts += "⌘" }
        return parts + KeyCombo.keyName(keyCode)
    }

    static func keyName(_ code: UInt16) -> String {
        let names: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
            18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
            26: "7", 27: "−", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[",
            34: "I", 35: "P", 36: "↩", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";",
            42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space",
            50: "`", 51: "⌫", 53: "Esc", 65: "Keypad .", 67: "Keypad ×", 69: "Keypad +",
            71: "Clear", 75: "Keypad /", 76: "Keypad Enter", 78: "Keypad −", 81: "Keypad =",
            82: "Keypad 0", 83: "Keypad 1", 84: "Keypad 2", 85: "Keypad 3", 86: "Keypad 4",
            87: "Keypad 5", 88: "Keypad 6", 89: "Keypad 7", 91: "Keypad 8", 92: "Keypad 9",
            64: "F17", 79: "F18", 80: "F19", 90: "F20", 96: "F5", 97: "F6", 98: "F7",
            99: "F3", 100: "F8", 101: "F9", 103: "F11", 105: "F13", 106: "F16",
            107: "F14", 109: "F10", 111: "F12", 113: "F15", 114: "Help", 115: "Home",
            116: "Page Up", 117: "⌦", 118: "F4", 119: "End", 120: "F2", 121: "Page Down",
            122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑",
        ]
        return names[code] ?? "Key \(code)"
    }

}

/// Something Click can do in response to a button or a gesture.
///
/// The list deliberately mirrors what people actually bind mice to on macOS,
/// plus the two device-level actions that only make sense here (DPI presets and
/// the wheel ratchet).
public enum Action: Codable, Equatable, Hashable, Sendable {
    /// Do nothing at all — but still swallow the button, so it stops behaving
    /// like its factory default.
    case none
    /// Let the button through untouched.
    case passthrough

    case missionControl
    case applicationWindows
    case showDesktop
    case launchpad
    case spaceLeft
    case spaceRight

    case back
    case forward

    case zoomIn
    case zoomOut

    /// Send a keyboard shortcut.
    case keyPress(KeyCombo)
    /// Send a plain mouse button, 0-based as CoreGraphics numbers them.
    case mouseButton(Int)

    /// Step to the next configured DPI preset, wrapping around.
    case cycleDPIPresets
    /// Jump to a specific preset by index.
    case dpiPreset(Int)
    /// Flip the wheel between ratchet and free spin.
    case toggleWheelRatchet

    /// Launch an application by bundle identifier.
    case launchApp(String)

    // Media and hardware keys, sent as the same system-defined events the
    // keyboard's function row produces.
    case volumeUp
    case volumeDown
    case mute
    case playPause
    case mediaNext
    case mediaPrevious
    case brightnessUp
    case brightnessDown

    public var displayName: String {
        switch self {
        case .none: return "Do nothing"
        case .passthrough: return "Leave to the system"
        case .missionControl: return "Mission Control"
        case .applicationWindows: return "Application Windows"
        case .showDesktop: return "Show Desktop"
        case .launchpad: return "Launchpad"
        case .spaceLeft: return "Space to the left"
        case .spaceRight: return "Space to the right"
        case .back: return "Back"
        case .forward: return "Forward"
        case .zoomIn: return "Zoom in"
        case .zoomOut: return "Zoom out"
        case let .keyPress(combo): return "Keyboard shortcut \(combo.displayString)"
        case let .mouseButton(button): return "Mouse button \(button < Int.max ? button + 1 : button)"
        case .cycleDPIPresets: return "Cycle DPI presets"
        case let .dpiPreset(index): return "DPI preset \(index < Int.max ? index + 1 : index)"
        case .toggleWheelRatchet: return "Toggle wheel ratchet"
        case let .launchApp(bundleID): return "Open \(bundleID)"
        case .volumeUp: return "Volume up"
        case .volumeDown: return "Volume down"
        case .mute: return "Mute"
        case .playPause: return "Play / pause"
        case .mediaNext: return "Next track"
        case .mediaPrevious: return "Previous track"
        case .brightnessUp: return "Display brightness up"
        case .brightnessDown: return "Display brightness down"
        }
    }

    /// Actions the user can pick from a menu without extra parameters.
    public static var simpleChoices: [Action] {
        [
            .none, .passthrough,
            .missionControl, .applicationWindows, .showDesktop, .launchpad,
            .spaceLeft, .spaceRight,
            .back, .forward,
            .zoomIn, .zoomOut,
            .volumeUp, .volumeDown, .mute,
            .playPause, .mediaNext, .mediaPrevious,
            .brightnessUp, .brightnessDown,
            .cycleDPIPresets, .toggleWheelRatchet,
        ]
    }
}
