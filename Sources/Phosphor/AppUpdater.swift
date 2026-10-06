import Combine
import Foundation
import Observation
import Sparkle

@MainActor @Observable
final class AppUpdater {
    @ObservationIgnored private let updater: SPUUpdater?
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var subscriptions: Set<AnyCancellable> = []
    private(set) var canCheckForUpdates = false
    private var automaticChecks = false
    private var automaticDownloads = false

    var isEnabled: Bool { updater != nil }
    var automaticallyChecksForUpdates: Bool {
        get { automaticChecks }
        set { updater?.automaticallyChecksForUpdates = newValue }
    }
    var automaticallyDownloadsUpdates: Bool {
        get { automaticDownloads }
        set { updater?.automaticallyDownloadsUpdates = newValue }
    }

    // Supplying an unstarted Sparkle updater lets tests exercise real preferences without network access.
    init(updater: SPUUpdater? = nil) {
        self.updater = updater
        guard let updater else { return }
        updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
            .store(in: &subscriptions)
        updater.publisher(for: \.automaticallyChecksForUpdates)
            .sink { [weak self] in self?.automaticChecks = $0 }
            .store(in: &subscriptions)
        updater.publisher(for: \.automaticallyDownloadsUpdates)
            .sink { [weak self] in self?.automaticDownloads = $0 }
            .store(in: &subscriptions)
    }

    static func forApplication() -> AppUpdater {
        #if DEBUG
        return AppUpdater()
        #else
        guard Bundle.main.bundleURL.pathExtension == "app",
              Bundle.main.object(forInfoDictionaryKey: "PhosphorUpdatesEnabled") as? Bool == true,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return AppUpdater()
        }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        let model = AppUpdater(updater: controller.updater)
        model.controller = controller
        controller.startUpdater()
        return model
        #endif
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        updater?.checkForUpdates()
    }
}
