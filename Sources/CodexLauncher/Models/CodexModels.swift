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
    }
}
