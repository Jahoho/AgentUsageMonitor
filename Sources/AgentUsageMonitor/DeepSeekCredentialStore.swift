import Foundation

protocol DeepSeekCredentialStoring: Sendable {
    func credentials() throws -> [DeepSeekCredential]
    func addCredential(label: String, apiKey: String) throws -> DeepSeekCredential
    func deleteCredential(id: String) throws
    func setDefaultCredential(id: String) throws
    func readSecret(for id: String) throws -> String?
    func resolvedCredentials() throws -> [DeepSeekResolvedCredential]
    func defaultResolvedCredential() throws -> DeepSeekResolvedCredential?
    func proxyCredential(for requestAPIKey: String?) throws -> DeepSeekProxyCredential?
}

struct DeepSeekCredential: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var label: String
    var isDefault: Bool
    let createdAt: Date
}

struct DeepSeekResolvedCredential: Equatable, Sendable {
    let credential: DeepSeekCredential
    let apiKey: String
}

struct DeepSeekProxyCredential: Equatable, Sendable {
    let accountID: String?
    let apiKey: String
}

struct DeepSeekCredentialStore: DeepSeekCredentialStoring, @unchecked Sendable {
    private let keychain: any SecretStore
    private let fileURL: URL

    init(
        keychain: any SecretStore = KeychainStore(service: "AgentUsageMonitor"),
        fileManager: FileManager = .default
    ) {
        self.keychain = keychain
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directoryURL = baseURL.appendingPathComponent("AgentUsageMonitor", isDirectory: true)
        self.fileURL = directoryURL.appendingPathComponent("deepseek-credentials.json")
        try? LocalDataProtection.prepareDirectory(at: directoryURL, fileManager: fileManager)
        try? LocalDataProtection.protectFile(at: self.fileURL, fileManager: fileManager)
    }

    init(keychain: any SecretStore, fileURL: URL) {
        self.keychain = keychain
        self.fileURL = fileURL
        try? LocalDataProtection.prepareDirectory(at: fileURL.deletingLastPathComponent())
        try? LocalDataProtection.protectFile(at: fileURL)
    }

    func credentials() throws -> [DeepSeekCredential] {
        var credentials = try loadCredentials()
        if credentials.isEmpty {
            try migrateLegacyKeyIfNeeded()
            credentials = try loadCredentials()
        } else {
            cleanupLegacyKeyIfDuplicated(in: credentials)
        }
        return credentials
    }

    func addCredential(label: String, apiKey: String) throws -> DeepSeekCredential {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedKey.isEmpty == false else {
            throw DeepSeekCredentialStoreError.emptyAPIKey
        }

        var credentials = try self.credentials()
        let displayLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let credential = DeepSeekCredential(
            id: UUID().uuidString,
            label: displayLabel.isEmpty ? "DeepSeek API \(credentials.count + 1)" : displayLabel,
            isDefault: credentials.isEmpty,
            createdAt: Date()
        )

        try keychain.save(trimmedKey, account: keychainAccount(for: credential.id))
        credentials.append(credential)

        do {
            try saveCredentials(normalized(credentials))
            return credential
        } catch {
            try CredentialTransactionSupport.rollbackAndThrow(
                operation: "Saving DeepSeek credential",
                primaryError: error
            ) {
                try keychain.delete(account: keychainAccount(for: credential.id))
            }
        }
    }

    func deleteCredential(id: String) throws {
        let previousCredentials = try credentials()
        guard previousCredentials.contains(where: { $0.id == id }) else {
            throw DeepSeekCredentialStoreError.credentialNotFound
        }

        let remainingCredentials = normalized(previousCredentials.filter { $0.id != id })
        try saveCredentials(remainingCredentials)

        do {
            try keychain.delete(account: keychainAccount(for: id))
        } catch {
            try CredentialTransactionSupport.rollbackAndThrow(
                operation: "Deleting DeepSeek credential",
                primaryError: error
            ) {
                try saveCredentials(previousCredentials)
            }
        }
    }

    func setDefaultCredential(id: String) throws {
        let existingCredentials = try credentials()
        guard existingCredentials.contains(where: { $0.id == id }) else {
            throw DeepSeekCredentialStoreError.credentialNotFound
        }

        let credentials = existingCredentials.map { credential in
            var nextCredential = credential
            nextCredential.isDefault = credential.id == id
            return nextCredential
        }
        try saveCredentials(normalized(credentials))
    }

    func readSecret(for id: String) throws -> String? {
        try keychain.read(account: keychainAccount(for: id))
    }

    func resolvedCredentials() throws -> [DeepSeekResolvedCredential] {
        try credentials().compactMap { credential in
            guard let apiKey = try readSecret(for: credential.id) else {
                return nil
            }

            return DeepSeekResolvedCredential(credential: credential, apiKey: apiKey)
        }
    }

    func defaultResolvedCredential() throws -> DeepSeekResolvedCredential? {
        let resolvedCredentials = try self.resolvedCredentials()
        return resolvedCredentials.first { $0.credential.isDefault } ?? resolvedCredentials.first
    }

    func proxyCredential(for requestAPIKey: String?) throws -> DeepSeekProxyCredential? {
        if let requestAPIKey {
            let matchedCredential = try resolvedCredentials().first { $0.apiKey == requestAPIKey }
            return DeepSeekProxyCredential(
                accountID: matchedCredential?.credential.id,
                apiKey: requestAPIKey
            )
        }

        guard let defaultCredential = try defaultResolvedCredential() else {
            return nil
        }

        return DeepSeekProxyCredential(
            accountID: defaultCredential.credential.id,
            apiKey: defaultCredential.apiKey
        )
    }

    private func migrateLegacyKeyIfNeeded() throws {
        guard try loadCredentials().isEmpty else {
            return
        }

        guard let legacyKey = try keychain.read(account: KeychainAccount.deepSeekAPIKey) else {
            return
        }

        let credential = DeepSeekCredential(
            id: UUID().uuidString,
            label: "DeepSeek API 1",
            isDefault: true,
            createdAt: Date()
        )

        try keychain.save(legacyKey, account: keychainAccount(for: credential.id))
        do {
            try saveCredentials([credential])
        } catch {
            try CredentialTransactionSupport.rollbackAndThrow(
                operation: "Migrating legacy DeepSeek credential",
                primaryError: error
            ) {
                try keychain.delete(account: keychainAccount(for: credential.id))
            }
        }

        do {
            try keychain.delete(account: KeychainAccount.deepSeekAPIKey)
        } catch {
            CredentialTransactionSupport.reportCleanupFailure(
                operation: "legacy DeepSeek credential",
                error: error
            )
        }
    }

    private func cleanupLegacyKeyIfDuplicated(in credentials: [DeepSeekCredential]) {
        do {
            guard let legacyKey = try keychain.read(account: KeychainAccount.deepSeekAPIKey) else {
                return
            }

            for credential in credentials {
                if try keychain.read(account: keychainAccount(for: credential.id)) == legacyKey {
                    try keychain.delete(account: KeychainAccount.deepSeekAPIKey)
                    return
                }
            }
        } catch {
            CredentialTransactionSupport.reportCleanupFailure(
                operation: "legacy DeepSeek credential",
                error: error
            )
        }
    }

    private func loadCredentials() throws -> [DeepSeekCredential] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([DeepSeekCredential].self, from: data)
    }

    private func saveCredentials(_ credentials: [DeepSeekCredential]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(credentials)
        try data.write(to: fileURL, options: [.atomic])
        try LocalDataProtection.protectFile(at: fileURL)
    }

    private func normalized(_ credentials: [DeepSeekCredential]) -> [DeepSeekCredential] {
        var sortedCredentials = credentials.sorted { $0.createdAt < $1.createdAt }

        if sortedCredentials.isEmpty {
            return []
        }

        if sortedCredentials.contains(where: \.isDefault) == false {
            sortedCredentials[0].isDefault = true
        }

        var foundDefault = false
        return sortedCredentials.map { credential in
            var nextCredential = credential
            if nextCredential.isDefault {
                if foundDefault {
                    nextCredential.isDefault = false
                } else {
                    foundDefault = true
                }
            }
            return nextCredential
        }
    }

    private func keychainAccount(for id: String) -> String {
        "deepseek-api-key-\(id)"
    }
}

enum DeepSeekCredentialStoreError: LocalizedError {
    case emptyAPIKey
    case credentialNotFound

    var errorDescription: String? {
        switch self {
        case .emptyAPIKey:
            return "DeepSeek API key is empty."
        case .credentialNotFound:
            return "DeepSeek API key was not found."
        }
    }
}
