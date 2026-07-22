import Foundation

struct JSONLineBuffer: Sendable {
    enum BufferError: Error, Equatable {
        case capacityExceeded
    }

    private let maximumBufferedBytes: Int
    private var buffer = Data()

    init(maximumBufferedBytes: Int) {
        precondition(maximumBufferedBytes > 0)
        self.maximumBufferedBytes = maximumBufferedBytes
    }

    mutating func append(_ data: Data) throws -> [Data] {
        guard
            data.count <= maximumBufferedBytes,
            buffer.count <= maximumBufferedBytes - data.count
        else {
            throw BufferError.capacityExceeded
        }

        buffer.append(data)
        guard let lastNewline = buffer.lastIndex(of: 0x0A) else { return [] }

        let lines: [Data] = buffer.prefix(upTo: lastNewline)
            .split(separator: 0x0A, omittingEmptySubsequences: true)
            .map { Data($0) }
        buffer = Data(buffer.suffix(from: buffer.index(after: lastNewline)))
        return lines
    }
}
