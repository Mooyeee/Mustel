import Foundation

struct IDEBridgeVersions: Equatable, Sendable {
    var isInstalled = false
    var visualStudioCode: AppVersion?
    var intellij: AppVersion?

    init(
        isInstalled: Bool = false,
        visualStudioCode: AppVersion? = nil,
        intellij: AppVersion? = nil
    ) {
        self.isInstalled = isInstalled
        self.visualStudioCode = visualStudioCode
        self.intellij = intellij
    }
}

protocol IDEBridgeProbing: Sendable {
    func isInstalled() -> Bool
    func installedVersions() -> IDEBridgeVersions
}

extension IDEBridgeProbing {
    func installedVersions() -> IDEBridgeVersions {
        IDEBridgeVersions(isInstalled: isInstalled())
    }
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
    private static var cachedVersions: (homePath: String, date: Date, versions: IDEBridgeVersions)?

    private let homeDirectory: URL

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    func isInstalled() -> Bool {
        installedVersions().isInstalled
    }

    func installedVersions() -> IDEBridgeVersions {
        Self.cacheLock.lock()
        defer { Self.cacheLock.unlock() }

        if let cached = Self.cachedVersions,
           cached.homePath == homeDirectory.path,
           Date().timeIntervalSince(cached.date) < 5 {
            return cached.versions
        }

        let versions = Self.detect(home: homeDirectory)
        Self.cachedVersions = (homeDirectory.path, Date(), versions)
        return versions
    }

    private static func detect(home: URL) -> IDEBridgeVersions {
        let visualStudioCode = visualStudioCodeVersion(home: home)
        let intellij = intellijVersion(home: home)
        return IDEBridgeVersions(
            isInstalled: visualStudioCode != nil || intellij != nil,
            visualStudioCode: visualStudioCode,
            intellij: intellij
        )
    }

    private static func visualStudioCodeVersion(home: URL) -> AppVersion? {
        var versions: [AppVersion] = []
        for relativePath in vsCodeExtensionDirectories {
            let directory = home.appendingPathComponent(relativePath, isDirectory: true)
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
                continue
            }
            for entry in entries where entry.hasPrefix(vsCodeFolderPrefix) {
                let packageJSON = directory
                    .appendingPathComponent(entry, isDirectory: true)
                    .appendingPathComponent("package.json")
                if let data = try? Data(contentsOf: packageJSON),
                   let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let value = object["version"] as? String,
                   let version = AppVersion(value) {
                    versions.append(version)
                    continue
                }
                if let version = AppVersion(entry) {
                    versions.append(version)
                }
            }
        }
        return versions.max()
    }

    private static func intellijVersion(home: URL) -> AppVersion? {
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
                for entry in entries where entry.localizedCaseInsensitiveContains("mustel") {
                    let lib = plugins
                        .appendingPathComponent(entry, isDirectory: true)
                        .appendingPathComponent("lib", isDirectory: true)
                    guard let jars = try? FileManager.default.contentsOfDirectory(atPath: lib.path) else {
                        continue
                    }
                    for jar in jars where jar.hasPrefix("mustel-intellij-") && jar.hasSuffix(".jar") {
                        if let version = AppVersion(jar) {
                            return version
                        }
                    }
                }
            }
        }
        return nil
    }
}
