import Foundation

struct CLILaunchRecord: Codable, Equatable, Sendable {
    var lastOpenedAt: Date
    var launchCount: Int
}

@MainActor
final class CLILaunchRecordStore {
    private let fileURL: URL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(fileURL: URL) {
        self.fileURL = fileURL
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() -> [String: CLILaunchRecord] {
        guard let data = try? Data(contentsOf: fileURL) else {
            return [:]
        }
        return (try? decoder.decode([String: CLILaunchRecord].self, from: data)) ?? [:]
    }

    func recordLaunch(for storageKey: String, at date: Date = Date()) -> [String: CLILaunchRecord] {
        var records = load()
        var record = records[storageKey] ?? CLILaunchRecord(lastOpenedAt: date, launchCount: 0)
        record.lastOpenedAt = date
        record.launchCount += 1
        records[storageKey] = record
        save(records)
        return records
    }

    private func save(_ records: [String: CLILaunchRecord]) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try encoder.encode(records)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Best-effort local metadata.
        }
    }
}
