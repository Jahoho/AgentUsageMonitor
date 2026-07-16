import Foundation
import OSLog

struct CredentialStoreTransactionError: LocalizedError {
    let operation: String
    let primaryErrorDescription: String
    let rollbackErrorDescription: String

    var errorDescription: String? {
        "\(operation) failed and its rollback also failed. Original error: \(primaryErrorDescription). Rollback error: \(rollbackErrorDescription)."
    }
}

enum CredentialTransactionSupport {
    private static let logger = Logger(
        subsystem: "AgentUsageMonitor",
        category: "CredentialStore"
    )

    static func rollbackAndThrow(
        operation: String,
        primaryError: Error,
        rollback: () throws -> Void
    ) throws -> Never {
        do {
            try rollback()
        } catch {
            logger.error(
                "Credential rollback failed for \(operation, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            throw CredentialStoreTransactionError(
                operation: operation,
                primaryErrorDescription: primaryError.localizedDescription,
                rollbackErrorDescription: error.localizedDescription
            )
        }

        throw primaryError
    }

    static func reportCleanupFailure(operation: String, error: Error) {
        logger.error(
            "Credential cleanup will be retried for \(operation, privacy: .public): \(error.localizedDescription, privacy: .public)"
        )
    }
}
