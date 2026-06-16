import SwiftUI

struct ContentView: View {
    @StateObject private var configStore = ConfigStore()
    @StateObject private var catalogStore = ModelCatalogStore()

    var body: some View {
        NavigationSplitView {
            SidebarView(store: configStore)
        } detail: {
            DetailView(store: configStore, catalogStore: catalogStore)
        }
        .alert("Codex Launcher", isPresented: Binding(
            get: { configStore.errorMessage != nil },
            set: { if !$0 { configStore.errorMessage = nil } }
        )) {
            Button("OK") { configStore.errorMessage = nil }
        } message: {
            Text(configStore.errorMessage ?? "")
        }
        .alert(item: $configStore.pendingLaunchConfirmation) { confirmation in
            Alert(
                title: Text(confirmation.title),
                message: Text(confirmation.message),
                primaryButton: .destructive(Text("关闭并继续")) {
                    configStore.confirmPendingLaunch()
                },
                secondaryButton: .cancel(Text("取消")) {
                    configStore.cancelPendingLaunch()
                }
            )
        }
    }
}
