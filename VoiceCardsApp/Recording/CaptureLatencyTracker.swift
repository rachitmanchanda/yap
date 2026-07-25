import Foundation
import OSLog

struct CaptureLatencySnapshot: Codable, Sendable {
    var recordingReadyMS: Int?
    var stopToTranscriptMS: Int?
    var rewriteMS: Int?
    var stopToInsertMS: Int?
    var measuredAt: Date

    static var latest: CaptureLatencySnapshot? {
        guard let defaults = UserDefaults(suiteName: AppGroup.identifier),
              let data = defaults.data(forKey: "latestCaptureLatency") else {
            return nil
        }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    var summary: String {
        [
            recordingReadyMS.map { "ready \($0) ms" },
            stopToTranscriptMS.map { "transcript \($0) ms" },
            rewriteMS.map { "rewrite \($0) ms" },
            stopToInsertMS.map { "insert \($0) ms" }
        ]
        .compactMap(\.self)
        .joined(separator: " · ")
    }
}

/// Persists the last real-device timing so speed work is driven by measurements, not animation feel.
@MainActor
final class CaptureLatencyTracker {
    private let logger = Logger(subsystem: "com.APP.VoiceCards", category: "CaptureLatency")
    private var snapshot = CaptureLatencySnapshot(measuredAt: .now)
    private var requestedAt: Date?
    private var stoppedAt: Date?
    private var rewriteStartedAt: Date?

    func captureRequested() {
        requestedAt = .now
        stoppedAt = nil
        rewriteStartedAt = nil
        snapshot = CaptureLatencySnapshot(measuredAt: .now)
    }

    func recordingStarted() {
        snapshot.recordingReadyMS = milliseconds(since: requestedAt)
        persist()
    }

    func recordingStopped() {
        stoppedAt = .now
    }

    func transcriptReady() {
        snapshot.stopToTranscriptMS = milliseconds(since: stoppedAt)
        persist()
    }

    func rewriteStarted() {
        rewriteStartedAt = .now
    }

    func rewriteFinished() {
        snapshot.rewriteMS = milliseconds(since: rewriteStartedAt)
        persist()
    }

    func textInserted() {
        snapshot.stopToInsertMS = milliseconds(since: stoppedAt)
        persist()
    }

    private func milliseconds(since date: Date?) -> Int? {
        date.map { max(0, Int(Date.now.timeIntervalSince($0) * 1_000)) }
    }

    private func persist() {
        snapshot.measuredAt = .now
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults(suiteName: AppGroup.identifier)?
                .set(data, forKey: "latestCaptureLatency")
        }
        logger.info("Capture latency: \(self.snapshot.summary, privacy: .public)")
    }
}
