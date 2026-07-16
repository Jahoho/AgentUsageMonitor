import AgentUsageCore
import SwiftUI

struct ResetBankView: View {
    let bank: CodexResetBank

    private var availableCount: Int {
        bank.availableCount()
    }

    var body: some View {
        Text("Reset bank: \(summaryText)")
            .font(.system(size: 10, weight: .regular, design: .rounded))
            .foregroundStyle(DesignSurface.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .help(helpText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryText: String {
        guard availableCount > 0 else {
            return "none available"
        }

        guard let nextExpiry = bank.nextExpiry() else {
            return "\(availableCount) available · expiry not exposed"
        }

        return "\(availableCount) available · expires \(expiryDateText(nextExpiry.expiresAt)) · \(relativeExpiryText(nextExpiry.expiresAt))"
    }

    private var helpText: String {
        if bank.entries.isEmpty {
            return "Official reset count only. Expiry dates were not exposed by the official source."
        }

        return bank.availableEntries()
            .map { "\($0.label): \($0.expiresAt.formatted(date: .abbreviated, time: .omitted))" }
            .joined(separator: "\n")
    }

    private func relativeExpiryText(_ date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSinceNow))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600

        if days > 0 {
            return "in \(days)d \(hours)h"
        }

        if hours > 0 {
            return "in \(hours)h"
        }

        return "today"
    }

    private func expiryDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate(isInCurrentYear(date) ? "MMM d" : "MMM d yyyy")
        return formatter.string(from: date)
    }

    private func isInCurrentYear(_ date: Date) -> Bool {
        let calendar = Calendar.current
        return calendar.component(.year, from: date) == calendar.component(.year, from: Date())
    }
}
