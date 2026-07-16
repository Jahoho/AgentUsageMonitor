import Foundation
import Testing
@testable import AgentUsageMonitor

@Test func deepSeekCredentialStoreAddsDefaultsAndDeletesCredentials() throws {
    let secretStore = InMemorySecretStore()
    let fileURL = temporaryCredentialFileURL()
    let store = DeepSeekCredentialStore(
        keychain: secretStore,
        fileURL: fileURL
    )

    let first = try store.addCredential(label: "", apiKey: "sk-first")
    let second = try store.addCredential(label: "Work", apiKey: "sk-second")

    #expect(first.isDefault)
    #expect(second.isDefault == false)
    #expect(try store.readSecret(for: first.id) == "sk-first")

    try store.setDefaultCredential(id: second.id)
    let updated = try store.credentials()
    #expect(updated.first { $0.id == second.id }?.isDefault == true)

    try store.deleteCredential(id: second.id)
    #expect(try store.credentials().map(\.id) == [first.id])
    #expect(try store.readSecret(for: second.id) == nil)
    #expect(try testPOSIXPermissions(at: fileURL) == LocalDataProtection.filePermissions)
    #expect(
        try testPOSIXPermissions(at: fileURL.deletingLastPathComponent())
            == LocalDataProtection.directoryPermissions
    )
}

@Test func deepSeekCredentialStoreMigratesLegacyKey() throws {
    let secretStore = InMemorySecretStore()
    try secretStore.save("legacy-key", account: KeychainAccount.deepSeekAPIKey)
    let store = DeepSeekCredentialStore(
        keychain: secretStore,
        fileURL: temporaryCredentialFileURL()
    )

    let credentials = try store.credentials()

    #expect(credentials.count == 1)
    #expect(credentials[0].isDefault)
    #expect(try store.readSecret(for: credentials[0].id) == "legacy-key")
    #expect(try secretStore.read(account: KeychainAccount.deepSeekAPIKey) == nil)
}

@Test func deepSeekCredentialStoreRemovesNewSecretWhenMetadataWriteFails() throws {
    let secretStore = InMemorySecretStore()
    let store = DeepSeekCredentialStore(
        keychain: secretStore,
        fileURL: try blockedCredentialFileURL(named: "deepseek-credentials.json")
    )

    do {
        _ = try store.addCredential(label: "Work", apiKey: "sk-secret")
        Issue.record("Expected DeepSeek metadata write to fail.")
    } catch {
        #expect(error is CredentialStoreTransactionError == false)
    }

    #expect(secretStore.storedAccountCount == 0)
}

@Test func deepSeekCredentialStoreReportsWhenSecretRollbackAlsoFails() throws {
    let secretStore = InMemorySecretStore()
    secretStore.setDeleteFailure(true)
    let store = DeepSeekCredentialStore(
        keychain: secretStore,
        fileURL: try blockedCredentialFileURL(named: "deepseek-credentials.json")
    )

    do {
        _ = try store.addCredential(label: "Work", apiKey: "sk-secret")
        Issue.record("Expected DeepSeek metadata write to fail.")
    } catch {
        #expect(error is CredentialStoreTransactionError)
    }

    #expect(secretStore.storedAccountCount == 1)
}

@Test func deepSeekCredentialStoreRestoresMetadataWhenKeychainDeleteFails() throws {
    let secretStore = InMemorySecretStore()
    let store = DeepSeekCredentialStore(
        keychain: secretStore,
        fileURL: temporaryCredentialFileURL()
    )
    let credential = try store.addCredential(label: "Work", apiKey: "sk-secret")
    secretStore.setDeleteFailure(true)

    do {
        try store.deleteCredential(id: credential.id)
        Issue.record("Expected DeepSeek Keychain deletion to fail.")
    } catch {
        #expect(error is TestSecretStoreError)
    }

    #expect(try store.credentials().map(\.id) == [credential.id])
    #expect(try store.readSecret(for: credential.id) == "sk-secret")
}

@Test func deepSeekCredentialStoreRejectsUnknownDefaultCredential() throws {
    let store = DeepSeekCredentialStore(
        keychain: InMemorySecretStore(),
        fileURL: temporaryCredentialFileURL()
    )
    _ = try store.addCredential(label: "Work", apiKey: "sk-secret")

    #expect(throws: DeepSeekCredentialStoreError.self) {
        try store.setDefaultCredential(id: "missing")
    }
}

private final class InMemorySecretStore: SecretStore, @unchecked Sendable {
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
                throw TestSecretStoreError.deleteFailed
            }
            _ = values.removeValue(forKey: account)
        }
    }
}

private enum TestSecretStoreError: Error {
    case deleteFailed
}

private func temporaryCredentialFileURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("AgentUsageMonitorTests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("deepseek-credentials.json")
}

private func blockedCredentialFileURL(named fileName: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("AgentUsageMonitorTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let blockingFile = root.appendingPathComponent("not-a-directory")
    try Data("blocked".utf8).write(to: blockingFile)
    return blockingFile.appendingPathComponent(fileName)
}
