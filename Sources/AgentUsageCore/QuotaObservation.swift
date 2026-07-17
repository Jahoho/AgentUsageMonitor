import Foundation

/// A scalar sample of one current official quota window.
///
/// This model intentionally cannot carry a provider snapshot, account identity,
/// source payload, or display text. Historical samples are analysis inputs only;
/// they must never become a fallback for current quota UI.
public struct QuotaObservation: Codable, Equatable, Sendable {
    public let providerID: String
    public let accountScopeID: String
    public let quotaID: String
    public let remainingFraction: Double
    public let capturedAt: Date
    public let resetAt: Date

    public init(
        providerID: String,
        accountScopeID: String,
        quotaID: String,
        remainingFraction: Double,
        capturedAt: Date,
        resetAt: Date
    ) {
        self.providerID = providerID
        self.accountScopeID = accountScopeID
        self.quotaID = quotaID
        self.remainingFraction = remainingFraction
        self.capturedAt = capturedAt
        self.resetAt = resetAt
    }
}
