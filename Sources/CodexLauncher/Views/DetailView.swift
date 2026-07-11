import SwiftUI

struct DetailView: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var catalogStore: ModelCatalogStore
    @StateObject private var discoveryStore = ModelDiscoveryStore()
    @State private var lastCatalogPath = ""
    @State private var savePreviewSummary: String?

    var body: some View {
        if store.isOfficialSelected {
            OfficialCodexView(store: store)
        } else if store.isProviderRouteSelected {
            ProviderRouteView(store: store)
        } else if store.draft == nil {
            ContentUnavailableView(
                "选择一个 Profile",
                systemImage: "person.crop.circle.badge.plus",
                description: Text("从左侧选择或新建一个 Codex profile。")
            )
        } else {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        ProfileEditorView(store: store, discoveryStore: discoveryStore)
                        Divider()
                        ModelCatalogView(store: store, catalogStore: catalogStore, discoveryStore: discoveryStore)
                    }
                }
            }
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        savePreviewSummary = store.profileChangeSummary(catalogModels: catalogStore.models)
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    .keyboardShortcut("s", modifiers: [.command])

                    Button {
                        store.materializeSelectedProfileAndLaunch()
                    } label: {
                        Label("Run Codex", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .onAppear { reloadCatalogIfNeeded(force: true) }
            .onChange(of: store.selectedProfileID) { _, _ in reloadCatalogIfNeeded(force: true) }
            .onChange(of: store.draft?.modelProvider ?? "") { _, _ in reloadCatalogIfNeeded(force: false) }
            .sheet(item: Binding(
                get: { savePreviewSummary.map { SavePreviewPayload(summary: $0) } },
                set: { if $0 == nil { savePreviewSummary = nil } }
            )) { payload in
                SavePreviewView(
                    title: "Review Profile Changes",
                    summary: payload.summary,
                    confirmTitle: "Save Profile",
                    onCancel: { savePreviewSummary = nil },
                    onConfirm: {
                        store.saveDraft()
                        reloadCatalogIfNeeded(force: true)
                        savePreviewSummary = nil
                    }
                )
            }
        }
    }

    private func reloadCatalogIfNeeded(force: Bool) {
        let path = store.catalogPathForCurrentDraft()
        guard force || path != lastCatalogPath else { return }
        lastCatalogPath = path
        catalogStore.load(path: path)
    }
}

private struct ProviderRouteView: View {
    @ObservedObject var store: ConfigStore
    @State private var savePreviewSummary: String?

    var body: some View {
        Group {
            if store.providerDraft == nil {
                ContentUnavailableView(
                    "选择一个 Model Provider",
                    systemImage: "network",
                    description: Text("从左侧选择 provider 后可以编辑 base_url、env_key 和 wire_api。")
                )
            } else {
                ProviderEditorView(store: store)
            }
        }
        .id(store.selectedProviderRouteID ?? "")
        .onAppear { store.ensureProviderRouteDraft() }
        .onChange(of: store.selectedProviderRouteID ?? "") { _, _ in store.ensureProviderRouteDraft() }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    savePreviewSummary = store.providerChangeSummary()
                } label: {
                    Label("Save Provider", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(store.providerDraft == nil)
            }
        }
        .sheet(item: Binding(
            get: { savePreviewSummary.map { SavePreviewPayload(summary: $0) } },
            set: { if $0 == nil { savePreviewSummary = nil } }
        )) { payload in
            SavePreviewView(
                title: "Review Provider Changes",
                summary: payload.summary,
                confirmTitle: "Save Provider",
                onCancel: { savePreviewSummary = nil },
                onConfirm: {
                    store.saveProviderDraft()
                    savePreviewSummary = nil
                }
            )
        }
    }
}

private struct SavePreviewPayload: Identifiable {
    var id = UUID()
    var summary: String
}

private struct OfficialCodexView: View {
    @ObservedObject var store: ConfigStore

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "app.badge")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("官方版本")
                .font(.title2)
                .fontWeight(.semibold)

            Text("直接启动 \(CodexAppLauncher.appURL.path)，不切换 profile，也不写入 active model 配置。")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)

            Button {
                store.materializeSelectedProfileAndLaunch()
            } label: {
                Label("运行官方 Codex", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
