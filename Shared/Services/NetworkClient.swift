import Foundation

struct HTTPResponse: Sendable {
    let data: Data
    let statusCode: Int
}

protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

struct URLSessionHTTPClient: HTTPClient {
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return HTTPResponse(data: data, statusCode: http.statusCode)
    }
}

struct APIErrorEnvelope: Decodable {
    struct Detail: Decodable { let message: String? }
    let error: Detail?
}

enum HTTPServiceError: LocalizedError {
    case rejected(status: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .rejected(let status, let message):
            message?.nilIfBlank ?? "The service rejected the request (HTTP \(status))."
        }
    }
}
