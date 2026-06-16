import SwiftUI

struct ProviderEditorView: View {
    @ObservedObject var store: ConfigStore
    @State private var showAdvanced = false
    @State private var revealToken = false

    var body: some View {
        Form {
            Section("Model Provider") {
                TextField("id", text: draftBinding(\.id))
                    .fontDesign(.monospaced)
                    .textFieldStyle(.roundedBorder)
                    .editableSurface()

                TextField("name", text: draftBinding(\.name))
                    .fontDesign(.monospaced)
                    .textFieldStyle(.roundedBorder)
                    .editableSurface()

                TextField("base_url", text: draftBinding(\.baseURL))
                    .fontDesign(.monospaced)
                    .textFieldStyle(.roundedBorder)
                    .editableSurface()

                Text("自定义 provider 的实际 API URL，例如 Ollama、LM Studio、vLLM 或代理服务。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("default catalog") {
                    Text(store.providerDraft.map { store.defaultCatalogPath(for: $0.id) } ?? "")
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                    TextField("env_key", text: draftBinding(\.envKey))
                        .fontDesign(.monospaced)
                        .textFieldStyle(.roundedBorder)
                        .editableSurface()

                    HStack(spacing: 8) {
                        if revealToken {
                            TextField("token", text: draftBinding(\.token))
                                .fontDesign(.monospaced)
                                .textFieldStyle(.roundedBorder)
                                .editableSurface()
                        } else {
                            SecureField("token", text: draftBinding(\.token))
                                .fontDesign(.monospaced)
                                .textFieldStyle(.roundedBorder)
                                .editableSurface()
                        }

                        Button {
                            revealToken.toggle()
                        } label: {
                            Image(systemName: revealToken ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                        .help(revealToken ? "隐藏 token" : "显示 token")

                        Button {
                            store.providerDraft?.token = ""
                            store.providerDraft?.hasStoredToken = false
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("清空 token")
                    }

                    Text("env_key 写入 config.toml；token 存到 macOS Keychain，并在 Fetch Models 和启动 Codex 时注入。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("wire_api", selection: draftBinding(\.wireAPI)) {
                    Text("responses").tag("responses")
                }
                .pickerStyle(.segmented)
                .editableSurface()
            }

            HStack {
                Button {
                    store.saveProviderDraft()
                } label: {
                    Label("Save Provider", systemImage: "square.and.arrow.down")
                }
                .disabled(store.providerDraft == nil)
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 250)
    }

    private func draftBinding(_ keyPath: WritableKeyPath<ProviderDraft, String>) -> Binding<String> {
        Binding {
            store.providerDraft?[keyPath: keyPath] ?? ""
        } set: { newValue in
            store.providerDraft?[keyPath: keyPath] = newValue
        }
    }
}
