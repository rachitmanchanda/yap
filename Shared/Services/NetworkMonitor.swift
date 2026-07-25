import Foundation
import Network
import Observation

@MainActor
@Observable
final class NetworkMonitor {
    private(set) var isConnected = true
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "VoiceCards.NetworkMonitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.isConnected = path.status == .satisfied }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }
}
