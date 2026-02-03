import Foundation
import CryptoKit

/// Represents the local user's identity
struct Identity: Codable, Sendable {
    /// Unique identifier for this device/user
    let userId: String
    
    /// Display name shown to other users
    var displayName: String
    
    /// Public key data (P-256)
    let publicKeyData: Data
    
    /// Creation timestamp
    let createdAt: Date
    
    init(userId: String = UUID().uuidString, displayName: String, publicKeyData: Data, createdAt: Date = Date()) {
        self.userId = userId
        self.displayName = displayName
        self.publicKeyData = publicKeyData
        self.createdAt = createdAt
    }
}

// MARK: - Identity Extensions

extension Identity {
    /// Base64 encoded public key for transmission
    var publicKeyBase64: String {
        publicKeyData.base64EncodedString()
    }
    
    /// Short ID for display (first 8 characters)
    var shortId: String {
        String(userId.prefix(8))
    }
}

/// Wrapper for identity keypair stored in Keychain
struct IdentityKeyPair: Sendable {
    let privateKey: P256.KeyAgreement.PrivateKey
    
    var publicKey: P256.KeyAgreement.PublicKey {
        privateKey.publicKey
    }
    
    var publicKeyData: Data {
        publicKey.rawRepresentation
    }
    
    init() {
        self.privateKey = P256.KeyAgreement.PrivateKey()
    }
    
    init(privateKey: P256.KeyAgreement.PrivateKey) {
        self.privateKey = privateKey
    }
    
    init(privateKeyData: Data) throws {
        self.privateKey = try P256.KeyAgreement.PrivateKey(rawRepresentation: privateKeyData)
    }
}
