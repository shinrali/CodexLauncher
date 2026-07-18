import SwiftUI

struct ProfileEditorView: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var discoveryStore: ModelDiscoveryStore
    @State private var fetchTask: Task<Void, Never>?
    @State private var showAdvanced = false

    var body: some View {
        Form {
            Section("Profile") {
                TextField("Profile name", text: draftBinding(\.id))
                    .textFieldStyle(.roundedBorder)
                    .editableSurface()

                ModelPicker(
                    title: "model",
                    selection: draftBinding(\.model),
                    models: discoveryStore.models
                )

                Picker("model_provider", selection: draftBinding(\.modelProvider)) {
                    ForEach(store.providers.keys.sorted(), id: \.self) { providerID in
                        Text(providerPickerTitle(for: providerID)).tag(providerID)
                    }
                    if !currentProviderID.isEmpty, store.providers[currentProviderID] == nil {
                        Text("\(currentProviderID) (missing)").tag(currentProviderID)
                    }
                }
                .editableSurface()
                .onChange(of: currentProviderID) { _, newValue in
                    if !newValue.isEmpty {
                        store.draft?.modelCatalogJSON = store.defaultCatalogPath(for: newValue)
                        store.draft?.openAIBaseURL = ""
                    }
                    store.selectProvider(newValue)
                    fetchModelsIfNeeded()
                }

                HStack {
                    Text("model_catalog_json")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(currentCatalogPath.isEmpty ? "选择 model_provider 后自动生成" : currentCatalogPath)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                TextField("openai_base_url", text: draftBinding(\.openAIBaseURL))
                    .fontDesign(.monospaced)
                    .textFieldStyle(.roundedBorder)
                    .editableSurface()
                Text("仅用于内置 openai provider 的 base URL override；自定义 provider 通常不用填。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Models") {
                HStack {
                    Button {
                        fetchModels()
                    } label: {
                        Label(discoveryStore.isLoading ? "Loading" : "Fetch Models", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(discoveryStore.isLoading || currentBaseURL.isEmpty)

                    if let error = discoveryStore.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if !discoveryStore.models.isEmpty {
                        Text("已加载 \(discoveryStore.models.count) 个模型")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
        .frame(minHeight: 330)
        .onAppear { fetchModelsIfNeeded() }
        .onDisappear { fetchTask?.cancel() }
        .onChange(of: currentBaseURL) { _, _ in fetchModelsIfNeeded() }
        .onChange(of: currentProviderFingerprint) { _, _ in fetchModelsIfNeeded() }
    }

    private func draftBinding(_ keyPath: WritableKeyPath<ProfileDraft, String>) -> Binding<String> {
        Binding {
            store.draft?[keyPath: keyPath] ?? ""
        } set: { newValue in
            store.draft?[keyPath: keyPath] = newValue
        }
    }

    private var currentBaseURL: String {
        if let provider = store.providers[currentProviderID], !provider.baseURL.isEmpty {
            return provider.baseURL
        }
        return store.draft?.openAIBaseURL ?? ""
    }

    private var currentProvider: ModelProviderEntry? {
        store.providerForDiscovery(currentProviderID)
    }

    private var currentProviderFingerprint: String {
        currentProvider.map(String.init(describing:)) ?? ""
    }

    private var currentProviderID: String {
        store.draft?.modelProvider ?? ""
    }

    private var currentCatalogPath: String {
        currentProviderID.isEmpty ? "" : store.defaultCatalogPath(for: currentProviderID)
    }

    private func providerPickerTitle(for providerID: String) -> String {
        guard let provider = store.providers[providerID] else { return providerID }
        let name = provider.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != providerID else { return providerID }
        return "\(name) (\(providerID))"
    }

    private func fetchModelsIfNeeded() {
        fetchTask?.cancel()
        let baseURL = currentBaseURL
        let token = currentToken
        guard var provider = currentProvider else { return }
        provider.baseURL = baseURL
        fetchTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await discoveryStore.fetchIfNeeded(provider: provider, tokenOverride: token)
        }
    }

    private func fetchModels() {
        fetchTask?.cancel()
        let baseURL = currentBaseURL
        let token = currentToken
        guard var provider = currentProvider else { return }
        provider.baseURL = baseURL
        fetchTask = Task {
            await discoveryStore.fetch(provider: provider, tokenOverride: token)
        }
    }

    private var currentToken: String {
        store.tokenForProvider(currentProviderID)
    }
}

private struct ModelPicker: View {
    let title: String
    @Binding var selection: String
    let models: [DiscoveredModel]

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .trailing)

            TextField(title, text: $selection)
                .fontDesign(.monospaced)
                .textFieldStyle(.roundedBorder)
                .editableSurface()

            Menu {
                if models.isEmpty {
                    Text("暂无模型")
                } else {
                    ForEach(models) { model in
                        Button {
                            selection = model.slug
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.displayName.isEmpty ? model.slug : model.displayName)
                                if !model.displayName.isEmpty, model.displayName != model.slug {
                                    Text(model.slug)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "chevron.down.circle")
            }
            .menuStyle(.button)
        }
    }
}
