import Foundation

func diagnosticTextTests() -> [TestCase] {
    [
        TestCase(name: "provider diagnostics are flattened and trimmed") {
            try expectEqual(
                DiagnosticText.sanitized("  Sign in\nrequired\tto continue  "),
                "Sign in required to continue"
            )
        },
        TestCase(name: "empty provider diagnostics get a safe fallback") {
            try expectEqual(DiagnosticText.sanitized(" \n\t "), "Codex returned an error")
        },
        TestCase(name: "provider diagnostics are bounded") {
            let diagnostic = DiagnosticText.sanitized(String(repeating: "x", count: 1_000))
            try expectEqual(diagnostic.count, DiagnosticText.maximumLength)
            try expect(diagnostic.hasSuffix("…"), "expected a truncation marker")
        },
        TestCase(name: "C0 and C1 control characters are stripped") {
            try expectEqual(
                DiagnosticText.sanitized("bad\u{07}output\u{9B} here"),
                "badoutput here"
            )
        },
        TestCase(name: "home directory paths are redacted") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            try expectEqual(
                DiagnosticText.sanitized("ENOENT at \(home)/.codex/config.toml"),
                "ENOENT at ~/.codex/config.toml"
            )
        },
    ]
}
