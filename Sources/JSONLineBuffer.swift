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
        var lines: [Data] = []

        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            if !line.isEmpty {
                lines.append(line)
            }
        }

        return lines
    }
}
