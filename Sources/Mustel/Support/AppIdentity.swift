import Foundation

enum AppIdentity {
    static let bundleIdentifier = "com.mooyee.Mustel"
    static let legacyBundleIdentifier = "com.ionutdanielfagadau.Mustel"
    static let repository = "Mooyeee/mustel"
    static let releaseAssetName = "Mustel.zip"

    static var isAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var versionString: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !value.isEmpty else {
            return nil
        }
        return value
    }

    static var version: AppVersion? {
        versionString.flatMap(AppVersion.init)
    }
}

struct AppVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
    private let components: [Int]

    init?(_ raw: String) {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstDigit = value.firstIndex(where: { $0.isNumber }) else { return nil }
        value = String(value[firstDigit...])

        var components: [Int] = []
        for part in value.split(separator: ".", omittingEmptySubsequences: false) {
            let digits = part.prefix { $0.isNumber }
            guard !digits.isEmpty, let number = Int(digits) else { break }
            components.append(number)
        }
        guard !components.isEmpty else { return nil }
        self.components = components
    }

    var description: String {
        components.map(String.init).joined(separator: ".")
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}
