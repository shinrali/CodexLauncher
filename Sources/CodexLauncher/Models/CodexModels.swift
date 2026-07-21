import Foundation

struct ProfileEntry: Identifiable, Hashable, Codable {
    var id: String
    var model: String
    var openAIBaseURL: String
    var modelProvider: String
    var modelCatalogJSON: String
}

struct ModelProviderEntry: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var baseURL: String
    var envKey: String
    var wireAPI: String
    var usesManagedTokenHelper: Bool
    var authCommand: String
    var authArgs: [String]
    var authCwd: String
    var authTimeoutMS: Int?
    var authRefreshIntervalMS: Int?
    var queryParams: [String: String]
    var httpHeaders: [String: String]
    var envHTTPHeaders: [String: String]

    init(
        id: String,
        name: String,
        baseURL: String,
        envKey: String,
        wireAPI: String,
        usesManagedTokenHelper: Bool = false,
        authCommand: String = "",
        authArgs: [String] = [],
        authCwd: String = "",
        authTimeoutMS: Int? = nil,
        authRefreshIntervalMS: Int? = nil,
        queryParams: [String: String] = [:],
        httpHeaders: [String: String] = [:],
        envHTTPHeaders: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.envKey = envKey
        self.wireAPI = wireAPI
        self.usesManagedTokenHelper = usesManagedTokenHelper
        self.authCommand = authCommand
        self.authArgs = authArgs
        self.authCwd = authCwd
        self.authTimeoutMS = authTimeoutMS
        self.authRefreshIntervalMS = authRefreshIntervalMS
        self.queryParams = queryParams
        self.httpHeaders = httpHeaders
        self.envHTTPHeaders = envHTTPHeaders
    }
}

enum ProviderAuthMode: String, CaseIterable, Identifiable {
    case localFile
    case environment
    case command

    var id: String { rawValue }
}

struct LauncherState: Codable {
    var profiles: [ProfileEntry]
}

struct CatalogModel: Identifiable {
    var id = UUID()
    var slug: String
    var displayName: String
    var description: String
    var contextWindow: Int?
    var maxContextWindow: Int?
    var rawFields: [String: Any] = [:]
}

struct DiscoveredModel: Identifiable, Hashable {
    var id: String { slug }
    var slug: String
    var displayName: String
}

struct ProfileDraft: Equatable {
    var originalID: String
    var id: String
    var model: String
    var openAIBaseURL: String
    var modelProvider: String
    var modelCatalogJSON: String
}

extension ProfileDraft {
    init(profile: ProfileEntry) {
        originalID = profile.id
        id = profile.id
        model = profile.model
        openAIBaseURL = profile.openAIBaseURL
        modelProvider = profile.modelProvider
        modelCatalogJSON = profile.modelCatalogJSON
    }
}

struct ProviderDraft: Equatable {
    var originalID: String
    var id: String
    var name: String
    var baseURL: String
    var envKey: String
    var wireAPI: String
    var token: String
    var hasStoredToken: Bool
    var authMode: ProviderAuthMode
    var authCommand: String
    var authArgs: String
    var authCwd: String
    var authTimeoutMS: String
    var authRefreshIntervalMS: String
}

extension ProviderDraft {
    init(provider: ModelProviderEntry, token: String = "", hasStoredToken: Bool = false) {
        originalID = provider.id
        id = provider.id
        name = provider.name
        baseURL = provider.baseURL
        envKey = provider.envKey
        wireAPI = provider.wireAPI
        self.token = token
        self.hasStoredToken = hasStoredToken
        if provider.usesManagedTokenHelper {
            authMode = .localFile
        } else {
            authMode = provider.authCommand.isEmpty ? .environment : .command
        }
        authCommand = provider.authCommand
        authArgs = provider.authArgs.joined(separator: "\n")
        authCwd = provider.authCwd
        authTimeoutMS = provider.authTimeoutMS.map(String.init) ?? ""
        authRefreshIntervalMS = provider.authRefreshIntervalMS.map(String.init) ?? ""
    }
}
