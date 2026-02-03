import Foundation

/// Type of routing packet
enum PacketType: String, Codable, Sendable {
    case message          // Regular chat message
    case groupMessage     // Group chat message
    case keyExchange      // Public key exchange
    case peerAnnounce     // Peer discovery announcement
    case ack              // Message acknowledgment
    case ping             // Keepalive ping
}

/// Routing packet for BLE mesh transmission
struct RoutingPacket: Codable, Sendable, Identifiable {
    /// Unique packet identifier
    let packetId: String
    
    /// Type of packet
    let type: PacketType
    
    /// Source peer ID (original sender)
    let sourcePeerId: String
    
    /// Source peer display name
    let sourcePeerName: String
    
    /// Destination ID (peer ID for direct, group ID for group)
    let destinationId: String
    
    /// Current hop count
    var hopCount: Int
    
    /// Maximum allowed hops (TTL)
    let maxHops: Int
    
    /// Packet creation timestamp
    let timestamp: Date
    
    /// Encrypted payload data
    let payload: Data
    
    /// Chat type (for message routing)
    let chatType: ChatType?
    
    /// For group messages: list of recipient IDs
    let recipientIds: [String]?
    
    var id: String { packetId }
    
    init(
        packetId: String = UUID().uuidString,
        type: PacketType,
        sourcePeerId: String,
        sourcePeerName: String,
        destinationId: String,
        hopCount: Int = 0,
        maxHops: Int = 5,
        timestamp: Date = Date(),
        payload: Data,
        chatType: ChatType? = .direct,
        recipientIds: [String]? = nil
    ) {
        self.packetId = packetId
        self.type = type
        self.sourcePeerId = sourcePeerId
        self.sourcePeerName = sourcePeerName
        self.destinationId = destinationId
        self.hopCount = hopCount
        self.maxHops = maxHops
        self.timestamp = timestamp
        self.payload = payload
        self.chatType = chatType
        self.recipientIds = recipientIds
    }
    
    /// Creates a relay copy with incremented hop count
    func relayed() -> RoutingPacket {
        var copy = self
        copy.hopCount += 1
        return copy
    }
    
    /// Whether this packet can be relayed (not expired)
    var canRelay: Bool {
        hopCount < maxHops
    }
    
    /// Whether this packet has exceeded TTL
    var isExpired: Bool {
        hopCount >= maxHops
    }
}

// MARK: - Packet Encoding

extension RoutingPacket {
    /// Encodes the packet to Data for BLE transmission
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
    
    /// Decodes a packet from BLE data
    static func decode(from data: Data) throws -> RoutingPacket {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RoutingPacket.self, from: data)
    }
}

// MARK: - Key Exchange Payload

/// Payload for key exchange packets
struct KeyExchangePayload: Codable, Sendable {
    let peerId: String
    let displayName: String
    let publicKeyData: Data
    
    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }
    
    static func decode(from data: Data) throws -> KeyExchangePayload {
        try JSONDecoder().decode(KeyExchangePayload.self, from: data)
    }
}

// MARK: - Peer Announce Payload

/// Payload for peer announcement packets
struct PeerAnnouncePayload: Codable, Sendable {
    let peerId: String
    let displayName: String
    let publicKeyData: Data?
    let relayEnabled: Bool
    
    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }
    
    static func decode(from data: Data) throws -> PeerAnnouncePayload {
        try JSONDecoder().decode(PeerAnnouncePayload.self, from: data)
    }
}

// MARK: - Ack Payload

/// Payload for acknowledgment packets
struct AckPayload: Codable, Sendable {
    let originalPacketId: String
    let status: String // "delivered", "read"
    
    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }
    
    static func decode(from data: Data) throws -> AckPayload {
        try JSONDecoder().decode(AckPayload.self, from: data)
    }
}
