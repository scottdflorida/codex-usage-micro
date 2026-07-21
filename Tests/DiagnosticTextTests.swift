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
    ]
}
