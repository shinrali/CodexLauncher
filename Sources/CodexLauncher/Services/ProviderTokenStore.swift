import Foundation

enum ProviderTokenStore {
    private static let lock = NSLock()

    private struct Payload: Codable {
        var version = 1
        var tokens: [String: String] = [:]
    }

    static var defaultStoreURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexLauncher", isDirectory: true)
            .appendingPathComponent("provider-secrets.json")
    }

    static func load(providerID: String, storeURL: URL = defaultStoreURL) -> String? {
        let providerID = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !providerID.isEmpty else { return nil }
        return lock.withLock {
            guard let data = try? Data(contentsOf: storeURL),
                  let payload = try? JSONDecoder().decode(Payload.self, from: data)
            else { return nil }
            return payload.tokens[providerID]
        }
    }

    static func save(_ token: String, providerID: String, storeURL: URL = defaultStoreURL) throws {
        let providerID = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !providerID.isEmpty else { return }

        try lock.withLock {
            var payload = try loadPayload(from: storeURL)
            payload.tokens[providerID] = token
            try write(payload, to: storeURL)
        }
    }

    static func delete(providerID: String, storeURL: URL = defaultStoreURL) throws {
        let providerID = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !providerID.isEmpty,
              FileManager.default.fileExists(atPath: storeURL.path)
        else { return }

        try lock.withLock {
            var payload = try loadPayload(from: storeURL)
            payload.tokens.removeValue(forKey: providerID)
            try write(payload, to: storeURL)
        }
    }

    private static func loadPayload(from url: URL) throws -> Payload {
        guard FileManager.default.fileExists(atPath: url.path) else { return Payload() }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Payload.self, from: data)
    }

    private static func write(_ payload: Payload, to url: URL) throws {
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
