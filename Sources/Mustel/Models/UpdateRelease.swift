import Foundation

struct UpdateAsset: Equatable, Sendable {
    let name: String
    let url: URL
    let size: Int?

    var version: AppVersion? {
        AppVersion(name)
    }
}

struct UpdateRelease: Equatable, Sendable {
    let version: AppVersion
    let tagName: String
    let name: String
    let notes: String
    let pageURL: URL
    let assetURL: URL?
    let assetName: String?
    let assetSize: Int?
    let visualStudioCodeAsset: UpdateAsset?
    let intellijAsset: UpdateAsset?

    init(
        version: AppVersion,
        tagName: String,
        name: String,
        notes: String,
        pageURL: URL,
        assetURL: URL?,
        assetName: String?,
        assetSize: Int?,
        visualStudioCodeAsset: UpdateAsset? = nil,
        intellijAsset: UpdateAsset? = nil
    ) {
        self.version = version
        self.tagName = tagName
        self.name = name
        self.notes = notes
        self.pageURL = pageURL
        self.assetURL = assetURL
        self.assetName = assetName
        self.assetSize = assetSize
        self.visualStudioCodeAsset = visualStudioCodeAsset
        self.intellijAsset = intellijAsset
    }

    var displayVersion: String { "v\(version)" }
}

enum UpdateError: LocalizedError, Equatable {
    case noReleases
    case missingAsset
    case invalidResponse
    case httpStatus(Int)
    case invalidVersion(String)
    case downloadFailed(String)
    case notAppBundle
    case invalidBundle
    case versionMismatch(expected: String, actual: String?)
    case invalidSignature(String)
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .noReleases:
            return "No GitHub releases have been published yet."
        case .missingAsset:
            return "The latest release does not include a \(AppIdentity.releaseAssetName) asset."
        case .invalidResponse:
            return "GitHub returned an invalid response."
        case let .httpStatus(status):
            return "GitHub returned HTTP \(status)."
        case let .invalidVersion(value):
            return "Could not read the version from “\(value)”."
        case let .downloadFailed(message):
            return "Could not download the update: \(message)"
        case .notAppBundle:
            return "Updates are available only when Mustel runs from the installed app."
        case .invalidBundle:
            return "The update does not contain a valid Mustel.app bundle."
        case let .versionMismatch(expected, actual):
            return "The downloaded app is version \(actual ?? "unknown"), expected \(expected)."
        case let .invalidSignature(message):
            return "The downloaded app failed code-signature validation: \(message)"
        case let .installFailed(message):
            return "Could not install the update: \(message)"
        }
    }
}
