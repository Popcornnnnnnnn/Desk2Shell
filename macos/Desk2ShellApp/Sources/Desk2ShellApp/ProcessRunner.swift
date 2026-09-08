import Foundation

struct ProcessResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

enum ProcessRunner {
    static func run(
        _ executable: String,
        _ arguments: [String],
        environment: [String: String] = [:],
        input: Data? = nil
    ) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        if let input {
            let pipe = Pipe()
            process.standardInput = pipe
            try process.run()
            pipe.fileHandleForWriting.write(input)
            try pipe.fileHandleForWriting.close()
        } else {
            try process.run()
        }

        process.waitUntilExit()
        let stdout = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return ProcessResult(stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)
    }

    static func checked(_ executable: String, _ arguments: [String], environment: [String: String] = [:]) throws -> String {
        let result = try run(executable, arguments, environment: environment)
        guard result.exitCode == 0 else {
            let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw Desk2ShellError.commandFailed(detail.isEmpty ? "命令执行失败：\(executable)" : detail)
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
