import Foundation

public enum CodexResetStatus: String, Codable, Sendable {
    case available
    case used
    case expired
    case unknown
}

public enum CodexResetRecommendation: String, Codable, Sendable {
    case none
    case hold
    case useSoon
    case expiring
}

public struct CodexResetEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let grantedAt: Date?
    public let expiresAt: Date
    public let status: CodexResetStatus
    public let source: String
    public let confidence: UsageConfidence

    public init(
        id: String,
        label: String,
        grantedAt: Date?,
        expiresAt: Date,
        status: CodexResetStatus,
        source: String,
        confidence: UsageConfidence
    ) {
        self.id = id
        self.label = label
        self.grantedAt = grantedAt
        self.expiresAt = expiresAt
        self.status = status
        self.source = source
        self.confidence = confidence
    }
}

public struct CodexResetBank: Codable, Equatable, Sendable {
    public let entries: [CodexResetEntry]
    public let reportedAvailableCount: Int?
    public let source: String
    public let updatedAt: Date

    public init(
        entries: [CodexResetEntry],
        reportedAvailableCount: Int? = nil,
        source: String,
        updatedAt: Date = Date()
    ) {
        self.entries = entries
        self.reportedAvailableCount = reportedAvailableCount
        self.source = source
        self.updatedAt = updatedAt
    }

    public func availableEntries(now: Date = Date()) -> [CodexResetEntry] {
        entries
            .filter { $0.status == .available && $0.expiresAt > now }
            .sorted { $0.expiresAt < $1.expiresAt }
    }

    public func availableCount(now: Date = Date()) -> Int {
        if let reportedAvailableCount {
            return max(0, reportedAvailableCount)
        }

        return availableEntries(now: now).count
    }

    public func nextExpiry(now: Date = Date()) -> CodexResetEntry? {
        availableEntries(now: now).first
    }

    public func recommendation(now: Date = Date()) -> CodexResetRecommendation {
        guard let nextExpiry = nextExpiry(now: now) else {
            return availableCount(now: now) > 0 ? .hold : .none
        }

        let secondsUntilExpiry = nextExpiry.expiresAt.timeIntervalSince(now)
        if secondsUntilExpiry <= 2 * 86_400 {
            return .expiring
        }

        if secondsUntilExpiry <= 7 * 86_400 {
            return .useSoon
        }

        return .hold
    }
}

public enum CodexResetParser {
    public static func resetBank(
        in object: [String: Any],
        source: String,
        updatedAt: Date = Date()
    ) -> CodexResetBank? {
        let entries = resetCandidateObjects(in: object)
            .compactMap { entry(from: $0, source: source) }
            .reduce(into: [String: CodexResetEntry]()) { entriesByID, entry in
                entriesByID[entry.id] = entry
            }
            .values
            .sorted { $0.expiresAt < $1.expiresAt }
        let reportedAvailableCount = availableCount(in: object)

        guard entries.isEmpty == false || reportedAvailableCount != nil else {
            return nil
        }

        return CodexResetBank(
            entries: Array(entries),
            reportedAvailableCount: reportedAvailableCount,
            source: source,
            updatedAt: updatedAt
        )
    }

    private static func availableCount(in object: [String: Any]) -> Int? {
        if isResetCreditsContainer(object),
           let count = intValue(object["availableCount"] ?? object["available_count"]) {
            return count
        }

        if let credits = object["rateLimitResetCredits"] as? [String: Any] {
            return intValue(credits["availableCount"] ?? credits["available_count"])
        }

        if let credits = object["rate_limit_reset_credits"] as? [String: Any] {
            return intValue(credits["available_count"] ?? credits["availableCount"])
        }

        for value in object.values {
            if let dictionary = value as? [String: Any],
               let count = availableCount(in: dictionary) {
                return count
            }
        }

        return nil
    }

    private static func resetCandidateObjects(in object: [String: Any]) -> [[String: Any]] {
        let candidateKeys = Set([
            "reset_bank",
            "resetBank",
            "resets",
            "banked_resets",
            "bankedResets",
            "promotional_resets",
            "promotionalResets",
            "rate_limit_resets",
            "rateLimitResets"
        ])

        var candidates: [[String: Any]] = []

        func walk(_ value: Any, key: String?, depth: Int) {
            guard depth <= 8 else { return }

            if let array = value as? [[String: Any]], key.map(candidateKeys.contains) == true {
                candidates.append(contentsOf: array)
                return
            }

            if let dictionary = value as? [String: Any] {
                if isResetCreditsContainer(dictionary),
                   let credits = dictionary["credits"] as? [[String: Any]] {
                    candidates.append(contentsOf: credits)
                }

                if key.map(candidateKeys.contains) == true {
                    if let nested = dictionary["resets"] as? [[String: Any]] {
                        candidates.append(contentsOf: nested)
                    } else if looksLikeResetEntry(dictionary) {
                        candidates.append(dictionary)
                    }
                }

                for (nestedKey, nestedValue) in dictionary {
                    walk(nestedValue, key: nestedKey, depth: depth + 1)
                }
            }
        }

        walk(object, key: nil, depth: 0)
        return candidates
    }

    private static func isResetCreditsContainer(_ object: [String: Any]) -> Bool {
        object["availableCount"] != nil || object["available_count"] != nil
    }

    private static func looksLikeResetEntry(_ object: [String: Any]) -> Bool {
        dateValue(for: ["expires_at", "expiresAt", "expiration", "expires"], in: object) != nil
            && (object["used_percent"] == nil && object["usedPercent"] == nil)
    }

    private static func entry(from object: [String: Any], source: String) -> CodexResetEntry? {
        guard let expiresAt = dateValue(
            for: ["expires_at", "expiresAt", "expiration", "expires", "expires_on", "expiresOn"],
            in: object
        ) else {
            return nil
        }

        let id = stringValue(for: ["id", "reset_id", "resetId"], in: object)
            ?? "reset-\(Int(expiresAt.timeIntervalSince1970))"
        let label = stringValue(
            for: ["title", "label", "name", "type", "resetType", "reset_type", "source"],
            in: object
        )
            ?? "Codex reset"
        let grantedAt = dateValue(for: ["granted_at", "grantedAt", "created_at", "createdAt"], in: object)

        return CodexResetEntry(
            id: id,
            label: label,
            grantedAt: grantedAt,
            expiresAt: expiresAt,
            status: status(from: stringValue(for: ["status", "state"], in: object), expiresAt: expiresAt),
            source: source,
            confidence: .official
        )
    }

    private static func status(from value: String?, expiresAt: Date, now: Date = Date()) -> CodexResetStatus {
        guard expiresAt > now else {
            return .expired
        }

        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "available", "active", "unused", "banked":
            return .available
        case "used", "consumed", "redeemed":
            return .used
        case "expired":
            return .expired
        case .some:
            return .unknown
        case .none:
            return .available
        }
    }

    private static func stringValue(for keys: [String], in object: [String: Any]) -> String? {
        for key in keys {
            guard let value = object[key] as? String else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false {
                return trimmed
            }
        }
        return nil
    }

    private static func dateValue(for keys: [String], in object: [String: Any]) -> Date? {
        for key in keys {
            guard let value = object[key] else { continue }
            if let date = date(from: value) {
                return date
            }
        }
        return nil
    }

    private static func date(from value: Any) -> Date? {
        if let value = value as? Date {
            return value
        }
        if let value = value as? Int {
            return Date(timestamp: TimeInterval(value))
        }
        if let value = value as? Double {
            return Date(timestamp: value)
        }
        if let value = value as? NSNumber {
            return Date(timestamp: value.doubleValue)
        }
        guard let value = value as? String else {
            return nil
        }

        if let seconds = Double(value) {
            return Date(timestamp: seconds)
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Double { return Int(value) }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }
}
