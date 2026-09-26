import Foundation

enum MouseControl: String, CaseIterable, Identifiable {
    case middle, wheelMode, forward, back, thumb, thumbwheel

    var id: String { rawValue }
    var title: String {
        switch self {
        case .middle: return "Middle button"
        case .wheelMode: return "Top button"
        case .forward: return "Forward button"
        case .back: return "Back button"
        case .thumb: return "Thumb button"
        case .thumbwheel: return "Thumb wheel"
        }
    }
    var symbol: String {
        switch self {
        case .middle: return "computermouse"
        case .wheelMode: return "circle.dashed"
        case .forward: return "arrow.right"
        case .back: return "arrow.left"
        case .thumb: return "hand.point.up.left"
        case .thumbwheel: return "arrow.left.and.right"
        }
    }
    var detail: String {
        switch self {
        case .middle: return "Press the main scroll wheel."
        case .wheelMode: return "The small button below the main wheel."
        case .forward: return "The front button above your thumb."
        case .back: return "The rear button above your thumb."
        case .thumb: return "Press the button under the thumb rest."
        case .thumbwheel: return "Roll the side wheel to scroll horizontally."
        }
    }
    var defaultLabel: String {
        switch self {
        case .middle: return "Middle click"
        case .wheelMode: return "Shift wheel mode"
        case .forward: return "Mouse button 5"
        case .back: return "Mouse button 4"
        case .thumb: return "Mouse default"
        case .thumbwheel: return "Horizontal scroll"
        }
    }
    var buttonNumber: Int? {
        switch self {
        case .middle: return 2
        case .back: return 3
        case .forward: return 4
        default: return nil
        }
    }
    var needsHID: Bool { self == .thumb || self == .wheelMode }
}
