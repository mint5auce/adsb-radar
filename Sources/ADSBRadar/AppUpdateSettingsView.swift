import SwiftUI

struct CheckForAppUpdatesButton: View {
    let updater: AppUpdater

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!updater.canCheckForUpdates)
    }
}

struct AppUpdateSettingsView: View {
    @Bindable var updater: AppUpdater

    var body: some View {
        Section("App updates") {
            if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                Text("Version \(version)")
            }
            if updater.isEnabled {
                Toggle("Automatically check for updates", isOn: $updater.automaticallyChecksForUpdates)
                Toggle("Automatically download and install updates", isOn: $updater.automaticallyDownloadsUpdates)
                    .disabled(!updater.automaticallyChecksForUpdates)
                CheckForAppUpdatesButton(updater: updater)
                Text("Update preferences apply immediately. Downloads are provided by GitHub.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Updates are unavailable for this copy of the app.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
