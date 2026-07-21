import Darwin
import Foundation

protocol UsageFetching: Sendable {
    func fetch() async throws -> UsageReport
}

struct CodexClient: UsageFetching {
    private let executableLocator: CodexExecutableLocator
    private let timeout: Duration

    init(
        executableLocator: CodexExecutableLocator = CodexExecutableLocator(),
        timeout: Duration = AppConfiguration.requestTimeout
    ) {
        self.executableLocator = executableLocator
        self.timeout = timeout
    }

    func fetch() async throws -> UsageReport {
        guard let executableURL = executableLocator.locate() else {
            throw CodexClientError.executableNotFound
        }

        let session = CodexRPCSession(executableURL: executableURL, timeout: timeout)
        let response = try await session.readRateLimits()

        do {
            return try CodexResponseParser.parseRateLimitsResponse(response)
        } catch CodexResponseParsingError.server(let message) {
            throw CodexClientError.server(DiagnosticText.sanitized(message))
        } catch {
            throw CodexClientError.invalidResponse
        }
    }
}

enum CodexClientError: LocalizedError, Equatable {
    case executableNotFound
    case launchFailed(String)
    case connectionClosed(String?)
    case timedOut
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            "Codex is not installed"
        case .launchFailed(let message):
            "Could not start Codex: \(DiagnosticText.sanitized(message))"
        case .connectionClosed(let detail):
            detail.map { "Codex closed the connection: \(DiagnosticText.sanitized($0))" }
                ?? "Codex closed the connection"
        case .timedOut:
            "Codex did not respond"
        case .invalidResponse:
            "Codex returned an unfamiliar response"
        case .server(let message):
            DiagnosticText.sanitized(message)
        }
    }
}

struct CodexExecutableLocator: Sendable {
    private static let knownLocations = [
        "/Applications/ChatGPT.app/Contents/Resources/codex",
        "/opt/homebrew/bin/codex",
        "/usr/local/bin/codex",
    ]

    private let environmentPath: String?

    init(environmentPath: String? = ProcessInfo.processInfo.environment["PATH"]) {
        self.environmentPath = environmentPath
    }

    func locate() -> URL? {
        let searchPaths = Self.knownLocations + pathCandidates
        return searchPaths.lazy
            .filter(FileManager.default.isExecutableFile(atPath:))
            .map(URL.init(fileURLWithPath:))
            .first
    }

    private var pathCandidates: [String] {
        environmentPath?
            .split(separator: ":", omittingEmptySubsequences: true)
            .map { directory in
                URL(fileURLWithPath: String(directory), isDirectory: true)
                    .appendingPathComponent("codex", isDirectory: false)
                    .path
            } ?? []
    }
}

actor CodexRPCSession {
    private enum Phase {
        case idle
        case initializing
        case readingRateLimits
        case finished
    }

    private enum RequestID {
        static let initialize = 1
        static let rateLimits = 2
    }

    private static let maximumErrorBytes = 16_384

    private let executableURL: URL
    private let timeout: Duration

    private var phase = Phase.idle
    private var process: Process?
    private var standardInput: FileHandle?
    private var standardOutput: FileHandle?
    private var standardError: FileHandle?
    private var outputBuffer = JSONLineBuffer(maximumBufferedBytes: 1_048_576)
    private var errorBuffer = Data()
    private var continuation: CheckedContinuation<Data, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var forceTerminationTask: Task<Void, Never>?
    private var processExitStatus: Int32?
    private var reachedOutputEOF = false

    init(executableURL: URL, timeout: Duration) {
        self.executableURL = executableURL
        self.timeout = timeout
    }

    func readRateLimits() async throws -> Data {
        try Task.checkCancellation()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                start(continuation: continuation)
            }
        } onCancel: {
            Task { await self.cancel() }
        }
    }

    private func start(continuation: CheckedContinuation<Data, Error>) {
        guard phase == .idle else {
            continuation.resume(throwing: CodexClientError.invalidResponse)
            return
        }

        self.continuation = continuation

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let outputHandle = outputPipe.fileHandleForReading
        let errorHandle = errorPipe.fileHandleForReading

        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }

            // FileHandle delivers stdout serially. Waiting on this private I/O callback keeps
            // actor delivery in the same order, including the final data chunk and EOF.
            let delivered = DispatchSemaphore(value: 0)
            Task {
                await self.receiveOutput(data)
                delivered.signal()
            }
            delivered.wait()
        }
        errorHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { await self?.receiveError(data) }
        }
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            Task { await self?.processDidTerminate(status: status) }
        }

        self.process = process
        standardInput = inputPipe.fileHandleForWriting
        standardOutput = outputHandle
        standardError = errorHandle
        phase = .initializing

        do {
            try process.run()
            try sendInitializeRequest()
            scheduleTimeout()
        } catch {
            finish(with: .failure(CodexClientError.launchFailed(error.localizedDescription)))
        }
    }

    private func receiveOutput(_ data: Data) {
        guard phase != .finished else { return }
        guard !data.isEmpty else {
            reachedOutputEOF = true
            finishAfterProcessExitIfReady()
            return
        }

        let lines: [Data]
        do {
            lines = try outputBuffer.append(data)
        } catch {
            finish(with: .failure(CodexClientError.invalidResponse))
            return
        }

        for line in lines {
            handleMessage(line)

            if phase == .finished {
                return
            }
        }
    }

    private func receiveError(_ data: Data) {
        guard phase != .finished, !data.isEmpty, errorBuffer.count < Self.maximumErrorBytes else {
            return
        }

        let bytesRemaining = Self.maximumErrorBytes - errorBuffer.count
        errorBuffer.append(data.prefix(bytesRemaining))
    }

    private func handleMessage(_ data: Data) {
        guard !data.isEmpty, let header = try? JSONDecoder().decode(RPCMessageHeader.self, from: data) else {
            return
        }

        if let message = header.error?.message {
            finish(with: .failure(CodexClientError.server(DiagnosticText.sanitized(message))))
            return
        }

        switch (phase, header.id) {
        case (.initializing, RequestID.initialize):
            do {
                try sendInitializedNotification()
                try sendRateLimitsRequest()
                phase = .readingRateLimits
            } catch {
                finish(with: .failure(CodexClientError.connectionClosed(error.localizedDescription)))
            }

        case (.readingRateLimits, RequestID.rateLimits):
            finish(with: .success(data))

        default:
            break
        }
    }

    private func processDidTerminate(status: Int32) {
        guard phase != .finished else {
            releaseProcess()
            return
        }

        processExitStatus = status
        finishAfterProcessExitIfReady()
    }

    private func finishAfterProcessExitIfReady() {
        guard reachedOutputEOF, let processExitStatus else { return }

        let detail = stderrDescription
        let fallback = processExitStatus == 0 ? nil : "exit status \(processExitStatus)"
        finish(with: .failure(CodexClientError.connectionClosed(detail ?? fallback)))
    }

    private func scheduleTimeout() {
        timeoutTask = Task { [weak self, timeout] in
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }
            await self?.timeOut()
        }
    }

    private func timeOut() {
        guard phase != .finished else { return }
        finish(with: .failure(CodexClientError.timedOut))
    }

    private func cancel() {
        guard phase != .finished else { return }
        finish(with: .failure(CancellationError()))
    }

    private func finish(with result: Result<Data, Error>) {
        guard phase != .finished else { return }
        phase = .finished

        timeoutTask?.cancel()
        timeoutTask = nil
        standardOutput?.readabilityHandler = nil
        standardError?.readabilityHandler = nil
        try? standardInput?.close()

        if process?.isRunning == true {
            process?.terminate()
            scheduleForcedTermination()
        } else {
            releaseProcess()
        }
        standardInput = nil
        standardOutput = nil
        standardError = nil

        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(with: result)
    }

    private func sendInitializeRequest() throws {
        try writeJSON([
            "id": RequestID.initialize,
            "method": "initialize",
            "params": [
                "clientInfo": [
                    "name": "codex-usage-micro",
                    "title": AppConfiguration.name,
                    "version": AppConfiguration.version,
                ],
                "capabilities": ["experimentalApi": true],
            ],
        ])
    }

    private func sendInitializedNotification() throws {
        try writeJSON(["method": "initialized"])
    }

    private func sendRateLimitsRequest() throws {
        try writeJSON([
            "id": RequestID.rateLimits,
            "method": "account/rateLimits/read",
            "params": NSNull(),
        ])
    }

    private func writeJSON(_ object: [String: Any]) throws {
        guard let standardInput else {
            throw CodexClientError.connectionClosed(nil)
        }

        var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        data.append(0x0A)
        try standardInput.write(contentsOf: data)
    }

    private var stderrDescription: String? {
        guard
            let value = String(data: errorBuffer, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else {
            return nil
        }
        return String(value.prefix(512))
    }

    private func scheduleForcedTermination() {
        forceTerminationTask = Task { [self] in
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
            forceTerminateIfNeeded()
        }
    }

    private func forceTerminateIfNeeded() {
        guard let process, process.isRunning else {
            releaseProcess()
            return
        }
        kill(process.processIdentifier, SIGKILL)
    }

    private func releaseProcess() {
        forceTerminationTask?.cancel()
        forceTerminationTask = nil
        process?.terminationHandler = nil
        process = nil
    }
}

private struct RPCMessageHeader: Decodable {
    let id: Int?
    let error: RPCErrorPayload?
}
