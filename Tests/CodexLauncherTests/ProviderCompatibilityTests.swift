import Foundation
import Testing
@testable import CodexLauncher

@MainActor
struct ProviderCompatibilityTests {
    @Test func providerTokensUsePrivateApplicationSupportJSON() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storeURL = directory.appendingPathComponent("CodexLauncher/provider-secrets.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        try ProviderTokenStore.save("local-secret", providerID: "proxy", storeURL: storeURL)

        #expect(ProviderTokenStore.load(providerID: "proxy", storeURL: storeURL) == "local-secret")
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: storeURL.path)
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: storeURL.deletingLastPathComponent().path)
        #expect((fileAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)

        try ProviderTokenStore.delete(providerID: "proxy", storeURL: storeURL)
        #expect(ProviderTokenStore.load(providerID: "proxy", storeURL: storeURL) == nil)
    }

    @Test func commandAuthIsUsedForModelDiscovery() async throws {
        let capture = RequestCapture()
        MockURLProtocol.handler = { request in
            capture.request = request
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(#"{"data":[{"id":"test-model","name":"Test Model"}]}"#.utf8))
        }
        defer { MockURLProtocol.handler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let store = ModelDiscoveryStore(session: URLSession(configuration: configuration))
        let provider = ModelProviderEntry(
            id: "proxy",
            name: "Proxy",
            baseURL: "https://example.com/v1",
            envKey: "",
            wireAPI: "responses",
            authCommand: "/usr/bin/printf",
            authArgs: ["command-token"],
            authTimeoutMS: 1000,
            queryParams: ["api-version": "2026-07-01"],
            httpHeaders: ["X-Static": "kept"]
        )

        await store.fetch(provider: provider)

        #expect(store.errorMessage == nil)
        #expect(store.models.map(\.slug) == ["test-model"])
        #expect(capture.request?.value(forHTTPHeaderField: "Authorization") == "Bearer command-token")
        #expect(capture.request?.value(forHTTPHeaderField: "X-Static") == "kept")
        #expect(URLComponents(url: capture.request!.url!, resolvingAgainstBaseURL: false)?.queryItems?.contains(
            URLQueryItem(name: "api-version", value: "2026-07-01")
        ) == true)
    }

    @Test func preservesNestedAndUnknownProviderConfiguration() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let configURL = directory.appendingPathComponent("config.toml")
        let stateURL = directory.appendingPathComponent("launcher-state.json")
        let original = """
        model_provider = "proxy"

        [model_providers.proxy]
        name = "Proxy"
        base_url = "https://example.com/v1"
        wire_api = "responses"
        env_key = "SHOULD_NOT_COEXIST"
        experimental_bearer_token = "SHOULD_NOT_COEXIST"
        requires_openai_auth = true
        query_params = { api-version = "2026-07-01" }
        http_headers = { "X-Static" = "kept" }
        custom_future_key = "preserve-me"

        [model_providers.proxy.auth]
        command = "/usr/bin/printf"
        args = ["token"]
        timeout_ms = 4000
        refresh_interval_ms = 0

        [model_providers.proxy.future]
        enabled = true
        """
        try original.write(to: configURL, atomically: true, encoding: .utf8)

        let store = ConfigStore(
            configURL: configURL,
            launcherStateURL: stateURL,
            providerTokenStoreURL: directory.appendingPathComponent("provider-secrets.json")
        )
        #expect(store.providers.keys.sorted() == ["proxy"])
        #expect(store.providers["proxy"]?.authCommand == "/usr/bin/printf")
        #expect(store.providers["proxy"]?.queryParams["api-version"] == "2026-07-01")

        store.selectProviderRoute("proxy")
        store.providerDraft?.name = "Renamed Proxy"
        store.saveProviderDraft()

        let saved = try String(contentsOf: configURL, encoding: .utf8)
        #expect(saved.contains("name = \"Renamed Proxy\""))
        #expect(saved.contains("custom_future_key = \"preserve-me\""))
        #expect(saved.contains("query_params = { api-version = \"2026-07-01\" }"))
        #expect(saved.contains("[model_providers.proxy.auth]"))
        #expect(saved.contains("command = \"/usr/bin/printf\""))
        #expect(!saved.contains("env_key = \"SHOULD_NOT_COEXIST\""))
        #expect(!saved.contains("experimental_bearer_token"))
        #expect(!saved.contains("requires_openai_auth"))
        #expect(saved.contains("[model_providers.proxy.future]"))
        #expect(saved.contains("enabled = true"))
    }

    @Test func renamesProviderAndItsNestedTables() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let configURL = directory.appendingPathComponent("config.toml")
        let stateURL = directory.appendingPathComponent("launcher-state.json")
        try """
        [model_providers.old]
        name = "Old"
        base_url = "https://example.com/v1"
        wire_api = "responses"

        [model_providers.old.auth]
        command = "/usr/bin/printf"
        args = ["token"]
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let store = ConfigStore(
            configURL: configURL,
            launcherStateURL: stateURL,
            providerTokenStoreURL: directory.appendingPathComponent("provider-secrets.json")
        )
        store.selectProviderRoute("old")
        store.providerDraft?.id = "new"
        store.saveProviderDraft()

        let saved = try String(contentsOf: configURL, encoding: .utf8)
        #expect(saved.contains("[model_providers.new]"))
        #expect(saved.contains("[model_providers.new.auth]"))
        #expect(!saved.contains("[model_providers.old]"))
        #expect(!saved.contains("[model_providers.old.auth]"))
    }
}

private final class RequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequest: URLRequest?

    var request: URLRequest? {
        get { lock.withLock { storedRequest } }
        set { lock.withLock { storedRequest = newValue } }
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
