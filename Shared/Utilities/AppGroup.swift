import Foundation

enum AppGroup {
    static let identifier = "group.com.APP.shared"
    static let storeFilename = "VoiceCards.sqlite"
    static let audioDirectoryName = "PendingAudio"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static func requireContainerURL() throws -> URL {
        guard let url = containerURL else { throw AppGroupError.containerUnavailable }
        return url
    }

    static func audioDirectory() throws -> URL {
        let url = try requireContainerURL().appending(path: audioDirectoryName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

enum AppGroupError: LocalizedError {
    case containerUnavailable

    var errorDescription: String? {
        "The shared App Group is unavailable. Check signing and the group.com.APP.shared entitlement."
    }
}
