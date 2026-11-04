import Foundation

protocol ProcessRunning: Sendable {
    func run(executable: String, arguments: [String]) throws -> String
}

struct SystemProcessRunner: ProcessRunning {
    func run(executable: String, arguments: [String]) throws -> String {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = standardError

        try process.run()

        let readGroup = DispatchGroup()
        let outputLock = NSLock()
        var outputData = Data()
        var errorData = Data()
        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            let data = standardOutput.fileHandleForReading.readDataToEndOfFile()
            outputLock.lock()
            outputData = data
            outputLock.unlock()
            readGroup.leave()
        }
        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            let data = standardError.fileHandleForReading.readDataToEndOfFile()
            outputLock.lock()
            errorData = data
            outputLock.unlock()
            readGroup.leave()
        }

        process.waitUntilExit()
        readGroup.wait()
        guard process.terminationStatus == 0 else {
            outputLock.lock()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? ""
            outputLock.unlock()
            throw DiscoveryError.commandFailed(executable, process.terminationStatus, errorMessage)
        }
        outputLock.lock()
        let result = String(data: outputData, encoding: .utf8) ?? ""
        outputLock.unlock()
        return result
    }
}
