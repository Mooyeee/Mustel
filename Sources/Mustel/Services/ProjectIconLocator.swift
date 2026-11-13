import Foundation

enum ProjectIconLocator {
    static func locate(projectPath: String, platformHint: String) -> URL? {
        guard !projectPath.isEmpty else { return nil }
        let resolvedPath = FlutterProjectLocator.resolveAppPath(projectPath) ?? projectPath
        let project = URL(fileURLWithPath: resolvedPath, isDirectory: true)
        if let icon = locateInProject(project, platformHint: platformHint) {
            return icon
        }
        return locateInWorkspace(project, platformHint: platformHint)
    }

    private static func locateInWorkspace(_ workspace: URL, platformHint: String) -> URL? {
        let fileManager = FileManager.default
        let excluded = Set(["build", "node_modules", "Pods", "macos", "ios", "android", "web"])
        var directories = [(workspace, 0)]
        var index = 0
        var matches: [URL] = []

        while index < directories.count {
            guard directories.count <= 2_000 else { return nil }
            let (directory, depth) = directories[index]
            index += 1
            guard depth < 4,
                  let children = try? fileManager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles]
                  ) else { continue }
            for child in children {
                guard let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                      values.isDirectory == true, values.isSymbolicLink != true else { continue }
                if fileManager.fileExists(atPath: child.appendingPathComponent("pubspec.yaml").path),
                   let icon = locateInProject(child, platformHint: platformHint) {
                    matches.append(icon)
                }
                if !excluded.contains(child.lastPathComponent) {
                    directories.append((child, depth + 1))
                }
            }
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func locateInProject(
        _ project: URL,
        platformHint: String
    ) -> URL? {
        let hint = platformHint.lowercased()
        let platforms: [String]
        if hint.contains("macos") || hint.contains("mac os") {
            platforms = ["macos", "ios", "android", "web"]
        } else if hint.contains("iphone") || hint.contains("ipad") || hint.contains("ios") {
            platforms = ["ios", "macos", "android", "web"]
        } else if hint.contains("android") {
            platforms = ["android", "ios", "macos", "web"]
        } else if hint.contains("chrome") || hint.contains("web") || hint.contains("edge") {
            platforms = ["web", "macos", "ios", "android"]
        } else {
            platforms = ["macos", "ios", "android", "web"]
        }

        let candidates = (
            hint.contains("macos") || hint.contains("mac os") ||
            hint.contains("iphone") || hint.contains("ipad") || hint.contains("ios") ||
            hint.contains("android") || hint.contains("chrome") ||
            hint.contains("web") || hint.contains("edge")
        ) ? Array(platforms.prefix(1)) : platforms

        for platform in candidates {
            if platform == "macos" || platform == "ios" {
                let assets = project.appendingPathComponent(
                    "\(platform)/Runner/Assets.xcassets/AppIcon.appiconset", isDirectory: true
                )
                if let icon = assetCatalogIcon(in: assets) { return icon }
                if let icon = alternateAppleIcon(in: project.appendingPathComponent(platform)) { return icon }
            } else if platform == "android" {
                if let icon = androidIcon(in: project) { return icon }
            } else if platform == "web" {
                if let icon = webIcon(in: project) { return icon }
            }
        }
        return nil
    }

    private static func alternateAppleIcon(in platform: URL) -> URL? {
        let catalogs = files(in: platform, maxDepth: 6) { $0.pathExtension == "appiconset" }
        for catalog in catalogs {
            if let icon = assetCatalogIcon(in: catalog) { return icon }
        }
        return nil
    }

    private static func androidIcon(in project: URL) -> URL? {
        let src = project.appendingPathComponent("android/app/src", isDirectory: true)
        let manager = FileManager.default
        let sourceSets = ((try? manager.contentsOfDirectory(
            at: src, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )) ?? []).sorted { left, right in
            if (left.lastPathComponent == "main") != (right.lastPathComponent == "main") {
                return left.lastPathComponent == "main"
            }
            return left.lastPathComponent < right.lastPathComponent
        }
        let manifests = sourceSets.compactMap { source -> (String, String)? in
            let parser = AndroidIconManifest()
            let manifest = source.appendingPathComponent("AndroidManifest.xml")
            guard let xml = XMLParser(contentsOf: manifest) else { return nil }
            xml.delegate = parser
            guard xml.parse(), let icon = parser.icon else { return nil }
            let components = icon.split(separator: "/")
            guard components.count == 2,
                  components[0] == "@mipmap" || components[0] == "@drawable" else { return nil }
            return (String(components[0].dropFirst()), String(components[1]))
        }
        let resources = sourceSets.flatMap { source in
            files(in: source.appendingPathComponent("res"), maxDepth: 2) { url in
                let directory = url.deletingLastPathComponent().lastPathComponent
                return (directory.hasPrefix("mipmap") || directory.hasPrefix("drawable"))
                    && ["png", "jpg", "jpeg", "webp"].contains(url.pathExtension.lowercased())
            }
        }
        let densityOrder = ["xxxhdpi", "xxhdpi", "xhdpi", "hdpi", "mdpi"]
        func priority(_ url: URL) -> Int {
            let directory = url.deletingLastPathComponent().lastPathComponent
            return densityOrder.firstIndex(where: { directory.contains("-\($0)") }) ?? densityOrder.count
        }
        for (kind, name) in manifests + [("mipmap", "ic_launcher"), ("drawable", "ic_launcher")] {
            let candidates = resources.filter {
                $0.deletingLastPathComponent().lastPathComponent.hasPrefix(kind)
                    && $0.deletingPathExtension().lastPathComponent == name
            }.sorted {
                if priority($0) != priority($1) { return priority($0) < priority($1) }
                return $0.path < $1.path
            }
            if let icon = candidates.first { return icon }
        }
        return resources.first {
            let name = $0.deletingPathExtension().lastPathComponent.lowercased()
            return name.contains("launcher") || name.contains("app_icon")
        }
    }

    private static func webIcon(in project: URL) -> URL? {
        let web = project.appendingPathComponent("web", isDirectory: true)
        let manifest = web.appendingPathComponent("manifest.json")
        if let data = try? Data(contentsOf: manifest),
           let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let icons = json["icons"] as? [[String: Any]] {
            let sorted = icons.sorted {
                func size(_ icon: [String: Any]) -> Int {
                    let value = icon["sizes"] as? String ?? ""
                    return Int(value.split(separator: "x").first ?? "") ?? 0
                }
                return size($0) > size($1)
            }
            for icon in sorted {
                guard let src = icon["src"] as? String, !src.contains("://") else { continue }
                let relative = String(src.drop(while: { $0 == "/" }))
                let url = web.appendingPathComponent(relative).standardizedFileURL
                guard url.path.hasPrefix(web.standardizedFileURL.path + "/"),
                      ["png", "jpg", "jpeg", "ico"].contains(url.pathExtension.lowercased()),
                      FileManager.default.fileExists(atPath: url.path) else { continue }
                return url
            }
        }
        for path in ["icons/Icon-512.png", "icons/Icon-192.png", "favicon.png"] {
            let url = web.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    private static func files(in root: URL, maxDepth: Int, matching: (URL) -> Bool) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var matches: [URL] = []
        var count = 0
        while let url = enumerator.nextObject() as? URL {
            count += 1
            if count > 10_000 { break }
            if enumerator.level >= maxDepth { enumerator.skipDescendants() }
            if matching(url) {
                matches.append(url)
                if url.pathExtension == "appiconset" { enumerator.skipDescendants() }
            }
        }
        return matches.sorted { $0.path < $1.path }
    }

    private static func assetCatalogIcon(in directory: URL) -> URL? {
        struct Catalog: Decodable {
            struct Image: Decodable {
                let filename: String?
                let size: String?
                let scale: String?
                let appearances: [Appearance]?
            }

            struct Appearance: Decodable {}
            let images: [Image]
        }

        guard let data = try? Data(contentsOf: directory.appendingPathComponent("Contents.json")),
              let catalog = try? JSONDecoder().decode(Catalog.self, from: data) else { return nil }
        let images = catalog.images.filter { $0.appearances == nil }.sorted {
            func pixels(_ image: Catalog.Image) -> Double {
                let size = Double(image.size?.split(separator: "x").first ?? "") ?? 0
                let scale = Double(image.scale?.replacingOccurrences(of: "x", with: "") ?? "") ?? 1
                return size * scale
            }
            return pixels($0) > pixels($1)
        }
        for image in images {
            guard let filename = image.filename, !filename.isEmpty,
                  filename == URL(fileURLWithPath: filename).lastPathComponent else { continue }
            let url = directory.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }
}

private final class AndroidIconManifest: NSObject, XMLParserDelegate {
    var icon: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        if elementName == "application" {
            icon = attributeDict["android:icon"]
        }
    }
}
