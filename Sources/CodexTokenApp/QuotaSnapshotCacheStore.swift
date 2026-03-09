import CodexTokenCore
import Foundation

@MainActor
final class QuotaSnapshotCacheStore {
    private let fileURL: URL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(fileURL: URL) {
        self.fileURL = fileURL
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() -> [String: QuotaSnapshot] {
        guard let data = try? Data(contentsOf: fileURL) else {
            return [:]
        }
        return (try? decoder.decode([String: QuotaSnapshot].self, from: data)) ?? [:]
    }

    func save(_ snapshots: [String: QuotaSnapshot]) {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try encoder.encode(snapshots)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Best-effort local cache.
        }
    }
}
