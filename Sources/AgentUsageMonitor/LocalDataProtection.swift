import Foundation

enum LocalDataProtection {
    static let directoryPermissions = 0o700
    static let filePermissions = 0o600

    static func prepareDirectory(
        at url: URL,
        fileManager: FileManager = .default
    ) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        try fileManager.setAttributes(
            [.posixPermissions: directoryPermissions],
            ofItemAtPath: url.path
        )

        for itemName in try fileManager.contentsOfDirectory(atPath: url.path) {
            let itemURL = url.appendingPathComponent(itemName)
            let attributes = try fileManager.attributesOfItem(atPath: itemURL.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                continue
            }
            try protectFile(at: itemURL, fileManager: fileManager)
        }
    }

    static func protectFile(
        at url: URL,
        fileManager: FileManager = .default
    ) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        try fileManager.setAttributes(
            [.posixPermissions: filePermissions],
            ofItemAtPath: url.path
        )
    }
}
