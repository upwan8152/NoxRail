import Foundation
import CoreBluetooth

/// BLE constants for NoxRail mesh network
enum BLEConstants {
    /// Main NoxRail service UUID
    static let serviceUUID = CBUUID(string: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")
    
    /// Characteristic for writing data to a peer
    static let writeCharacteristicUUID = CBUUID(string: "A1B2C3D4-E5F6-7890-ABCD-EF1234567891")
    
    /// Characteristic for receiving notifications from a peer
    static let notifyCharacteristicUUID = CBUUID(string: "A1B2C3D4-E5F6-7890-ABCD-EF1234567892")
    
    /// Local name prefix for advertising
    static let localNamePrefix = "NoxRail"
    
    /// Maximum BLE packet size (MTU - 3 bytes overhead)
    /// Most iOS devices support at least 185 bytes
    static let maxPacketSize = 512
    
    /// Scan interval in seconds
    static let scanInterval: TimeInterval = 2.0
    
    /// Connection timeout in seconds
    static let connectionTimeout: TimeInterval = 10.0
    
    /// Peer stale timeout in seconds
    static let peerStaleTimeout: TimeInterval = 30.0
    
    /// Time between peer announcements
    static let announceInterval: TimeInterval = 5.0
}

/// BLE connection state
enum BLEConnectionState: String, Sendable {
    case disconnected
    case connecting
    case connected
    case disconnecting
}

/// BLE power state
enum BLEPowerState: String, Sendable {
    case unknown
    case resetting
    case unsupported
    case unauthorized
    case poweredOff
    case poweredOn
    
    init(from cbState: CBManagerState) {
        switch cbState {
        case .unknown: self = .unknown
        case .resetting: self = .resetting
        case .unsupported: self = .unsupported
        case .unauthorized: self = .unauthorized
        case .poweredOff: self = .poweredOff
        case .poweredOn: self = .poweredOn
        @unknown default: self = .unknown
        }
    }
    
    var isReady: Bool {
        self == .poweredOn
    }
    
    var displayMessage: String {
        switch self {
        case .unknown: return "Bluetooth status unknown"
        case .resetting: return "Bluetooth is resetting"
        case .unsupported: return "Bluetooth is not supported"
        case .unauthorized: return "Bluetooth access not authorized"
        case .poweredOff: return "Bluetooth is turned off"
        case .poweredOn: return "Bluetooth is ready"
        }
    }
}

/// Represents a connected BLE peer
struct BLEPeer: Identifiable, Sendable {
    let id: String
    let peripheral: CBPeripheral?
    let central: CBCentral?
    var displayName: String
    var rssi: Int
    var lastSeen: Date
    var connectionState: BLEConnectionState
    var writeCharacteristic: CBCharacteristic?
    var notifyCharacteristic: CBCharacteristic?
    
    var isConnected: Bool {
        connectionState == .connected
    }
    
    init(
        id: String,
        peripheral: CBPeripheral? = nil,
        central: CBCentral? = nil,
        displayName: String = "Unknown",
        rssi: Int = -100,
        lastSeen: Date = Date(),
        connectionState: BLEConnectionState = .disconnected,
        writeCharacteristic: CBCharacteristic? = nil,
        notifyCharacteristic: CBCharacteristic? = nil
    ) {
        self.id = id
        self.peripheral = peripheral
        self.central = central
        self.displayName = displayName
        self.rssi = rssi
        self.lastSeen = lastSeen
        self.connectionState = connectionState
        self.writeCharacteristic = writeCharacteristic
        self.notifyCharacteristic = notifyCharacteristic
    }
}
