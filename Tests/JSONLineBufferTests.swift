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
