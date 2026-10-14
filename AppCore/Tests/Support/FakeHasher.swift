// A `SHA256Hashing` for tests that answers only the inputs it was given digests for.

import AppCore
import Foundation
import Testing

struct FakeHasher: SHA256Hashing {
    let digests: [Data: Data]

    init(_ digests: [Data: Data] = [:]) {
        self.digests = digests
    }

    func sha256(_ data: Data) -> Data {
        guard let digest = digests[data] else {
            Issue.record("FakeHasher has no digest for a \(data.count)-byte input")
            return Data()
        }
        return digest
    }
}
