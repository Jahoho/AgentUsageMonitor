import Foundation

protocol OpenRouterCredentialStoring: Sendable {
    func credentials() throws -> [OpenRouterCredential]
    func addCredential(label: String, apiKey: String) throws -> OpenRouterCredential
    func deleteCredential(id: String) throws
    func setDefaultCredential(id: String) throws
    func readSecret(for id: String) throws -> String?
    func resolvedCredentials() throws -> [OpenRouterResolvedCredential]
    func defaultResolvedCredential() throws -> OpenRouterResolvedCredential?
}

extension OpenRouterCredentialStoring {
    func hasAPIKey() throws -> Bool {
        try credentials().isEmpty == false
    }

    func apiKey() throws -> String? {
        try defaultResolvedCredential()?.apiKey
    }

    func saveAPIKey(_ apiKey: String) throws {
        _ = try addCredential(label: "", apiKey: apiKey)
    }

    func deleteAPIKey() throws {
        for credential in try credentials() {
            try deleteCredential(id: credential.id)
        }
    }
}

struct OpenRouterCredential: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var label: String
    var isDefault: Bool
    let createdAt: Date
}

struct OpenRouterResolvedCredential: Equatable, Sendable {
    let credential: OpenRouterCredential
    let apiKey: String
}

struct OpenRouterCredentialStore: OpenRouterCredentialStoring, @unchecked Sendable {
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
        self.fileURL = directoryURL.appendingPathComponent("openrouter-credentials.json")
        try? LocalDataProtection.prepareDirectory(at: directoryURL, fileManager: fileManager)
        try? LocalDataProtection.protectFile(at: self.fileURL, fileManager: fileManager)
    }

    init(keychain: any SecretStore, fileURL: URL) {
        self.keychain = keychain
        self.fileURL = fileURL
        try? LocalDataProtection.prepareDirectory(at: fileURL.deletingLastPathComponent())
        try? LocalDataProtection.protectFile(at: fileURL)
    }

    func credentials() throws -> [OpenRouterCredential] {
        var credentials = try loadCredentials()
        if credentials.isEmpty {
            try migrateLegacyKeyIfNeeded()
            credentials = try loadCredentials()
        } else {
            cleanupLegacyKeyIfDuplicated(in: credentials)
        }
        return credentials
    }

    func addCredential(label: String, apiKey: String) throws -> OpenRouterCredential {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedKey.isEmpty == false else {
            throw OpenRouterCredentialStoreError.emptyAPIKey
        }

        var credentials = try self.credentials()
        let displayLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let credential = OpenRouterCredential(
            id: UUID().uuidString,
            label: displayLabel.isEmpty ? "OpenRouter API \(credentials.count + 1)" : displayLabel,
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
                operation: "Saving OpenRouter credential",
                primaryError: error
            ) {
                try keychain.delete(account: keychainAccount(for: credential.id))
            }
        }
    }

    func deleteCredential(id: String) throws {
        let previousCredentials = try credentials()
        guard previousCredentials.contains(where: { $0.id == id }) else {
            throw OpenRouterCredentialStoreError.credentialNotFound
        }

        let remainingCredentials = normalized(previousCredentials.filter { $0.id != id })
        try saveCredentials(remainingCredentials)

        do {
            try keychain.delete(account: keychainAccount(for: id))
        } catch {
            try CredentialTransactionSupport.rollbackAndThrow(
                operation: "Deleting OpenRouter credential",
                primaryError: error
            ) {
                try saveCredentials(previousCredentials)
            }
        }
    }

    func setDefaultCredential(id: String) throws {
        let existingCredentials = try credentials()
        guard existingCredentials.contains(where: { $0.id == id }) else {
            throw OpenRouterCredentialStoreError.credentialNotFound
        }

        let updatedCredentials = existingCredentials.map { credential in
            var nextCredential = credential
            nextCredential.isDefault = credential.id == id
            return nextCredential
        }
        try saveCredentials(normalized(updatedCredentials))
    }

    func readSecret(for id: String) throws -> String? {
        try keychain.read(account: keychainAccount(for: id))
    }

    func resolvedCredentials() throws -> [OpenRouterResolvedCredential] {
        try credentials().compactMap { credential in
            guard let apiKey = try readSecret(for: credential.id) else {
                return nil
            }
            return OpenRouterResolvedCredential(credential: credential, apiKey: apiKey)
        }
    }

    func defaultResolvedCredential() throws -> OpenRouterResolvedCredential? {
        let resolvedCredentials = try resolvedCredentials()
        return resolvedCredentials.first { $0.credential.isDefault } ?? resolvedCredentials.first
    }

    private func migrateLegacyKeyIfNeeded() throws {
        guard try loadCredentials().isEmpty else {
            return
        }
        guard let legacyKey = try keychain.read(account: KeychainAccount.openRouterAPIKey) else {
            return
        }

        let credential = OpenRouterCredential(
            id: UUID().uuidString,
            label: "OpenRouter API 1",
            isDefault: true,
            createdAt: Date()
        )
        let account = keychainAccount(for: credential.id)
        try keychain.save(legacyKey, account: account)

        do {
            try saveCredentials([credential])
        } catch {
            try CredentialTransactionSupport.rollbackAndThrow(
                operation: "Migrating legacy OpenRouter credential",
                primaryError: error
            ) {
                try keychain.delete(account: account)
            }
        }

        do {
            try keychain.delete(account: KeychainAccount.openRouterAPIKey)
        } catch {
            CredentialTransactionSupport.reportCleanupFailure(
                operation: "legacy OpenRouter credential",
                error: error
            )
        }
    }

    private func cleanupLegacyKeyIfDuplicated(in credentials: [OpenRouterCredential]) {
        do {
            guard let legacyKey = try keychain.read(account: KeychainAccount.openRouterAPIKey) else {
                return
            }

            for credential in credentials {
                if try keychain.read(account: keychainAccount(for: credential.id)) == legacyKey {
                    try keychain.delete(account: KeychainAccount.openRouterAPIKey)
                    return
                }
            }
        } catch {
            CredentialTransactionSupport.reportCleanupFailure(
                operation: "legacy OpenRouter credential",
                error: error
            )
        }
    }

    private func loadCredentials() throws -> [OpenRouterCredential] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([OpenRouterCredential].self, from: data)
    }

    private func saveCredentials(_ credentials: [OpenRouterCredential]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(credentials)
        try data.write(to: fileURL, options: [.atomic])
        try LocalDataProtection.protectFile(at: fileURL)
    }

    private func normalized(_ credentials: [OpenRouterCredential]) -> [OpenRouterCredential] {
        var sortedCredentials = credentials.sorted { $0.createdAt < $1.createdAt }
        guard sortedCredentials.isEmpty == false else {
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
        "openrouter-api-key-\(id)"
    }
}

enum OpenRouterCredentialStoreError: LocalizedError {
    case emptyAPIKey
    case credentialNotFound

    var errorDescription: String? {
        switch self {
        case .emptyAPIKey:
            return "OpenRouter API key is empty."
        case .credentialNotFound:
            return "OpenRouter API key was not found."
        }
    }
}
