import AppKit
import SwiftUI

struct ProjectIconView: View {
    let projectPath: String
    let platformHint: String
    @State private var image: NSImage?
    private static let fallbackImage = Bundle.module.url(forResource: "FlutterDefaultIcon", withExtension: "png")
        .flatMap { NSImage(contentsOf: $0) }

    var body: some View {
        Group {
            if let image = image ?? Self.fallbackImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
        .task(id: "\(projectPath)|\(platformHint)") {
            image = nil
            let path = projectPath
            let hint = platformHint
            let icon = await Task.detached(priority: .utility) {
                guard let url = ProjectIconLocator.locate(projectPath: path, platformHint: hint) else { return nil as CGImage? }
                return ProjectIconImage.load(from: url)
            }.value
            guard !Task.isCancelled, let icon else { return }
            image = NSImage(cgImage: icon, size: .zero)
        }
    }
}
