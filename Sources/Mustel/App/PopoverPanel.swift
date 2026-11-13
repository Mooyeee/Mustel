import AppKit
import Observation
import SwiftUI

final class PopoverPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 380, height: 100)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        isMovable = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
    }
}

@MainActor
@Observable
final class PopoverLayout {
    var visibleHeight: CGFloat = 0
}

struct PopoverContentView: View {
    let model: AppViewModel
    let layout: PopoverLayout

    var body: some View {
        ContentView(model: model)
            .padding(.top, PopoverShape.arrowHeight)
            .background {
                PopoverShape()
                    .fill(.regularMaterial)
            }
            .overlay {
                PopoverShape()
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
            .mask(alignment: .top) {
                PopoverShape()
                    .frame(height: max(0, layout.visibleHeight))
            }
    }
}


struct PopoverShape: Shape {
    static let arrowHeight: CGFloat = 8
    static let arrowWidth: CGFloat = 18
    static let cornerRadius: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        let bodyTop = rect.minY + Self.arrowHeight
        let bodyBottom = rect.maxY
        let radius = max(0, min(Self.cornerRadius, (bodyBottom - bodyTop) / 2))
        let arrowHalf = Self.arrowWidth / 2
        let midX = rect.midX

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + radius, y: bodyTop))
        path.addLine(to: CGPoint(x: midX - arrowHalf, y: bodyTop))
        path.addLine(to: CGPoint(x: midX, y: rect.minY))
        path.addLine(to: CGPoint(x: midX + arrowHalf, y: bodyTop))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: bodyTop))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: bodyTop + radius),
            control: CGPoint(x: rect.maxX, y: bodyTop)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: bodyBottom - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: bodyBottom),
            control: CGPoint(x: rect.maxX, y: bodyBottom)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: bodyBottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: bodyBottom - radius),
            control: CGPoint(x: rect.minX, y: bodyBottom)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: bodyTop + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: bodyTop),
            control: CGPoint(x: rect.minX, y: bodyTop)
        )
        path.closeSubpath()
        return path
    }
}
