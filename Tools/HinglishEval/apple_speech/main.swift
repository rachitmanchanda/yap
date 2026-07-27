import Foundation
import Speech

private func emit(_ object: [String: Any], status: Int32 = 0) -> Never {
    let data = try! JSONSerialization.data(withJSONObject: object)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0A]))
    exit(status)
}

private func normalize(_ text: String) -> String {
    guard text.unicodeScalars.contains(where: { !$0.isASCII && $0.properties.isAlphabetic }) else {
        return text
    }
    return text
        .applyingTransform(.toLatin, reverse: false)?
        .applyingTransform(.stripCombiningMarks, reverse: false)
        ?? text
}

private func authorizationStatus() -> SFSpeechRecognizerAuthorizationStatus {
    if SFSpeechRecognizer.authorizationStatus() != .notDetermined {
        return SFSpeechRecognizer.authorizationStatus()
    }
    let semaphore = DispatchSemaphore(value: 0)
    var status = SFSpeechRecognizerAuthorizationStatus.notDetermined
    SFSpeechRecognizer.requestAuthorization {
        status = $0
        semaphore.signal()
    }
    semaphore.wait()
    return status
}

private func transcribe(audioPath: String, localeIdentifier: String) {
    guard authorizationStatus() == .authorized else {
        emit([
            "error": "Apple Speech permission is required. Enable it for the helper in System Settings → Privacy & Security → Speech Recognition."
        ], status: 2)
    }
    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)),
          recognizer.isAvailable else {
        emit(["error": "Apple Speech is unavailable for locale \(localeIdentifier)."], status: 3)
    }

    let request = SFSpeechURLRecognitionRequest(url: URL(fileURLWithPath: audioPath))
    request.shouldReportPartialResults = false
    request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition

    let semaphore = DispatchSemaphore(value: 0)
    var transcript: String?
    var failure: Error?
    var task: SFSpeechRecognitionTask?
    task = recognizer.recognitionTask(with: request) { result, error in
        if let error {
            failure = error
            task?.cancel()
            semaphore.signal()
        } else if let result, result.isFinal {
            transcript = result.bestTranscription.formattedString
            task?.finish()
            semaphore.signal()
        }
    }
    if semaphore.wait(timeout: .now() + 120) == .timedOut {
        task?.cancel()
        emit(["error": "Apple Speech timed out."], status: 4)
    }
    if let failure {
        emit(["error": failure.localizedDescription], status: 5)
    }
    guard let transcript, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        emit(["error": "Apple Speech returned no text."], status: 6)
    }
    emit(["transcript": normalize(transcript)])
}

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    emit(["error": "Usage: yap-apple-speech normalize <text> | transcribe <audio> [locale]"], status: 64)
}

switch arguments[1] {
case "normalize":
    emit(["text": normalize(arguments[2])])
case "transcribe":
    transcribe(audioPath: arguments[2], localeIdentifier: arguments.count > 3 ? arguments[3] : "en-IN")
default:
    emit(["error": "Unknown command '\(arguments[1])'."], status: 64)
}
