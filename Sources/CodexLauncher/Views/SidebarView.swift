import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: ConfigStore
    @State private var pendingDelete: SidebarDeleteTarget?

    var body: some View {
        VStack(spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SidebarCard(title: "Official", systemImage: "app.badge", addAction: nil) {
                        SidebarButton(
                            isSelected: store.selectedProfileID == ConfigStore.officialProfileID,
                            action: { store.select(ConfigStore.officialProfileID) }
                        ) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("官方版本")
                                        .lineLimit(1)
                                    Text("不使用任何 profile")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            } icon: {
                                Image(systemName: "app.badge")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }

                    SidebarCard(title: "Profiles", systemImage: "person.crop.circle", addAction: store.addProfile) {
                        ForEach(store.profiles) { profile in
                            SidebarButton(
                                isSelected: store.selectedProfileID == profile.id,
                                action: { store.select(profile.id) }
                            ) {
                                ProfileSidebarRow(profile: profile) {
                                    pendingDelete = SidebarDeleteTarget(kind: .profile, targetID: profile.id)
                                }
                            }
                        }
                    }

                    SidebarCard(title: "Model Providers", systemImage: "network", addAction: store.addProvider) {
                        ForEach(store.providers.keys.sorted(), id: \.self) { providerID in
                            SidebarButton(
                                isSelected: store.selectedProfileID == ConfigStore.providerSelectionPrefix + providerID,
                                action: { store.selectProviderRoute(providerID) }
                            ) {
                                ProviderSidebarRow(provider: store.providers[providerID]) {
                                    pendingDelete = SidebarDeleteTarget(kind: .provider, targetID: providerID)
                                }
                            }
                        }
                    }

                }
                .padding(10)
            }
        }
        .background(.regularMaterial)
        .navigationTitle("Codex")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    store.reload()
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
            }
        }
        .confirmationDialog(
            "确认删除",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { target in
            Button("删除 \(target.targetID)", role: .destructive) {
                switch target.kind {
                case .profile:
                    store.deleteProfile(id: target.targetID)
                case .provider:
                    store.deleteProvider(id: target.targetID)
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) {
                pendingDelete = nil
            }
        } message: { target in
            Text(target.kind == .profile ? "这个 profile 会被移除。" : "引用这个 provider 的 profile 会自动改到剩余 provider。")
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.configURL.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if !store.statusMessage.isEmpty {
                    Text(store.statusMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(10)
        }
    }
}

private struct SidebarCard<Content: View>: View {
    let title: String
    let systemImage: String
    let addAction: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                if let addAction {
                    Button(action: addAction) {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)

            VStack(spacing: 2) {
                content
            }
            .padding(6)
            .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct SidebarButton<Content: View>: View {
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        Button(action: action) {
            content
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    isSelected ? Color.accentColor.opacity(0.18) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct ProviderSidebarRow: View {
    let provider: ModelProviderEntry?
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(primaryTitle)
                        .lineLimit(1)
                    if let provider, !provider.name.isEmpty, provider.name != provider.id {
                        Text(provider.id)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let baseURL = provider?.baseURL, !baseURL.isEmpty {
                        Text(baseURL)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } icon: {
                Image(systemName: "network")
                    .foregroundStyle(.blue)
            }
            Spacer()
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private var primaryTitle: String {
        guard let provider else { return "Unknown" }
        return provider.name.isEmpty ? provider.id : provider.name
    }
}

private struct ProfileSidebarRow: View {
    let profile: ProfileEntry
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.id)
                        .lineLimit(1)
                    if !profile.model.isEmpty {
                        Text(profile.model)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } icon: {
                Image(systemName: iconName)
                    .foregroundStyle(.blue)
            }
            Spacer()
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private var iconName: String {
        if profile.id.contains("local") { return "desktopcomputer" }
        if profile.id.contains("vllm") { return "server.rack" }
        if profile.id.contains("ollama") { return "cpu" }
        return "person.crop.circle"
    }
}

private struct SidebarDeleteTarget: Identifiable {
    enum Kind {
        case profile
        case provider
    }

    var kind: Kind
    var targetID: String

    var id: String { "\(kind)-\(targetID)" }
}
