import Foundation

@MainActor
final class ModelDiscoveryStore: ObservableObject {
    @Published private(set) var models: [DiscoveredModel] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private var lastFetchKey = ""
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchIfNeeded(provider: ModelProviderEntry, tokenOverride: String = "") async {
        let key = fetchKey(provider: provider, tokenOverride: tokenOverride)
        guard key != lastFetchKey else { return }
        await fetch(provider: provider, tokenOverride: tokenOverride)
    }

    func fetch(provider: ModelProviderEntry, tokenOverride: String = "") async {
        let trimmedBaseURL = provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBaseURL.isEmpty else {
            models = []
            errorMessage = nil
            lastFetchKey = ""
            return
        }

        guard let url = modelsURL(from: trimmedBaseURL, queryParams: provider.queryParams) else {
            models = []
            errorMessage = "base_url 不是有效 URL。"
            return
        }

        isLoading = true
        errorMessage = nil
        lastFetchKey = fetchKey(provider: provider, tokenOverride: tokenOverride)

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            for (header, value) in provider.httpHeaders {
                request.setValue(value, forHTTPHeaderField: header)
            }
            for (header, envKey) in provider.envHTTPHeaders {
                if let value = await environmentValue(for: envKey), !value.isEmpty {
                    request.setValue(value, forHTTPHeaderField: header)
                }
            }

            let injectedToken = tokenOverride.trimmingCharacters(in: .whitespacesAndNewlines)
            if !provider.authCommand.isEmpty {
                let token = try await commandToken(for: provider)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            } else if !injectedToken.isEmpty {
                request.setValue("Bearer \(injectedToken)", forHTTPHeaderField: "Authorization")
            } else if !provider.envKey.isEmpty, let token = await environmentValue(for: provider.envKey), !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw ModelDiscoveryError.httpStatus(http.statusCode, body ?? "")
            }

            models = try parseModels(from: data)
            errorMessage = models.isEmpty ? "没有从 /models 返回可用模型。" : nil
        } catch {
            models = []
            errorMessage = "拉取模型列表失败：\(error.localizedDescription)"
        }

        isLoading = false
    }

    private func environmentValue(for envKey: String) async -> String? {
        let cleanEnvKey = envKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanEnvKey.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else {
            return nil
        }

        if let token = ProcessInfo.processInfo.environment[cleanEnvKey], !token.isEmpty {
            return token
        }

        return await Task.detached {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lic", "printenv \(cleanEnvKey)"]
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { return nil }

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let token = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return token?.isEmpty == false ? token : nil
            } catch {
                return nil
            }
        }.value
    }

    private func commandToken(for provider: ModelProviderEntry) async throws -> String {
        try await Task.detached {
            let process = Process()
            let output = Pipe()
            let errorOutput = Pipe()
            let command = provider.authCommand.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !command.isEmpty else { throw ModelDiscoveryError.missingAuthCommand }

            if command.hasPrefix("/") {
                process.executableURL = URL(fileURLWithPath: command)
                process.arguments = provider.authArgs
            } else {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = [command] + provider.authArgs
            }
            if !provider.authCwd.isEmpty {
                process.currentDirectoryURL = URL(fileURLWithPath: NSString(string: provider.authCwd).expandingTildeInPath)
            }
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = output
            process.standardError = errorOutput

            try process.run()
            let timeout = TimeInterval(provider.authTimeoutMS ?? 5_000) / 1_000
            let deadline = Date().addingTimeInterval(max(timeout, 0.001))
            while process.isRunning, Date() < deadline {
                do {
                    try await Task.sleep(for: .milliseconds(25))
                } catch {
                    if process.isRunning { process.terminate() }
                    throw error
                }
            }
            if process.isRunning {
                process.terminate()
                throw ModelDiscoveryError.authCommandTimedOut(provider.authTimeoutMS ?? 5_000)
            }

            let data = output.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorOutput.fileHandleForReading.readDataToEndOfFile()
            let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let stderr = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard process.terminationStatus == 0 else {
                throw ModelDiscoveryError.authCommandFailed(Int(process.terminationStatus), stderr)
            }
            guard !token.isEmpty else { throw ModelDiscoveryError.emptyAuthToken }
            return token
        }.value
    }

    private func modelsURL(from baseURL: String, queryParams: [String: String]) -> URL? {
        guard var components = URLComponents(string: baseURL) else { return nil }
        var path = components.path
        if path.hasSuffix("/") {
            path.removeLast()
        }
        if path.hasSuffix("/models") {
            components.path = path
        } else {
            components.path = path + "/models"
        }
        if !queryParams.isEmpty {
            var items = components.queryItems ?? []
            items.append(contentsOf: queryParams.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) })
            components.queryItems = items
        }
        return components.url
    }

    private func fetchKey(provider: ModelProviderEntry, tokenOverride: String) -> String {
        "\(provider)|\(tokenOverride.isEmpty ? "env" : "token")"
    }

    private func parseModels(from data: Data) throws -> [DiscoveredModel] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else { return [] }

        if let dataArray = dictionary["data"] as? [[String: Any]] {
            return parseArray(dataArray)
        }

        if let modelsArray = dictionary["models"] as? [[String: Any]] {
            return parseArray(modelsArray)
        }

        if let modelStrings = dictionary["models"] as? [String] {
            return modelStrings.map { DiscoveredModel(slug: $0, displayName: $0) }
        }

        return []
    }

    private func parseArray(_ array: [[String: Any]]) -> [DiscoveredModel] {
        array.compactMap { item in
            let slug = item["id"] as? String
                ?? item["slug"] as? String
                ?? item["name"] as? String
                ?? item["model"] as? String
                ?? ""
            guard !slug.isEmpty else { return nil }

            let displayName = item["display_name"] as? String
                ?? item["name"] as? String
                ?? slug

            return DiscoveredModel(slug: slug, displayName: displayName)
        }
        .sorted { $0.slug.localizedStandardCompare($1.slug) == .orderedAscending }
    }
}

private enum ModelDiscoveryError: LocalizedError {
    case httpStatus(Int, String)
    case missingAuthCommand
    case authCommandTimedOut(Int)
    case authCommandFailed(Int, String)
    case emptyAuthToken

    var errorDescription: String? {
        switch self {
        case let .httpStatus(statusCode, body):
            if body.isEmpty {
                return "HTTP \(statusCode)"
            }
            return "HTTP \(statusCode): \(body)"
        case .missingAuthCommand:
            return "Provider auth command 为空。"
        case let .authCommandTimedOut(milliseconds):
            return "Provider auth command 超时（\(milliseconds) ms）。"
        case let .authCommandFailed(status, stderr):
            return stderr.isEmpty ? "Provider auth command 失败：exit \(status)" : "Provider auth command 失败：exit \(status): \(stderr)"
        case .emptyAuthToken:
            return "Provider auth command 没有返回 token。"
        }
    }
}
