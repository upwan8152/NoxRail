import Foundation
import SwiftData

/// Represents a discovered BLE peer in the mesh network
@Model
final class Peer {
    /// Unique identifier for the peer (derived from BLE peripheral identifier)
    @Attribute(.unique) var peerId: String
    
    /// Display name of the peer
    var displayName: String
    
    /// Public key for encryption (base64 encoded)
    var publicKeyData: Data?
    
    /// Signal strength (RSSI)
    var rssi: Int
    
    /// Last time this peer was seen
    var lastSeen: Date
    
    /// Whether currently connected via BLE
    var isConnected: Bool
    
    /// Whether this peer is available for messaging
    var isAvailable: Bool
    
    /// Number of hops to reach this peer (0 = direct connection)
    var hopDistance: Int
    
    init(
        peerId: String,
        displayName: String,
        publicKeyData: Data? = nil,
        rssi: Int = -100,
        lastSeen: Date = Date(),
        isConnected: Bool = false,
        isAvailable: Bool = true,
        hopDistance: Int = 0
    ) {
        self.peerId = peerId
        self.displayName = displayName
        self.publicKeyData = publicKeyData
        self.rssi = rssi
        self.lastSeen = lastSeen
        self.isConnected = isConnected
        self.isAvailable = isAvailable
        self.hopDistance = hopDistance
    }
}

// MARK: - Peer Extensions

extension Peer {
    /// Signal strength description
    var signalStrength: SignalStrength {
        switch rssi {
        case -50...0:
            return .excellent
        case -65..<(-50):
            return .good
        case -80..<(-65):
            return .fair
        default:
            return .weak
        }
    }
    
    /// Whether this peer has exchanged keys
    var hasExchangedKeys: Bool {
        publicKeyData != nil
    }
    
    /// Time since last seen
    var timeSinceLastSeen: TimeInterval {
        Date().timeIntervalSince(lastSeen)
    }
    
    /// Whether the peer is considered stale (not seen recently)
    var isStale: Bool {
        timeSinceLastSeen > 30 // 30 seconds
    }
}

/// Signal strength levels
enum SignalStrength: String, Sendable {
    case excellent
    case good
    case fair
    case weak
    
    var icon: String {
        switch self {
        case .excellent: return "wifi"
        case .good: return "wifi"
        case .fair: return "wifi.exclamationmark"
        case .weak: return "wifi.slash"
        }
    }
    
    var color: String {
        switch self {
        case .excellent: return "green"
        case .good: return "blue"
        case .fair: return "orange"
        case .weak: return "red"
        }
    }
}
