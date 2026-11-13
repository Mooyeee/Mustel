import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let model: AppViewModel
    private let statusItem: NSStatusItem
    private let panel = PopoverPanel()
    private let layout = PopoverLayout()
    private var hostingView: SizingHostingView<PopoverContentView>?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var isAnimatingSize = false
    private var pendingSize: NSSize?
    private var currentContentSize: NSSize = .zero
    private var isHidingPanel = false
    private var sizeAnimationTimer: Timer?

    init(model: AppViewModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureStatusItem()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = model.logoAnimator.currentImage
        model.logoAnimator.onFrameChanged = { [weak self] image in
            self?.statusItem.button?.image = image
        }
        button.toolTip = "Mustel"
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let hostingView = SizingHostingView(rootView: PopoverContentView(model: model, layout: layout))
        hostingView.onSizeChange = { [weak self] size in
            MainActor.assumeIsolated {
                self?.updatePopoverSize(size)
            }
        }
        let container = NSView(frame: NSRect(origin: .zero, size: NSSize(width: 380, height: 1)))
        container.wantsLayer = true
        container.layer?.masksToBounds = true
        hostingView.frame = container.bounds
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)
        panel.contentView = container
        hostingView.layoutSubtreeIfNeeded()
        let initialSize = hostingView.fittingSize
        container.frame = NSRect(origin: .zero, size: initialSize)
        hostingView.frame = container.bounds
        layout.visibleHeight = initialSize.height
        updatePopoverSize(initialSize)
        self.hostingView = hostingView

        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
        ) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                self.hidePanel()
                return nil
            }
            self.closePanelIfClickedOutside()
            return event
        }
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.closePanelIfClickedOutside()
            }
        }
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let quitItem = NSMenuItem(
                title: "Quit Mustel",
                action: #selector(quitApplication),
                keyEquivalent: ""
            )
            quitItem.target = self
            menu.addItem(quitItem)
            menu.popUp(positioning: nil, at: NSPoint(x: button.bounds.minX, y: button.bounds.minY), in: button)
        } else if panel.isVisible {
            hidePanel()
        } else {
            showPanel(relativeTo: button)
        }
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }

    private func showPanel(relativeTo button: NSStatusBarButton) {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }

        var size = currentContentSize
        if size == .zero, let hostingView {
            hostingView.layoutSubtreeIfNeeded()
            size = hostingView.fittingSize
            currentContentSize = size
        }
        guard size.width > 0, size.height > 0 else { return }

        let buttonFrame = button.window?.convertToScreen(button.convert(button.bounds, to: nil))
            ?? .zero
        var origin = NSPoint(
            x: buttonFrame.midX - size.width / 2,
            y: buttonFrame.minY - size.height
        )
        if let screen = button.window?.screen {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        }

        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        layout.visibleHeight = size.height
        isHidingPanel = false
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func hidePanel() {
        guard panel.isVisible, !isHidingPanel else { return }
        isHidingPanel = true
        sizeAnimationTimer?.invalidate()
        sizeAnimationTimer = nil
        isAnimatingSize = false
        pendingSize = nil
        if model.launchForm.isPresented {
            model.launchForm.toggle()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isHidingPanel else { return }
                self.isHidingPanel = false
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
            }
        }
    }

    private func updatePopoverSize(_ size: NSSize) {
        let targetSize = NSSize(
            width: max(size.width, 380),
            height: max(size.height, 1)
        )
        guard targetSize != currentContentSize,
              targetSize != pendingSize else {
            return
        }

        if isAnimatingSize {
            pendingSize = targetSize
            return
        }

        let previousSize = currentContentSize
        currentContentSize = targetSize

        guard panel.isVisible,
              let hostingView,
              let contentView = panel.contentView else {
            panel.setContentSize(targetSize)
            if let contentView = panel.contentView {
                contentView.frame = NSRect(origin: .zero, size: targetSize)
                hostingView?.autoresizingMask = [.width, .height]
                hostingView?.frame = contentView.bounds
            }
            layout.visibleHeight = targetSize.height
            return
        }

        animateContentSize(
            from: max(layout.visibleHeight, previousSize.height),
            to: targetSize,
            hostingView: hostingView,
            contentView: contentView
        )
    }

    private func animateContentSize(
        from startHeight: CGFloat,
        to targetSize: NSSize,
        hostingView: NSView,
        contentView: NSView
    ) {
        isAnimatingSize = true
        let startFrame = panel.frame
        let top = startFrame.maxY
        var targetFrame = startFrame
        targetFrame.origin.y = top - targetSize.height
        targetFrame.size = targetSize

        if let screen = panel.screen {
            let visible = screen.visibleFrame
            targetFrame.origin.x = min(
                max(targetFrame.origin.x, visible.minX + 8),
                visible.maxX - targetSize.width - 8
            )
        }

        let isExpanding = targetSize.height > startHeight
        if isExpanding {
            // Grow the window immediately; only the mask animates.
            panel.setFrame(targetFrame, display: true)
        }
        hostingView.autoresizingMask = [.width, .height]
        hostingView.frame = contentView.bounds
        layout.visibleHeight = startHeight

        sizeAnimationTimer?.invalidate()
        let startedAt = Date()
        let duration = 0.24
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else {
                    timer.invalidate()
                    return
                }
                let progress = min(1, Date().timeIntervalSince(startedAt) / duration)
                let eased = progress * progress * (3 - 2 * progress)
                self.layout.visibleHeight = startHeight
                    + (targetSize.height - startHeight) * eased

                guard progress >= 1 else { return }
                timer.invalidate()
                self.sizeAnimationTimer = nil
                self.isAnimatingSize = false
                self.layout.visibleHeight = targetSize.height
                self.panel.setFrame(targetFrame, display: true)
                self.hostingView?.autoresizingMask = [.width, .height]
                self.hostingView?.frame = contentView.bounds
                self.panel.invalidateShadow()
                if let pendingSize = self.pendingSize {
                    self.pendingSize = nil
                    self.updatePopoverSize(pendingSize)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        sizeAnimationTimer = timer
    }

    func tearDown() {
        sizeAnimationTimer?.invalidate()
        sizeAnimationTimer = nil
        hostingView?.onSizeChange = nil
        hostingView = nil
        panel.orderOut(nil)
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
        }
        localEventMonitor = nil
        globalEventMonitor = nil
    }

    private func closePanelIfClickedOutside() {
        guard panel.isVisible else { return }
        let mouseLocation = NSEvent.mouseLocation
        let visibleHeight = max(layout.visibleHeight, 1)
        let visibleFrame = NSRect(
            x: panel.frame.minX,
            y: panel.frame.maxY - visibleHeight,
            width: panel.frame.width,
            height: visibleHeight
        )
        if visibleFrame.contains(mouseLocation) {
            return
        }
        if model.launchForm.isPresented,
           NSApp.windows.contains(where: { $0.isVisible && $0 !== panel && $0.frame.contains(mouseLocation) }) {
            return
        }
        if let button = statusItem.button,
           let buttonWindow = button.window {
            let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
            if buttonFrame.contains(mouseLocation) {
                return
            }
        }
        hidePanel()
    }
}

private final class SizingHostingView<Content: View>: NSHostingView<Content> {
    var onSizeChange: ((NSSize) -> Void)?
    private var lastSize: NSSize = .zero

    override func layout() {
        super.layout()
        let size = fittingSize
        guard size.width > 0, size.height > 0, size != lastSize else { return }
        lastSize = size
        onSizeChange?(size)
    }
}
