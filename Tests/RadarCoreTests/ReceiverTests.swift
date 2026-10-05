import Foundation
import Testing
@testable import RadarCore

struct ReceiverTests {
    @Test func missingDongleProducesAnActionableReceptionStatus() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("missing-dongle")
        try "#!/bin/sh\necho 'FATAL: rtlsdr: no supported devices found.' >&2\nexit 1\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let source = ReadsbReceiver(executable: executable)
        await source.start(location: nil)
        var reading = await source.poll()
        for _ in 0..<50 {
            if case .failed = reading.status { break }
            try await Task.sleep(for: .milliseconds(20))
            reading = await source.poll()
        }
        #expect(reading.status == .failed("No RTL-SDR receiver found. Connect the dongle and retry."))
        await source.stop()
    }

    @Test func receivesSnapshotsAndCanStopAndRestartItsOwnedProcess() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("receiver")
        try """
        #!/bin/sh
        for argument in "$@"; do
          case "$argument" in --write-json=*) output="${argument#--write-json=}" ;; esac
        done
        printf '%s' '{"now":1000,"aircraft":[{"hex":"abc123","lat":52,"lon":-2,"seen_pos":0}]}' > "$output/aircraft.json"
        exec /bin/sleep 30
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let source = ReadsbReceiver(executable: executable)
        await source.start(location: nil)
        var reading = await source.poll()
        for _ in 0..<50 where reading.snapshot == nil {
            try await Task.sleep(for: .milliseconds(20))
            reading = await source.poll()
        }
        #expect(reading.status == .receiving)
        #expect(reading.snapshot?.observations.first?.address == "abc123")
        await source.stop()
        #expect(await source.poll().status == .stopped)
        await source.start(location: nil)
        try await Task.sleep(for: .milliseconds(100))
        #expect(await source.poll().status == .receiving)
        await source.stop()
    }
}
