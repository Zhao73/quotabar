import Foundation

public protocol FileSystem {
    func fileExists(at url: URL) -> Bool
    func read(from url: URL) throws -> Data
    func write(_ data: Data, to url: URL, options: Data.WritingOptions) throws
    func contentsOfDirectory(at url: URL) throws -> [URL]
    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool) throws
    func removeItem(at url: URL) throws
}

public final class LocalFileSystem: FileSystem {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    public func read(from url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    public func write(_ data: Data, to url: URL, options: Data.WritingOptions = .atomic) throws {
        let directory = url.deletingLastPathComponent()
        if !fileExists(at: directory) {
            try createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try data.write(to: url, options: options)
    }

    public func contentsOfDirectory(at url: URL) throws -> [URL] {
        try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
    }

    public func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool) throws {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: createIntermediates,
            attributes: nil
        )
    }

    public func removeItem(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }
}

public final class InMemoryFileSystem: FileSystem {
    private var files: [String: Data]
    private var directories: Set<String>

    public init() {
        self.files = [:]
        self.directories = ["/"]
    }

    public func fileExists(at url: URL) -> Bool {
        let path = normalize(url)
        return files[path] != nil || directories.contains(path)
    }

    public func read(from url: URL) throws -> Data {
        let path = normalize(url)
        guard let data = files[path] else {
            throw CocoaError(.fileNoSuchFile)
        }
        return data
    }

    public func write(_ data: Data, to url: URL, options: Data.WritingOptions = .atomic) throws {
        let path = normalize(url)
        let directory = normalize(url.deletingLastPathComponent())
        guard directories.contains(directory) else {
            throw CocoaError(.fileNoSuchFile)
        }
        files[path] = data
    }

    public func contentsOfDirectory(at url: URL) throws -> [URL] {
        let parent = normalize(url)
        guard directories.contains(parent) else {
            throw CocoaError(.fileNoSuchFile)
        }

        return files.keys
            .filter { key in
                let candidate = URL(fileURLWithPath: key)
                return normalize(candidate.deletingLastPathComponent()) == parent
            }
            .sorted()
            .map { URL(fileURLWithPath: $0) }
    }

    public func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool) throws {
        let normalized = normalize(url)
        directories.insert(normalized)
        if createIntermediates {
            var current = url
            while current.path != "/" && !current.path.isEmpty {
                directories.insert(normalize(current))
                current.deleteLastPathComponent()
            }
            directories.insert("/")
        }
    }

    public func removeItem(at url: URL) throws {
        let normalized = normalize(url)
        if files.removeValue(forKey: normalized) != nil {
            return
        }

        if directories.contains(normalized) {
            directories = directories.filter { !$0.hasPrefix(normalized) || $0 == "/" }
            files = files.filter { !$0.key.hasPrefix(normalized) }
            return
        }

        throw CocoaError(.fileNoSuchFile)
    }

    private func normalize(_ url: URL) -> String {
        url.standardizedFileURL.path
    }
}
