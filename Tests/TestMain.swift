import Darwin
import Foundation

@main
enum TestMain {
    static func main() async {
        // Same guard as CodexUsageMicro.main(): a fixture that closes stdin must
        // surface EPIPE from the session's write instead of killing the runner.
        signal(SIGPIPE, SIG_IGN)

        var tests = usageModelTests()
        tests.append(contentsOf: menuBarTests())
        tests.append(contentsOf: usageViewControllerTests())
        tests.append(contentsOf: snapshotOutputTests())
        tests.append(contentsOf: codexResponseParserTests())
        tests.append(contentsOf: jsonLineBufferTests())
        tests.append(contentsOf: diagnosticTextTests())
        tests.append(contentsOf: codexExecutableLocatorTests())
        tests.append(contentsOf: codexRPCSessionTests())
        tests.append(contentsOf: refreshFailurePolicyTests())
        tests.append(contentsOf: refreshThrottleTests())
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
