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
                    Picker("Authentication", selection: authModeBinding) {
                        Text("Local Token").tag(ProviderAuthMode.localFile)
                        Text("Environment").tag(ProviderAuthMode.environment)
                        Text("Command").tag(ProviderAuthMode.command)
                    }
                    .pickerStyle(.segmented)

                    if store.providerDraft?.authMode == .command {
                        TextField("command", text: draftBinding(\.authCommand))
                            .fontDesign(.monospaced)
                            .textFieldStyle(.roundedBorder)
                            .editableSurface()

                        TextField("cwd (optional)", text: draftBinding(\.authCwd))
                            .fontDesign(.monospaced)
                            .textFieldStyle(.roundedBorder)
                            .editableSurface()

                        TextEditor(text: draftBinding(\.authArgs))
                            .fontDesign(.monospaced)
                            .frame(minHeight: 70)
                            .overlay(alignment: .topLeading) {
                                if store.providerDraft?.authArgs.isEmpty != false {
                                    Text("args：每行一个参数")
                                        .foregroundStyle(.tertiary)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 8)
                                        .allowsHitTesting(false)
                                }
                            }
                            .editableSurface()

                        HStack {
                            TextField("timeout_ms", text: draftBinding(\.authTimeoutMS))
                                .fontDesign(.monospaced)
                                .textFieldStyle(.roundedBorder)
                            TextField("refresh_interval_ms", text: draftBinding(\.authRefreshIntervalMS))
                                .fontDesign(.monospaced)
                                .textFieldStyle(.roundedBorder)
                        }

                        Text("Codex 执行 command 并从 stdout 读取 bearer token；不要同时配置 env_key。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if store.providerDraft?.authMode == .localFile {
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

                        Text("推荐模式。token 保存在 CodexLauncher 自己的本地 secrets JSON，不使用 Keychain；Codex 通过本地 helper 按需读取，不再依赖 ChatGPT.app 继承环境变量。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        TextField("env_key (optional)", text: draftBinding(\.envKey))
                            .fontDesign(.monospaced)
                            .textFieldStyle(.roundedBorder)
                            .editableSurface()

                        Text("仅保存环境变量名，不保存 token；无需认证的 provider 可留空。需要认证时，请确保变量存在于 ChatGPT.app 的运行环境中。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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

    private var authModeBinding: Binding<ProviderAuthMode> {
        Binding {
            store.providerDraft?.authMode ?? .localFile
        } set: { newValue in
            store.providerDraft?.authMode = newValue
        }
    }
}
