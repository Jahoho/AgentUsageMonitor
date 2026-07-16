import Foundation
import Testing
@testable import AgentUsageMonitor

@Test func localDataProtectionTightensExistingDirectoryAndFilePermissions() throws {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("LocalDataProtectionTests-\(UUID().uuidString)", isDirectory: true)
    let fileURL = directoryURL.appendingPathComponent("usage.json")
    defer { try? FileManager.default.removeItem(at: directoryURL) }
    try FileManager.default.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o755]
    )
    try Data("{}".utf8).write(to: fileURL)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o644],
        ofItemAtPath: fileURL.path
    )

    try LocalDataProtection.prepareDirectory(at: directoryURL)

    #expect(try testPOSIXPermissions(at: directoryURL) == LocalDataProtection.directoryPermissions)
    #expect(try testPOSIXPermissions(at: fileURL) == LocalDataProtection.filePermissions)
}

@Test func localDataProtectionDoesNotFollowSymbolicLinks() throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("LocalDataProtectionSymlinkTests-\(UUID().uuidString)", isDirectory: true)
    let protectedDirectoryURL = rootURL.appendingPathComponent("ApplicationData", isDirectory: true)
    let externalFileURL = rootURL.appendingPathComponent("external.json")
    let linkURL = protectedDirectoryURL.appendingPathComponent("linked.json")
    defer { try? FileManager.default.removeItem(at: rootURL) }

    try FileManager.default.createDirectory(
        at: protectedDirectoryURL,
        withIntermediateDirectories: true
    )
    try Data("{}".utf8).write(to: externalFileURL)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o644],
        ofItemAtPath: externalFileURL.path
    )
    try FileManager.default.createSymbolicLink(
        at: linkURL,
        withDestinationURL: externalFileURL
    )

    try LocalDataProtection.prepareDirectory(at: protectedDirectoryURL)

    #expect(try testPOSIXPermissions(at: externalFileURL) == 0o644)
}

func testPOSIXPermissions(at url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
}
