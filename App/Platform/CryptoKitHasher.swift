import AppCore
import CryptoKit
import Foundation

/// SHA-256 through CryptoKit.
struct CryptoKitHasher: SHA256Hashing {
    func sha256(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }
}
