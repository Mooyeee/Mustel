import Foundation

/// Resolves the Swift Package Manager resource bundle (`Mustel_Mustel.bundle`).
///
/// SwiftPM generates a `Bundle.module` accessor per target kind, and the locations it searches
/// have changed between Swift toolchains. Some versions only look next to the main bundle (the
/// `.app` root) and then fall back to an absolute path inside the machine that built the app,
/// which makes packaged releases crash on every other Mac.
///
/// Looking the bundle up ourselves keeps the packaged app working no matter which toolchain built
/// it, while `Bundle.module` stays available as the last resort for `swift run` and tests.
enum AppResources {
    static let bundle: Bundle = {
        let bundleName = "Mustel_Mustel.bundle"

        var directories: [URL] = []
        if let resources = Bundle.main.resourceURL {
            // Packaged app: Mustel.app/Contents/Resources
            directories.append(resources)
        }
        if let executable = Bundle.main.executableURL?.deletingLastPathComponent() {
            // Command line tools: next to the executable
            directories.append(executable)
        }
        // Packaged app root and command line tools: where older accessors look
        directories.append(Bundle.main.bundleURL)
        if let frameworkResources = Bundle(for: BundleFinder.self).resourceURL {
            // Package linked into a framework
            directories.append(frameworkResources)
        }

        for directory in directories {
            let candidate = directory.appendingPathComponent(bundleName)
            if let bundle = Bundle(url: candidate) {
                return bundle
            }
        }

        return .module
    }()

    static func url(forResource name: String, withExtension fileExtension: String?) -> URL? {
        bundle.url(forResource: name, withExtension: fileExtension)
    }
}

private final class BundleFinder {}
