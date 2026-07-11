import AppKit
import Foundation

enum CodexAppLauncher {
    private static let supportedAppURLs = [
        URL(fileURLWithPath: "/Applications/ChatGPT.app"),
        URL(fileURLWithPath: "/Applications/Codex.app")
    ]
    static let bundleIdentifier = "com.openai.codex"

    static var appURL: URL {
        supportedAppURLs.first { FileManager.default.fileExists(atPath: $0.path) }
            ?? supportedAppURLs[0]
    }

    static var appDisplayName: String {
        appURL.deletingPathExtension().lastPathComponent
    }

    static var isRunning: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty == false
    }

    static func launch(restartRunningApp: Bool = false, environment: [String: String] = [:]) throws {
        guard FileManager.default.fileExists(atPath: appURL.path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: appURL.path])
        }

        if restartRunningApp {
            terminateRunningApps()
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        if !environment.isEmpty {
            configuration.environment = ProcessInfo.processInfo.environment.merging(environment) { _, injected in injected }
        }
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }

    private static func terminateRunningApps() {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        guard !runningApps.isEmpty else { return }

        for app in runningApps {
            app.terminate()
        }

        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            let stillRunning = runningApps.contains { !$0.isTerminated }
            if !stillRunning { return }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }

        for app in runningApps where !app.isTerminated {
            app.forceTerminate()
        }
    }
}
