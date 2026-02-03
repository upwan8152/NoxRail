import Foundation
import CryptoKit

/// Encrypted message payload structure
struct EncryptedPayload: Codable, Sendable {
    /// Random nonce used for encryption
    let nonce: Data
    
    /// Encrypted ciphertext
    let ciphertext: Data
    
    /// Authentication tag for integrity verification
    let tag: Data
    
    /// Sender's public key (for recipient to derive shared secret)
    let senderPublicKey: Data
    
    /// Encodes to Data for transmission
    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }
    
    /// Decodes from transmission data
    static func decode(from data: Data) throws -> EncryptedPayload {
        try JSONDecoder().decode(EncryptedPayload.self, from: data)
    }
}

/// Service for end-to-end encryption using ECDH + AES-GCM
final class EncryptionService: @unchecked Sendable {
    
    // MARK: - Singleton
    
    static let shared = EncryptionService()
    
    // MARK: - Properties
    
    private var keyPair: IdentityKeyPair?
    private var identity: Identity?
    private let queue = DispatchQueue(label: "com.noxrail.encryption", qos: .userInitiated)
    
    // MARK: - Errors
    
    enum EncryptionError: Error, LocalizedError {
        case notInitialized
        case keyGenerationFailed
        case keyAgreementFailed
        case encryptionFailed
        case decryptionFailed
        case invalidPublicKey
        case invalidPayload
        case peerKeyNotFound
        case keychainError(Error)
        
        var errorDescription: String? {
            switch self {
            case .notInitialized: return "Encryption service not initialized"
            case .keyGenerationFailed: return "Failed to generate key pair"
            case .keyAgreementFailed: return "Failed to perform key agreement"
            case .encryptionFailed: return "Failed to encrypt message"
            case .decryptionFailed: return "Failed to decrypt message"
            case .invalidPublicKey: return "Invalid public key"
            case .invalidPayload: return "Invalid encrypted payload"
            case .peerKeyNotFound: return "Peer public key not found"
            case .keychainError(let error): return "Keychain error: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Initialization
    
    private init() {}
    
    /// Initializes the encryption service, loading or generating identity
    func initialize() async throws -> Identity {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: EncryptionError.notInitialized)
                    return
                }
                
                do {
                    let identity = try self.loadOrCreateIdentity()
                    continuation.resume(returning: identity)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Loads existing identity or creates a new one
    private func loadOrCreateIdentity() throws -> Identity {
        // Check if we already have a cached identity
        if let existingIdentity = identity, keyPair != nil {
            return existingIdentity
        }
        
        // Try to load from keychain
        if KeychainService.identityKeyExists() {
            let privateKeyData = try KeychainService.loadIdentityPrivateKey()
            let userId = try KeychainService.loadIdentityUserId()
            let displayName = try KeychainService.loadIdentityDisplayName()
            
            let loadedKeyPair = try IdentityKeyPair(privateKeyData: privateKeyData)
            self.keyPair = loadedKeyPair
            
            let loadedIdentity = Identity(
                userId: userId,
                displayName: displayName,
                publicKeyData: loadedKeyPair.publicKeyData
            )
            self.identity = loadedIdentity
            
            return loadedIdentity
        }
        
        // Generate new identity
        return try createNewIdentity(displayName: generateDefaultDisplayName())
    }
    
    /// Creates a new identity with the given display name
    func createNewIdentity(displayName: String) throws -> Identity {
        let newKeyPair = IdentityKeyPair()
        let userId = UUID().uuidString
        
        // Save to keychain
        try KeychainService.saveIdentityPrivateKey(newKeyPair.privateKey.rawRepresentation)
        try KeychainService.saveIdentityUserId(userId)
        try KeychainService.saveIdentityDisplayName(displayName)
        
        self.keyPair = newKeyPair
        
        let newIdentity = Identity(
            userId: userId,
            displayName: displayName,
            publicKeyData: newKeyPair.publicKeyData
        )
        self.identity = newIdentity
        
        return newIdentity
    }
    
    /// Updates display name
    func updateDisplayName(_ name: String) throws {
        try KeychainService.saveIdentityDisplayName(name)
        if var currentIdentity = identity {
            currentIdentity.displayName = name
            identity = currentIdentity
        }
    }
    
    /// Gets the current identity
    func getIdentity() -> Identity? {
        return identity
    }
    
    /// Gets the current key pair
    func getKeyPair() -> IdentityKeyPair? {
        return keyPair
    }
    
    // MARK: - Key Exchange
    
    /// Stores a peer's public key
    func storePeerPublicKey(peerId: String, publicKeyData: Data) throws {
        // Validate the key first
        _ = try P256.KeyAgreement.PublicKey(rawRepresentation: publicKeyData)
        try KeychainService.savePeerPublicKey(peerId: peerId, keyData: publicKeyData)
    }
    
    /// Gets a peer's public key
    func getPeerPublicKey(peerId: String) throws -> P256.KeyAgreement.PublicKey {
        let keyData = try KeychainService.loadPeerPublicKey(peerId: peerId)
        return try P256.KeyAgreement.PublicKey(rawRepresentation: keyData)
    }
    
    /// Checks if we have a peer's public key
    func hasPeerPublicKey(peerId: String) -> Bool {
        return KeychainService.peerPublicKeyExists(peerId: peerId)
    }
    
    // MARK: - Encryption
    
    /// Encrypts a message for a specific recipient
    func encrypt(message: String, forPeerId peerId: String) throws -> EncryptedPayload {
        guard let keyPair = keyPair else {
            throw EncryptionError.notInitialized
        }
        
        let recipientPublicKey = try getPeerPublicKey(peerId: peerId)
        
        return try encrypt(
            message: message,
            recipientPublicKey: recipientPublicKey,
            senderKeyPair: keyPair
        )
    }
    
    /// Encrypts a message using recipient's public key
    func encrypt(
        message: String,
        recipientPublicKey: P256.KeyAgreement.PublicKey,
        senderKeyPair: IdentityKeyPair
    ) throws -> EncryptedPayload {
        // Convert message to data
        guard let messageData = message.data(using: .utf8) else {
            throw EncryptionError.encryptionFailed
        }
        
        // Perform ECDH key agreement
        let sharedSecret = try senderKeyPair.privateKey.sharedSecretFromKeyAgreement(
            with: recipientPublicKey
        )
        
        // Derive symmetric key using HKDF
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: "NoxRail-v1".data(using: .utf8)!,
            sharedInfo: Data(),
            outputByteCount: 32
        )
        
        // Generate random nonce
        let nonce = AES.GCM.Nonce()
        
        // Encrypt with AES-GCM
        let sealedBox = try AES.GCM.seal(messageData, using: symmetricKey, nonce: nonce)
        
        guard let combined = sealedBox.combined else {
            throw EncryptionError.encryptionFailed
        }
        
        // Extract components
        let nonceData = Data(nonce)
        let ciphertext = sealedBox.ciphertext
        let tag = sealedBox.tag
        
        return EncryptedPayload(
            nonce: nonceData,
            ciphertext: Data(ciphertext),
            tag: Data(tag),
            senderPublicKey: senderKeyPair.publicKeyData
        )
    }
    
    // MARK: - Decryption
    
    /// Decrypts an encrypted payload from a known peer
    func decrypt(payload: EncryptedPayload, fromPeerId peerId: String) throws -> String {
        guard let keyPair = keyPair else {
            throw EncryptionError.notInitialized
        }
        
        // Get sender's public key from payload (or use stored key)
        let senderPublicKey = try P256.KeyAgreement.PublicKey(
            rawRepresentation: payload.senderPublicKey
        )
        
        return try decrypt(
            payload: payload,
            senderPublicKey: senderPublicKey,
            recipientKeyPair: keyPair
        )
    }
    
    /// Decrypts an encrypted payload
    func decrypt(
        payload: EncryptedPayload,
        senderPublicKey: P256.KeyAgreement.PublicKey,
        recipientKeyPair: IdentityKeyPair
    ) throws -> String {
        // Perform ECDH key agreement
        let sharedSecret = try recipientKeyPair.privateKey.sharedSecretFromKeyAgreement(
            with: senderPublicKey
        )
        
        // Derive symmetric key using HKDF
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: "NoxRail-v1".data(using: .utf8)!,
            sharedInfo: Data(),
            outputByteCount: 32
        )
        
        // Reconstruct nonce
        guard let nonce = try? AES.GCM.Nonce(data: payload.nonce) else {
            throw EncryptionError.invalidPayload
        }
        
        // Reconstruct sealed box
        let sealedBox = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: payload.ciphertext,
            tag: payload.tag
        )
        
        // Decrypt
        let decryptedData = try AES.GCM.open(sealedBox, using: symmetricKey)
        
        guard let message = String(data: decryptedData, encoding: .utf8) else {
            throw EncryptionError.decryptionFailed
        }
        
        return message
    }
    
    // MARK: - Group Encryption
    
    /// Encrypts a message for multiple recipients (group chat)
    /// Returns a dictionary of recipient ID to encrypted payload
    func encryptForGroup(
        message: String,
        recipientIds: [String]
    ) throws -> [String: EncryptedPayload] {
        guard let keyPair = keyPair else {
            throw EncryptionError.notInitialized
        }
        
        var payloads: [String: EncryptedPayload] = [:]
        
        for recipientId in recipientIds {
            guard hasPeerPublicKey(peerId: recipientId) else {
                // Skip recipients we don't have keys for
                continue
            }
            
            let recipientPublicKey = try getPeerPublicKey(peerId: recipientId)
            let payload = try encrypt(
                message: message,
                recipientPublicKey: recipientPublicKey,
                senderKeyPair: keyPair
            )
            payloads[recipientId] = payload
        }
        
        return payloads
    }
    
    // MARK: - Helpers
    
    private func generateDefaultDisplayName() -> String {
        let adjectives = ["Swift", "Blue", "Cyber", "Neon", "Mesh", "Dark", "Light", "Quantum"]
        let nouns = ["Node", "Rail", "Link", "Wave", "Pulse", "Spark", "Beam", "Core"]
        
        let adj = adjectives.randomElement() ?? "Swift"
        let noun = nouns.randomElement() ?? "Node"
        let num = Int.random(in: 100...999)
        
        return "\(adj)\(noun)\(num)"
    }
    
    // MARK: - Reset
    
    /// Resets the encryption service (deletes all keys)
    func reset() throws {
        try KeychainService.deleteAll()
        keyPair = nil
        identity = nil
    }
}
