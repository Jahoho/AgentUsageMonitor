import Foundation
import Testing
@testable import AgentUsageMonitor

@Test func openRouterCredentialStoreAddsDefaultsAndDeletesCredentials() throws {
    let keychain = OpenRouterInMemorySecretStore()
    let fileURL = temporaryOpenRouterCredentialFileURL()
    let store = OpenRouterCredentialStore(
        keychain: keychain,
        fileURL: fileURL
    )

    let first = try store.addCredential(label: "", apiKey: "  sk-or-v1-first\n")
    let second = try store.addCredential(label: "Work", apiKey: "sk-or-v1-second")

    #expect(first.label == "OpenRouter API 1")
    #expect(first.isDefault)
    #expect(second.isDefault == false)
    #expect(try store.readSecret(for: first.id) == "sk-or-v1-first")
    #expect(try store.resolvedCredentials().count == 2)

    try store.setDefaultCredential(id: second.id)
    #expect(try store.credentials().first { $0.id == second.id }?.isDefault == true)

    try store.deleteCredential(id: second.id)
    #expect(try store.credentials().map(\.id) == [first.id])
    #expect(try store.readSecret(for: second.id) == nil)
    #expect(try testPOSIXPermissions(at: fileURL) == LocalDataProtection.filePermissions)
    #expect(
        try testPOSIXPermissions(at: fileURL.deletingLastPathComponent())
            == LocalDataProtection.directoryPermissions
    )
}

@Test func openRouterCredentialStoreMigratesLegacyKeyAfterMetadataIsSaved() throws {
    let keychain = OpenRouterInMemorySecretStore()
    try keychain.save("legacy-key", account: KeychainAccount.openRouterAPIKey)
    let store = OpenRouterCredentialStore(
        keychain: keychain,
        fileURL: temporaryOpenRouterCredentialFileURL()
    )

    let credentials = try store.credentials()

    #expect(credentials.count == 1)
    #expect(credentials[0].label == "OpenRouter API 1")
    #expect(credentials[0].isDefault)
    #expect(try store.readSecret(for: credentials[0].id) == "legacy-key")
    #expect(try keychain.read(account: KeychainAccount.openRouterAPIKey) == nil)
}

@Test func openRouterCredentialStoreRejectsEmptyAPIKey() {
    let store = OpenRouterCredentialStore(
        keychain: OpenRouterInMemorySecretStore(),
        fileURL: temporaryOpenRouterCredentialFileURL()
    )

    #expect(throws: OpenRouterCredentialStoreError.self) {
        try store.addCredential(label: "Test", apiKey: "  \n")
    }
}

@Test func openRouterCredentialStoreRemovesNewSecretWhenMetadataWriteFails() throws {
    let keychain = OpenRouterInMemorySecretStore()
    let store = OpenRouterCredentialStore(
        keychain: keychain,
        fileURL: try blockedOpenRouterCredentialFileURL()
    )

    do {
        _ = try store.addCredential(label: "Work", apiKey: "sk-or-v1-secret")
        Issue.record("Expected OpenRouter metadata write to fail.")
    } catch {
        #expect(error is CredentialStoreTransactionError == false)
    }

    #expect(keychain.storedAccountCount == 0)
}

@Test func openRouterCredentialStoreRestoresMetadataWhenKeychainDeleteFails() throws {
    let keychain = OpenRouterInMemorySecretStore()
    let store = OpenRouterCredentialStore(
        keychain: keychain,
        fileURL: temporaryOpenRouterCredentialFileURL()
    )
    let credential = try store.addCredential(label: "Work", apiKey: "sk-or-v1-secret")
    keychain.setDeleteFailure(true)

    do {
        try store.deleteCredential(id: credential.id)
        Issue.record("Expected OpenRouter Keychain deletion to fail.")
    } catch {
        #expect(error is OpenRouterTestSecretStoreError)
    }

    #expect(try store.credentials().map(\.id) == [credential.id])
    #expect(try store.readSecret(for: credential.id) == "sk-or-v1-secret")
}

private final class OpenRouterInMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    private var shouldFailDelete = false

    var storedAccountCount: Int {
        lock.withLock { values.count }
    }

    func setDeleteFailure(_ shouldFail: Bool) {
        lock.withLock {
            shouldFailDelete = shouldFail
        }
    }

    func save(_ value: String, account: String) throws {
        lock.withLock {
            values[account] = value
        }
    }

    func read(account: String) throws -> String? {
        lock.withLock {
            values[account]
        }
    }

    func delete(account: String) throws {
        try lock.withLock {
            if shouldFailDelete {
                throw OpenRouterTestSecretStoreError.deleteFailed
            }
            _ = values.removeValue(forKey: account)
        }
    }
}

private enum OpenRouterTestSecretStoreError: Error {
    case deleteFailed
}

private func temporaryOpenRouterCredentialFileURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("AgentUsageMonitorTests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("openrouter-credentials.json")
}

private func blockedOpenRouterCredentialFileURL() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("AgentUsageMonitorTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let blockingFile = root.appendingPathComponent("not-a-directory")
    try Data("blocked".utf8).write(to: blockingFile)
    return blockingFile.appendingPathComponent("openrouter-credentials.json")
}
