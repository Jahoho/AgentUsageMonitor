import Foundation

public enum UsageConfidence: String, Codable, CaseIterable, Sendable {
    case official = "Official"
    case observed = "Observed"
    case estimated = "Estimated"
    case unavailable = "Unavailable"
}

public enum ProviderKind: String, Codable, Sendable {
    case subscription
    case api
    case local
}

public enum ProviderHealth: String, Codable, Sendable {
    case ready = "Ready"
    case needsSetup = "Needs setup"
    case unavailable = "Unavailable"
    case error = "Error"
}

public struct UsageMetric: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let value: String
    public let subvalue: String?
    public let detail: String
    public let confidence: UsageConfidence

    public init(
        id: String,
        label: String,
        value: String,
        subvalue: String? = nil,
        detail: String = "",
        confidence: UsageConfidence
    ) {
        self.id = id
        self.label = label
        self.value = value
        self.subvalue = subvalue
        self.detail = detail
        self.confidence = confidence
    }
}

public struct UsageBar: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let remainingFraction: Double?
    public let usedText: String
    public let resetText: String
    public let resetAt: Date?
    public let confidence: UsageConfidence

    public init(
        id: String,
        label: String,
        remainingFraction: Double?,
        usedText: String,
        resetText: String,
        resetAt: Date? = nil,
        confidence: UsageConfidence
    ) {
        self.id = id
        self.label = label
        self.remainingFraction = remainingFraction
        self.usedText = usedText
        self.resetText = resetText
        self.resetAt = resetAt
        self.confidence = confidence
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case remainingFraction
        case usedFraction
        case usedText
        case resetText
        case resetAt
        case confidence
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        remainingFraction = try container.decodeIfPresent(Double.self, forKey: .remainingFraction)
            ?? container.decodeIfPresent(Double.self, forKey: .usedFraction)
        usedText = try container.decode(String.self, forKey: .usedText)
        resetText = try container.decode(String.self, forKey: .resetText)
        resetAt = try container.decodeIfPresent(Date.self, forKey: .resetAt)
        confidence = try container.decode(UsageConfidence.self, forKey: .confidence)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encodeIfPresent(remainingFraction, forKey: .remainingFraction)
        try container.encode(usedText, forKey: .usedText)
        try container.encode(resetText, forKey: .resetText)
        try container.encodeIfPresent(resetAt, forKey: .resetAt)
        try container.encode(confidence, forKey: .confidence)
    }
}

public extension UsageBar {
    func displayResetText(now: Date = Date()) -> String {
        guard let resetAt else {
            return resetText
        }

        return Self.resetDescription(from: resetAt, now: now)
    }

    static func resetDescription(from date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        if seconds <= 0 {
            return "Reset now"
        }

        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60

        if days > 0 {
            return "Resets in \(days)d \(hours)h"
        }

        if hours > 0 {
            return "Resets in \(hours)h \(minutes)m"
        }

        return "Resets in \(minutes)m"
    }

    static func resetDate(fromDisplayText text: String, updatedAt: Date) -> Date? {
        guard
            let regex = try? NSRegularExpression(
                pattern: #"(?i)resets?\s+in\s+(?:(\d+)\s*d)?\s*(?:(\d+)\s*h)?\s*(?:(\d+)\s*m)?"#
            ),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else {
            return nil
        }

        let days = intCapture(at: 1, in: text, match: match) ?? 0
        let hours = intCapture(at: 2, in: text, match: match) ?? 0
        let minutes = intCapture(at: 3, in: text, match: match) ?? 0
        let seconds = (days * 86_400) + (hours * 3_600) + (minutes * 60)

        guard seconds > 0 else {
            return nil
        }

        return updatedAt.addingTimeInterval(TimeInterval(seconds))
    }

    private static func intCapture(at index: Int, in text: String, match: NSTextCheckingResult) -> Int? {
        guard
            match.numberOfRanges > index,
            match.range(at: index).location != NSNotFound,
            let range = Range(match.range(at: index), in: text)
        else {
            return nil
        }

        return Int(text[range])
    }
}

public struct UsageActivityBucket: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let axisLabel: String?
    public let value: Double
    public let valueText: String
    public let confidence: UsageConfidence

    public init(
        id: String,
        label: String,
        axisLabel: String? = nil,
        value: Double,
        valueText: String,
        confidence: UsageConfidence
    ) {
        self.id = id
        self.label = label
        self.axisLabel = axisLabel
        self.value = value
        self.valueText = valueText
        self.confidence = confidence
    }
}

public struct UsageModelSummary: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let model: String
    public let providerNames: [String]
    public let requestCount: Int
    public let inputTokens: Int
    public let outputTokens: Int
    public let reasoningTokens: Int
    public let totalTokens: Int
    public let spendUSD: Double?
    public let latestAt: Date?
    public let confidence: UsageConfidence

    public init(
        id: String,
        model: String,
        providerNames: [String] = [],
        requestCount: Int,
        inputTokens: Int,
        outputTokens: Int,
        reasoningTokens: Int = 0,
        totalTokens: Int,
        spendUSD: Double? = nil,
        latestAt: Date? = nil,
        confidence: UsageConfidence
    ) {
        self.id = id
        self.model = model
        self.providerNames = providerNames
        self.requestCount = requestCount
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.reasoningTokens = reasoningTokens
        self.totalTokens = totalTokens
        self.spendUSD = spendUSD
        self.latestAt = latestAt
        self.confidence = confidence
    }
}

public struct ProviderAccountSnapshot: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let detail: String
    public let isDefault: Bool
    public let health: ProviderHealth
    public let metrics: [UsageMetric]
    public let bars: [UsageBar]
    public let activity: [UsageActivityBucket]?
    public let activityTitle: String?
    public let models: [UsageModelSummary]
    public let notes: [String]

    public init(
        id: String,
        name: String,
        detail: String = "",
        isDefault: Bool = false,
        health: ProviderHealth,
        metrics: [UsageMetric],
        bars: [UsageBar] = [],
        activity: [UsageActivityBucket]? = nil,
        activityTitle: String? = nil,
        models: [UsageModelSummary] = [],
        notes: [String] = []
    ) {
        self.id = id
        self.name = name
        self.detail = detail
        self.isDefault = isDefault
        self.health = health
        self.metrics = metrics
        self.bars = bars
        self.activity = activity
        self.activityTitle = activityTitle
        self.models = models
        self.notes = notes
    }
}

public struct ProviderAction: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let url: URL?

    public init(id: String, title: String, url: URL?) {
        self.id = id
        self.title = title
        self.url = url
    }
}

public enum ProviderSourceStatus: String, Codable, Sendable {
    case success = "Success"
    case partial = "Partial"
    case failure = "Failed"
    case cancelled = "Cancelled"
    case notAttempted = "Not attempted"
}

public struct ProviderSourceDiagnostic: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let confidence: UsageConfidence
    public let status: ProviderSourceStatus
    public let attemptedAt: Date?
    public let lastSuccessAt: Date?
    public let lastFailureAt: Date?
    public let message: String
    public let isFallback: Bool

    public init(
        id: String,
        name: String,
        confidence: UsageConfidence,
        status: ProviderSourceStatus,
        attemptedAt: Date? = nil,
        lastSuccessAt: Date? = nil,
        lastFailureAt: Date? = nil,
        message: String = "",
        isFallback: Bool = false
    ) {
        self.id = id
        self.name = name
        self.confidence = confidence
        self.status = status
        self.attemptedAt = attemptedAt
        self.lastSuccessAt = lastSuccessAt
        self.lastFailureAt = lastFailureAt
        self.message = message
        self.isFallback = isFallback
    }

    public func preservingHistory(from previous: ProviderSourceDiagnostic?) -> ProviderSourceDiagnostic {
        ProviderSourceDiagnostic(
            id: id,
            name: name,
            confidence: confidence,
            status: status,
            attemptedAt: attemptedAt,
            lastSuccessAt: lastSuccessAt ?? previous?.lastSuccessAt,
            lastFailureAt: lastFailureAt ?? previous?.lastFailureAt,
            message: message,
            isFallback: isFallback
        )
    }

    public func markingFallback() -> ProviderSourceDiagnostic {
        ProviderSourceDiagnostic(
            id: id,
            name: name,
            confidence: confidence,
            status: status,
            attemptedAt: attemptedAt,
            lastSuccessAt: lastSuccessAt,
            lastFailureAt: lastFailureAt,
            message: message,
            isFallback: true
        )
    }
}

public struct ProviderSnapshot: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let kind: ProviderKind
    public let updatedAt: Date
    public let health: ProviderHealth
    public let headline: String
    public let metrics: [UsageMetric]
    public let bars: [UsageBar]
    public let quotaCreditBank: CodexResetBank?
    public let activity: [UsageActivityBucket]?
    public let accounts: [ProviderAccountSnapshot]?
    public let sourceDiagnostics: [ProviderSourceDiagnostic]?
    public let notes: [String]
    public let actions: [ProviderAction]

    public init(
        id: String,
        name: String,
        kind: ProviderKind,
        updatedAt: Date = Date(),
        health: ProviderHealth,
        headline: String,
        metrics: [UsageMetric],
        bars: [UsageBar],
        quotaCreditBank: CodexResetBank? = nil,
        activity: [UsageActivityBucket]? = nil,
        accounts: [ProviderAccountSnapshot]? = nil,
        sourceDiagnostics: [ProviderSourceDiagnostic]? = nil,
        notes: [String],
        actions: [ProviderAction]
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.updatedAt = updatedAt
        self.health = health
        self.headline = headline
        self.metrics = metrics
        self.bars = bars
        self.quotaCreditBank = quotaCreditBank
        self.activity = activity
        self.accounts = accounts
        self.sourceDiagnostics = sourceDiagnostics
        self.notes = notes
        self.actions = actions
    }
}

public extension ProviderSnapshot {
    func replacingSourceDiagnostics(
        _ sourceDiagnostics: [ProviderSourceDiagnostic]?
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            id: id,
            name: name,
            kind: kind,
            updatedAt: updatedAt,
            health: health,
            headline: headline,
            metrics: metrics,
            bars: bars,
            quotaCreditBank: quotaCreditBank,
            activity: activity,
            accounts: accounts,
            sourceDiagnostics: sourceDiagnostics,
            notes: notes,
            actions: actions
        )
    }

    static func unavailable(
        id: String,
        name: String,
        kind: ProviderKind,
        headline: String,
        notes: [String],
        actions: [ProviderAction] = []
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            id: id,
            name: name,
            kind: kind,
            health: .unavailable,
            headline: headline,
            metrics: [],
            bars: [],
            notes: notes,
            actions: actions
        )
    }
}
