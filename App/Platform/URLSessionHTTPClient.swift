import AppCore
import Foundation

/// Sends requests with an ephemeral `URLSession`.
struct URLSessionHTTPClient: HTTPClient {
    /// A transport failure; carries neither the URL nor any header.
    struct TransportError: Error, CustomStringConvertible {
        let code: URLError.Code
        var description: String { "Network error \(code.rawValue)" }
    }

    private let session = URLSession(configuration: .ephemeral)

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url, timeoutInterval: request.timeout)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        do {
            let (body, response) = try await session.data(for: urlRequest)
            let http = response as? HTTPURLResponse
            var headers: [String: String] = [:]
            for (name, value) in http?.allHeaderFields ?? [:] {
                if let name = name as? String, let value = value as? String {
                    headers[name] = value
                }
            }
            return HTTPResponse(status: http?.statusCode ?? 0, body: body, headers: headers)
        } catch let error as URLError {
            throw TransportError(code: error.code)
        }
    }
}
