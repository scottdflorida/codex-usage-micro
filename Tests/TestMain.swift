import Darwin
import Foundation

@main
enum TestMain {
    static func main() async {
        let tests =
            usageModelTests()
            + codexResponseParserTests()
            + jsonLineBufferTests()
            + diagnosticTextTests()
            + codexRPCSessionTests()
        var failures = 0

        for test in tests {
            do {
                try await test.body()
                print("PASS  \(test.name)")
            } catch {
                failures += 1
                fputs("FAIL  \(test.name): \(error)\n", stderr)
            }
        }

        print("\n\(tests.count - failures)/\(tests.count) tests passed")
        if failures > 0 {
            exit(EXIT_FAILURE)
        }
    }
}
