import Foundation

/// Loads and saves `Config` as pretty-printed JSON.
public final class ConfigStore {
    public let url: URL

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MouseDriver", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    public init(url: URL = ConfigStore.defaultURL) {
        self.url = url
    }

    /// Returns the saved config, or the default one if nothing has been saved yet.
    public func load() throws -> Config {
        guard FileManager.default.fileExists(atPath: url.path) else { return .default }
        return try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
    }

    public func save(_ config: Config) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: url, options: .atomic)
    }
}
