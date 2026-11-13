import Foundation

protocol UpdateInstalling: Sendable {
    func install(archiveURL: URL, release: UpdateRelease) async throws
}

struct UpdateInstaller: UpdateInstalling {
    let bundleURL: URL
    let bundleIdentifier: String

    init(
        bundleURL: URL = Bundle.main.bundleURL,
        bundleIdentifier: String = AppIdentity.bundleIdentifier
    ) {
        self.bundleURL = bundleURL
        self.bundleIdentifier = bundleIdentifier
    }

    func install(archiveURL: URL, release: UpdateRelease) async throws {
        guard bundleURL.pathExtension == "app",
              FileManager.default.fileExists(atPath: bundleURL.path) else {
            throw UpdateError.notAppBundle
        }

        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MustelInstall-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        var keepsWorkDirectory = false
        defer {
            if !keepsWorkDirectory {
                try? FileManager.default.removeItem(at: workDirectory)
            }
        }

        try run(
            "/usr/bin/ditto",
            arguments: ["-x", "-k", archiveURL.path, workDirectory.path],
            error: UpdateError.installFailed
        )
        if archiveURL.deletingLastPathComponent().lastPathComponent.hasPrefix("MustelUpdate-") {
            try? FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent())
        }

        let appURL = try FileManager.default
            .contentsOfDirectory(at: workDirectory, includingPropertiesForKeys: nil)
            .first { $0.pathExtension == "app" }
        guard let appURL else {
            throw UpdateError.invalidBundle
        }

        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: infoURL) as? [String: Any],
              info["CFBundleIdentifier"] as? String == bundleIdentifier else {
            throw UpdateError.invalidBundle
        }
        let downloadedVersion = (info["CFBundleShortVersionString"] as? String)
            .flatMap(AppVersion.init)
        guard downloadedVersion == release.version else {
            throw UpdateError.versionMismatch(
                expected: release.version.description,
                actual: downloadedVersion?.description
            )
        }

        try run(
            "/usr/bin/codesign",
            arguments: ["--verify", "--deep", "--strict", appURL.path],
            error: UpdateError.invalidSignature
        )

        let scriptURL = workDirectory.appendingPathComponent("install.sh")
        try installScript.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            scriptURL.path,
            String(ProcessInfo.processInfo.processIdentifier),
            appURL.path,
            bundleURL.path,
            workDirectory.path
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        keepsWorkDirectory = true
    }

    private var installScript: String {
        """
        #!/bin/bash
        set -euo pipefail

        pid="$1"
        new_app="$2"
        target_app="$3"
        work_directory="$4"
        log_directory="$HOME/Library/Logs/Mustel"
        mkdir -p "$log_directory"
        exec >>"$log_directory/update.log" 2>&1

        echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") Waiting for Mustel to quit (pid $pid)…"
        while kill -0 "$pid" 2>/dev/null; do
          sleep 0.2
        done

        backup_app="${target_app}.backup"
        restore() {
          status=$?
          if [ "$status" -ne 0 ]; then
            echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") Update failed; restoring the previous app."
            if [ -d "$backup_app" ]; then
              rm -rf "$target_app"
              mv "$backup_app" "$target_app"
            fi
            /usr/bin/open "$target_app" || true
          fi
          rm -rf "$work_directory"
        }
        trap restore EXIT

        rm -rf "$backup_app"
        mv "$target_app" "$backup_app"

        if /usr/bin/ditto "$new_app" "$target_app" \\
            && /usr/bin/codesign --verify --deep --strict "$target_app"; then
          /usr/bin/xattr -dr com.apple.quarantine "$target_app" 2>/dev/null || true
          rm -rf "$backup_app"
          echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") Update installed."
          /usr/bin/open "$target_app"
        else
          exit 1
        fi
        """
    }

    private func run(
        _ executable: String,
        arguments: [String],
        error: (String) -> UpdateError
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw error(message?.isEmpty == false ? message! : "Command failed.")
        }
    }
}
