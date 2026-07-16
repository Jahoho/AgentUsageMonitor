import AgentUsageCore
import Foundation

protocol UsageEventStoring: Sendable {
    func load(providerID: String?) async -> [UsageEvent]
    func append(_ event: UsageEvent) async
}

actor JSONUsageEventStore: UsageEventStoring {
    private let fileURL: URL
    private let legacyFileURL: URL

    init(fileManager: FileManager = .default) {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directoryURL = baseURL.appendingPathComponent("AgentUsageMonitor", isDirectory: true)
        try? LocalDataProtection.prepareDirectory(at: directoryURL, fileManager: fileManager)
        self.fileURL = directoryURL.appendingPathComponent("usage-events.jsonl")
        self.legacyFileURL = directoryURL.appendingPathComponent("usage-events.json")
        try? LocalDataProtection.protectFile(at: self.fileURL, fileManager: fileManager)
        try? LocalDataProtection.protectFile(at: self.legacyFileURL, fileManager: fileManager)
    }

    init(fileURL: URL, legacyFileURL: URL? = nil) {
        self.fileURL = fileURL
        self.legacyFileURL = legacyFileURL ?? fileURL.deletingPathExtension().appendingPathExtension("json")
        try? LocalDataProtection.prepareDirectory(at: fileURL.deletingLastPathComponent())
        try? LocalDataProtection.protectFile(at: self.fileURL)
        try? LocalDataProtection.protectFile(at: self.legacyFileURL)
    }

    func load(providerID: String? = nil) async -> [UsageEvent] {
        let events = loadJSONLEvents() ?? loadAndMigrateLegacyEvents()

        guard let providerID else {
            return events
        }

        return events.filter { $0.providerID == providerID }
    }

    func append(_ event: UsageEvent) async {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        guard var data = try? encoder.encode(event) else {
            return
        }
        data.append(Data("\n".utf8))

        if FileManager.default.fileExists(atPath: fileURL.path) {
            guard let handle = try? FileHandle(forWritingTo: fileURL) else {
                return
            }
            defer {
                try? handle.close()
            }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? LocalDataProtection.protectFile(at: fileURL)
        } else {
            try? data.write(to: fileURL, options: [.atomic])
            try? LocalDataProtection.protectFile(at: fileURL)
        }
    }

    private func loadJSONLEvents() -> [UsageEvent]? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return []
        }

        let decoder = JSONDecoder()
        return text
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                try? decoder.decode(UsageEvent.self, from: Data(String(line).utf8))
            }
    }

    private func loadAndMigrateLegacyEvents() -> [UsageEvent] {
        guard
            let data = try? Data(contentsOf: legacyFileURL),
            let events = try? JSONDecoder().decode([UsageEvent].self, from: data)
        else {
            return []
        }

        writeJSONLEvents(events)
        return events
    }

    private func writeJSONLEvents(_ events: [UsageEvent]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let lines = events.compactMap { event -> Data? in
            guard var data = try? encoder.encode(event) else {
                return nil
            }
            data.append(Data("\n".utf8))
            return data
        }

        var output = Data()
        for line in lines {
            output.append(line)
        }
        try? output.write(to: fileURL, options: [.atomic])
        try? LocalDataProtection.protectFile(at: fileURL)
    }
}
