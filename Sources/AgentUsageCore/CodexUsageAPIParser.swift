import Foundation

public enum CodexUsageAPIParsingError: LocalizedError, Equatable {
    case invalidPayload
    case missingRateLimit

    public var errorDescription: String? {
        switch self {
        case .invalidPayload:
            return "Codex usage API response was not a JSON object."
        case .missingRateLimit:
            return "Codex usage API response did not include rate limit windows."
        }
    }
}

public enum CodexUsageAPIParser {
    public static func parseSnapshot(
        from data: Data,
        source: String = "OAuth API",
        email: String? = nil,
        accountPlan: String? = nil,
        updatedAt: Date = Date()
    ) throws -> CodexRateLimitSnapshot {
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw CodexUsageAPIParsingError.invalidPayload
        }

        guard let object = value as? [String: Any] else {
            throw CodexUsageAPIParsingError.invalidPayload
        }
        guard let rateLimitObject = rateLimitDictionary(in: object, depth: 0) else {
            throw CodexUsageAPIParsingError.missingRateLimit
        }

        let primaryObject = dictionary(
            in: rateLimitObject,
            keys: ["primary_window", "primaryWindow", "primary"]
        )
        let secondaryObject = dictionary(
            in: rateLimitObject,
            keys: ["secondary_window", "secondaryWindow", "secondary"]
        )
        let primary = primaryObject.flatMap(makeWindow)
        let secondary = secondaryObject.flatMap(makeWindow)

        guard primary != nil || secondary != nil else {
            throw CodexUsageAPIParsingError.missingRateLimit
        }

        return CodexRateLimitSnapshot(
            primary: primary,
            secondary: secondary,
            source: source,
            email: email,
            plan: accountPlan,
            accountPlan: accountPlan,
            quotaPlan: normalizedPlan(from: rateLimitObject),
            resetBank: CodexResetParser.resetBank(
                in: object,
                source: source,
                updatedAt: updatedAt
            ),
            updatedAt: updatedAt
        )
    }

    private static func rateLimitDictionary(
        in object: [String: Any],
        depth: Int
    ) -> [String: Any]? {
        guard depth < 12 else { return nil }

        for key in ["rate_limit", "rateLimit"] {
            if let direct = object[key] as? [String: Any] {
                return direct
            }
        }

        for value in object.values {
            if let dictionary = value as? [String: Any] {
                if let found = rateLimitDictionary(in: dictionary, depth: depth + 1) {
                    return found
                }
            } else if let array = value as? [[String: Any]] {
                for dictionary in array {
                    if let found = rateLimitDictionary(in: dictionary, depth: depth + 1) {
                        return found
                    }
                }
            }
        }

        return nil
    }

    private static func dictionary(
        in object: [String: Any],
        keys: [String]
    ) -> [String: Any]? {
        for key in keys {
            if let value = object[key] as? [String: Any] {
                return value
            }
        }
        return nil
    }

    private static func makeWindow(from object: [String: Any]) -> CodexRateLimitWindow? {
        guard let usedPercent = flexibleDouble(
            object["used_percent"] ?? object["usedPercent"] ?? object["used"]
        ) else {
            return nil
        }

        let limitWindowSeconds = flexibleDouble(
            object["limit_window_seconds"] ?? object["limitWindowSeconds"]
        )
        let windowMinutes = flexibleInt(
            object["window_duration_mins"] ?? object["windowDurationMins"]
        ) ?? limitWindowSeconds.map { Int($0 / 60) }
        let resetValue = flexibleDouble(
            object["reset_at"] ?? object["resetAt"] ?? object["resets_at"] ?? object["resetsAt"]
        )

        return CodexRateLimitWindow(
            usedPercent: usedPercent,
            windowMinutes: windowMinutes,
            resetsAt: resetValue.map(Date.init(timestamp:))
        )
    }

    private static func normalizedPlan(from object: [String: Any]) -> String? {
        let value = object["planType"] as? String
            ?? object["plan_type"] as? String
            ?? object["plan"] as? String
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.isEmpty == false
        else {
            return nil
        }
        return value
    }

    private static func flexibleDouble(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String {
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private static func flexibleInt(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Double { return Int(value) }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String {
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }
}
