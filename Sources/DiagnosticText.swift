import Foundation

enum DiagnosticText {
    static let maximumLength = 240

    static func sanitized(_ message: String) -> String {
        let flattened =
            message
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")

        guard !flattened.isEmpty else {
            return "Codex returned an error"
        }
        guard flattened.count > maximumLength else {
            return flattened
        }

        return flattened.prefix(maximumLength - 1) + "…"
    }
}
