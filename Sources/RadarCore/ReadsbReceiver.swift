import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum ReceptionStatus: Equatable, Sendable {
    case stopped, starting, waiting, receiving
    case failed(String)
}

public enum ReceptionFailureReason: Equatable, Sendable {
    case receiverNotFound
}

public struct ReceptionReading: Sendable {
    public let status: ReceptionStatus
    public let snapshot: ReceiverSnapshot?
    public let failureReason: ReceptionFailureReason?

    public init(status: ReceptionStatus, snapshot: ReceiverSnapshot? = nil, failureReason: ReceptionFailureReason? = nil) {
        self.status = status
        self.snapshot = snapshot
        self.failureReason = failureReason
    }
}

public protocol AircraftDataSource: Sendable {
    func start(location: GeographicCoordinate?) async
    func poll() async -> ReceptionReading
    func stop() async
}

/// Owns a single decoder and its private snapshot directory; never attaches to other receivers.
public actor ReadsbReceiver: AircraftDataSource {
    private let executableOverride: URL?
    private var process: Process?
    private var directory: URL?
    private var log: FileHandle?
    private var startedAt: Date?
    private var failure: ReceptionReading?
    private var generation = 0

    public init(executable: URL? = nil) {
        self.executableOverride = executable
    }

    public func start(location: GeographicCoordinate?) async {
        generation += 1
        let request = generation
        await stopOwnedProcess()
        guard request == generation else { return }
        failure = nil
        guard let executable = executableOverride ?? Self.findExecutable() else {
            failure = ReceptionReading(status: .failed("readsb is not installed. Install it with Homebrew, then retry."))
            return
        }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("phosphor-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let logURL = output.appendingPathComponent("receiver.log")
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
            let handle = try FileHandle(forWritingTo: logURL)
            let child = Process()
            child.executableURL = executable
            var arguments = ["--device-type=rtlsdr", "--quiet", "--write-json=\(output.path)", "--write-json-every=1"]
            if let location {
                arguments += ["--lat=\(location.latitude)", "--lon=\(location.longitude)"]
            }
            child.arguments = arguments
            child.standardOutput = FileHandle.nullDevice
            child.standardError = handle
            process = child
            directory = output
            log = handle
            try child.run()
            startedAt = .now
        } catch {
            failure = ReceptionReading(status: .failed("Cannot start reception: \(error.localizedDescription)"))
            await stopOwnedProcess()
        }
    }

    public func poll() async -> ReceptionReading {
        if let failure { return failure }
        guard let process, let directory else { return ReceptionReading(status: .stopped, snapshot: nil) }
        guard process.isRunning else {
            let diagnostic = Self.readDiagnostic(directory.appendingPathComponent("receiver.log"))
            let reading = Self.failureReading(diagnostic)
            failure = reading
            return reading
        }
        let file = directory.appendingPathComponent("aircraft.json")
        guard FileManager.default.fileExists(atPath: file.path) else {
            let status: ReceptionStatus = Date.now.timeIntervalSince(startedAt ?? .now) > 8
                ? .failed("No receiver snapshots. Check the dongle and retry.") : .starting
            return ReceptionReading(status: status, snapshot: nil)
        }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            if let modified = attributes[.modificationDate] as? Date, Date.now.timeIntervalSince(modified) > 5 {
                return ReceptionReading(status: .failed("Receiver updates have stopped. Retry reception."), snapshot: nil)
            }
            let snapshot = try ReceiverSnapshot.decode(Data(contentsOf: file))
            return ReceptionReading(status: snapshot.observations.isEmpty ? .waiting : .receiving, snapshot: snapshot)
        } catch {
            return ReceptionReading(status: .failed("Cannot read receiver updates. Retry reception."), snapshot: nil)
        }
    }

    public func stop() async {
        generation += 1
        failure = nil
        await stopOwnedProcess()
    }

    private func stopOwnedProcess() async {
        let child = process
        let output = directory
        let handle = log
        process = nil
        directory = nil
        log = nil
        startedAt = nil
        if let child, child.isRunning {
            child.terminate()
            let deadline = Date.now.addingTimeInterval(2)
            while child.isRunning, Date.now < deadline {
                try? await Task.sleep(for: .milliseconds(25))
            }
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            // Reap only our child after termination, before removing its output directory.
            child.waitUntilExit()
        }
        try? handle?.close()
        if let output { try? FileManager.default.removeItem(at: output) }
    }

    private static func readDiagnostic(_ url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: end > 2000 ? end - 2000 : 0)
        let data = (try? handle.readToEnd()) ?? Data()
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
        return lines.suffix(3).joined(separator: " · ")
    }

    private static func failureReading(_ diagnostic: String) -> ReceptionReading {
        let text = diagnostic.lowercased()
        if text.contains("no supported devices") {
            return ReceptionReading(status: .failed("No RTL-SDR receiver found. Connect the dongle and retry."), failureReason: .receiverNotFound)
        }
        if text.contains("usb_claim_interface") || text.contains("resource busy") {
            return ReceptionReading(status: .failed("RTL-SDR receiver is busy. Close other SDR applications and retry."))
        }
        return ReceptionReading(status: .failed(diagnostic.isEmpty ? "Receiver stopped. Check the dongle and retry." : "Receiver stopped: \(diagnostic)"))
    }

    private static func findExecutable() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        let paths = [environment["READSB_PATH"], "/opt/homebrew/bin/readsb", "/usr/local/bin/readsb"]
            .compactMap { $0 } + (environment["PATH"] ?? "").split(separator: ":").map { "\($0)/readsb" }
        return paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map { URL(fileURLWithPath: $0) }
    }
}
