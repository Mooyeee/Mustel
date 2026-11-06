import Foundation

struct DiscoverySummary: Equatable {
    let discoveredTargetCount: Int
    let skippedRuns: Int
    let unsupportedRuns: Int
    let ideManagedRuns: Int

    var statusText: String {
        var text: String
        if discoveredTargetCount == 0, ideManagedRuns > 0 {
            text = "\(ideManagedRuns) IDE-managed Flutter run(s) found. They are not attached by a second Flutter tool; IDE sessions appear in the bridge below."
        } else if discoveredTargetCount == 0, unsupportedRuns > 0 {
            text = "Existing desktop/web runs need a VM Service info file (`--vmservice-out-file`) to attach automatically."
        } else if discoveredTargetCount == 0 {
            text = skippedRuns == 0
                ? "No attachable Flutter runs found."
                : "\(skippedRuns) Flutter run session(s) could not be identified."
        } else {
            text = "\(discoveredTargetCount) existing Flutter target(s) detected."
        }

        if skippedRuns > 0 {
            text += " \(skippedRuns) run(s) skipped; use `flutter run -d <device>` if the device is ambiguous."
        }
        if discoveredTargetCount > 0, unsupportedRuns > 0 {
            text += " Or launch desktop/web projects here."
        }
        if discoveredTargetCount > 0, ideManagedRuns > 0 {
            text += " Skipped \(ideManagedRuns) IDE-managed run(s) to avoid conflicting with their IDE."
        }
        return text
    }
}
