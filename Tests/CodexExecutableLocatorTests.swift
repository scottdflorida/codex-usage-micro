import Foundation

func codexExecutableLocatorTests() -> [TestCase] {
    [
        TestCase(name: "executable locator ignores unsafe and non-file candidates") {
            let fileManager = FileManager.default
            let testDirectory = fileManager.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let binDirectory = testDirectory.appendingPathComponent("bin", isDirectory: true)
            let executable = binDirectory.appendingPathComponent("codex", isDirectory: false)

            try fileManager.createDirectory(
                at: binDirectory,
                withIntermediateDirectories: true
            )
            defer { try? fileManager.removeItem(at: testDirectory) }

            let created = fileManager.createFile(
                atPath: executable.path,
                contents: Data("#!/bin/sh\n".utf8),
                attributes: [.posixPermissions: 0o700]
            )
            try expect(created, "expected to create an executable fixture")

            let locator = CodexExecutableLocator(
                environmentPath: "relative-bin:\(binDirectory.path)",
                knownLocations: [testDirectory.path]
            )
            try expectEqual(locator.locate(), executable.standardizedFileURL)
        },
        TestCase(name: "executable locator returns nil when no safe candidate exists") {
            let locator = CodexExecutableLocator(
                environmentPath: ".:relative-bin",
                knownLocations: []
            )
            try expectEqual(locator.locate(), nil)
        },
    ]
}
