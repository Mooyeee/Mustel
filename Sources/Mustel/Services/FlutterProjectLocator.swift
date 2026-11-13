import Foundation

/// Resolves the app package behind a path that may be an IDE workspace folder
/// or a Dart pub workspace root.
///
/// In a pub workspace the outer `pubspec.yaml` is a valid package (it declares
/// `workspace:` and has its own `name:`), so treating it as the app package
/// yields the workspace name and none of the app's icons.
enum FlutterProjectLocator {
    private static let platformDirectories = ["android", "ios", "macos", "web", "linux", "windows"]

    /// Returns the directory of the Flutter app package for `path`.
    ///
    /// - Parameters:
    ///   - path: A project, workspace folder, or pub workspace root.
    ///   - targetPath: An optional Dart entrypoint (for example the value of
    ///     `flutter run --target`) relative to `path`.
    /// - Returns: `nil` when `path` is a workspace root with more than one
    ///   possible app and no entrypoint to disambiguate.
    static func resolveAppPath(_ path: String, targetPath: String? = nil) -> String? {
        guard !path.isEmpty else { return nil }
        let directory = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        guard let pubspec = PubspecDocument(directory: directory) else { return nil }

        if let targetApp = appRoot(forTargetPath: targetPath, relativeTo: directory) {
            return targetApp.path
        }
        guard pubspec.isWorkspaceRoot else { return directory.path }

        // The workspace root itself may also be the runnable app.
        if isFlutterApp(directory) { return directory.path }

        let members = pubspec.workspaceMemberURLs(relativeTo: directory)
            .filter(isFlutterApp)
        return members.count == 1 ? members[0].path : nil
    }

    /// Reads the pubspec `name` of the resolved app package.
    ///
    /// Returns `nil` when the path is an ambiguous pub workspace root, so
    /// callers can fall back to a folder name instead of showing the workspace
    /// name.
    static func appName(for path: String, targetPath: String? = nil) -> String? {
        guard let resolved = resolveAppPath(path, targetPath: targetPath) else { return nil }
        return PubspecDocument(directory: URL(fileURLWithPath: resolved, isDirectory: true))?.name
    }

    private static func appRoot(forTargetPath targetPath: String?, relativeTo root: URL) -> URL? {
        guard let targetPath, !targetPath.isEmpty else { return nil }
        let target = URL(fileURLWithPath: targetPath, relativeTo: root).standardizedFileURL
        var candidate = target.hasDirectoryPath ? target : target.deletingLastPathComponent()
        let rootPath = root.standardizedFileURL.path

        while candidate.path == rootPath || candidate.path.hasPrefix(rootPath + "/") {
            if FileManager.default.fileExists(
                atPath: candidate.appendingPathComponent("pubspec.yaml").path
            ) {
                return candidate
            }
            if candidate.path == rootPath { break }
            candidate = candidate.deletingLastPathComponent()
        }
        return nil
    }

    private static func isFlutterApp(_ directory: URL) -> Bool {
        let fileManager = FileManager.default
        if platformDirectories.contains(where: {
            fileManager.fileExists(atPath: directory.appendingPathComponent($0).path)
        }) {
            return true
        }
        // A freshly created app may not have platform folders yet, but still
        // has a Flutter entrypoint. This also avoids treating plugin packages
        // in the same workspace as runnable apps.
        return PubspecDocument(directory: directory)?.declaresFlutter == true
            && fileManager.fileExists(
                atPath: directory.appendingPathComponent("lib/main.dart").path
            )
    }
}

struct PubspecDocument {
    let name: String?
    let workspaceMembers: [String]?

    var isWorkspaceRoot: Bool { workspaceMembers != nil }
    var declaresFlutter: Bool {
        lines.contains { line in
            line.text == "flutter:" || line.text.hasPrefix("flutter: ")
        }
    }

    private let lines: [Line]

    private struct Line {
        let indent: Int
        let text: String
    }

    init?(directory: URL) {
        let url = directory.appendingPathComponent("pubspec.yaml")
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        let lines = contents.split(whereSeparator: \.isNewline).map { rawLine in
            let raw = String(rawLine)
            let indent = raw.prefix { $0 == " " || $0 == "\t" }.count
            return Line(indent: indent, text: String(raw.dropFirst(indent)))
        }
        self.lines = lines
        name = Self.topLevelValue("name", in: lines)
        workspaceMembers = Self.workspaceMembers(in: lines)
    }

    func workspaceMemberURLs(relativeTo root: URL) -> [URL] {
        let rootURL = root.standardizedFileURL
        let rootPath = rootURL.path
        return (workspaceMembers ?? []).compactMap { member in
            guard !member.hasPrefix("/") else { return nil }
            let url = URL(fileURLWithPath: member, relativeTo: rootURL).standardizedFileURL
            guard url.path.hasPrefix(rootPath + "/") else { return nil }
            return url
        }
    }

    private static func topLevelValue(_ key: String, in lines: [Line]) -> String? {
        for line in lines where line.indent == 0 {
            guard !line.text.hasPrefix("#"), line.text.hasPrefix("\(key):") else { continue }
            return scalar(String(line.text.dropFirst(key.count + 1)))
        }
        return nil
    }

    private static func workspaceMembers(in lines: [Line]) -> [String]? {
        guard let keyIndex = lines.firstIndex(where: {
            $0.indent == 0 && !$0.text.hasPrefix("#") && $0.text.hasPrefix("workspace:")
        }) else {
            return nil
        }

        let inline = String(lines[keyIndex].text.dropFirst("workspace:".count))
        if inline.trimmingCharacters(in: .whitespaces).hasPrefix("[") {
            return flowList(inline)
        }

        var members: [String] = []
        var index = keyIndex + 1
        while index < lines.count {
            let line = lines[index]
            index += 1
            if line.text.isEmpty || line.text.hasPrefix("#") { continue }
            guard line.indent > 0 else { break }

            let item: String
            if line.text.hasPrefix("- ") {
                item = String(line.text.dropFirst(2))
            } else if line.text == "-" {
                item = ""
            } else {
                break
            }
            if let value = scalar(item) { members.append(value) }
        }
        return members
    }

    private static func flowList(_ raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else { return [] }
        let inner = trimmed.dropFirst().dropLast()
        return inner.split(separator: ",").compactMap { scalar(String($0)) }
    }

    private static func scalar(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        if let quote = trimmed.first, quote == "\"" || quote == "'" {
            let contents = trimmed.dropFirst()
            guard let end = contents.firstIndex(of: quote) else { return nil }
            let value = String(contents[..<end]).trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }

        var value = trimmed
        if let comment = value.firstIndex(of: "#") {
            value = String(value[..<comment]).trimmingCharacters(in: .whitespaces)
        }
        return value.isEmpty ? nil : value
    }
}
