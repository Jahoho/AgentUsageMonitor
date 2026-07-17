import AgentUsageCore
import Foundation

protocol QuotaObservationStoring: Sendable {
    func record(_ candidates: [QuotaObservation], now: Date) async throws
    func load(now: Date) async throws -> [QuotaObservation]
}

actor QuotaObservationStore: QuotaObservationStoring {
    static let defaultMinimumSampleInterval: TimeInterval = 5 * 60
    static let defaultRetentionInterval: TimeInterval = 90 * 24 * 60 * 60
    static let defaultCompactionInterval: TimeInterval = 24 * 60 * 60
    static let defaultResetCycleTolerance: TimeInterval = 5 * 60
    static let defaultFutureDateTolerance: TimeInterval = 5 * 60

    private let fileURL: URL
    private let fileManager: FileManager
    private let minimumSampleInterval: TimeInterval
    private let retentionInterval: TimeInterval
    private let compactionInterval: TimeInterval
    private let resetCycleTolerance: TimeInterval
    private let futureDateTolerance: TimeInterval

    private var cachedObservations: [QuotaObservation]?
    private var lastCompactionAt: Date?
    private var needsCompaction = false

    init(
        fileManager: FileManager = .default,
        minimumSampleInterval: TimeInterval = QuotaObservationStore.defaultMinimumSampleInterval,
        retentionInterval: TimeInterval = QuotaObservationStore.defaultRetentionInterval,
        compactionInterval: TimeInterval = QuotaObservationStore.defaultCompactionInterval,
        resetCycleTolerance: TimeInterval = QuotaObservationStore.defaultResetCycleTolerance,
        futureDateTolerance: TimeInterval = QuotaObservationStore.defaultFutureDateTolerance
    ) {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directoryURL = baseURL.appendingPathComponent("AgentUsageMonitor", isDirectory: true)
        self.init(
            fileURL: directoryURL.appendingPathComponent("quota-observations-v1.jsonl"),
            fileManager: fileManager,
            minimumSampleInterval: minimumSampleInterval,
            retentionInterval: retentionInterval,
            compactionInterval: compactionInterval,
            resetCycleTolerance: resetCycleTolerance,
            futureDateTolerance: futureDateTolerance
        )
    }

    init(
        fileURL: URL,
        fileManager: FileManager = .default,
        minimumSampleInterval: TimeInterval = QuotaObservationStore.defaultMinimumSampleInterval,
        retentionInterval: TimeInterval = QuotaObservationStore.defaultRetentionInterval,
        compactionInterval: TimeInterval = QuotaObservationStore.defaultCompactionInterval,
        resetCycleTolerance: TimeInterval = QuotaObservationStore.defaultResetCycleTolerance,
        futureDateTolerance: TimeInterval = QuotaObservationStore.defaultFutureDateTolerance
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.minimumSampleInterval = max(0, minimumSampleInterval)
        self.retentionInterval = max(0, retentionInterval)
        self.compactionInterval = max(0, compactionInterval)
        self.resetCycleTolerance = max(0, resetCycleTolerance)
        self.futureDateTolerance = max(0, futureDateTolerance)
    }

    func record(_ candidates: [QuotaObservation], now: Date = Date()) async throws {
        try loadIfNeeded(now: now)
        guard var observations = cachedObservations else {
            return
        }

        let retentionCutoff = now.addingTimeInterval(-retentionInterval)
        let retained = observations.filter { $0.capturedAt >= retentionCutoff }
        if retained.count != observations.count {
            needsCompaction = true
            observations = retained
        }

        var latestBySeries = latestObservationsBySeries(in: observations)
        var accepted: [QuotaObservation] = []

        for candidate in candidates.sorted(by: observationSort) {
            guard isValid(candidate, now: now), candidate.capturedAt >= retentionCutoff else {
                continue
            }

            let series = SeriesKey(candidate)
            if let latest = latestBySeries[series] {
                guard candidate.capturedAt > latest.capturedAt else {
                    continue
                }

                let sameResetCycle = abs(candidate.resetAt.timeIntervalSince(latest.resetAt))
                    <= resetCycleTolerance
                let elapsed = candidate.capturedAt.timeIntervalSince(latest.capturedAt)
                guard sameResetCycle == false || elapsed >= minimumSampleInterval else {
                    continue
                }
            }

            accepted.append(candidate)
            latestBySeries[series] = candidate
        }

        let updatedObservations = (observations + accepted).sorted(by: observationSort)
        let shouldCompact = needsCompaction && isCompactionDue(now: now)

        if shouldCompact {
            try writeAll(updatedObservations)
            lastCompactionAt = now
            needsCompaction = false
        } else if accepted.isEmpty == false {
            try append(accepted)
        }

        cachedObservations = updatedObservations
    }

    func load(now: Date = Date()) async throws -> [QuotaObservation] {
        try loadIfNeeded(now: now)
        guard var observations = cachedObservations else {
            return []
        }

        let retentionCutoff = now.addingTimeInterval(-retentionInterval)
        let retained = observations.filter { $0.capturedAt >= retentionCutoff }
        if retained.count != observations.count {
            observations = retained
            needsCompaction = true
        }

        if needsCompaction && isCompactionDue(now: now) {
            try writeAll(observations)
            lastCompactionAt = now
            needsCompaction = false
        }

        cachedObservations = observations
        return observations
    }

    private func loadIfNeeded(now: Date) throws {
        guard cachedObservations == nil else {
            return
        }

        try LocalDataProtection.prepareDirectory(
            at: fileURL.deletingLastPathComponent(),
            fileManager: fileManager
        )
        try LocalDataProtection.protectFile(at: fileURL, fileManager: fileManager)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            cachedObservations = []
            lastCompactionAt = now
            return
        }

        let text = try String(contentsOf: fileURL, encoding: .utf8)
        let decoder = JSONDecoder()
        let retentionCutoff = now.addingTimeInterval(-retentionInterval)
        var observationsByPoint: [ObservationPointKey: QuotaObservation] = [:]
        var discardedLine = false

        for line in text.split(whereSeparator: \.isNewline) {
            guard
                let observation = try? decoder.decode(
                    QuotaObservation.self,
                    from: Data(String(line).utf8)
                ),
                isValid(observation, now: now),
                observation.capturedAt >= retentionCutoff
            else {
                discardedLine = true
                continue
            }

            let point = ObservationPointKey(observation)
            if observationsByPoint.updateValue(observation, forKey: point) != nil {
                discardedLine = true
            }
        }

        let observations = observationsByPoint.values.sorted(by: observationSort)
        cachedObservations = observations
        lastCompactionAt = now

        if discardedLine {
            try writeAll(observations)
            needsCompaction = false
        }
    }

    private func append(_ observations: [QuotaObservation]) throws {
        guard observations.isEmpty == false else {
            return
        }

        try LocalDataProtection.prepareDirectory(
            at: fileURL.deletingLastPathComponent(),
            fileManager: fileManager
        )
        let data = try encodedLines(observations)

        if fileManager.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.synchronize()
        } else {
            try data.write(to: fileURL, options: [.atomic])
        }

        try LocalDataProtection.protectFile(at: fileURL, fileManager: fileManager)
    }

    private func writeAll(_ observations: [QuotaObservation]) throws {
        try LocalDataProtection.prepareDirectory(
            at: fileURL.deletingLastPathComponent(),
            fileManager: fileManager
        )
        try encodedLines(observations).write(to: fileURL, options: [.atomic])
        try LocalDataProtection.protectFile(at: fileURL, fileManager: fileManager)
    }

    private func encodedLines(_ observations: [QuotaObservation]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var output = Data()

        for observation in observations {
            output.append(try encoder.encode(observation))
            output.append(Data("\n".utf8))
        }

        return output
    }

    private func latestObservationsBySeries(
        in observations: [QuotaObservation]
    ) -> [SeriesKey: QuotaObservation] {
        var latest: [SeriesKey: QuotaObservation] = [:]
        for observation in observations {
            let key = SeriesKey(observation)
            if latest[key].map({ observation.capturedAt > $0.capturedAt }) ?? true {
                latest[key] = observation
            }
        }
        return latest
    }

    private func isValid(_ observation: QuotaObservation, now: Date) -> Bool {
        let identifiers = [
            observation.providerID,
            observation.accountScopeID,
            observation.quotaID
        ]
        guard identifiers.allSatisfy({ value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty == false && trimmed.count <= 256
        }) else {
            return false
        }

        guard observation.remainingFraction.isFinite,
              (0...1).contains(observation.remainingFraction),
              observation.resetAt > observation.capturedAt,
              observation.capturedAt <= now.addingTimeInterval(futureDateTolerance)
        else {
            return false
        }

        return true
    }

    private func isCompactionDue(now: Date) -> Bool {
        guard let lastCompactionAt else {
            return true
        }
        return now.timeIntervalSince(lastCompactionAt) >= compactionInterval
    }

    private func observationSort(_ lhs: QuotaObservation, _ rhs: QuotaObservation) -> Bool {
        if lhs.capturedAt != rhs.capturedAt {
            return lhs.capturedAt < rhs.capturedAt
        }
        if lhs.providerID != rhs.providerID {
            return lhs.providerID < rhs.providerID
        }
        if lhs.accountScopeID != rhs.accountScopeID {
            return lhs.accountScopeID < rhs.accountScopeID
        }
        return lhs.quotaID < rhs.quotaID
    }
}

private struct SeriesKey: Hashable {
    let providerID: String
    let accountScopeID: String
    let quotaID: String

    init(_ observation: QuotaObservation) {
        providerID = observation.providerID
        accountScopeID = observation.accountScopeID
        quotaID = observation.quotaID
    }
}

private struct ObservationPointKey: Hashable {
    let series: SeriesKey
    let capturedAt: Date

    init(_ observation: QuotaObservation) {
        series = SeriesKey(observation)
        capturedAt = observation.capturedAt
    }
}
