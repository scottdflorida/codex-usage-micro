import Darwin
import Foundation

struct CodexClient: Sendable {
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
    private static let defaultLocations = [
        "/Applications/ChatGPT.app/Contents/Resources/codex",
        "/opt/homebrew/bin/codex",
        "/usr/local/bin/codex",
    ]

    private let environmentPath: String?
    private let knownLocations: [String]

    init(
        environmentPath: String? = ProcessInfo.processInfo.environment["PATH"],
        knownLocations: [String] = Self.defaultLocations
    ) {
        self.environmentPath = environmentPath
        self.knownLocations = knownLocations
    }

    func locate() -> URL? {
        var visitedPaths: Set<String> = []
        for path in knownLocations + pathCandidates {
            guard path.hasPrefix("/") else { continue }
            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard visitedPaths.insert(url.path).inserted else { continue }

            var isDirectory = ObjCBool(false)
            guard
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                !isDirectory.boolValue,
                FileManager.default.isExecutableFile(atPath: url.path)
            else {
                continue
            }
            return url
        }
        return nil
    }

    private var pathCandidates: [String] {
        environmentPath?
            .split(separator: ":", omittingEmptySubsequences: true)
            .compactMap { directory -> String? in
                let path = String(directory)
                guard path.hasPrefix("/") else { return nil }
                return URL(fileURLWithPath: path, isDirectory: true)
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
    private var outputBuffer = JSONLineBuffer(maximumBufferedBytes: 1_048_576)
    private var errorBuffer = Data()
    private var continuation: CheckedContinuation<Data, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var forceTerminationTask: Task<Void, Never>?
    private var processExitStatus: Int32?
    private var reachedOutputEOF = false
    private var reachedErrorEOF = false
    private var wasCancelledBeforeStart = false

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
            if wasCancelledBeforeStart {
                continuation.resume(throwing: CancellationError())
            } else {
                continuation.resume(throwing: CodexClientError.invalidResponse)
            }
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

        startReading(outputHandle) { [weak self] data in
            await self?.receiveOutput(data)
        }
        startReading(errorHandle) { [weak self] data in
            await self?.receiveError(data)
        }
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            Task { await self?.processDidTerminate(status: status) }
        }

        self.process = process
        standardInput = inputPipe.fileHandleForWriting
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
        guard phase != .finished else { return }
        guard !data.isEmpty else {
            reachedErrorEOF = true
            finishAfterProcessExitIfReady()
            return
        }
        guard errorBuffer.count < Self.maximumErrorBytes else {
            return
        }

        let bytesRemaining = Self.maximumErrorBytes - errorBuffer.count
        errorBuffer.append(data.prefix(bytesRemaining))
    }

    private func handleMessage(_ data: Data) {
        guard !data.isEmpty, let header = try? JSONDecoder().decode(RPCMessageHeader.self, from: data) else {
            return
        }

        // Server-initiated requests use an independent id namespace; only a
        // message without a method key can be the response to ours.
        guard !header.isRequestOrNotification, header.id == expectedRequestID else {
            return
        }

        if let message = header.error?.message {
            finish(with: .failure(CodexClientError.server(DiagnosticText.sanitized(message))))
            return
        }

        switch phase {
        case .initializing:
            do {
                try sendInitializedNotification()
                try sendRateLimitsRequest()
                phase = .readingRateLimits
            } catch {
                finish(with: .failure(CodexClientError.connectionClosed(error.localizedDescription)))
            }

        case .readingRateLimits:
            finish(with: .success(data))

        case .idle, .finished:
            break
        }
    }

    private var expectedRequestID: Int? {
        switch phase {
        case .initializing: RequestID.initialize
        case .readingRateLimits: RequestID.rateLimits
        case .idle, .finished: nil
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
        guard reachedOutputEOF, reachedErrorEOF, let processExitStatus else { return }

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
        if continuation == nil {
            wasCancelledBeforeStart = true
        }
        finish(with: .failure(CancellationError()))
    }

    private func finish(with result: Result<Data, Error>) {
        guard phase != .finished else { return }
        phase = .finished

        timeoutTask?.cancel()
        timeoutTask = nil
        try? standardInput?.close()

        if process?.isRunning == true {
            process?.terminate()
            scheduleForcedTermination()
        } else {
            releaseProcess()
        }
        standardInput = nil

        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(with: result)
    }

    private nonisolated func startReading(
        _ handle: FileHandle,
        deliver: @escaping @Sendable (Data) async -> Void
    ) {
        // The task owns the handle for the life of the loop, so the descriptor
        // cannot be closed and recycled underneath a blocked read.
        Task.detached(priority: .utility) {
            let descriptor = handle.fileDescriptor
            while true {
                var buffer = [UInt8](repeating: 0, count: 64 * 1024)
                let bytesRead = buffer.withUnsafeMutableBytes { bytes in
                    Darwin.read(descriptor, bytes.baseAddress, bytes.count)
                }
                if bytesRead < 0, errno == EINTR {
                    continue
                }
                let data = bytesRead > 0 ? Data(buffer.prefix(bytesRead)) : Data()
                await deliver(data)
                if data.isEmpty {
                    try? handle.close()
                    return
                }
            }
        }
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
                ]
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
    let isRequestOrNotification: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case error
        case method
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isRequestOrNotification = container.contains(.method)
        if let integerID = try? container.decode(Int.self, forKey: .id) {
            id = integerID
        } else if let stringID = try? container.decode(String.self, forKey: .id) {
            id = Int(stringID)
        } else {
            id = nil
        }

        let containsError: Bool
        if container.contains(.error) {
            containsError = try !container.decodeNil(forKey: .error)
        } else {
            containsError = false
        }
        if containsError {
            error =
                (try? container.decode(RPCErrorPayload.self, forKey: .error))
                ?? RPCErrorPayload(message: "Codex returned an error")
        } else {
            error = nil
        }
    }
}
