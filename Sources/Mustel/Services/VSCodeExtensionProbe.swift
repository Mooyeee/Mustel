import Foundation

protocol VSCodeExtensionProbing: Sendable {
    func isInstalled() -> Bool
}

struct VSCodeExtensionProbe: VSCodeExtensionProbing {
    private static let folderPrefix = "local.mustel-vscode-"
    private static let extensionDirectories = [
        ".vscode/extensions",
        ".vscode-insiders/extensions",
        ".vscode-oss/extensions",
        ".vscode-server/extensions",
        ".cursor/extensions",
        ".windsurf/extensions"
    ]

    func isInstalled() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return Self.extensionDirectories.contains { relativePath in
            let directory = home.appendingPathComponent(relativePath, isDirectory: true)
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
                return false
            }
            return entries.contains { $0.hasPrefix(Self.folderPrefix) }
        }
    }
}
