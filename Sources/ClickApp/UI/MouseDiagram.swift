import AppKit
import SwiftUI

/// Original bundled mouse illustration; callouts remain native keyboard-accessible controls.
struct MouseDiagram: View {
    @Binding var selected: MouseControl
    var caption: (MouseControl) -> String

    private static let artwork: NSImage? = {
        // SwiftPM's resource accessor covers `swift run`; an installed app uses
        // the resource bundle copied into its standard Resources directory.
        let packaged = Bundle.main.resourceURL?.appendingPathComponent("Click_ClickApp.bundle")
        let resources = packaged.flatMap(Bundle.init(url:)) ?? Bundle.module
        guard let url = resources.url(forResource: "mx-master-3-for-mac", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 560, geometry.size.height / 500)
            ZStack {
                if let artwork = Self.artwork {
                    Image(nsImage: artwork)
                        .resizable().interpolation(.high).scaledToFit()
                        .frame(width: 500, height: 430)
                        .shadow(color: .black.opacity(0.14), radius: 14, x: 4, y: 16)
                        .position(x: 280, y: 246)
                        .accessibilityHidden(true)
                }
                callout(.middle, at: CGPoint(x: 463, y: 100), from: CGPoint(x: 221, y: 116))
                callout(.wheelMode, at: CGPoint(x: 475, y: 197), from: CGPoint(x: 267, y: 145))
                callout(.thumbwheel, at: CGPoint(x: 466, y: 300), from: CGPoint(x: 207, y: 206))
                callout(.forward, at: CGPoint(x: 87, y: 163), from: CGPoint(x: 203, y: 235))
                callout(.back, at: CGPoint(x: 92, y: 263), from: CGPoint(x: 242, y: 259))
                callout(.thumb, at: CGPoint(x: 87, y: 362), from: CGPoint(x: 177, y: 291))
            }
            .frame(width: 560, height: 500)
            .scaleEffect(scale, anchor: .center)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("MX Master button layout")
    }

    private func callout(_ control: MouseControl, at point: CGPoint, from anchor: CGPoint) -> some View {
        let isSelected = selected == control
        return ZStack {
            Path { path in
                path.move(to: anchor)
                path.addLine(to: CGPoint(x: point.x + (point.x < anchor.x ? 66 : -66), y: point.y))
            }
            .stroke(isSelected ? Color.accentColor.opacity(0.7) : Color.secondary.opacity(0.35), lineWidth: 1)
            Button { selected = control } label: {
                Circle().fill(isSelected ? Color.accentColor : Color.white)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(.black.opacity(0.28), lineWidth: 1))
                    .frame(width: 28, height: 28).contentShape(Circle())
            }
            .buttonStyle(.plain).position(anchor).accessibilityHidden(true)
            Button { selected = control } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(control.title).font(.system(size: 12, weight: .semibold))
                    Text(caption(control)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(width: 116, alignment: .leading).padding(11)
                .background(isSelected ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.09), lineWidth: isSelected ? 1.5 : 1))
                .shadow(color: .black.opacity(isSelected ? 0.04 : 0.02), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(control.title), \(caption(control))")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .position(point)
        }
    }
}
