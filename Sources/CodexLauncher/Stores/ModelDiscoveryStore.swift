import Foundation

@MainActor
final class ModelDiscoveryStore: ObservableObject {
    @Published private(set) var models: [DiscoveredModel] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private var lastFetchKey = ""

    func fetchIfNeeded(baseURL: String, envKey: String, providerID: String, tokenOverride: String = "") async {
        let key = "\(baseURL)|\(envKey)|\(providerID)|\(tokenOverride.isEmpty ? "env" : "token")"
        guard key != lastFetchKey else { return }
        await fetch(baseURL: baseURL, envKey: envKey, providerID: providerID, tokenOverride: tokenOverride)
    }

    func fetch(baseURL: String, envKey: String, providerID: String, tokenOverride: String = "") async {
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBaseURL.isEmpty else {
            models = []
            errorMessage = nil
            lastFetchKey = ""
            return
        }

        guard let url = modelsURL(from: trimmedBaseURL) else {
            models = []
            errorMessage = "base_url 不是有效 URL。"
            return
        }

        isLoading = true
        errorMessage = nil
        lastFetchKey = "\(baseURL)|\(envKey)|\(providerID)|\(tokenOverride.isEmpty ? "env" : "token")"

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            let injectedToken = tokenOverride.trimmingCharacters(in: .whitespacesAndNewlines)
            if !injectedToken.isEmpty {
                request.setValue("Bearer \(injectedToken)", forHTTPHeaderField: "Authorization")
            } else if !envKey.isEmpty, let token = await token(for: envKey, providerID: providerID), !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            let (data, response) = try await URLSession.shared.data(for: request)
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

    private func token(for envKey: String, providerID: String) async -> String? {
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

    private func modelsURL(from baseURL: String) -> URL? {
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
        return components.url
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

    var errorDescription: String? {
        switch self {
        case let .httpStatus(statusCode, body):
            if body.isEmpty {
                return "HTTP \(statusCode)"
            }
            return "HTTP \(statusCode): \(body)"
        }
    }
}
