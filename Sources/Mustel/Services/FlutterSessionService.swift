import Foundation

enum FlutterSessionEvent: Equatable, Sendable {
    case machine([MachineOutput])
    case stderr(String)
    case exited(Int32)
}

protocol FlutterSessionServicing: AnyObject {
    var onEvent: ((FlutterSessionEvent) -> Void)? { get set }
    func start() throws
    func stop()
    func send(_ payload: [String: Any]) throws
}

final class FlutterSessionService: FlutterSessionServicing {
    var onEvent: ((FlutterSessionEvent) -> Void)?

    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private let decoder = MachineProtocolDecoder()

    init(target: FlutterTarget, flutterExecutable: String) {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = Self.arguments(for: target, flutterExecutable: flutterExecutable)
        process.currentDirectoryURL = URL(fileURLWithPath: target.projectPath, isDirectory: true)
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
    }

    static func arguments(for target: FlutterTarget, flutterExecutable: String) -> [String] {
        var arguments = [FlutterExecutableLocator.resolve(flutterExecutable, projectPath: target.projectPath)]
        switch target.mode {
        case .attach:
            arguments.append(contentsOf: ["attach", "--machine", "--no-dds", "--device-id", target.deviceID])
        case .attachURL:
            arguments.append(contentsOf: ["attach", "--machine", "--no-dds", "--device-id", target.deviceID])
            if let vmServiceURL = target.vmServiceURL {
                arguments.append(contentsOf: ["--debug-uri", vmServiceURL])
            }
        case .run:
            arguments.append(contentsOf: ["run", "--machine", "--device-id", target.deviceID])
        }
        if let targetPath = target.targetPath {
            arguments.append(contentsOf: ["--target", targetPath])
        }
        return arguments
    }

    func start() throws {
        let stdoutBuffer = LineBuffer()
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let bytes = handle.availableData
            guard !bytes.isEmpty else { return }
            for line in stdoutBuffer.append(bytes) {
                guard let self else { return }
                let outputs = self.decoder.decode(line)
                guard !outputs.isEmpty else { continue }
                self.emit(.machine(outputs))
            }
        }

        let stderrBuffer = LineBuffer()
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let bytes = handle.availableData
            guard !bytes.isEmpty else { return }
            for line in stderrBuffer.append(bytes) {
                self?.emit(.stderr(line))
            }
        }

        process.terminationHandler = { [weak self] process in
            self?.output.fileHandleForReading.readabilityHandler = nil
            self?.errors.fileHandleForReading.readabilityHandler = nil
            self?.emit(.exited(process.terminationStatus))
        }

        try process.run()
    }

    func stop() {
        output.fileHandleForReading.readabilityHandler = nil
        errors.fileHandleForReading.readabilityHandler = nil
        if process.isRunning {
            process.terminate()
        }
    }

    func send(_ payload: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: [payload])
        var line = data
        line.append(10)
        try input.fileHandleForWriting.write(contentsOf: line)
    }

    private func emit(_ event: FlutterSessionEvent) {
        onEvent?(event)
    }

    deinit {
        if process.isRunning {
            process.terminate()
        }
    }
}
