import Foundation

enum DiagnosticText {
    static let maximumLength = 240
    static let maximumNameLength = 48

    static func sanitized(_ message: String) -> String {
        let redacted = flattened(message)
            .replacingOccurrences(
                of: FileManager.default.homeDirectoryForCurrentUser.path,
                with: "~"
            )

        guard !redacted.isEmpty else {
            return "Codex returned an error"
        }
        return truncated(redacted, to: maximumLength)
    }

    static func sanitizedName(_ name: String) -> String {
        truncated(flattened(name), to: maximumNameLength)
    }

    private static func flattened(_ text: String) -> String {
        let flattened =
            text
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        let scalars = flattened.unicodeScalars.filter {
            !(0x00...0x1F).contains($0.value) && !(0x7F...0x9F).contains($0.value)
        }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func truncated(_ text: String, to maximumLength: Int) -> String {
        guard text.count > maximumLength else {
            return text
        }
        return text.prefix(maximumLength - 1) + "…"
    }
}
