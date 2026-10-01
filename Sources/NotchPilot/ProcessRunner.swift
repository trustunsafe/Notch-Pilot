import Foundation

/// Runs a short-lived command-line tool and returns its output.
///
/// Two failure modes this guards against (both froze the UI, since some
/// callers run on the main thread):
/// - **Pipe deadlock.** Calling `waitUntilExit()` before reading stdout
///   blocks forever once the child writes more than the pipe buffer
///   (~64 KB): the child waits for a reader, we wait for the child.
///   `pgrep -fl claude` easily exceeds that with Claude Code's long
///   command lines. Here both pipes are drained while the child runs.
/// - **Hung tools.** `lsof` can stall indefinitely on some systems. The
///   child is SIGKILLed after `timeout` seconds.
enum ProcessRunner {
    struct Result {
        let status: Int32
        let stdout: Data
        let stderr: Data
    }

    private final class Box: @unchecked Sendable { var data = Data() }

    static func run(
        _ path: String,
        _ args: [String],
        environment: [String: String]? = nil,
        timeout: TimeInterval = 2
    ) -> Result? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        if let environment { task.environment = environment }
        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe

        do {
            try task.run()
        } catch {
            return nil
        }

        let pid = task.processIdentifier
        let killer = DispatchWorkItem {
            if task.isRunning { kill(pid, SIGKILL) }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)

        let errBox = Box()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        task.waitUntilExit()
        killer.cancel()

        return Result(status: task.terminationStatus, stdout: outData, stderr: errBox.data)
    }
}
