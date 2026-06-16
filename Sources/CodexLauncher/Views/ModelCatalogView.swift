import SwiftUI

struct ModelCatalogView: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var catalogStore: ModelCatalogStore
    @ObservedObject var discoveryStore: ModelDiscoveryStore
    @State private var showAllModels = false
    @State private var autosaveTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Model Catalog JSON", systemImage: "curlybraces.square")
                    .font(.headline)

                Spacer()

                Button {
                    showAllModels.toggle()
                } label: {
                    Label(showAllModels ? "Hide All" : "Show All", systemImage: "list.bullet")
                }

                Button {
                    catalogStore.importModels(discoveryStore.models)
                    let path = catalogPath
                    if !path.isEmpty {
                        catalogStore.save(path: path)
                    }
                } label: {
                    Label("Import All", systemImage: "square.and.arrow.down.on.square")
                }
                .disabled(discoveryStore.models.isEmpty || catalogPath.isEmpty)

                Button {
                    let path = catalogPath
                    if !path.isEmpty {
                        catalogStore.save(path: path)
                    }
                } label: {
                    Label("Save JSON", systemImage: "doc.badge.gearshape")
                }
                .disabled(catalogPath.isEmpty)
            }

            if let error = catalogStore.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if catalogPath.isEmpty {
                ContentUnavailableView(
                    "没有模型 JSON 路径",
                    systemImage: "doc.badge.plus",
                    description: Text("选择 model_provider 后会自动使用对应的模型 JSON。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if currentModelSlug.isEmpty {
                ContentUnavailableView(
                    "没有选择模型",
                    systemImage: "cube.transparent",
                    description: Text("先在 profile 里选择或输入 model，再编辑对应 JSON 条目。")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                if let modelBinding = catalogStore.bindingForModel(slug: currentModelSlug) {
                    CurrentModelJSONEditor(model: modelBinding, onChange: scheduleAutosave)
                } else {
                    ContentUnavailableView {
                        Label("JSON 里没有这个模型", systemImage: "doc.badge.plus")
                    } description: {
                        Text("当前 profile model 是 \(currentModelSlug)，但 model_catalog_json 里没有同 slug 条目。")
                    } actions: {
                        Button {
                            createCurrentModelEntry()
                        } label: {
                            Label("创建 JSON 条目", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                }

                if showAllModels {
                    Divider()
                    AllModelsList(catalogStore: catalogStore)
                        .frame(minHeight: 180)
                }
            }
        }
        .padding()
        .onDisappear {
            autosaveTask?.cancel()
        }
    }

    private var currentModelSlug: String {
        store.draft?.model.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var catalogPath: String {
        store.catalogPathForCurrentDraft()
    }

    private func createCurrentModelEntry() {
        let discoveredName = discoveryStore.models.first(where: { $0.slug == currentModelSlug })?.displayName
        catalogStore.ensureModel(slug: currentModelSlug, displayName: discoveredName)
        let path = catalogPath
        if !path.isEmpty {
            catalogStore.save(path: path)
        }
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        let path = catalogPath
        guard !path.isEmpty else { return }

        autosaveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                catalogStore.save(path: path)
            }
        }
    }
}

private struct CurrentModelJSONEditor: View {
    @Binding var model: CatalogModel
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("当前 JSON 条目")
                    .font(.headline)
                Spacer()
                Text(model.slug)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
            }

            Form {
                TextField("display_name", text: $model.displayName)
                TextField("description", text: $model.description, axis: .vertical)
                    .lineLimit(1...3)

                HStack {
                    Text("context_window")
                    Spacer()
                    ContextWindowField(title: "context_window", value: $model.contextWindow)
                        .frame(width: 140)
                }

                HStack {
                    Text("max_context_window")
                    Spacer()
                    ContextWindowField(title: "max_context_window", value: $model.maxContextWindow)
                        .frame(width: 140)
                }
            }
            .formStyle(.grouped)
            .onChange(of: model.displayName) { _, _ in onChange() }
            .onChange(of: model.description) { _, _ in onChange() }
            .onChange(of: model.contextWindow) { _, _ in onChange() }
            .onChange(of: model.maxContextWindow) { _, _ in onChange() }
        }
    }
}

private struct AllModelsList: View {
    @ObservedObject var catalogStore: ModelCatalogStore

    var body: some View {
        List {
            ForEach(catalogStore.models) { model in
                HStack {
                    Text(model.slug)
                        .fontDesign(.monospaced)
                    Spacer()
                    Text(model.displayName)
                        .foregroundStyle(.secondary)
                    Button(role: .destructive) {
                        catalogStore.models.removeAll { $0.id == model.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.inset)
    }
}

private struct ContextWindowField: View {
    let title: String
    @Binding var value: Int?
    @State private var isCustom = false
    @State private var customText = ""

    private let commonValues = [
        ("4k", 4096),
        ("8k", 8192),
        ("16k", 16384),
        ("32k", 32768),
        ("64k", 65536),
        ("96k", 98304),
        ("128k", 131072),
        ("256k", 262144)
    ]

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Picker(title, selection: Binding(
                get: {
                    if isCustom { return -1 }
                    guard let value else { return 0 }
                    return commonValues.contains(where: { $0.1 == value }) ? value : -1
                },
                set: { newValue in
                    if newValue == -1 {
                        isCustom = true
                        customText = value.map(String.init) ?? ""
                    } else {
                        isCustom = false
                        customText = ""
                        value = newValue == 0 ? nil : newValue
                    }
                }
            )) {
                Text("空").tag(0)
                ForEach(commonValues, id: \.1) { label, size in
                    Text(label).tag(size)
                }
                Text("自定义").tag(-1)
            }
            .labelsHidden()
            .pickerStyle(.menu)

            if isCustom {
                TextField(title, text: customBinding)
                    .fontDesign(.monospaced)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .onAppear {
            syncCustomState()
        }
        .onChange(of: value) { _, _ in
            syncCustomState()
        }
    }

    private var customBinding: Binding<String> {
        Binding {
            customText
        } set: { newValue in
            customText = newValue
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if let number = Int(trimmed), number > 0 {
                value = number
            }
        }
    }

    private func syncCustomState() {
        guard let value else {
            if !isCustom {
                customText = ""
            }
            return
        }

        if commonValues.contains(where: { $0.1 == value }) {
            if !isCustom {
                customText = ""
            }
        } else {
            isCustom = true
            customText = String(value)
        }
    }
}
