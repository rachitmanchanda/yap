@preconcurrency import AVFoundation
import Foundation
import Observation

enum AudioRecorderError: LocalizedError {
    case permissionDenied
    case tooShort
    case unableToStart

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "Microphone permission is off. Enable it in Settings to record."
        case .tooShort: "That recording was too short. Try speaking for at least one second."
        case .unableToStart: "The recorder could not start."
        }
    }
}

@MainActor
@Observable
final class AudioRecorder {
    private(set) var elapsed: TimeInterval = 0
    private(set) var level: Float = 0
    private(set) var isRecording = false
    var onMaximumDuration: (() -> Void)?
    var onPCMData: (@Sendable (Data) -> Void)?

    private var engine: AVAudioEngine?
    private var pipeline: AudioCapturePipeline?
    private var meterTask: Task<Void, Never>?
    private var startedAt: Date?
    private(set) var currentURL: URL?
    private let maximumDuration: TimeInterval = 180

    func requestPermissionAndStart() async throws {
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else { throw AudioRecorderError.permissionDenied }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .spokenAudio, options: [])
        try session.setPreferredSampleRate(16_000)
        try session.setPreferredIOBufferDuration(0.032)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let directory = try AppGroup.audioDirectory()
        // The same 16 kHz PCM feeds both streaming and a WAV retry file. Writing AAC directly
        // from an Int16 converter is unsupported on some routes and produced Core Audio `!dat`.
        let url = directory.appending(path: "\(UUID().uuidString).wav")
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioRecorderError.unableToStart
        }

        let pipeline = try AudioCapturePipeline(
            inputFormat: inputFormat,
            outputURL: url,
            onPCMData: onPCMData,
            onLevel: { [weak self] value in
                Task { @MainActor in self?.level = value }
            }
        )
        input.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) { buffer, _ in
            pipeline.process(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw AudioRecorderError.unableToStart
        }

        self.engine = engine
        self.pipeline = pipeline
        currentURL = url
        startedAt = .now
        elapsed = 0
        level = 0
        isRecording = true
        startMetering()
    }

    func stop() throws -> URL {
        stopEngine()
        guard elapsed >= 0.65 else {
            if let currentURL { try? FileManager.default.removeItem(at: currentURL) }
            throw AudioRecorderError.tooShort
        }
        guard let currentURL else { throw AudioRecorderError.unableToStart }
        return currentURL
    }

    func cancel() {
        stopEngine()
        if let currentURL { try? FileManager.default.removeItem(at: currentURL) }
        currentURL = nil
    }

    private func stopEngine() {
        meterTask?.cancel()
        meterTask = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        // Releasing AVAudioFile finalizes the m4a container before it is uploaded.
        pipeline = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    private func startMetering() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(40))
                guard let self, isRecording else { break }
                elapsed = Date.now.timeIntervalSince(startedAt ?? .now)
                if elapsed >= maximumDuration {
                    onMaximumDuration?()
                    break
                }
            }
        }
    }
}

/// Conversion and file I/O stay off the main actor because the audio tap runs on a real-time thread.
private final class AudioCapturePipeline: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private let file: AVAudioFile
    private let onPCMData: (@Sendable (Data) -> Void)?
    private let onLevel: @Sendable (Float) -> Void
    private let lock = NSLock()

    init(
        inputFormat: AVAudioFormat,
        outputURL: URL,
        onPCMData: (@Sendable (Data) -> Void)?,
        onLevel: @escaping @Sendable (Float) -> Void
    ) throws {
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioRecorderError.unableToStart
        }
        self.converter = converter
        self.outputFormat = outputFormat
        file = try AVAudioFile(
            forWriting: outputURL,
            settings: outputFormat.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: false
        )
        self.onPCMData = onPCMData
        self.onLevel = onLevel
    }

    func process(_ input: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }

        let ratio = outputFormat.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up)) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return
        }
        let supply = AudioInputSupply()
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            guard !supply.didSupply else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supply.didSupply = true
            inputStatus.pointee = .haveData
            return input
        }
        guard conversionError == nil, status != .error, output.frameLength > 0,
              let channel = output.int16ChannelData?[0] else {
            return
        }

        try? file.write(from: output)
        let count = Int(output.frameLength)
        onPCMData?(Data(bytes: channel, count: count * MemoryLayout<Int16>.size))

        var squareSum: Double = 0
        for index in stride(from: 0, to: count, by: 4) {
            let normalized = Double(channel[index]) / Double(Int16.max)
            squareSum += normalized * normalized
        }
        let sampleCount = max(1, (count + 3) / 4)
        let rms = sqrt(squareSum / Double(sampleCount))
        onLevel(Float(min(1, rms * 5)))
    }
}

private final class AudioInputSupply: @unchecked Sendable {
    var didSupply = false
}
