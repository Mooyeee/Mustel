import AppKit

@main
enum MustelApp {
    @MainActor private static var appDelegate: AppDelegate?

    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--check-resources") {
            exit(ResourceCheck.run())
        }

        let application = NSApplication.shared
        let delegate = AppDelegate()
        appDelegate = delegate
        application.delegate = delegate
        application.run()
    }
}
