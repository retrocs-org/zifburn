import Foundation

enum StreamSource: Sendable {
    case stdout
    case stderr
}

enum RunEvent: Sendable {
    /// A completed line (terminated by `\n`).
    case line(String, StreamSource)
    /// A line that minipro will overwrite (terminated by `\r`) – progress updates.
    case transient(String, StreamSource)
    case exited(Int32)
}

/// Wraps `Process` and turns its stdout/stderr into an `AsyncStream` of events.
/// Splits on both `\n` and `\r` so minipro's in-place progress counters arrive
/// as individual `transient` events instead of one huge blob at the end.
final class RunningProcess: @unchecked Sendable {
    let events: AsyncStream<RunEvent>

    private let continuation: AsyncStream<RunEvent>.Continuation
    private let process = Process()
    private let outPipe = Pipe()
    private let errPipe = Pipe()
    private let lock = NSLock()
    private var pending: [StreamSource: Data] = [:]

    init(executable: URL, arguments: [String]) throws {
        var captured: AsyncStream<RunEvent>.Continuation?
        events = AsyncStream(bufferingPolicy: .unbounded) { captured = $0 }
        continuation = captured!

        process.executableURL = executable
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["NO_COLOR"] = "1"
        process.environment = env
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outPipe
        process.standardError = errPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                self?.ingest(data, from: .stdout)
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                self?.ingest(data, from: .stderr)
            }
        }
        process.terminationHandler = { [weak self] proc in
            self?.finish(status: proc.terminationStatus)
        }

        try process.run()
    }

    var isRunning: Bool { process.isRunning }

    /// Sends SIGINT (lets minipro clean up and power down the socket),
    /// escalating to SIGTERM if it hasn't exited after a few seconds.
    func interrupt() {
        guard process.isRunning else { return }
        process.interrupt()
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.process.isRunning else { return }
            self.process.terminate()
        }
    }

    // MARK: - Output handling

    private func ingest(_ data: Data, from source: StreamSource) {
        lock.lock()
        defer { lock.unlock() }
        ingestLocked(data, source)
    }

    private func ingestLocked(_ data: Data, _ source: StreamSource) {
        var buffer = pending[source, default: Data()]
        buffer.append(data)
        let bytes = [UInt8](buffer)

        var start = 0
        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            if b == 0x0A {
                emit(bytes[start..<i], source, transient: false)
                start = i + 1
            } else if b == 0x0D {
                if i + 1 < bytes.count, bytes[i + 1] == 0x0A {
                    // CRLF – treat as an ordinary line ending.
                    emit(bytes[start..<i], source, transient: false)
                    i += 1
                } else {
                    emit(bytes[start..<i], source, transient: true)
                }
                start = i + 1
            }
            i += 1
        }
        pending[source] = start < bytes.count ? Data(bytes[start...]) : Data()
    }

    private func emit(_ bytes: ArraySlice<UInt8>, _ source: StreamSource, transient: Bool) {
        let text = OutputParser.clean(String(decoding: bytes, as: UTF8.self))
        guard !text.isEmpty else { return }
        continuation.yield(transient ? .transient(text, source) : .line(text, source))
    }

    private func finish(status: Int32) {
        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil
        let restOut = try? outPipe.fileHandleForReading.readToEnd()
        let restErr = try? errPipe.fileHandleForReading.readToEnd()

        lock.lock()
        if let restOut, !restOut.isEmpty { ingestLocked(restOut, .stdout) }
        if let restErr, !restErr.isEmpty { ingestLocked(restErr, .stderr) }
        for source in [StreamSource.stdout, .stderr] {
            if let rest = pending[source], !rest.isEmpty {
                emit(ArraySlice([UInt8](rest)), source, transient: false)
            }
            pending[source] = Data()
        }
        lock.unlock()

        continuation.yield(.exited(status))
        continuation.finish()
    }
}

/// Everything a finished minipro invocation produced.
struct CommandResult: Sendable {
    var status: Int32 = -1
    var lines: [String] = []
    var stdout: [String] = []
    var stderr: [String] = []

    var succeeded: Bool { status == 0 }

    /// The most useful line to show when something went wrong.
    var failureReason: String {
        let interesting = lines.last { line in
            let l = line.lowercased()
            return l.contains("error") || l.contains("fail") || l.contains("mismatch")
                || l.contains("not ") || l.contains("invalid") || l.contains("unsupported")
        }
        return interesting ?? lines.last ?? "minipro exited with status \(status)"
    }
}
