import Foundation

func jsonLineBufferTests() -> [TestCase] {
    return [
        TestCase(name: "JSON lines survive arbitrary chunk boundaries") {
            var buffer = JSONLineBuffer(maximumBufferedBytes: 128)
            let first = try buffer.append(Data(#"{"id""#.utf8))
            let second = try buffer.append(Data(#":1}"#.utf8))
            let lines = try buffer.append(Data("\n".utf8))
            try expectEqual(first, [])
            try expectEqual(second, [])
            try expectEqual(lines, [Data(#"{"id":1}"#.utf8)])
        },
        TestCase(name: "multiple JSON lines are emitted in order") {
            var buffer = JSONLineBuffer(maximumBufferedBytes: 128)
            let lines = try buffer.append(Data("{\"id\":1}\n{\"id\":2}\n".utf8))
            try expectEqual(lines, [Data(#"{"id":1}"#.utf8), Data(#"{"id":2}"#.utf8)])
        },
        TestCase(name: "partial trailing line is retained") {
            var buffer = JSONLineBuffer(maximumBufferedBytes: 128)
            let first = try buffer.append(Data("{\"id\":1}\n{\"id\"".utf8))
            let second = try buffer.append(Data(":2}\n".utf8))
            try expectEqual(first, [Data(#"{"id":1}"#.utf8)])
            try expectEqual(second, [Data(#"{"id":2}"#.utf8)])
        },
        TestCase(name: "a newline-dense chunk drains in order and carries its remainder") {
            var buffer = JSONLineBuffer(maximumBufferedBytes: 1_048_576)
            var chunk = Data()
            for index in 0..<4_096 {
                chunk.append(Data("{\"id\":\(index)}\n".utf8))
            }
            chunk.append(Data("{\"id\":".utf8))

            let lines = try buffer.append(chunk)
            try expectEqual(lines.count, 4_096)
            try expectEqual(lines.first, Data(#"{"id":0}"#.utf8))
            try expectEqual(lines.last, Data(#"{"id":4095}"#.utf8))

            let remainder = try buffer.append(Data("4096}\n".utf8))
            try expectEqual(remainder, [Data(#"{"id":4096}"#.utf8)])
        },
        TestCase(name: "CRLF terminators split across chunks keep lines decodable") {
            var buffer = JSONLineBuffer(maximumBufferedBytes: 128)
            let first = try buffer.append(Data("{\"id\":1}\r".utf8))
            let second = try buffer.append(Data("\n{\"id\":2}\r\n".utf8))
            try expectEqual(first, [])
            try expectEqual(second, [Data("{\"id\":1}\r".utf8), Data("{\"id\":2}\r".utf8)])
            for line in second {
                _ = try JSONDecoder().decode([String: Int].self, from: line)
            }
        },
        TestCase(name: "blank lines are dropped") {
            var buffer = JSONLineBuffer(maximumBufferedBytes: 128)
            let lines = try buffer.append(Data("\n\n{\"id\":1}\n\n".utf8))
            try expectEqual(lines, [Data(#"{"id":1}"#.utf8)])
        },
        TestCase(name: "buffer capacity is enforced") {
            var buffer = JSONLineBuffer(maximumBufferedBytes: 8)
            let lines = try buffer.append(Data("12345678".utf8))
            try expectEqual(lines, [])
            try expectThrows(JSONLineBuffer.BufferError.capacityExceeded) {
                _ = try buffer.append(Data("9".utf8))
            }
        },
    ]
}
