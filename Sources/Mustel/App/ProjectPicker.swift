import AppKit

@MainActor
struct NSOpenPanelProjectPicker: ProjectPicking {
    func chooseProject() -> String? {
        let panel = NSOpenPanel()
        panel.title = "Choose a Flutter project"
        panel.prompt = "Choose Project"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK else { return nil }
        return panel.url?.path
    }
}
