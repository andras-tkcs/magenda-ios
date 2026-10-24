// AppCore's HTTP types: the methods the Google clients use and reading a response's headers.

import AppCore
import Foundation
import Testing

@Suite("HTTP types")
struct HTTPTests {
    @Test("A header is found whatever its case, and is nil when absent")
    func headerLookup() {
        let response = HTTPResponse(
            status: 200, body: Data(), headers: ["Retry-After": "30", "Location": "https://a"])
        #expect(response.header("retry-after") == "30")
        #expect(response.header("LOCATION") == "https://a")
        #expect(response.header("ETag") == nil)
    }

    @Test("A response has no headers unless given some")
    func defaultHeaders() {
        #expect(HTTPResponse(status: 204, body: Data()).headers.isEmpty)
    }

    @Test("PUT and PATCH are methods")
    func methods() {
        #expect(HTTPMethod.put.rawValue == "PUT")
        #expect(HTTPMethod.patch.rawValue == "PATCH")
    }
}
