import Foundation
import Security

/// Service for secure storage of keys and sensitive data in iOS Keychain
final class KeychainService: Sendable {
    
    // MARK: - Constants
    
    private static let serviceName = "com.noxrail.keychain"
    
    enum KeychainKey: String {
        case identityPrivateKey = "identity.privateKey"
        case identityUserId = "identity.userId"
        case identityDisplayName = "identity.displayName"
        case peerPublicKeyPrefix = "peer.publicKey."
    }
    
    enum KeychainError: Error, LocalizedError {
        case encodingFailed
        case decodingFailed
        case saveFailed(OSStatus)
        case loadFailed(OSStatus)
        case deleteFailed(OSStatus)
        case itemNotFound
        case unexpectedData
        
        var errorDescription: String? {
            switch self {
            case .encodingFailed: return "Failed to encode data"
            case .decodingFailed: return "Failed to decode data"
            case .saveFailed(let status): return "Failed to save: \(status)"
            case .loadFailed(let status): return "Failed to load: \(status)"
            case .deleteFailed(let status): return "Failed to delete: \(status)"
            case .itemNotFound: return "Item not found"
            case .unexpectedData: return "Unexpected data format"
            }
        }
    }
    
    // MARK: - Generic Operations
    
    /// Saves data to keychain
    static func save(key: String, data: Data) throws {
        // Delete existing item first
        try? delete(key: key)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }
    
    /// Loads data from keychain
    static func load(key: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.loadFailed(status)
        }
        
        guard let data = result as? Data else {
            throw KeychainError.unexpectedData
        }
        
        return data
    }
    
    /// Deletes an item from keychain
    static func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
    
    /// Checks if a key exists
    static func exists(key: String) -> Bool {
        do {
            _ = try load(key: key)
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - String Operations
    
    /// Saves a string to keychain
    static func saveString(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        try save(key: key, data: data)
    }
    
    /// Loads a string from keychain
    static func loadString(key: String) throws -> String {
        let data = try load(key: key)
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingFailed
        }
        return string
    }
    
    // MARK: - Identity Key Operations
    
    /// Saves the identity private key
    static func saveIdentityPrivateKey(_ keyData: Data) throws {
        try save(key: KeychainKey.identityPrivateKey.rawValue, data: keyData)
    }
    
    /// Loads the identity private key
    static func loadIdentityPrivateKey() throws -> Data {
        try load(key: KeychainKey.identityPrivateKey.rawValue)
    }
    
    /// Checks if identity key exists
    static func identityKeyExists() -> Bool {
        exists(key: KeychainKey.identityPrivateKey.rawValue)
    }
    
    /// Saves identity user ID
    static func saveIdentityUserId(_ userId: String) throws {
        try saveString(key: KeychainKey.identityUserId.rawValue, value: userId)
    }
    
    /// Loads identity user ID
    static func loadIdentityUserId() throws -> String {
        try loadString(key: KeychainKey.identityUserId.rawValue)
    }
    
    /// Saves identity display name
    static func saveIdentityDisplayName(_ displayName: String) throws {
        try saveString(key: KeychainKey.identityDisplayName.rawValue, value: displayName)
    }
    
    /// Loads identity display name
    static func loadIdentityDisplayName() throws -> String {
        try loadString(key: KeychainKey.identityDisplayName.rawValue)
    }
    
    // MARK: - Peer Key Operations
    
    /// Saves a peer's public key
    static func savePeerPublicKey(peerId: String, keyData: Data) throws {
        let key = KeychainKey.peerPublicKeyPrefix.rawValue + peerId
        try save(key: key, data: keyData)
    }
    
    /// Loads a peer's public key
    static func loadPeerPublicKey(peerId: String) throws -> Data {
        let key = KeychainKey.peerPublicKeyPrefix.rawValue + peerId
        return try load(key: key)
    }
    
    /// Checks if a peer's public key exists
    static func peerPublicKeyExists(peerId: String) -> Bool {
        let key = KeychainKey.peerPublicKeyPrefix.rawValue + peerId
        return exists(key: key)
    }
    
    /// Deletes a peer's public key
    static func deletePeerPublicKey(peerId: String) throws {
        let key = KeychainKey.peerPublicKeyPrefix.rawValue + peerId
        try delete(key: key)
    }
    
    // MARK: - Cleanup
    
    /// Deletes all NoxRail keychain items (for testing/reset)
    static func deleteAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}
