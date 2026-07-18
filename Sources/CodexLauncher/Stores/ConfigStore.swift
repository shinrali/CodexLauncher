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
    private var didNormalizeProviderWireAPIs = false
    private var didNormalizeProviderBaseURLs = false
    private var didNormalizeProviderEnvKeys = false
    private var providerSourceIDs: [String: String] = [:]
    private let fileManager = FileManager.default
    private let configURLOverride: URL?
    private let launcherStateURLOverride: URL?
    private let providerTokenStoreURL: URL

    var configURL: URL {
        if let configURLOverride { return configURLOverride }
        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
            .appendingPathComponent("config.toml")
    }

    var launcherStateURL: URL {
        if let launcherStateURLOverride { return launcherStateURLOverride }
        return fileManager.homeDirectoryForCurrentUser
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

    init(
        configURL: URL? = nil,
        launcherStateURL: URL? = nil,
        providerTokenStoreURL: URL = ProviderTokenStore.defaultStoreURL
    ) {
        configURLOverride = configURL
        launcherStateURLOverride = launcherStateURL
        self.providerTokenStoreURL = providerTokenStoreURL
        reload()
    }

    func reload() {
        do {
            originalText = try String(contentsOf: configURL, encoding: .utf8)
            parse(text: originalText)
            if didImportLegacyProfiles {
                try writeLauncherState()
            }
            if didImportLegacyProfiles || didNormalizeProviderWireAPIs || didNormalizeProviderBaseURLs || didNormalizeProviderEnvKeys {
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
        providerSourceIDs.removeValue(forKey: id)
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

        let sourceID = providerSourceIDs.removeValue(forKey: providerDraft.originalID) ?? providerDraft.originalID
        let previousProvider = providers.removeValue(forKey: providerDraft.originalID)
        let cleanToken = providerDraft.token.trimmingCharacters(in: .whitespacesAndNewlines)
        let usesCommandAuth = providerDraft.authMode == .command
        let cleanEnvKey = usesCommandAuth ? "" : normalizedEnvKey(providerDraft.envKey, providerID: cleanID, hasToken: !cleanToken.isEmpty)
        let authArgs = providerDraft.authArgs
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        providers[cleanID] = ModelProviderEntry(
            id: cleanID,
            name: providerDraft.name,
            baseURL: normalizedBaseURL(providerDraft.baseURL),
            envKey: cleanEnvKey,
            wireAPI: providerDraft.wireAPI,
            authCommand: usesCommandAuth ? providerDraft.authCommand.trimmingCharacters(in: .whitespacesAndNewlines) : "",
            authArgs: usesCommandAuth ? authArgs : [],
            authCwd: usesCommandAuth ? providerDraft.authCwd.trimmingCharacters(in: .whitespacesAndNewlines) : "",
            authTimeoutMS: usesCommandAuth ? Int(providerDraft.authTimeoutMS.trimmingCharacters(in: .whitespacesAndNewlines)) : nil,
            authRefreshIntervalMS: usesCommandAuth ? Int(providerDraft.authRefreshIntervalMS.trimmingCharacters(in: .whitespacesAndNewlines)) : nil,
            queryParams: previousProvider?.queryParams ?? [:],
            httpHeaders: previousProvider?.httpHeaders ?? [:],
            envHTTPHeaders: previousProvider?.envHTTPHeaders ?? [:]
        )
        providerSourceIDs[cleanID] = sourceID

        do {
            if cleanID != providerDraft.originalID {
                try ProviderTokenStore.delete(providerID: providerDraft.originalID, storeURL: providerTokenStoreURL)
            }
            if cleanToken.isEmpty || usesCommandAuth {
                try ProviderTokenStore.delete(providerID: cleanID, storeURL: providerTokenStoreURL)
            } else {
                try ProviderTokenStore.save(cleanToken, providerID: cleanID, storeURL: providerTokenStoreURL)
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
        ProviderTokenStore.load(providerID: providerID, storeURL: providerTokenStoreURL) ?? ""
    }

    func providerForDiscovery(_ providerID: String) -> ModelProviderEntry? {
        providers[providerID]
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
                let appName = CodexAppLauncher.appDisplayName
                statusMessage = restartRunningApp ? "已关闭并启动官方版本 \(appName).app" : "已启动官方版本 \(appName).app"
            case let .profile(id):
                try writeConfig(activeProfileID: id)
                try writeProfileOverlay(profileID: id)
                try CodexAppLauncher.launch(
                    restartRunningApp: restartRunningApp,
                    environment: launchEnvironment(profileID: id)
                )
                let appName = CodexAppLauncher.appDisplayName
                statusMessage = restartRunningApp ? "已关闭并用 profile 启动 \(appName).app：\(id)" : "已写入当前 profile 配置并启动 \(appName).app：\(id)"
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
        didNormalizeProviderWireAPIs = false
        didNormalizeProviderBaseURLs = false
        didNormalizeProviderEnvKeys = false
        providerSourceIDs = [:]

        let sections = TOMLSupport.splitSections(text)
        let sectionNames = Set(sections.compactMap(\.name))

        for section in sections {
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
            } else if let id = providerRootID(for: name, sectionNames: sectionNames) {
                let authValues = sections.first(where: { $0.name == "model_providers.\(id).auth" })
                    .map { TOMLSupport.keyValues(in: $0.lines) } ?? [:]
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
                let rawEnvKey = values["env_key"] ?? ""
                let usesCommandAuth = authValues["command"]?.isEmpty == false
                let envKey = usesCommandAuth
                    ? ""
                    : normalizedEnvKey(rawEnvKey, providerID: id, hasToken: ProviderTokenStore.load(providerID: id, storeURL: providerTokenStoreURL)?.isEmpty == false)
                if rawEnvKey != envKey {
                    didNormalizeProviderEnvKeys = true
                }
                parsedProviders[id] = ModelProviderEntry(
                    id: id,
                    name: values["name"] ?? "",
                    baseURL: baseURL,
                    envKey: envKey,
                    wireAPI: wireAPI,
                    authCommand: authValues["command"] ?? "",
                    authArgs: TOMLSupport.stringArray(authValues["args"]),
                    authCwd: authValues["cwd"] ?? "",
                    authTimeoutMS: authValues["timeout_ms"].flatMap(Int.init),
                    authRefreshIntervalMS: authValues["refresh_interval_ms"].flatMap(Int.init),
                    queryParams: TOMLSupport.inlineStringTable(values["query_params"]),
                    httpHeaders: TOMLSupport.inlineStringTable(values["http_headers"]),
                    envHTTPHeaders: TOMLSupport.inlineStringTable(values["env_http_headers"])
                )
                providerSourceIDs[id] = id
            }
        }

        if parsedProviders.isEmpty {
            parsedProviders = loadProvidersFromRecentBackups()
            providerSourceIDs = Dictionary(uniqueKeysWithValues: parsedProviders.keys.map { ($0, $0) })
        }

        didImportLegacyProfiles = stateProfiles.isEmpty && parsedProfiles.isEmpty == false
        profiles = (didImportLegacyProfiles ? parsedProfiles : stateProfiles)
            .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        providers = parsedProviders
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

        let token = ProviderTokenStore.load(providerID: provider.id, storeURL: providerTokenStoreURL) ?? ""
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
        let cleanToken = providerDraft.token.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanEnvKey = providerDraft.envKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if providerDraft.authMode == .command {
            if providerDraft.authCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                warnings.append("Command auth 需要填写 command。")
            }
            if !cleanEnvKey.isEmpty || !cleanToken.isEmpty {
                warnings.append("Command auth 保存时不会使用 env_key 或本地静态 token。")
            }
            for (label, value) in [("timeout_ms", providerDraft.authTimeoutMS), ("refresh_interval_ms", providerDraft.authRefreshIntervalMS)] {
                let cleanValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanValue.isEmpty, Int(cleanValue) == nil {
                    warnings.append("\(label) 必须是整数。")
                }
            }
        } else if !cleanToken.isEmpty && cleanEnvKey.isEmpty {
            warnings.append("已保存 token 但 env_key 为空，保存时会自动写入：\(defaultEnvKey(for: providerDraft.id))")
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
        appendChange("auth_mode", before?.authCommand.isEmpty == false ? ProviderAuthMode.command.rawValue : ProviderAuthMode.environment.rawValue, providerDraft.authMode.rawValue, to: &lines)
        appendChange("auth.command", before?.authCommand, providerDraft.authCommand, to: &lines)
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

    private func launchEnvironment(profileID: String) -> [String: String] {
        guard let profile = profiles.first(where: { $0.id == profileID }),
              let provider = providers[profile.modelProvider]
        else { return [:] }
        guard provider.authCommand.isEmpty else { return [:] }

        let token = ProviderTokenStore.load(providerID: provider.id, storeURL: providerTokenStoreURL) ?? ""
        let envKey = effectiveEnvKey(for: provider, forceDefault: !token.isEmpty)
        guard envKey.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else {
            return [:]
        }

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
        providerSourceIDs = Dictionary(uniqueKeysWithValues: providers.keys.map { ($0, $0) })
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

        chunks.append(renderProviders(activeProfileID: activeProfileID))

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

    private func renderProviders(activeProfileID: String? = nil) -> String {
        let activeProviderID = activeProfileID.flatMap { profileID in
            profiles.first(where: { $0.id == profileID })?.modelProvider
        }

        let originalSections = TOMLSupport.splitSections(originalText)

        return providers.keys.sorted().compactMap { key -> String? in
            guard let provider = providers[key] else { return nil }
            let sourceID = providerSourceIDs[key] ?? key
            let sourceRootName = "model_providers.\(sourceID)"
            let targetRootName = "model_providers.\(key)"
            let usesCommandAuth = !provider.authCommand.isEmpty
            let envKey = usesCommandAuth ? "" : effectiveEnvKey(for: provider, forceDefault: activeProviderID == key)

            var rootLines = originalSections.first(where: { $0.name == sourceRootName })?.lines
                ?? ["[\(targetRootName)]"]
            rootLines = renamedSectionHeader(in: rootLines, from: sourceRootName, to: targetRootName)
            var rootUpdates: [String: String?] = [
                "name": provider.name.isEmpty ? nil : TOMLSupport.quoted(provider.name),
                "base_url": provider.baseURL.isEmpty ? nil : TOMLSupport.quoted(provider.baseURL),
                "env_key": envKey.isEmpty ? nil : TOMLSupport.quoted(envKey),
                "wire_api": provider.wireAPI.isEmpty ? nil : TOMLSupport.quoted(provider.wireAPI)
            ]
            if usesCommandAuth {
                rootUpdates.updateValue(nil, forKey: "experimental_bearer_token")
                rootUpdates.updateValue(nil, forKey: "requires_openai_auth")
            }
            rootLines = TOMLSupport.updatingKeys(in: rootLines, values: rootUpdates)

            var chunks = [trimTrailingBlankLines(rootLines).joined(separator: "\n")]
            let childPrefix = sourceRootName + "."
            for section in originalSections where section.name?.hasPrefix(childPrefix) == true {
                guard let sectionName = section.name else { continue }
                if sectionName == sourceRootName + ".auth" { continue }
                let suffix = String(sectionName.dropFirst(sourceRootName.count))
                let targetName = targetRootName + suffix
                let lines = renamedSectionHeader(in: section.lines, from: sectionName, to: targetName)
                chunks.append(trimTrailingBlankLines(lines).joined(separator: "\n"))
            }

            if usesCommandAuth {
                let sourceAuthName = sourceRootName + ".auth"
                let targetAuthName = targetRootName + ".auth"
                var authLines = originalSections.first(where: { $0.name == sourceAuthName })?.lines
                    ?? ["[\(targetAuthName)]"]
                authLines = renamedSectionHeader(in: authLines, from: sourceAuthName, to: targetAuthName)
                authLines = TOMLSupport.updatingKeys(in: authLines, values: [
                    "command": TOMLSupport.quoted(provider.authCommand),
                    "args": provider.authArgs.isEmpty ? nil : TOMLSupport.quotedArray(provider.authArgs),
                    "cwd": provider.authCwd.isEmpty ? nil : TOMLSupport.quoted(provider.authCwd),
                    "timeout_ms": provider.authTimeoutMS.map(String.init),
                    "refresh_interval_ms": provider.authRefreshIntervalMS.map(String.init)
                ])
                chunks.append(trimTrailingBlankLines(authLines).joined(separator: "\n"))
            }

            return chunks.filter { !$0.isEmpty }.joined(separator: "\n\n")
        }
        .joined(separator: "\n\n")
    }

    private func providerRootID(for sectionName: String, sectionNames: Set<String>) -> String? {
        let prefix = "model_providers."
        guard sectionName.hasPrefix(prefix) else { return nil }
        let remainder = String(sectionName.dropFirst(prefix.count))
        for index in remainder.indices where remainder[index] == "." {
            let parent = prefix + String(remainder[..<index])
            if sectionNames.contains(parent) { return nil }
        }
        return remainder
    }

    private func renamedSectionHeader(in lines: [String], from oldName: String, to newName: String) -> [String] {
        guard oldName != newName else { return lines }
        return lines.map { line in
            line.trimmingCharacters(in: .whitespaces) == "[\(oldName)]" ? "[\(newName)]" : line
        }
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

    private func normalizedEnvKey(_ value: String?, providerID: String, hasToken: Bool) -> String {
        let cleanValue = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanValue.isEmpty, hasToken else { return cleanValue }
        return defaultEnvKey(for: providerID)
    }

    private func effectiveEnvKey(for provider: ModelProviderEntry, forceDefault: Bool = false) -> String {
        let cleanValue = provider.envKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanValue.isEmpty, forceDefault else { return cleanValue }
        return defaultEnvKey(for: provider.id)
    }

    private func defaultEnvKey(for providerID: String) -> String {
        let characters = providerID.uppercased().unicodeScalars.map { scalar -> Character in
            let value = scalar.value
            if (65...90).contains(value) || (48...57).contains(value) || value == 95 {
                return Character(scalar)
            }
            return "_"
        }
        var key = String(characters)
            .split(separator: "_")
            .joined(separator: "_")
        if key.isEmpty {
            key = "PROVIDER"
        }
        if key.first?.isNumber == true {
            key = "PROVIDER_\(key)"
        }
        if !key.hasSuffix("_API_KEY") {
            key += "_API_KEY"
        }
        return key
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
        let backupDirectory = configURLOverride == nil
            ? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".codex/backups")
            : configURL.deletingLastPathComponent().appendingPathComponent("backups")

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
        let sections = TOMLSupport.splitSections(text)
        let sectionNames = Set(sections.compactMap(\.name))
        for section in sections {
            guard let name = section.name,
                  let id = providerRootID(for: name, sectionNames: sectionNames)
            else { continue }
            let values = TOMLSupport.keyValues(in: section.lines)
            let authValues = sections.first(where: { $0.name == "model_providers.\(id).auth" })
                .map { TOMLSupport.keyValues(in: $0.lines) } ?? [:]
            parsedProviders[id] = ModelProviderEntry(
                id: id,
                name: values["name"] ?? "",
                baseURL: normalizedBaseURL(values["base_url"]),
                envKey: values["env_key"] ?? "",
                wireAPI: normalizedWireAPI(values["wire_api"]),
                authCommand: authValues["command"] ?? "",
                authArgs: TOMLSupport.stringArray(authValues["args"]),
                authCwd: authValues["cwd"] ?? "",
                authTimeoutMS: authValues["timeout_ms"].flatMap(Int.init),
                authRefreshIntervalMS: authValues["refresh_interval_ms"].flatMap(Int.init),
                queryParams: TOMLSupport.inlineStringTable(values["query_params"]),
                httpHeaders: TOMLSupport.inlineStringTable(values["http_headers"]),
                envHTTPHeaders: TOMLSupport.inlineStringTable(values["env_http_headers"])
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

        let backupDirectory = configURLOverride == nil
            ? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".codex/backups")
            : url.deletingLastPathComponent().appendingPathComponent("backups")
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
            return "需要先关闭当前 \(CodexAppLauncher.appDisplayName).app，才能切回官方默认配置。是否关闭并继续？"
        case let .profile(profileID):
            return "需要先关闭当前 \(CodexAppLauncher.appDisplayName).app，才能切换到 profile：\(profileID)。是否关闭并继续？"
        }
    }
}
