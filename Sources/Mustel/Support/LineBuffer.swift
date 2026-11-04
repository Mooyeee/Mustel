import Foundation

final class LineBuffer {
    private let lock = NSLock()
    private var data = Data()

    func append(_ bytes: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }

        data.append(bytes)
        var lines: [String] = []
        while let newline = data.firstIndex(of: 10) {
            let line = data[..<newline]
            data.removeSubrange(...newline)
            if let string = String(data: line, encoding: .utf8) {
                lines.append(string)
            }
        }
        return lines
    }
}
