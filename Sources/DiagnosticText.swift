import Foundation

enum DiagnosticText {
    static let maximumLength = 240

    static func sanitized(_ message: String) -> String {
        let flattened =
            message
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        let scalars = flattened.unicodeScalars.filter {
            !(0x00...0x1F).contains($0.value) && !(0x7F...0x9F).contains($0.value)
        }
        let redacted = String(String.UnicodeScalarView(scalars))
            .replacingOccurrences(
                of: FileManager.default.homeDirectoryForCurrentUser.path,
                with: "~"
            )

        guard !redacted.isEmpty else {
            return "Codex returned an error"
        }
        guard redacted.count > maximumLength else {
            return redacted
        }

        return redacted.prefix(maximumLength - 1) + "…"
    }
}
