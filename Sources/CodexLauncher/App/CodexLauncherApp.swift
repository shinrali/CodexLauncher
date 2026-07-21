import SwiftUI
import Darwin

@main
struct CodexLauncherApp: App {
    init() {
        let arguments = CommandLine.arguments
        guard arguments.count == 3, arguments[1] == ProviderTokenStore.helperArgument else { return }

        let providerID = arguments[2]
        guard let token = ProviderTokenStore.load(providerID: providerID), !token.isEmpty else {
            FileHandle.standardError.write(Data("CodexLauncher: no stored token for provider \(providerID)\n".utf8))
            exit(EXIT_FAILURE)
        }
        FileHandle.standardOutput.write(Data("\(token)\n".utf8))
        exit(EXIT_SUCCESS)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 980, minHeight: 660)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
