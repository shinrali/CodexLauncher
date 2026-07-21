import Foundation

enum ProviderTokenStore {
    private static let lock = NSLock()
    static let helperArgument = "--print-provider-token"

    private struct Payload: Codable {
        var version = 1
        var tokens: [String: String] = [:]
    }

    static var defaultStoreURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexLauncher", isDirectory: true)
            .appendingPathComponent("provider-secrets.json")
    }

    static func helperURL(storeURL: URL = defaultStoreURL) -> URL {
        storeURL.deletingLastPathComponent()
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("CodexLauncherTokenHelper")
    }

    static func helperArguments(providerID: String) -> [String] {
        [helperArgument, providerID]
    }

    static func isManagedHelper(
        command: String,
        args: [String],
        providerID: String,
        storeURL: URL = defaultStoreURL
    ) -> Bool {
        let commandURL = URL(fileURLWithPath: NSString(string: command).expandingTildeInPath)
        return commandURL.lastPathComponent == helperURL(storeURL: storeURL).lastPathComponent
            && args == helperArguments(providerID: providerID)
    }

    static func installHelper(
        sourceURL: URL? = Bundle.main.executableURL,
        storeURL: URL = defaultStoreURL
    ) throws {
        guard let sourceURL else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "找不到 CodexLauncher 可执行文件。"])
        }

        let fileManager = FileManager.default
        let destinationURL = helperURL(storeURL: storeURL)
        let directory = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        let sourceData = try Data(contentsOf: sourceURL)
        if (try? Data(contentsOf: destinationURL)) != sourceData {
            try sourceData.write(to: destinationURL, options: .atomic)
        }
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: destinationURL.path)
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
