import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let model: AppViewModel
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?

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

        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: ContentView(model: model))
        popover.contentSize = NSSize(width: 380, height: 400)
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) {
            [weak self] event in
            self?.closePopoverIfClickedOutside()
            return event
        }
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) {
            [weak self] _ in
            DispatchQueue.main.async {
                self?.closePopoverIfClickedOutside()
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
        } else if popover.isShown {
            popover.performClose(sender)
        } else {
            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }

    func popoverWillShow(_ notification: Notification) {
        guard let button = statusItem.button,
              let statusBarWindow = button.window,
              let popoverWindow = popover.contentViewController?.view.window else {
            return
        }

        let buttonFrame = statusBarWindow.convertToScreen(button.convert(button.bounds, to: nil))
        var popoverFrame = popoverWindow.frame
        popoverFrame.origin.x = buttonFrame.midX - popoverFrame.width / 2
        popoverFrame.origin.y = buttonFrame.minY - popoverFrame.height
        popoverWindow.setFrame(popoverFrame, display: true)
    }

    func popoverDidClose(_ notification: Notification) {
        if model.launchForm.isPresented {
            model.launchForm.toggle()
        }
    }

    func tearDown() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
        }
        localEventMonitor = nil
        globalEventMonitor = nil
    }

    private func closePopoverIfClickedOutside() {
        guard popover.isShown else { return }
        let mouseLocation = NSEvent.mouseLocation
        if let popoverWindow = popover.contentViewController?.view.window,
           popoverWindow.frame.contains(mouseLocation) {
            return
        }
        if model.launchForm.isPresented,
           NSApp.windows.contains(where: { $0.isVisible && $0.frame.contains(mouseLocation) }) {
            return
        }
        if let button = statusItem.button,
           let buttonWindow = button.window {
            let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
            if buttonFrame.contains(mouseLocation) {
                return
            }
        }
        popover.performClose(nil)
    }
}
