import Foundation

protocol LocalCommandReading: Sendable {
    func firstSuccessfulOutput(commands: [[String]]) -> String?
}

struct LocalCommandReader: LocalCommandReading {
    private let timeoutSeconds: TimeInterval

    init(timeoutSeconds: TimeInterval = 2) {
        self.timeoutSeconds = timeoutSeconds
    }

    func firstSuccessfulOutput(commands: [[String]]) -> String? {
        for command in commands {
            if let output = run(command), output.isEmpty == false {
                return output
            }
        }

        return nil
    }

    private func run(_ command: [String]) -> String? {
        guard command.isEmpty == false else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            semaphore.signal()
        }

        let timeoutMilliseconds = max(1, Int(timeoutSeconds * 1_000))
        guard semaphore.wait(timeout: .now() + .milliseconds(timeoutMilliseconds)) == .success else {
            if process.isRunning {
                process.terminate()
            }
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
