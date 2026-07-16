import AgentUsageCore
import Foundation

protocol CodexUsageLogReading: Sendable {
    func loadEvents() -> [UsageEvent]
}

struct CodexUsageLogReader: CodexUsageLogReading, @unchecked Sendable {
    private static let replayBurstThreshold = 20
    private static let staleRateLimitResetToleranceSeconds: Int64 = 600
    private static let legacyPersistentCacheVersion = 1
    private static let persistentCacheVersion = 2
    private static let parsedFileCache = CodexParsedLogFileCache()
    private static let persistentCacheCoordinator = CodexPersistentLogCacheCoordinator()
    static let defaultMaxLogFileCount: Int? = nil
    static let defaultMaxTotalLogBytes: Int? = nil

    private let fileManager: FileManager
    private let environment: [String: String]
    private let maxLogFileCount: Int?
    private let maxTotalLogBytes: Int?
    private let persistentCacheURL: URL?

    init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        maxLogFileCount: Int? = Self.defaultMaxLogFileCount,
        maxTotalLogBytes: Int? = Self.defaultMaxTotalLogBytes,
        persistentCacheURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.environment = environment
        self.maxLogFileCount = maxLogFileCount
        self.maxTotalLogBytes = maxTotalLogBytes
        self.persistentCacheURL = persistentCacheURL
            ?? Self.defaultPersistentCacheURL(environment: environment)

        if let resolvedCacheURL = self.persistentCacheURL {
            try? LocalDataProtection.prepareDirectory(
                at: resolvedCacheURL.deletingLastPathComponent(),
                fileManager: fileManager
            )
            try? LocalDataProtection.protectFile(at: resolvedCacheURL, fileManager: fileManager)
        }
    }

    func loadEvents() -> [UsageEvent] {
        let codexHomeURL = codexHomeURL()

        guard let persistentCacheURL else {
            return loadEvents(codexHomeURL: codexHomeURL)
        }

        let coordinationKey = [
            codexHomeURL.standardizedFileURL.path,
            persistentCacheURL.standardizedFileURL.path
        ].joined(separator: "\u{0}")
        return Self.persistentCacheCoordinator.load(key: coordinationKey) {
            loadEvents(codexHomeURL: codexHomeURL)
        }
    }

    private func loadEvents(codexHomeURL: URL) -> [UsageEvent] {
        var seenSessionIDs = Set<String>()
        let dateParser = CodexLogDateParser()
        let logFileScan = codexLogFiles(codexHomeURL: codexHomeURL)
        let storedCache = loadPersistentCache(codexHomeURL: codexHomeURL)
        var uncertainRoots = logFileScan.uncertainRoots
        var activeEntries: [String: CodexPersistentLogCacheEntry] = [:]

        for file in logFileScan.files {
            let cacheKey = CodexParsedLogFileCacheKey(file: file)
            let storedEntry = storedCache?.files[file.url.path]
            let parsedFile: ParsedCodexLogFile
            if let storedEntry, storedEntry.matches(file) {
                parsedFile = storedCache?.version == Self.legacyPersistentCacheVersion
                    ? storedEntry.parsedFile.removingDenseReplayBursts(
                        minimumCount: Self.replayBurstThreshold
                    )
                    : storedEntry.parsedFile
                Self.parsedFileCache.set(parsedFile, for: cacheKey)
            } else {
                guard let parsed = parsedLogFile(file, dateParser: dateParser) else {
                    uncertainRoots.insert(file.url.standardizedFileURL.path)
                    continue
                }
                parsedFile = parsed
            }

            activeEntries[file.url.path] = CodexPersistentLogCacheEntry(
                modifiedAt: file.modifiedAt.timeIntervalSince1970,
                byteCount: file.byteCount,
                parsedFile: parsedFile
            )
        }

        if uncertainRoots.isEmpty {
            Self.parsedFileCache.prune(
                keeping: Set(logFileScan.files.map { CodexParsedLogFileCacheKey(file: $0) })
            )
        } else {
            guard let storedCache else {
                return []
            }

            for (path, entry) in storedCache.files where shouldPreserveCachedPath(path, under: uncertainRoots) {
                activeEntries[path] = activeEntries[path] ?? entry
            }
        }

        savePersistentCacheIfNeeded(
            previousCache: storedCache,
            codexHomeURL: codexHomeURL,
            entries: activeEntries
        )

        let orderedEntries = activeEntries.sorted { lhs, rhs in
            if lhs.value.modifiedAt == rhs.value.modifiedAt {
                return lhs.key > rhs.key
            }
            return lhs.value.modifiedAt > rhs.value.modifiedAt
        }

        return orderedEntries.flatMap { _, entry -> [UsageEvent] in
            let parsedFile = entry.parsedFile

            if let sessionID = parsedFile.sessionID {
                guard seenSessionIDs.insert(sessionID).inserted else {
                    return []
                }
            }

            return parsedFile.events
        }
    }

    private func shouldPreserveCachedPath(_ path: String, under uncertainRoots: Set<String>) -> Bool {
        let normalizedPath = normalizedFileSystemPath(path)
        return uncertainRoots.contains { rootPath in
            let normalizedRootPath = normalizedFileSystemPath(rootPath)
            return normalizedPath == normalizedRootPath
                || normalizedPath.hasPrefix(normalizedRootPath + "/")
        }
    }

    private func normalizedFileSystemPath(_ path: String) -> String {
        var normalizedPath = URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path

        // macOS may report temporary files through either side of these aliases.
        for (alias, destination) in [
            ("/var", "/private/var"),
            ("/tmp", "/private/tmp"),
            ("/etc", "/private/etc")
        ] where normalizedPath == alias || normalizedPath.hasPrefix(alias + "/") {
            normalizedPath = destination + normalizedPath.dropFirst(alias.count)
            break
        }

        guard normalizedPath.count > 1, normalizedPath.hasSuffix("/") else {
            return normalizedPath
        }
        return String(normalizedPath.dropLast())
    }

    private func parsedLogFile(_ file: CodexLogFile, dateParser: CodexLogDateParser) -> ParsedCodexLogFile? {
        let cacheKey = CodexParsedLogFileCacheKey(file: file)
        if let cachedFile = Self.parsedFileCache.value(for: cacheKey) {
            return cachedFile
        }

        guard let text = try? String(contentsOf: file.url, encoding: .utf8) else {
            return nil
        }

        let lines = text.split(whereSeparator: \.isNewline)
        let parsedFile = ParsedCodexLogFile(
            sessionID: sessionIdentity(in: lines),
            events: loadEvents(from: lines, dateParser: dateParser)
        )
        Self.parsedFileCache.set(parsedFile, for: cacheKey)
        return parsedFile
    }

    private func codexLogFiles(codexHomeURL rootURL: URL) -> CodexLogFileScan {
        let directories = [
            rootURL.appendingPathComponent("sessions", isDirectory: true),
            rootURL.appendingPathComponent("archived_sessions", isDirectory: true)
        ]

        var files: [CodexLogFile] = []
        var uncertainRoots = Set<String>()
        for directoryURL in directories {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) else {
                continue
            }
            guard isDirectory.boolValue else {
                uncertainRoots.insert(directoryURL.standardizedFileURL.path)
                continue
            }

            let errorFlag = CodexLogScanErrorFlag()
            guard let enumerator = fileManager.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles],
                errorHandler: { failedURL, _ in
                    errorFlag.markEncountered(at: failedURL)
                    return true
                }
            ) else {
                uncertainRoots.insert(directoryURL.standardizedFileURL.path)
                continue
            }

            for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
                guard let file = logFile(from: fileURL) else {
                    uncertainRoots.insert(fileURL.standardizedFileURL.path)
                    continue
                }
                files.append(file)
            }

            uncertainRoots.formUnion(errorFlag.encounteredPaths)
        }
        return CodexLogFileScan(files: boundedLogFiles(files), uncertainRoots: uncertainRoots)
    }

    private func logFile(from url: URL) -> CodexLogFile? {
        guard
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]),
            values.isRegularFile == true
        else {
            return nil
        }

        return CodexLogFile(
            url: url,
            modifiedAt: values.contentModificationDate ?? .distantPast,
            byteCount: max(0, values.fileSize ?? 0)
        )
    }

    private func boundedLogFiles(_ files: [CodexLogFile]) -> [CodexLogFile] {
        let sortedFiles = files.sorted { lhs, rhs in
            if lhs.modifiedAt == rhs.modifiedAt {
                return lhs.url.path > rhs.url.path
            }
            return lhs.modifiedAt > rhs.modifiedAt
        }

        var selected: [CodexLogFile] = []
        var selectedByteCount = 0

        for file in sortedFiles {
            if let maxLogFileCount, selected.count >= maxLogFileCount {
                break
            }

            if let maxTotalLogBytes {
                guard file.byteCount <= maxTotalLogBytes else {
                    continue
                }
                guard selectedByteCount <= maxTotalLogBytes - file.byteCount else {
                    break
                }
            }

            selected.append(file)
            selectedByteCount += file.byteCount
        }

        return selected
    }

    private func codexHomeURL() -> URL {
        let codexHome: String
        if let value = environment["CODEX_HOME"], value.isEmpty == false {
            codexHome = value
        } else if let home = environment["HOME"], home.isEmpty == false {
            codexHome = URL(fileURLWithPath: home).appendingPathComponent(".codex").path
        } else {
            codexHome = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex").path
        }

        return URL(fileURLWithPath: codexHome)
    }

    private static func defaultPersistentCacheURL(environment: [String: String]) -> URL? {
        guard let home = environment["HOME"], home.isEmpty == false else {
            return nil
        }

        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Library/Caches/AgentUsageMonitor", isDirectory: true)
            .appendingPathComponent("codex-observed-usage-v1.json")
    }

    private func loadPersistentCache(codexHomeURL: URL) -> CodexPersistentLogCache? {
        guard
            let persistentCacheURL,
            let data = try? Data(contentsOf: persistentCacheURL),
            let cache = try? JSONDecoder().decode(CodexPersistentLogCache.self, from: data),
            cache.version == Self.legacyPersistentCacheVersion
                || cache.version == Self.persistentCacheVersion,
            cache.codexHomePath == codexHomeURL.standardizedFileURL.path
        else {
            return nil
        }

        return cache
    }

    private func savePersistentCacheIfNeeded(
        previousCache: CodexPersistentLogCache?,
        codexHomeURL: URL,
        entries: [String: CodexPersistentLogCacheEntry]
    ) {
        guard let persistentCacheURL else {
            return
        }

        let nextCache = CodexPersistentLogCache(
            version: Self.persistentCacheVersion,
            codexHomePath: codexHomeURL.standardizedFileURL.path,
            files: entries
        )
        guard nextCache != previousCache else {
            return
        }

        do {
            try LocalDataProtection.prepareDirectory(
                at: persistentCacheURL.deletingLastPathComponent(),
                fileManager: fileManager
            )
            let data = try JSONEncoder().encode(nextCache)
            try data.write(to: persistentCacheURL, options: .atomic)
            try LocalDataProtection.protectFile(at: persistentCacheURL, fileManager: fileManager)
        } catch {
            // Observed activity cache failures must never affect official quota refreshes.
        }
    }

    private func sessionIdentity(in lines: [Substring]) -> String? {
        for line in lines.prefix(12) {
            guard
                let object = jsonObject(from: Data(line.utf8)),
                object["type"] as? String == "session_meta",
                let payload = object["payload"] as? [String: Any]
            else {
                continue
            }

            return stringValue(payload["id"])
        }

        return nil
    }

    private func loadEvents(from lines: [Substring], dateParser: CodexLogDateParser) -> [UsageEvent] {
        let isReplayProneSession = isReplayProneSession(in: lines)
        let replaySecondKeys = replaySecondKeys(
            in: lines,
            isReplayProneSession: isReplayProneSession,
            dateParser: dateParser
        )
        var modelContext = CodexModelContext()
        var cumulativeUsageGuard = CodexCumulativeUsageGuard()
        return lines
            .compactMap { line -> UsageEvent? in
                guard shouldParseEventLine(line),
                      let object = jsonObject(from: Data(line.utf8))
                else {
                    return nil
                }

                modelContext.update(from: object)
                if shouldSkipSessionReplay(
                    from: object,
                    isReplayProneSession: isReplayProneSession,
                    replaySecondKeys: replaySecondKeys,
                    dateParser: dateParser
                ) {
                    return nil
                }
                if cumulativeUsageGuard.shouldSkipDuplicate(from: object) {
                    return nil
                }
                return parseEvent(from: object, modelContext: modelContext, dateParser: dateParser)
            }
    }

    private func replaySecondKeys(
        in lines: [Substring],
        isReplayProneSession: Bool,
        dateParser: CodexLogDateParser
    ) -> Set<Int64> {
        guard isReplayProneSession else {
            return []
        }

        let usageCountsBySecond = lines.reduce(into: [Int64: Int]()) { counts, line in
            guard
                hasUsageMarker(line),
                let object = jsonObject(from: Data(line.utf8)),
                hasUsagePayload(object),
                let secondKey = secondKey(from: object, dateParser: dateParser)
            else {
                return
            }

            counts[secondKey, default: 0] += 1
        }

        return Set(usageCountsBySecond.compactMap { secondKey, count in
            count >= Self.replayBurstThreshold ? secondKey : nil
        })
    }

    private func isReplayProneSession(in lines: [Substring]) -> Bool {
        for line in lines.prefix(8) {
            guard
                let object = jsonObject(from: Data(line.utf8)),
                object["type"] as? String == "session_meta",
                let payload = object["payload"] as? [String: Any],
                isReplayProneSessionPayload(payload)
            else {
                continue
            }

            return true
        }

        return false
    }

    private func isReplayProneSessionPayload(_ payload: [String: Any]) -> Bool {
        if payload["forked_from_id"] != nil {
            return true
        }

        if let source = payload["source"] as? [String: Any],
           source["subagent"] != nil {
            return true
        }

        return false
    }

    private func shouldSkipSessionReplay(
        from object: [String: Any],
        isReplayProneSession: Bool,
        replaySecondKeys: Set<Int64>,
        dateParser: CodexLogDateParser
    ) -> Bool {
        guard isReplayProneSession else {
            return false
        }

        guard
            hasUsagePayload(object),
            let secondKey = secondKey(from: object, dateParser: dateParser)
        else {
            return false
        }

        // Forked sessions can copy historical parent usage into the new log.
        // Dense same-second bursts catch bulk replay; stale reset times catch sparse replay rows.
        return replaySecondKeys.contains(secondKey) || hasStalePrimaryRateLimitReset(in: object, eventSecondKey: secondKey)
    }
    private func hasStalePrimaryRateLimitReset(in object: [String: Any], eventSecondKey: Int64) -> Bool {
        guard
            let payload = object["payload"] as? [String: Any],
            let rateLimits = payload["rate_limits"] as? [String: Any],
            let primary = rateLimits["primary"] as? [String: Any],
            let resetSecond = int64Value(primary["resets_at"])
        else {
            return false
        }

        return resetSecond < eventSecondKey - Self.staleRateLimitResetToleranceSeconds
    }

    private func hasUsagePayload(_ object: [String: Any]) -> Bool {
        guard
            let payload = object["payload"] as? [String: Any],
            let info = payload["info"] as? [String: Any]
        else {
            return false
        }

        return info["last_token_usage"] != nil
    }

    private func secondKey(from object: [String: Any], dateParser: CodexLogDateParser) -> Int64? {
        guard
            let timestamp = object["timestamp"] as? String,
            let createdAt = dateParser.parse(timestamp)
        else {
            return nil
        }

        return Int64(floor(createdAt.timeIntervalSince1970))
    }

    private func parseEvent(
        from object: [String: Any],
        modelContext: CodexModelContext,
        dateParser: CodexLogDateParser
    ) -> UsageEvent? {
        guard
            let timestamp = object["timestamp"] as? String,
            let createdAt = dateParser.parse(timestamp),
            let payload = object["payload"] as? [String: Any],
            let info = payload["info"] as? [String: Any],
            let usage = info["last_token_usage"] as? [String: Any]
        else {
            return nil
        }

        let inputTokens = intValue(usage["input_tokens"])
        let cachedInputTokens = intValue(usage["cached_input_tokens"])
        let outputTokens = intValue(usage["output_tokens"])
        let totalTokens = intValue(usage["total_tokens"])

        guard totalTokens > 0 else {
            return nil
        }

        return UsageEvent(
            providerID: "codex",
            model: modelName(from: payload, info: info, fallback: modelContext.displayName),
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            totalTokens: totalTokens,
            cachedInputTokens: cachedInputTokens,
            uncachedInputTokens: max(0, inputTokens - cachedInputTokens),
            createdAt: createdAt,
            confidence: .observed
        )
    }

    private func jsonObject(from data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func shouldParseEventLine(_ line: Substring) -> Bool {
        hasUsageMarker(line)
            || line.range(of: #""model""#) != nil
            || line.range(of: #""effort""#) != nil
            || line.range(of: #""reasoning_effort""#) != nil
    }

    private func hasUsageMarker(_ line: Substring) -> Bool {
        line.range(of: #""last_token_usage""#) != nil
    }

    private func modelName(
        from payload: [String: Any],
        info: [String: Any],
        fallback: String?
    ) -> String {
        let directModel = stringValue(info["model"])
            ?? stringValue(payload["model"])
            ?? fallback
        let directEffort = stringValue(info["effort"])
            ?? stringValue(info["reasoning_effort"])
            ?? stringValue(payload["effort"])
            ?? stringValue(payload["reasoning_effort"])

        return CodexModelContext.displayName(model: directModel, effort: directEffort) ?? "codex"
    }

    private func stringValue(_ value: Any?) -> String? {
        guard let value = value as? String else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private func intValue(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? Double { return Int(value) }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) ?? 0 }
        return 0
    }

    private func int64Value(_ value: Any?) -> Int64? {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? Double { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        if let value = value as? String { return Int64(value) }
        return nil
    }

}

private struct ParsedCodexLogFile: Codable, Equatable, Sendable {
    let sessionID: String?
    let events: [UsageEvent]

    func removingDenseReplayBursts(minimumCount: Int) -> ParsedCodexLogFile {
        let countsBySecond = events.reduce(into: [Int64: Int]()) { counts, event in
            let second = Int64(floor(event.createdAt.timeIntervalSince1970))
            counts[second, default: 0] += 1
        }
        let replaySeconds = Set(countsBySecond.compactMap { second, count in
            count >= minimumCount ? second : nil
        })
        guard replaySeconds.isEmpty == false else {
            return self
        }

        return ParsedCodexLogFile(
            sessionID: sessionID,
            events: events.filter { event in
                let second = Int64(floor(event.createdAt.timeIntervalSince1970))
                return replaySeconds.contains(second) == false
            }
        )
    }
}

private struct CodexPersistentLogCache: Codable, Equatable, Sendable {
    let version: Int
    let codexHomePath: String
    let files: [String: CodexPersistentLogCacheEntry]
}

private struct CodexPersistentLogCacheEntry: Codable, Equatable, Sendable {
    let modifiedAt: TimeInterval
    let byteCount: Int
    let parsedFile: ParsedCodexLogFile

    func matches(_ file: CodexLogFile) -> Bool {
        modifiedAt == file.modifiedAt.timeIntervalSince1970
            && byteCount == file.byteCount
    }
}

private struct CodexParsedLogFileCacheKey: Hashable {
    let path: String
    let modifiedAt: TimeInterval
    let byteCount: Int

    init(file: CodexLogFile) {
        path = file.url.path
        modifiedAt = file.modifiedAt.timeIntervalSince1970
        byteCount = file.byteCount
    }
}

private final class CodexParsedLogFileCache: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [CodexParsedLogFileCacheKey: ParsedCodexLogFile] = [:]

    func value(for key: CodexParsedLogFileCacheKey) -> ParsedCodexLogFile? {
        lock.lock()
        defer { lock.unlock() }
        return entries[key]
    }

    func set(_ value: ParsedCodexLogFile, for key: CodexParsedLogFileCacheKey) {
        lock.lock()
        entries[key] = value
        lock.unlock()
    }

    func prune(keeping keys: Set<CodexParsedLogFileCacheKey>) {
        lock.lock()
        entries = entries.filter { keys.contains($0.key) }
        lock.unlock()
    }
}

private final class CodexPersistentLogCacheCoordinator: @unchecked Sendable {
    private struct FlightState {
        var generation = 0
        var isRunning = false
        var result: [UsageEvent] = []
    }

    private let condition = NSCondition()
    private var states: [String: FlightState] = [:]

    func load(key: String, operation: () -> [UsageEvent]) -> [UsageEvent] {
        condition.lock()
        var state = states[key] ?? FlightState()

        if state.isRunning {
            let generation = state.generation
            while let current = states[key], current.isRunning, current.generation == generation {
                if withUnsafeCurrentTask(body: { $0?.isCancelled == true }) {
                    let previousResult = current.result
                    condition.unlock()
                    return previousResult
                }
                _ = condition.wait(until: Date().addingTimeInterval(0.05))
            }

            let sharedResult = states[key]?.result ?? []
            condition.unlock()
            return sharedResult
        }

        state.generation += 1
        state.isRunning = true
        states[key] = state
        condition.unlock()

        let result = operation()

        condition.lock()
        var completedState = states[key] ?? FlightState()
        completedState.isRunning = false
        completedState.result = result
        states[key] = completedState
        condition.broadcast()
        condition.unlock()
        return result
    }
}

private final class CodexLogScanErrorFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var paths = Set<String>()

    var encounteredPaths: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return paths
    }

    func markEncountered(at url: URL) {
        lock.lock()
        paths.insert(url.standardizedFileURL.path)
        lock.unlock()
    }
}

private final class CodexLogDateParser {
    private let fractionalFormatter: ISO8601DateFormatter
    private let formatter: ISO8601DateFormatter

    init() {
        fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
    }

    func parse(_ value: String) -> Date? {
        if let seconds = Double(value) {
            return Date(timestamp: seconds)
        }

        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        return formatter.date(from: value)
    }
}

private struct CodexCumulativeUsageGuard {
    private var previousTotalTokens: Int64?

    mutating func shouldSkipDuplicate(from object: [String: Any]) -> Bool {
        guard
            let payload = object["payload"] as? [String: Any],
            let info = payload["info"] as? [String: Any],
            info["last_token_usage"] != nil,
            let totalUsage = info["total_token_usage"] as? [String: Any],
            let totalTokens = Self.int64Value(totalUsage["total_tokens"])
        else {
            return false
        }

        defer {
            previousTotalTokens = totalTokens
        }

        return previousTotalTokens == totalTokens
    }

    private static func int64Value(_ value: Any?) -> Int64? {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? Double { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        if let value = value as? String { return Int64(value) }
        return nil
    }
}

private struct CodexModelContext {
    private var model: String?
    private var effort: String?

    var displayName: String? {
        Self.displayName(model: model, effort: effort)
    }

    mutating func update(from object: [String: Any]) {
        guard let payload = object["payload"] as? [String: Any] else {
            return
        }

        let info = payload["info"] as? [String: Any]
        let nextModel = Self.trimmedString(info?["model"])
            ?? Self.trimmedString(payload["model"])
        let nextEffort = Self.trimmedString(info?["effort"])
            ?? Self.trimmedString(info?["reasoning_effort"])
            ?? Self.trimmedString(payload["effort"])
            ?? Self.trimmedString(payload["reasoning_effort"])

        if let nextModel {
            if model != nextModel, nextEffort == nil {
                effort = nil
            }
            model = nextModel
        }

        if let nextEffort {
            effort = nextEffort
        }
    }

    static func displayName(model: String?, effort: String?) -> String? {
        guard let model = trimmedString(model) else {
            return nil
        }

        guard let effort = trimmedString(effort) else {
            return model
        }

        if model.localizedCaseInsensitiveContains(effort) {
            return model
        }

        return "\(model) \(effort)"
    }

    private static func trimmedString(_ value: Any?) -> String? {
        guard let value = value as? String else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}

private struct CodexLogFile {
    let url: URL
    let modifiedAt: Date
    let byteCount: Int
}

private struct CodexLogFileScan {
    let files: [CodexLogFile]
    let uncertainRoots: Set<String>
}
