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
                Section("Model") {
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

                Section("Tool Compatibility") {
                    LabeledContent("tool_mode") {
                        fieldPicker(
                            key: "tool_mode",
                            fallback: "direct",
                            options: [
                                ("Direct (Recommended)", "direct"),
                                ("Code Mode", "code_mode"),
                                ("Code Mode Only", "code_mode_only")
                            ]
                        )
                    }

                    LabeledContent("shell_type") {
                        fieldPicker(
                            key: "shell_type",
                            fallback: "default",
                            options: [
                                ("Default (Recommended)", "default"),
                                ("Local", "local"),
                                ("Unified Exec", "unified_exec"),
                                ("Shell Command", "shell_command"),
                                ("Disabled", "disabled")
                            ]
                        )
                    }

                    LabeledContent("apply_patch_tool_type") {
                        optionalFieldPicker(
                            key: "apply_patch_tool_type",
                            options: [
                                ("Null / Disabled (Recommended)", ""),
                                ("Freeform", "freeform")
                            ]
                        )
                    }

                    LabeledContent("multi_agent_version") {
                        fieldPicker(
                            key: "multi_agent_version",
                            fallback: "disabled",
                            options: [
                                ("Disabled (Recommended)", "disabled"),
                                ("V1", "v1"),
                                ("V2", "v2")
                            ]
                        )
                    }

                    Toggle("supports_parallel_tool_calls", isOn: boolField("supports_parallel_tool_calls"))
                    Toggle("supports_search_tool", isOn: boolField("supports_search_tool"))
                    Toggle("use_responses_lite", isOn: boolField("use_responses_lite"))

                    if stringValue("tool_mode", fallback: "direct") != "direct" || boolValue("use_responses_lite") {
                        Text("Code Mode 和 Responses Lite 会改变工具暴露及请求格式；第三方 OpenAI-compatible provider 应先使用 Direct 且关闭 Responses Lite。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    Button {
                        ModelCatalogStore.applyCompatibilityPreset(to: &model.rawFields)
                        onChange()
                    } label: {
                        Label("Restore Compatible Defaults", systemImage: "arrow.counterclockwise")
                    }
                }

                Section("Input And Output") {
                    Toggle("Image input", isOn: modalityField("image"))
                    Toggle("Audio input", isOn: modalityField("audio"))

                    LabeledContent("web_search_tool_type") {
                        fieldPicker(
                            key: "web_search_tool_type",
                            fallback: "text",
                            options: [
                                ("Text", "text"),
                                ("Text and Image", "text_and_image")
                            ]
                        )
                    }

                    LabeledContent("truncation_policy.mode") {
                        nestedStringFieldPicker(
                            parentKey: "truncation_policy",
                            key: "mode",
                            fallback: "bytes",
                            options: [
                                ("Bytes (Recommended)", "bytes"),
                                ("Tokens", "tokens")
                            ]
                        )
                    }
                }
            }
            .formStyle(.grouped)
            .onChange(of: model.displayName) { _, _ in onChange() }
            .onChange(of: model.description) { _, _ in onChange() }
            .onChange(of: model.contextWindow) { _, _ in onChange() }
            .onChange(of: model.maxContextWindow) { _, _ in onChange() }
        }
    }

    @ViewBuilder
    private func fieldPicker(
        key: String,
        fallback: String,
        options: [(String, String)]
    ) -> some View {
        Picker(key, selection: stringField(key, fallback: fallback)) {
            ForEach(options, id: \.1) { label, value in
                Text(label).tag(value)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(minWidth: 180)
    }

    @ViewBuilder
    private func optionalFieldPicker(
        key: String,
        options: [(String, String)]
    ) -> some View {
        Picker(key, selection: optionalStringField(key)) {
            ForEach(options, id: \.1) { label, value in
                Text(label).tag(value)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(minWidth: 180)
    }

    @ViewBuilder
    private func nestedStringFieldPicker(
        parentKey: String,
        key: String,
        fallback: String,
        options: [(String, String)]
    ) -> some View {
        Picker(key, selection: nestedStringField(parentKey: parentKey, key: key, fallback: fallback)) {
            ForEach(options, id: \.1) { label, value in
                Text(label).tag(value)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(minWidth: 180)
    }

    private func stringValue(_ key: String, fallback: String) -> String {
        model.rawFields[key] as? String ?? fallback
    }

    private func boolValue(_ key: String) -> Bool {
        model.rawFields[key] as? Bool ?? false
    }

    private func stringField(_ key: String, fallback: String) -> Binding<String> {
        Binding {
            stringValue(key, fallback: fallback)
        } set: { newValue in
            model.rawFields[key] = newValue
            onChange()
        }
    }

    private func optionalStringField(_ key: String) -> Binding<String> {
        Binding {
            model.rawFields[key] as? String ?? ""
        } set: { newValue in
            model.rawFields[key] = newValue.isEmpty ? NSNull() : newValue
            onChange()
        }
    }

    private func boolField(_ key: String) -> Binding<Bool> {
        Binding {
            boolValue(key)
        } set: { newValue in
            model.rawFields[key] = newValue
            onChange()
        }
    }

    private func modalityField(_ modality: String) -> Binding<Bool> {
        Binding {
            let modalities = model.rawFields["input_modalities"] as? [String] ?? ["text"]
            return modalities.contains(modality)
        } set: { enabled in
            var modalities = model.rawFields["input_modalities"] as? [String] ?? ["text"]
            if !modalities.contains("text") {
                modalities.insert("text", at: 0)
            }
            if enabled {
                if !modalities.contains(modality) {
                    modalities.append(modality)
                }
            } else {
                modalities.removeAll { $0 == modality }
            }
            model.rawFields["input_modalities"] = modalities
            onChange()
        }
    }

    private func nestedStringField(
        parentKey: String,
        key: String,
        fallback: String
    ) -> Binding<String> {
        Binding {
            let dictionary = model.rawFields[parentKey] as? [String: Any]
            return dictionary?[key] as? String ?? fallback
        } set: { newValue in
            var dictionary = model.rawFields[parentKey] as? [String: Any] ?? [:]
            dictionary[key] = newValue
            model.rawFields[parentKey] = dictionary
            onChange()
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
