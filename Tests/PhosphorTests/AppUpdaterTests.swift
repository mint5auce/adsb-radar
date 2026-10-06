import Foundation
import Sparkle
import Testing
@testable import Phosphor

@MainActor
struct AppUpdaterTests {
    @Test func automaticUpdatePreferencesPersistWithoutStartingTheUpdater() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".app")
        let identifier = "dev.mint5auce.phosphor.tests." + UUID().uuidString
        defer {
            UserDefaults.standard.removePersistentDomain(forName: identifier)
            try? FileManager.default.removeItem(at: directory)
        }
        let contents = directory.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": identifier, "CFBundleName": "Update test",
            "CFBundleVersion": "2", "CFBundlePackageType": "APPL",
            "SUEnableAutomaticChecks": false, "SUAutomaticallyUpdate": false,
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let bundle = try #require(Bundle(url: directory))
        func makeUpdater() -> SPUUpdater {
            SPUUpdater(hostBundle: bundle, applicationBundle: bundle,
                       userDriver: SPUStandardUserDriver(hostBundle: bundle, delegate: nil), delegate: nil)
        }
        let sdk = makeUpdater()
        let updater = AppUpdater(updater: sdk)
        #expect(updater.isEnabled)
        #expect(!updater.canCheckForUpdates)
        updater.automaticallyChecksForUpdates = true
        updater.automaticallyDownloadsUpdates = true
        let restored = AppUpdater(updater: makeUpdater())
        #expect(restored.automaticallyChecksForUpdates)
        #expect(restored.automaticallyDownloadsUpdates)
        sdk.automaticallyChecksForUpdates = false
        #expect(!updater.automaticallyChecksForUpdates)
    }

    @Test func disabledUpdaterCannotCheckOrEnableAutomaticUpdates() {
        let updater = AppUpdater()
        updater.automaticallyChecksForUpdates = true
        updater.automaticallyDownloadsUpdates = true
        updater.checkForUpdates()
        #expect(!updater.isEnabled)
        #expect(!updater.canCheckForUpdates)
        #expect(!updater.automaticallyChecksForUpdates)
        #expect(!updater.automaticallyDownloadsUpdates)
    }
}
