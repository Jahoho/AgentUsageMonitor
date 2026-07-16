import Foundation

public enum CodexUsageTextParser {
    public static func snapshot(from pageText: String, updatedAt: Date = Date()) -> ProviderSnapshot {
        let normalizedText = pageText.replacingOccurrences(of: "\r\n", with: "\n")
        let bars = parseBars(from: normalizedText, updatedAt: updatedAt)
        let resetBank = bars.isEmpty ? nil : parseResetBank(from: normalizedText, updatedAt: updatedAt)

        guard bars.isEmpty == false else {
            return ProviderSnapshot(
                id: "codex",
                name: "Codex",
                kind: .subscription,
                updatedAt: updatedAt,
                health: .needsSetup,
                headline: "Open Codex Web Debug and sign in",
                metrics: [
                    UsageMetric(
                        id: "codex-web-sync",
                        label: "Web debug",
                        value: "Not readable",
                        detail: "No Codex usage bars were found on the official page.",
                        confidence: .unavailable
                    )
                ],
                bars: [],
                quotaCreditBank: resetBank,
                notes: [
                    "Sign in through the in-app Codex Web Debug window.",
                    "Dashboard quota still comes only from OAuth API or CLI RPC."
                ],
                actions: []
            )
        }

        let remainingValues = bars.compactMap(\.remainingFraction)
        let averageRemaining = remainingValues.isEmpty ? 0 : remainingValues.reduce(0, +) / Double(remainingValues.count)

        return ProviderSnapshot(
            id: "codex",
            name: "Codex",
            kind: .subscription,
            updatedAt: updatedAt,
            health: .ready,
            headline: "Synced from Codex web session",
            metrics: [
                UsageMetric(
                    id: "quota-sections",
                    label: "Quota sections",
                    value: "\(bars.count)",
                    detail: "Usage sections found on the Codex page",
                    confidence: .official
                ),
                UsageMetric(
                    id: "average-remaining",
                    label: "Average left",
                    value: "\(Int((averageRemaining * 100).rounded()))%",
                    detail: "Average across detected usage bars",
                    confidence: .official
                )
            ],
            bars: bars,
            quotaCreditBank: resetBank,
            notes: [
                "Numbers are read from the official Codex page loaded inside the app.",
                "If OpenAI changes the page text, the parser may need an update."
            ],
            actions: []
        )
    }

    private static func parseBars(from text: String, updatedAt: Date) -> [UsageBar] {
        let labels = ["Session", "Daily", "Weekly", "Monthly", "Sonnet", "Opus"]

        return labels.compactMap { label in
            guard let labelRange = text.range(of: label, options: [.caseInsensitive]) else {
                return nil
            }

            let segment = segmentText(in: text, from: labelRange.lowerBound)
            guard let usedPercent = firstPercentUsed(in: segment) else {
                return nil
            }
            let remainingPercent = 100 - usedPercent

            let parsedResetText = resetText(in: segment)

            return UsageBar(
                id: "codex-\(label.lowercased())",
                label: label,
                remainingFraction: Double(remainingPercent) / 100,
                usedText: "\(remainingPercent)% left",
                resetText: parsedResetText ?? "Reset unknown",
                resetAt: parsedResetText.flatMap { UsageBar.resetDate(fromDisplayText: $0, updatedAt: updatedAt) },
                confidence: .official
            )
        }
    }

    private static func segmentText(in text: String, from startIndex: String.Index) -> String {
        let tail = text[startIndex...]
        let paragraphEnd = tail.range(of: "\n\n")?.lowerBound ?? tail.endIndex
        let paragraph = String(tail[..<paragraphEnd])

        if paragraph.count >= 1024 {
            return String(paragraph.prefix(1024))
        }

        return paragraph
    }

    private static func firstPercentUsed(in text: String) -> Int? {
        guard
            let regex = try? NSRegularExpression(pattern: #"(\d{1,3})\s*%\s*used"#, options: [.caseInsensitive]),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let range = Range(match.range(at: 1), in: text)
        else {
            return nil
        }

        return Int(text[range]).map { min(max($0, 0), 100) }
    }

    private static func resetText(in text: String) -> String? {
        guard
            let regex = try? NSRegularExpression(pattern: #"(Resets?\s+in\s+[^\n]+)"#, options: [.caseInsensitive]),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let range = Range(match.range(at: 1), in: text)
        else {
            return nil
        }

        return String(text[range])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseResetBank(from text: String, updatedAt: Date) -> CodexResetBank? {
        guard let section = resetBankSection(in: text) else {
            return nil
        }

        let searchText = [section, resetRelatedLines(in: text)]
            .filter { $0.isEmpty == false }
            .joined(separator: "\n")
        let availableCount = firstAvailableResetCount(in: section)
            ?? firstAvailableResetCount(in: searchText)
        let entries = resetExpiryEntries(in: searchText, updatedAt: updatedAt)

        guard availableCount != nil || entries.isEmpty == false else {
            return nil
        }

        return CodexResetBank(
            entries: entries,
            reportedAvailableCount: availableCount,
            source: "Codex web session",
            updatedAt: updatedAt
        )
    }

    private static func resetBankSection(in text: String) -> String? {
        let headings = ["Reset bank", "Reset credits", "Reset credit"]
        guard let range = headings
            .compactMap({ text.range(of: $0, options: [.caseInsensitive]) })
            .min(by: { $0.lowerBound < $1.lowerBound })
        else {
            return nil
        }

        let tail = text[range.lowerBound...]
        let paragraphEnd = tail.range(of: "\n\n")?.lowerBound ?? tail.endIndex
        return String(tail[..<paragraphEnd].prefix(4_000))
    }

    private static func resetRelatedLines(in text: String) -> String {
        let keywordPattern = #"(?i)(reset|credit|expire|expiry|expires|valid until|过期|到期)"#
        guard let regex = try? NSRegularExpression(pattern: keywordPattern) else {
            return ""
        }

        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .lazy
            .map(String.init)
            .filter { line in
                regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
            }
            .prefix(80)
            .joined(separator: "\n")
    }

    private static func firstAvailableResetCount(in text: String) -> Int? {
        guard
            let regex = try? NSRegularExpression(pattern: #"(\d{1,3})\s+(?:available|banked)\b"#, options: [.caseInsensitive]),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let range = Range(match.range(at: 1), in: text)
        else {
            return nil
        }

        return Int(text[range])
    }

    private static func resetExpiryEntries(in text: String, updatedAt: Date) -> [CodexResetEntry] {
        var seenExpiryTimestamps = Set<Int>()

        return expiryDateStrings(in: text).compactMap { rawDate -> Date? in
            dayDate(rawDate)
        }
        .sorted()
        .enumerated()
        .compactMap { index, expiresAt -> CodexResetEntry? in
            let timestamp = Int(expiresAt.timeIntervalSince1970)
            guard seenExpiryTimestamps.insert(timestamp).inserted else {
                return nil
            }

            return CodexResetEntry(
                id: "codex-web-reset-\(index)-\(Int(expiresAt.timeIntervalSince1970))",
                label: "Codex reset",
                grantedAt: nil,
                expiresAt: expiresAt,
                status: expiresAt > updatedAt ? .available : .expired,
                source: "Codex web session",
                confidence: .official
            )
        }
    }

    private static func expiryDateStrings(in text: String) -> [String] {
        let monthName = #"Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:t|tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?"#
        let patterns = [
            #"\b(\d{4}-\d{1,2}-\d{1,2})\b"#,
            #"\b(("# + monthName + #")\.?\s+\d{1,2},?\s+\d{4})\b"#,
            #"\b(\d{1,2}\s+("# + monthName + #")\.?,?\s+\d{4})\b"#,
            #"(\d{4}\s*年\s*\d{1,2}\s*月\s*\d{1,2}\s*日?)"#
        ]

        return patterns.flatMap { pattern -> [String] in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return []
            }

            return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
                guard let range = Range(match.range(at: 1), in: text) else {
                    return nil
                }
                return String(text[range])
            }
        }
    }

    private static func dayDate(_ value: String) -> Date? {
        let timeZone = TimeZone(secondsFromGMT: 0)!
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "Sept", with: "Sep", options: [.caseInsensitive])
            .replacingOccurrences(of: #"\s+"#, with: " ", options: [.regularExpression])
            .replacingOccurrences(of: #"年\s*"#, with: "年", options: [.regularExpression])
            .replacingOccurrences(of: #"月\s*"#, with: "月", options: [.regularExpression])
            .replacingOccurrences(of: #"日\s*"#, with: "日", options: [.regularExpression])

        let formats = [
            "yyyy-MM-dd",
            "yyyy-M-d",
            "MMM d, yyyy",
            "MMMM d, yyyy",
            "MMM d yyyy",
            "MMMM d yyyy",
            "d MMM yyyy",
            "d MMMM yyyy",
            "yyyy年M月d日",
            "yyyy年M月d"
        ]

        for format in formats {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = format

            if let date = formatter.date(from: normalized) {
                return endOfDay(for: date, timeZone: timeZone)
            }
        }

        return nil
    }

    private static func endOfDay(for date: Date, timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let startOfDay = calendar.startOfDay(for: date)
        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDay) ?? date
    }
}
