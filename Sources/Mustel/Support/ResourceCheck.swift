import AppKit
import Foundation

/// Headless self-check used by `scripts/smoke-test.sh` (`mustel --check-resources`).
///
/// It resolves every resource the app loads at runtime, so packaging regressions fail the build
/// instead of crashing the app on another Mac.
enum ResourceCheck {
    static func run() -> Int32 {
        var failures: [String] = []

        let files = [
            ("MustelMenuBar", "png"),
            ("FlutterDefaultIcon", "png"),
            ("FlutterLicense", "txt")
        ]
        for (name, fileExtension) in files
        where AppResources.url(forResource: name, withExtension: fileExtension) == nil {
            failures.append("\(name).\(fileExtension)")
        }
        for name in ["idle-to-run", "run", "run-to-idle"] where LottieAnimation.named(name) == nil {
            failures.append("Animations/\(name).json")
        }

        if failures.isEmpty {
            print("Resources OK (\(AppResources.bundle.bundlePath))")
            return 0
        }

        let message = "Missing resources: \(failures.joined(separator: ", "))\n"
        FileHandle.standardError.write(Data(message.utf8))
        return 1
    }
}
