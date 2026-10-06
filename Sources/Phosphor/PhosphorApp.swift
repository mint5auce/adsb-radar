import AppKit
import RadarCore
import SwiftUI

struct PhosphorApp: App {
    @NSApplicationDelegateAdaptor(RadarAppDelegate.self) private var delegate
    @State private var model: RadarModel
    @State private var updater: AppUpdater

    init() {
        _updater = State(initialValue: AppUpdater.forApplication())
        #if DEBUG
        if CommandLine.arguments.contains("--ui-fixture") {
            _model = State(initialValue: PreviewRenderer.interactiveModel(options: RadarLauncher.options))
            return
        }
        #endif
        _model = State(initialValue: RadarModel(options: RadarLauncher.options))
    }

    var body: some Scene {
        WindowGroup("Phosphor") {
            RadarWindow(model: model, updater: updater)
                .frame(minWidth: 800, minHeight: 560)
                .preferredColorScheme(.dark)
                .onAppear {
                    delegate.model = model
                    model.start()
                }
        }
        .defaultSize(width: 1200, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                CheckForAppUpdatesButton(updater: updater)
            }
        }
    }
}

@main
enum RadarLauncher {
    @MainActor static var options = RadarLaunchOptions()

    @MainActor static func main() {
        do { options = try RadarLaunchOptions(arguments: Array(CommandLine.arguments.dropFirst())) }
        catch { fputs("\(error)\n", stderr); exit(EXIT_FAILURE) }
        #if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--render-preview") ?? CommandLine.arguments.firstIndex(of: "--render-online-preview") ?? CommandLine.arguments.firstIndex(of: "--render-combined-preview") ?? CommandLine.arguments.firstIndex(of: "--render-local-enrichment-preview") ?? CommandLine.arguments.firstIndex(of: "--render-cache-preview"),
           CommandLine.arguments.indices.contains(index + 1) {
            NSApplication.shared.setActivationPolicy(.prohibited)
            let destination = CommandLine.arguments[index + 1]
            Task {
                do { try await PreviewRenderer.render(to: destination, options: options, online: CommandLine.arguments.contains("--render-online-preview"), combined: CommandLine.arguments.contains("--render-combined-preview"), localEnrichment: CommandLine.arguments.contains("--render-local-enrichment-preview"), cachePreview: CommandLine.arguments.contains("--render-cache-preview")) }
                catch { fputs("Preview failed: \(error)\n", stderr) }
                NSApplication.shared.terminate(nil)
            }
            NSApplication.shared.run()
            return
        }
        #endif
        PhosphorApp.main()
    }
}

@MainActor
final class RadarAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: RadarModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        Task {
            await model.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
