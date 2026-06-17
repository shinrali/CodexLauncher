import AppKit
import Foundation

@MainActor
final class ConfigStore: ObservableObject {
    static let officialProfileID = "__official_codex__"
    static let providerSelectionPrefix = "provider::"

    @Published private(set) var profiles: [ProfileEntry] = []
    @Published private(set) var providers: [String: ModelProviderEntry] = [:]
    @Published var selectedProfileID: String?
    @Published var selectedProviderID: String?
    @Published var draft: ProfileDraft?
    @Published var providerDraft: ProviderDraft?
    @Published var statusMessage = ""
    @Published var errorMessage: String?
    @Published var pendingLaunchConfirmation: LaunchConfirmation?

    private var originalText = ""
    private var didImportLegacyProfiles = false
    private var didNormalizeProviderNames = false
    private var didNormalizeProviderWireAPIs = false
    private var didNormalizeProviderBaseURLs = false
    private let fileManager = FileManager.default

    var configURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
            .appendingPathComponent("config.toml")
    }

    var launcherStateURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
            .appendingPathComponent("codex-launcher-state.json")
    }

    func defaultCatalogPath(for providerID: String) -> String {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
            .appendingPathComponent("\(providerID)-models.json")
            .path
    }

    func profileConfigURL(for profileID: String) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
            .appendingPathComponent("\(profileID).config.toml")
    }

    var isOfficialSelected: Bool {
        selectedProfileID == Self.officialProfileID
    }

    var selectedProviderRouteID: String? {
        guard let selectedProfileID,
              selectedProfileID.hasPrefix(Self.providerSelectionPrefix)
        else { return nil }
        return String(selectedProfileID.dropFirst(Self.providerSelectionPrefix.count))
    }

    var isProviderRouteSelected: Bool {
        selectedProviderRouteID != nil
    }

    init() {
        reload()
    }

    func reload() {
        do {
            originalText = try String(contentsOf: configURL, encoding: .utf8)
            parse(text: originalText)
            if didImportLegacyProfiles {
                try writeLauncherState()
            }
            if didImportLegacyProfiles || didNormalizeProviderNames || didNormalizeProviderWireAPIs || didNormalizeProviderBaseURLs {
                try writeConfig(activeProfileID: nil, clearActiveSettings: false)
            }
            if selectedProfileID == nil ||
                (selectedProfileID != Self.officialProfileID &&
                 selectedProviderRouteID == nil &&
                 profiles.contains(where: { $0.id == selectedProfileID }) == false) {
                selectedProfileID = Self.officialProfileID
            }
            refreshDraft()
            refreshProviderDraft()
            statusMessage = didImportLegacyProfiles ? "已迁移旧 profiles 并读取 \(configURL.path)" : "已读取 \(configURL.path)"
        } catch {
            profiles = []
            providers = [:]
            selectedProfileID = nil
            selectedProviderID = nil
            draft = nil
            providerDraft = nil
            errorMessage = "无法读取配置：\(error.localizedDescription)"
        }
    }

    func select(_ id: String?) {
        selectedProfileID = id
        if let providerID = selectedProviderRouteID {
            selectedProviderID = providerID
            draft = nil
            refreshProviderDraft()
            return
        }
        refreshDraft()
    }

    func selectProvider(_ id: String?) {
        selectedProviderID = id
        refreshProviderDraft()
    }

    func selectProviderRoute(_ id: String) {
        selectedProfileID = Self.providerSelectionPrefix + id
        selectedProviderID = id
        draft = nil
        refreshProviderDraft()
    }

    func ensureProviderRouteDraft() {
        guard let providerID = selectedProviderRouteID else { return }
        if selectedProviderID != providerID {
            selectedProviderID = providerID
        }
        refreshProviderDraft()
    }

    func catalogPathForCurrentDraft() -> String {
        guard let providerID = draft?.modelProvider.trimmingCharacters(in: .whitespacesAndNewlines),
              !providerID.isEmpty
        else { return "" }
        return defaultCatalogPath(for: providerID)
    }

    func addProfile() {
        let baseName = "new-profile"
        var nextName = baseName
        var suffix = 2
        while profiles.contains(where: { $0.id == nextName }) {
            nextName = "\(baseName)-\(suffix)"
            suffix += 1
        }

        let defaultProviderID: String
        if let existingProviderID = selectedProviderID ?? providers.keys.sorted().first {
            defaultProviderID = existingProviderID
        } else {
            let providerID = "local-provider"
            providers[providerID] = ModelProviderEntry(id: providerID, name: providerID, baseURL: "", envKey: "", wireAPI: "responses")
            selectedProviderID = providerID
            defaultProviderID = providerID
        }

        let profile = ProfileEntry(
            id: nextName,
            model: "",
            openAIBaseURL: "",
            modelProvider: defaultProviderID,
            modelCatalogJSON: defaultCatalogPath(for: defaultProviderID)
        )

        profiles.append(profile)
        profiles.sort { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        selectedProfileID = nextName
        refreshDraft()
        save()
    }

    func deleteSelectedProfile() {
        guard let id = selectedProfileID else { return }
        deleteProfile(id: id)
    }

    func deleteProfile(id: String) {
        guard id != Self.officialProfileID else { return }
        profiles.removeAll { $0.id == id }
        if selectedProfileID == id {
            selectedProfileID = Self.officialProfileID
        }
        refreshDraft()
        save()
    }

    func addProvider() {
        let baseName = "new-provider"
        var nextName = baseName
        var suffix = 2
        while providers[nextName] != nil {
            nextName = "\(baseName)-\(suffix)"
            suffix += 1
        }

        providers[nextName] = ModelProviderEntry(id: nextName, name: nextName, baseURL: "", envKey: "", wireAPI: "responses")
        selectProviderRoute(nextName)
        refreshProviderDraft()
        save()
    }

    func deleteSelectedProvider() {
        guard let id = selectedProviderID else { return }
        deleteProvider(id: id)
    }

    func deleteProvider(id: String) {
        providers.removeValue(forKey: id)
        profiles = profiles.map { profile in
            guard profile.modelProvider == id else { return profile }
            var updated = profile
            let replacement = providers.keys.sorted().first ?? ""
            updated.modelProvider = replacement
            updated.modelCatalogJSON = replacement.isEmpty ? "" : defaultCatalogPath(for: replacement)
            return updated
        }
        if selectedProviderID == id {
            selectedProviderID = providers.keys.sorted().first
        }
        if selectedProfileID == Self.providerSelectionPrefix + id {
            selectedProfileID = selectedProviderID.map { Self.providerSelectionPrefix + $0 } ?? Self.officialProfileID
        }
        refreshProviderDraft()
        refreshDraft()
        save()
    }

    func saveDraft() {
        guard let draft else { return }
        let cleanID = draft.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let providerID = draft.modelProvider.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanID.isEmpty, !providerID.isEmpty else {
            errorMessage = "Profile name 和 model_provider 不能为空。"
            return
        }

        if cleanID != draft.originalID, profiles.contains(where: { $0.id == cleanID }) {
            errorMessage = "已存在同名 profile：\(cleanID)"
            return
        }

        profiles.removeAll { $0.id == draft.originalID }
        profiles.append(ProfileEntry(
            id: cleanID,
            model: draft.model,
            openAIBaseURL: draft.openAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            modelProvider: providerID,
            modelCatalogJSON: defaultCatalogPath(for: providerID)
        ))
        profiles.sort { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        _ = syncProviderName(providerID: providerID, model: draft.model)

        selectedProfileID = cleanID
        refreshDraft()
        save()
    }

    func saveProviderDraft() {
        guard let providerDraft else { return }
        let cleanID = providerDraft.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanID.isEmpty else {
            errorMessage = "Provider id 不能为空。"
            return
        }

        if cleanID != providerDraft.originalID, providers[cleanID] != nil {
            errorMessage = "已存在同名 provider：\(cleanID)"
            return
        }

        providers.removeValue(forKey: providerDraft.originalID)
        providers[cleanID] = ModelProviderEntry(
            id: cleanID,
            name: providerDraft.name,
            baseURL: normalizedBaseURL(providerDraft.baseURL),
            envKey: providerDraft.envKey,
            wireAPI: providerDraft.wireAPI
        )

        do {
            if cleanID != providerDraft.originalID {
                try ProviderTokenStore.delete(providerID: providerDraft.originalID)
            }
            let cleanToken = providerDraft.token.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanToken.isEmpty {
                try ProviderTokenStore.delete(providerID: cleanID)
            } else {
                try ProviderTokenStore.save(cleanToken, providerID: cleanID)
            }
        } catch {
            errorMessage = "保存 token 失败：\(error.localizedDescription)"
            return
        }

        profiles = profiles.map { profile in
            guard profile.modelProvider == providerDraft.originalID else { return profile }
            var updated = profile
            updated.modelProvider = cleanID
            if updated.modelCatalogJSON == defaultCatalogPath(for: providerDraft.originalID) {
                updated.modelCatalogJSON = defaultCatalogPath(for: cleanID)
            }
            return updated
        }

        selectedProviderID = cleanID
        if isProviderRouteSelected {
            selectedProfileID = Self.providerSelectionPrefix + cleanID
        }
        refreshProviderDraft()
        refreshDraft()
        save()
    }

    func materializeSelectedProfileAndLaunch() {
        if isOfficialSelected {
            requestLaunch(.official)
            return
        }

        if isProviderRouteSelected {
            saveProviderDraft()
            return
        }

        saveDraft()
        guard let id = selectedProfileID else {
            errorMessage = "没有选中的 profile。"
            return
        }

        requestLaunch(.profile(id))
    }

    func tokenForProvider(_ providerID: String) -> String {
        ProviderTokenStore.load(providerID: providerID) ?? ""
    }

    func cancelPendingLaunch() {
        pendingLaunchConfirmation = nil
    }

    func confirmPendingLaunch() {
        guard let target = pendingLaunchConfirmation?.target else { return }
        pendingLaunchConfirmation = nil
        performLaunch(target, restartRunningApp: true)
    }

    private func requestLaunch(_ target: LaunchTarget) {
        if CodexAppLauncher.isRunning {
            pendingLaunchConfirmation = LaunchConfirmation(target: target)
            return
        }
        performLaunch(target, restartRunningApp: false)
    }

    private func performLaunch(_ target: LaunchTarget, restartRunningApp: Bool) {
        do {
            switch target {
            case .official:
                try writeConfig(activeProfileID: nil, clearActiveSettings: true)
                try CodexAppLauncher.launch(restartRunningApp: restartRunningApp)
                statusMessage = restartRunningApp ? "已关闭并启动官方版本 Codex.app" : "已启动官方版本 Codex.app"
            case let .profile(id):
                try writeConfig(activeProfileID: id)
                try writeProfileOverlay(profileID: id)
                try CodexAppLauncher.launch(
                    restartRunningApp: restartRunningApp,
                    environment: launchEnvironment(profileID: id)
                )
                statusMessage = restartRunningApp ? "已关闭并用 profile 启动 Codex.app：\(id)" : "已写入当前 profile 配置并启动 Codex.app：\(id)"
            }
        } catch {
            errorMessage = "启动失败：\(error.localizedDescription)"
        }
    }

    private func parse(text: String) {
        var parsedProfiles: [ProfileEntry] = []
        var parsedProviders: [String: ModelProviderEntry] = [:]
        let stateProfiles = loadLauncherProfiles()
        didImportLegacyProfiles = false
        didNormalizeProviderNames = false
        didNormalizeProviderWireAPIs = false
        didNormalizeProviderBaseURLs = false

        for section in TOMLSupport.splitSections(text) {
            guard let name = section.name else { continue }
            let values = TOMLSupport.keyValues(in: section.lines)

            if name.hasPrefix("profiles.") {
                let id = String(name.dropFirst("profiles.".count))
                parsedProfiles.append(ProfileEntry(
                    id: id,
                    model: values["model"] ?? "",
                    openAIBaseURL: values["openai_base_url"] ?? "",
                    modelProvider: values["model_provider"] ?? "",
                    modelCatalogJSON: values["model_catalog_json"] ?? ""
                ))
            } else if name.hasPrefix("model_providers.") {
                let id = String(name.dropFirst("model_providers.".count))
                let rawWireAPI = values["wire_api"] ?? ""
                let wireAPI = normalizedWireAPI(rawWireAPI)
                if rawWireAPI != wireAPI {
                    didNormalizeProviderWireAPIs = true
                }
                let rawBaseURL = values["base_url"] ?? ""
                let baseURL = normalizedBaseURL(rawBaseURL)
                if rawBaseURL != baseURL {
                    didNormalizeProviderBaseURLs = true
                }
                parsedProviders[id] = ModelProviderEntry(
                    id: id,
                    name: values["name"] ?? "",
                    baseURL: baseURL,
                    envKey: values["env_key"] ?? "",
                    wireAPI: wireAPI
                )
            }
        }

        if parsedProviders.isEmpty {
            parsedProviders = loadProvidersFromRecentBackups()
        }

        didImportLegacyProfiles = stateProfiles.isEmpty && parsedProfiles.isEmpty == false
        profiles = (didImportLegacyProfiles ? parsedProfiles : stateProfiles)
            .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        providers = parsedProviders
        didNormalizeProviderNames = profiles.reduce(false) { didChange, profile in
            syncProviderName(providerID: profile.modelProvider, model: profile.model) || didChange
        }
    }

    private func refreshDraft() {
        if isOfficialSelected {
            draft = nil
            return
        }

        guard let selectedProfileID,
              let profile = profiles.first(where: { $0.id == selectedProfileID })
        else {
            draft = nil
            return
        }

        draft = ProfileDraft(profile: profile)
        if selectedProviderID == nil {
            selectedProviderID = profile.modelProvider
            refreshProviderDraft()
        }
    }

    private func refreshProviderDraft() {
        guard let selectedProviderID,
              let provider = providers[selectedProviderID]
        else {
            providerDraft = nil
            return
        }

        let token = ProviderTokenStore.load(providerID: provider.id) ?? ""
        providerDraft = ProviderDraft(provider: provider, token: token, hasStoredToken: !token.isEmpty)
    }

    private func save() {
        do {
            try writeLauncherState()
            try writeConfig(activeProfileID: nil, clearActiveSettings: false)
            errorMessage = nil
            statusMessage = "已保存启动器 profile 和 \(configURL.lastPathComponent)"
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    func profileValidationWarnings(catalogModels: [CatalogModel]) -> [String] {
        guard let draft else { return [] }
        var warnings: [String] = []

        if draft.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            warnings.append("Profile name 为空。")
        }
        if draft.modelProvider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            warnings.append("model_provider 为空。")
        } else if providers[draft.modelProvider] == nil {
            warnings.append("model_provider 不存在：\(draft.modelProvider)")
        }
        if draft.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            warnings.append("model 为空。")
        } else if catalogModels.contains(where: { $0.slug == draft.model }) == false {
            warnings.append("model_catalog_json 里没有同 slug 条目：\(draft.model)")
        }
        if catalogPathForCurrentDraft().isEmpty {
            warnings.append("model_catalog_json 为空。")
        }

        return warnings
    }

    func providerValidationWarnings() -> [String] {
        guard let providerDraft else { return [] }
        var warnings: [String] = []

        if providerDraft.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            warnings.append("Provider id 为空。")
        }
        let rawBaseURL = providerDraft.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedURL = normalizedBaseURL(rawBaseURL)
        if rawBaseURL.isEmpty {
            warnings.append("base_url 为空，无法拉取 /models。")
        } else if URL(string: normalizedURL)?.scheme == nil || URL(string: normalizedURL)?.host == nil {
            warnings.append("base_url 不是有效 URL。")
        } else if normalizedURL != rawBaseURL {
            warnings.append("base_url 保存时会规范化为：\(normalizedURL)")
        }
        if providerDraft.wireAPI != "responses" {
            warnings.append("wire_api 应为 responses。")
        }

        return warnings
    }

    func profileChangeSummary(catalogModels: [CatalogModel]) -> String {
        guard let draft else { return "没有选中的 profile。" }
        let before = profiles.first(where: { $0.id == draft.originalID })
        var lines = ["Profile: \(draft.originalID)"]

        appendChange("id", before?.id, draft.id, to: &lines)
        appendChange("model", before?.model, draft.model, to: &lines)
        appendChange("model_provider", before?.modelProvider, draft.modelProvider, to: &lines)
        appendChange("model_catalog_json", before?.modelCatalogJSON, catalogPathForCurrentDraft(), to: &lines)
        appendChange("openai_base_url", before?.openAIBaseURL, draft.openAIBaseURL, to: &lines)

        let warnings = profileValidationWarnings(catalogModels: catalogModels)
        if !warnings.isEmpty {
            lines.append("")
            lines.append("Warnings:")
            lines.append(contentsOf: warnings.map { "- \($0)" })
        }

        return lines.joined(separator: "\n")
    }

    func providerChangeSummary() -> String {
        guard let providerDraft else { return "没有选中的 provider。" }
        let before = providers[providerDraft.originalID]
        var lines = ["Model Provider: \(providerDraft.originalID)"]

        appendChange("id", before?.id, providerDraft.id, to: &lines)
        appendChange("name", before?.name, providerDraft.name, to: &lines)
        appendChange("base_url", before?.baseURL, providerDraft.baseURL, to: &lines)
        appendChange("env_key", before?.envKey, providerDraft.envKey, to: &lines)
        appendChange("wire_api", before?.wireAPI, providerDraft.wireAPI, to: &lines)
        lines.append("default catalog: \(defaultCatalogPath(for: providerDraft.id))")

        let warnings = providerValidationWarnings()
        if !warnings.isEmpty {
            lines.append("")
            lines.append("Warnings:")
            lines.append(contentsOf: warnings.map { "- \($0)" })
        }

        return lines.joined(separator: "\n")
    }

    private func syncProviderName(providerID: String, model: String) -> Bool {
        let cleanProviderID = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanProviderID.isEmpty,
              !cleanModel.isEmpty,
              var provider = providers[cleanProviderID]
        else { return false }

        let expectedName = "\(cleanProviderID) \(cleanModel)"
        guard provider.name != expectedName else { return false }
        provider.name = expectedName
        providers[cleanProviderID] = provider
        return true
    }

    private func launchEnvironment(profileID: String) -> [String: String] {
        guard let profile = profiles.first(where: { $0.id == profileID }),
              let provider = providers[profile.modelProvider]
        else { return [:] }

        let envKey = provider.envKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard envKey.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else {
            return [:]
        }

        let token = ProviderTokenStore.load(providerID: provider.id) ?? ""
        guard !token.isEmpty else { return [:] }
        return [envKey: token]
    }

    private func writeConfig(activeProfileID: String?, clearActiveSettings: Bool = false) throws {
        originalText = try String(contentsOf: configURL, encoding: .utf8)
        let text = buildConfigText(activeProfileID: activeProfileID, clearActiveSettings: clearActiveSettings)
        guard text != originalText else { return }
        try backupFile(at: configURL)
        try text.write(to: configURL, atomically: true, encoding: .utf8)
        originalText = text
    }

    private func buildConfigText(activeProfileID: String?, clearActiveSettings: Bool) -> String {
        var preserved = TOMLSupport.splitSections(originalText).filter { section in
            guard let name = section.name else { return true }
            if name.hasPrefix("profiles.") { return false }
            if name.hasPrefix("model_providers.") { return false }
            return true
        }

        if activeProfileID != nil || clearActiveSettings {
            stripManagedTopLevelKeys(&preserved)
        }
        if let activeProfileID,
           let profile = profiles.first(where: { $0.id == activeProfileID }) {
            patchActiveProfileSettings(&preserved, profile: profile)
        }

        var chunks = preserved.map { trimTrailingBlankLines($0.lines).joined(separator: "\n") }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        chunks.append(renderProviders())

        return chunks
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private func stripManagedTopLevelKeys(_ sections: inout [TOMLSection]) {
        guard let rootIndex = sections.firstIndex(where: { $0.name == nil }) else { return }
        let managedKeys: Set<String> = ["profile", "model", "model_provider", "model_catalog_json", "openai_base_url"]
        sections[rootIndex].lines = sections[rootIndex].lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let equals = trimmed.firstIndex(of: "=") else { return true }
            let key = String(trimmed[..<equals]).trimmingCharacters(in: .whitespaces)
            return !managedKeys.contains(key)
        }
    }

    private func patchActiveProfileSettings(_ sections: inout [TOMLSection], profile: ProfileEntry) {
        if sections.firstIndex(where: { $0.name == nil }) == nil {
            sections.insert(TOMLSection(name: nil, lines: []), at: 0)
        }
        guard let rootIndex = sections.firstIndex(where: { $0.name == nil }) else { return }

        let catalogPath = profile.modelProvider.isEmpty ? profile.modelCatalogJSON : defaultCatalogPath(for: profile.modelProvider)
        var newLines: [String] = []
        if !profile.model.isEmpty { newLines.append("model = \(TOMLSupport.quoted(profile.model))") }
        if !profile.openAIBaseURL.isEmpty { newLines.append("openai_base_url = \(TOMLSupport.quoted(profile.openAIBaseURL))") }
        if !profile.modelProvider.isEmpty { newLines.append("model_provider = \(TOMLSupport.quoted(profile.modelProvider))") }
        if !catalogPath.isEmpty { newLines.append("model_catalog_json = \(TOMLSupport.quoted(catalogPath))") }

        var lines = sections[rootIndex].lines
        let insertIndex = lines.firstIndex { line in
            line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        } ?? lines.endIndex
        lines.insert(contentsOf: newLines, at: insertIndex)
        sections[rootIndex].lines = lines
    }

    private func renderProviders() -> String {
        providers.keys.sorted().compactMap { key -> String? in
            guard let provider = providers[key] else { return nil }
            var lines = ["[model_providers.\(key)]"]
            if !provider.name.isEmpty { lines.append("name = \(TOMLSupport.quoted(provider.name))") }
            if !provider.baseURL.isEmpty { lines.append("base_url = \(TOMLSupport.quoted(provider.baseURL))") }
            if !provider.envKey.isEmpty { lines.append("env_key = \(TOMLSupport.quoted(provider.envKey))") }
            if !provider.wireAPI.isEmpty { lines.append("wire_api = \(TOMLSupport.quoted(provider.wireAPI))") }
            return lines.joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }

    private func loadLauncherProfiles() -> [ProfileEntry] {
        guard let data = try? Data(contentsOf: launcherStateURL),
              let state = try? JSONDecoder().decode(LauncherState.self, from: data)
        else { return [] }
        return state.profiles
    }

    private func writeLauncherState() throws {
        try fileManager.createDirectory(at: launcherStateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let state = LauncherState(profiles: profiles)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: launcherStateURL, options: .atomic)
    }

    private func normalizedWireAPI(_ value: String?) -> String {
        let cleanValue = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanValue == "responses" ? "responses" : "responses"
    }

    private func normalizedBaseURL(_ value: String?) -> String {
        var cleanValue = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanValue.isEmpty else { return "" }

        if !cleanValue.contains("://") {
            cleanValue = "http://\(cleanValue)"
        }

        guard var components = URLComponents(string: cleanValue),
              components.scheme != nil,
              components.host != nil
        else { return cleanValue }

        if components.path.isEmpty || components.path == "/" {
            components.path = "/v1"
        }

        return components.url?.absoluteString ?? cleanValue
    }

    private func loadProvidersFromRecentBackups() -> [String: ModelProviderEntry] {
        let backupDirectory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
            .appendingPathComponent("backups")

        guard let files = try? fileManager.contentsOfDirectory(
            at: backupDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [:] }

        let candidates = files
            .filter { $0.lastPathComponent.hasPrefix("config-") && $0.pathExtension == "toml" }
            .sorted {
                let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }

        for url in candidates {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let providers = providerEntries(in: text)
            if !providers.isEmpty {
                didNormalizeProviderWireAPIs = true
                return providers
            }
        }

        return [:]
    }

    private func providerEntries(in text: String) -> [String: ModelProviderEntry] {
        var parsedProviders: [String: ModelProviderEntry] = [:]
        for section in TOMLSupport.splitSections(text) {
            guard let name = section.name,
                  name.hasPrefix("model_providers.")
            else { continue }

            let id = String(name.dropFirst("model_providers.".count))
            let values = TOMLSupport.keyValues(in: section.lines)
            parsedProviders[id] = ModelProviderEntry(
                id: id,
                name: values["name"] ?? "",
                baseURL: normalizedBaseURL(values["base_url"]),
                envKey: values["env_key"] ?? "",
                wireAPI: normalizedWireAPI(values["wire_api"])
            )
        }
        return parsedProviders
    }

    private func writeProfileOverlay(profileID: String) throws {
        guard let profile = profiles.first(where: { $0.id == profileID }) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "找不到 profile：\(profileID)"])
        }

        let url = profileConfigURL(for: profileID)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        var lines: [String] = []
        if !profile.model.isEmpty { lines.append("model = \(TOMLSupport.quoted(profile.model))") }
        if !profile.openAIBaseURL.isEmpty { lines.append("openai_base_url = \(TOMLSupport.quoted(profile.openAIBaseURL))") }
        if !profile.modelProvider.isEmpty { lines.append("model_provider = \(TOMLSupport.quoted(profile.modelProvider))") }
        let catalogPath = profile.modelProvider.isEmpty ? profile.modelCatalogJSON : defaultCatalogPath(for: profile.modelProvider)
        if !catalogPath.isEmpty { lines.append("model_catalog_json = \(TOMLSupport.quoted(catalogPath))") }

        let text = lines.joined(separator: "\n") + "\n"
        if let existing = try? String(contentsOf: url, encoding: .utf8), existing == text {
            return
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func trimTrailingBlankLines(_ lines: [String]) -> [String] {
        var lines = lines
        while lines.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lines.removeLast()
        }
        return lines
    }

    private func appendChange(_ name: String, _ oldValue: String?, _ newValue: String, to lines: inout [String]) {
        let old = oldValue ?? ""
        guard old != newValue else { return }
        lines.append("\(name): \(old.isEmpty ? "<empty>" : old) -> \(newValue.isEmpty ? "<empty>" : newValue)")
    }

    private func backupFile(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        let now = Date()
        if let lastBackupDate = Self.lastBackupDates[url.path],
           now.timeIntervalSince(lastBackupDate) < Self.backupMinimumInterval {
            return
        }

        let backupDirectory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
            .appendingPathComponent("backups")
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

        let timestamp = Self.backupTimestampFormatter.string(from: now)
        var backupURL = backupDirectory.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent)-\(timestamp).\(url.pathExtension)")
        var suffix = 2
        while fileManager.fileExists(atPath: backupURL.path) {
            backupURL = backupDirectory.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent)-\(timestamp)-\(suffix).\(url.pathExtension)")
            suffix += 1
        }
        try fileManager.copyItem(at: url, to: backupURL)
        Self.lastBackupDates[url.path] = now
    }

    private static var lastBackupDates: [String: Date] = [:]
    private static let backupMinimumInterval: TimeInterval = 300

    private static let backupTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter
    }()
}

enum LaunchTarget {
    case official
    case profile(String)
}

struct LaunchConfirmation: Identifiable {
    let id = UUID()
    let target: LaunchTarget

    var title: String {
        "Codex 正在运行"
    }

    var message: String {
        switch target {
        case .official:
            return "需要先关闭当前 Codex.app，才能切回官方默认配置。是否关闭并继续？"
        case let .profile(profileID):
            return "需要先关闭当前 Codex.app，才能切换到 profile：\(profileID)。是否关闭并继续？"
        }
    }
}
