import Foundation

struct CodexOAuthCredentials: Sendable {
    let accessToken: String
    let accountID: String?
    let email: String?
    let plan: String?
}

struct CodexAuthStore {
    private let fileManager: FileManager
    private let environment: [String: String]

    init(fileManager: FileManager = .default, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.fileManager = fileManager
        self.environment = environment
    }

    func loadCredentials() throws -> CodexOAuthCredentials {
        let authURL = try authFileURL()
        let data = try Data(contentsOf: authURL)

        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexAuthStoreError.invalidAuthFile
        }

        guard let accessToken = stringValue(for: ["access_token", "accessToken"], in: object) else {
            throw CodexAuthStoreError.missingAccessToken
        }

        let idToken = stringValue(for: ["id_token", "idToken"], in: object)
        let payload = idToken.flatMap(parseJWT)
        let authDict = payload?["https://api.openai.com/auth"] as? [String: Any]
        let profileDict = payload?["https://api.openai.com/profile"] as? [String: Any]
        let email = normalized(
            payload?["email"] as? String
                ?? profileDict?["email"] as? String
                ?? stringValue(for: ["email"], in: object)
        )
        let plan = normalized(
            authDict?["chatgpt_plan_type"] as? String
                ?? payload?["chatgpt_plan_type"] as? String
                ?? stringValue(for: ["plan", "plan_type", "planType"], in: object)
        )
        let accountID = normalized(
            stringValue(
                for: ["account_id", "accountId", "chatgpt_account_id", "chatgptAccountId"],
                in: object
            )
        )

        return CodexOAuthCredentials(
            accessToken: accessToken,
            accountID: accountID,
            email: email,
            plan: plan
        )
    }

    private func authFileURL() throws -> URL {
        if let codexHome = environment["CODEX_HOME"], codexHome.isEmpty == false {
            let url = URL(fileURLWithPath: codexHome).appendingPathComponent("auth.json")
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }

        let home = environment["HOME"] ?? NSHomeDirectory()
        let url = URL(fileURLWithPath: home)
            .appendingPathComponent(".codex")
            .appendingPathComponent("auth.json")
        guard fileManager.fileExists(atPath: url.path) else {
            throw CodexAuthStoreError.authFileNotFound
        }
        return url
    }

    private func stringValue(for keys: [String], in object: [String: Any]) -> String? {
        for key in keys {
            if let value = object[key] as? String, value.isEmpty == false {
                return value
            }
        }

        for value in object.values {
            if let dictionary = value as? [String: Any],
               let found = stringValue(for: keys, in: dictionary) {
                return found
            }
        }

        return nil
    }

    private func parseJWT(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 {
            payload.append("=")
        }

        guard
            let data = Data(base64Encoded: payload),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        return object
    }

    private func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), value.isEmpty == false else {
            return nil
        }
        return value
    }
}

enum CodexAuthStoreError: LocalizedError {
    case authFileNotFound
    case invalidAuthFile
    case missingAccessToken

    var errorDescription: String? {
        switch self {
        case .authFileNotFound:
            return "Codex auth.json was not found."
        case .invalidAuthFile:
            return "Codex auth.json is not valid JSON."
        case .missingAccessToken:
            return "Codex auth.json does not include an access token."
        }
    }
}
