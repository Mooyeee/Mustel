import Foundation

protocol UpdateServicing: Sendable {
    func latestRelease() async throws -> UpdateRelease?
    func download(
        _ release: UpdateRelease,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL
}

struct GitHubUpdateService: UpdateServicing {
    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL
            let size: Int?

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
                case size
            }
        }

        let tagName: String
        let name: String?
        let body: String?
        let htmlURL: URL
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case body
            case htmlURL = "html_url"
            case assets
        }
    }

    let repository: String
    let session: URLSession

    init(
        repository: String = AppIdentity.repository,
        session: URLSession = .shared
    ) {
        self.repository = repository
        self.session = session
    }

    func latestRelease() async throws -> UpdateRelease? {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
            throw UpdateError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Mustel/\(AppIdentity.versionString ?? "dev")", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw UpdateError.invalidResponse
        }
        if response.statusCode == 404 {
            return nil
        }
        guard (200..<300).contains(response.statusCode) else {
            throw UpdateError.httpStatus(response.statusCode)
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard let version = AppVersion(release.tagName)
            ?? release.name.flatMap(AppVersion.init) else {
            throw UpdateError.invalidVersion(release.tagName)
        }

        let zipAssets = release.assets.filter {
            $0.name.lowercased().hasSuffix(".zip")
                && !$0.name.localizedCaseInsensitiveContains("intellij")
        }
        let appAsset = zipAssets.first { $0.name == AppIdentity.releaseAssetName }
            ?? zipAssets.first { $0.name.localizedCaseInsensitiveContains("mustel") }
            ?? (zipAssets.count == 1 ? zipAssets.first : nil)
        let visualStudioCodeAsset = release.assets.first {
            $0.name.lowercased().hasSuffix(".vsix")
        }
        let intellijAsset = release.assets.first {
            $0.name.localizedCaseInsensitiveContains("intellij")
                && $0.name.lowercased().hasSuffix(".zip")
        }

        return UpdateRelease(
            version: version,
            tagName: release.tagName,
            name: release.name ?? release.tagName,
            notes: release.body ?? "",
            pageURL: release.htmlURL,
            assetURL: appAsset?.browserDownloadURL,
            assetName: appAsset?.name,
            assetSize: appAsset?.size,
            visualStudioCodeAsset: visualStudioCodeAsset.map {
                UpdateAsset(name: $0.name, url: $0.browserDownloadURL, size: $0.size)
            },
            intellijAsset: intellijAsset.map {
                UpdateAsset(name: $0.name, url: $0.browserDownloadURL, size: $0.size)
            }
        )
    }

    func download(
        _ release: UpdateRelease,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        guard let assetURL = release.assetURL else {
            throw UpdateError.missingAsset
        }
        let name = release.assetName ?? AppIdentity.releaseAssetName
        return try await UpdateDownloader().download(
            from: assetURL,
            suggestedName: name,
            progress: progress
        )
    }
}

private final class UpdateDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var progressHandler: (@Sendable (Double) -> Void)?
    private var destination: URL?
    private var session: URLSession?

    func download(
        from url: URL,
        suggestedName: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("MustelUpdate-\(UUID().uuidString)", isDirectory: true)
            do {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
            } catch {
                continuation.resume(throwing: UpdateError.downloadFailed(error.localizedDescription))
                return
            }

            lock.lock()
            self.continuation = continuation
            progressHandler = progress
            destination = directory.appendingPathComponent(suggestedName)
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 300
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            self.session = session
            lock.unlock()

            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        report(progress: Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let response = downloadTask.response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
            finish(.failure(UpdateError.downloadFailed("HTTP \(status)")))
            return
        }
        guard let destination else {
            finish(.failure(UpdateError.downloadFailed("Missing download destination.")))
            return
        }

        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            finish(.success(destination))
        } catch {
            finish(.failure(UpdateError.downloadFailed(error.localizedDescription)))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            finish(.failure(UpdateError.downloadFailed(error.localizedDescription)))
        } else if isPending {
            finish(.failure(UpdateError.downloadFailed("The download ended unexpectedly.")))
        }
    }

    private var isPending: Bool {
        lock.lock()
        defer { lock.unlock() }
        return continuation != nil
    }

    private func report(progress: Double) {
        lock.lock()
        let handler = progressHandler
        lock.unlock()
        handler?(progress)
    }

    private func finish(_ result: Result<URL, Error>) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        progressHandler = nil
        let session = self.session
        self.session = nil
        lock.unlock()

        session?.finishTasksAndInvalidate()
        continuation.resume(with: result)
    }
}
