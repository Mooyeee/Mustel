import Foundation

protocol IDEBridgeProbing: Sendable {
    func isInstalled() -> Bool
}

struct IDEBridgeProbe: IDEBridgeProbing {
    private static let vsCodeFolderPrefix = "local.mustel-vscode-"
    private static let vsCodeExtensionDirectories = [
        ".vscode/extensions",
        ".vscode-insiders/extensions",
        ".vscode-oss/extensions",
        ".vscode-server/extensions",
        ".cursor/extensions",
        ".windsurf/extensions"
    ]
    private static let jetBrainsRoots = [
        "Library/Application Support/JetBrains",
        "Library/Application Support/Google"
    ]

    private static let cacheLock = NSLock()
    private static var cachedResult: (date: Date, installed: Bool)?

    func isInstalled() -> Bool {
        Self.cacheLock.lock()
        defer { Self.cacheLock.unlock() }

        if let cached = Self.cachedResult, Date().timeIntervalSince(cached.date) < 5 {
            return cached.installed
        }

        let installed = Self.detect()
        Self.cachedResult = (Date(), installed)
        return installed
    }

    private static func detect() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if vsCodeExtensionDirectories.contains(where: { relativePath in
            let directory = home.appendingPathComponent(relativePath, isDirectory: true)
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
                return false
            }
            return entries.contains { $0.hasPrefix(vsCodeFolderPrefix) }
        }) {
            return true
        }

        for root in jetBrainsRoots {
            let rootURL = home.appendingPathComponent(root, isDirectory: true)
            guard let products = try? FileManager.default.contentsOfDirectory(atPath: rootURL.path) else {
                continue
            }
            for product in products {
                let plugins = rootURL
                    .appendingPathComponent(product, isDirectory: true)
                    .appendingPathComponent("plugins", isDirectory: true)
                guard let entries = try? FileManager.default.contentsOfDirectory(atPath: plugins.path) else {
                    continue
                }
                if entries.contains(where: { $0.localizedCaseInsensitiveContains("mustel") }) {
                    return true
                }
            }
        }

        return false
    }
}
