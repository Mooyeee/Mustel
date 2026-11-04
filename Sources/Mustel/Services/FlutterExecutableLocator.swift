import Foundation

enum FlutterExecutableLocator {
    static func resolve(_ configuredPath: String, projectPath: String? = nil) -> String {
        let configuredPath = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !configuredPath.isEmpty, !configuredPath.contains("/") else {
            return configuredPath
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var candidates: [String] = []
        if let projectPath {
            candidates.append("\(projectPath)/.fvm/flutter_sdk/bin/\(configuredPath)")
        }
        candidates.append(contentsOf: (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { "\($0)/\(configuredPath)" })
        candidates.append(contentsOf: [
            "\(home)/development/flutter/bin/\(configuredPath)",
            "\(home)/flutter/bin/\(configuredPath)",
            "\(home)/fvm/default/bin/\(configuredPath)",
            "\(home)/.fvm/default/bin/\(configuredPath)",
            "/opt/homebrew/bin/\(configuredPath)",
            "/usr/local/bin/\(configuredPath)"
        ])

        return candidates.first(where: FileManager.default.isExecutableFile(atPath:)) ?? configuredPath
    }
}
