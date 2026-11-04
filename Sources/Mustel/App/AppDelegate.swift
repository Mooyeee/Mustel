import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppViewModel()
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model.start()
        statusItemController = StatusItemController(model: model)
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
        statusItemController?.tearDown()
    }
}
