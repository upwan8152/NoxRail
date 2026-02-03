import Foundation
import Combine

/// Delegate protocol for mesh routing events
protocol MeshRoutingServiceDelegate: AnyObject {
    func meshRouting(_ service: MeshRoutingService, didReceiveMessage message: Message, from peerId: String)
    func meshRouting(_ service: MeshRoutingService, didSendMessage messageId: String, status: MessageStatus)
    func meshRouting(_ service: MeshRoutingService, didReceiveKeyExchange peerId: String)
}

/// Core mesh routing engine for multi-hop message delivery
@MainActor
final class MeshRoutingService: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var relayModeEnabled = false
    @Published private(set) var isActive = false
    @Published private(set) var stats = MeshStats()
    
    // MARK: - Properties
    
    private let bleService: BLEService
    private let encryptionService: EncryptionService
    private let peerManager: PeerManager
    
    /// Cache of seen message IDs for loop prevention
    private var seenMessages: [String: Date] = [:]
    
    /// Pending outgoing packets awaiting delivery confirmation
    private var pendingPackets: [String: RoutingPacket] = [:]
    
    /// Maximum time to keep seen messages in cache
    private let seenMessageTTL: TimeInterval = 300 // 5 minutes
    
    /// Default maximum hops for messages
    private let defaultMaxHops = 5
    
    private var cleanupTimer: Timer?
    private var announceTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    weak var delegate: MeshRoutingServiceDelegate?
    
    private var myPeerId: String {
        encryptionService.getIdentity()?.userId ?? ""
    }
    
    private var myDisplayName: String {
        encryptionService.getIdentity()?.displayName ?? "Unknown"
    }
    
    // MARK: - Singleton
    
    static let shared = MeshRoutingService()
    
    // MARK: - Initialization
    
    private init() {
        bleService = BLEService.shared
        encryptionService = EncryptionService.shared
        peerManager = PeerManager.shared
    }
    
    // MARK: - Lifecycle
    
    /// Starts the mesh routing service
    func start() async throws {
        guard !isActive else { return }
        
        NoxLogger.mesh.info("Starting mesh routing service")
        
        // Initialize encryption (load or create identity)
        let identity = try await encryptionService.initialize()
        
        // Set BLE local name
        bleService.localName = "\(BLEConstants.localNamePrefix)-\(identity.displayName)"
        
        // Start BLE service
        bleService.start()
        bleService.delegate = self
        
        // Setup peer manager
        peerManager.setup()
        peerManager.delegate = self
        
        // Start cleanup timer
        startCleanupTimer()
        
        // Start periodic announcements
        startAnnouncements()
        
        isActive = true
        
        NoxLogger.mesh.info("Mesh routing active as '\(identity.displayName)'")
    }
    
    /// Stops the mesh routing service
    func stop() {
        guard isActive else { return }
        
        NoxLogger.mesh.info("Stopping mesh routing service")
        
        stopCleanupTimer()
        stopAnnouncements()
        
        bleService.stop()
        peerManager.clearPeers()
        
        seenMessages.removeAll()
        pendingPackets.removeAll()
        
        isActive = false
    }
    
    // MARK: - Relay Mode
    
    /// Enables or disables relay mode
    func setRelayMode(_ enabled: Bool) {
        relayModeEnabled = enabled
        NoxLogger.mesh.info("Relay mode \(enabled ? "enabled" : "disabled")")
        
        // Announce updated relay status
        sendPeerAnnouncement()
    }
    
    // MARK: - Message Sending
    
    /// Sends a message to a single recipient (direct chat)
    func sendDirectMessage(
        content: String,
        to recipientId: String,
        chatId: String
    ) async throws -> Message {
        guard let identity = encryptionService.getIdentity() else {
            throw MeshRoutingError.notInitialized
        }
        
        // Encrypt message
        let encryptedPayload = try encryptionService.encrypt(message: content, forPeerId: recipientId)
        let payloadData = try encryptedPayload.encoded()
        
        // Create routing packet
        let packet = RoutingPacket(
            type: .message,
            sourcePeerId: identity.userId,
            sourcePeerName: identity.displayName,
            destinationId: recipientId,
            maxHops: defaultMaxHops,
            payload: payloadData,
            chatType: .direct
        )
        
        // Create message model
        let message = Message(
            messageId: packet.packetId,
            senderId: identity.userId,
            senderName: identity.displayName,
            destinationChatId: chatId,
            chatType: .direct,
            hopCount: 0,
            maxHops: defaultMaxHops,
            encryptedPayload: payloadData,
            decryptedContent: content,
            status: .sending,
            isOutgoing: true
        )
        
        // Route the packet
        try await routeOutgoing(packet: packet)
        
        stats.messagesSent += 1
        
        return message
    }
    
    /// Sends a message to a group
    func sendGroupMessage(
        content: String,
        to groupId: String,
        recipientIds: [String]
    ) async throws -> Message {
        guard let identity = encryptionService.getIdentity() else {
            throw MeshRoutingError.notInitialized
        }
        
        // For group messages, we encrypt separately for each recipient
        // but send one packet containing all encrypted payloads
        let encryptedPayloads = try encryptionService.encryptForGroup(
            message: content,
            recipientIds: recipientIds
        )
        
        // Encode all payloads
        let groupPayload = GroupMessagePayload(encryptedPayloads: encryptedPayloads)
        let payloadData = try JSONEncoder().encode(groupPayload)
        
        // Create routing packet
        let packet = RoutingPacket(
            type: .groupMessage,
            sourcePeerId: identity.userId,
            sourcePeerName: identity.displayName,
            destinationId: groupId,
            maxHops: defaultMaxHops,
            payload: payloadData,
            chatType: .group,
            recipientIds: recipientIds
        )
        
        // Create message model
        let message = Message(
            messageId: packet.packetId,
            senderId: identity.userId,
            senderName: identity.displayName,
            destinationChatId: groupId,
            chatType: .group,
            hopCount: 0,
            maxHops: defaultMaxHops,
            encryptedPayload: payloadData,
            decryptedContent: content,
            status: .sending,
            isOutgoing: true
        )
        
        // Route the packet
        try await routeOutgoing(packet: packet)
        
        stats.messagesSent += 1
        
        return message
    }
    
    /// Initiates key exchange with a peer
    func initiateKeyExchange(with peerId: String) throws {
        guard let identity = encryptionService.getIdentity(),
              let keyPair = encryptionService.getKeyPair() else {
            throw MeshRoutingError.notInitialized
        }
        
        let keyExchangePayload = KeyExchangePayload(
            peerId: identity.userId,
            displayName: identity.displayName,
            publicKeyData: keyPair.publicKeyData
        )
        
        let packet = RoutingPacket(
            type: .keyExchange,
            sourcePeerId: identity.userId,
            sourcePeerName: identity.displayName,
            destinationId: peerId,
            maxHops: 1, // Key exchange is direct only
            payload: try keyExchangePayload.encoded(),
            chatType: .direct
        )
        
        // Send directly
        sendPacket(packet)
        
        NoxLogger.mesh.info("Initiated key exchange with \(peerId)")
    }
    
    // MARK: - Routing
    
    /// Routes an outgoing packet to the mesh
    private func routeOutgoing(packet: RoutingPacket) async throws {
        // Mark as seen
        seenMessages[packet.packetId] = Date()
        
        // Store for tracking
        pendingPackets[packet.packetId] = packet
        
        // Broadcast to all connected peers
        sendPacket(packet)
        
        NoxLogger.mesh.debug("Routed outgoing packet \(packet.packetId) to mesh")
    }
    
    /// Handles an incoming packet from BLE
    private func handleIncomingPacket(_ packet: RoutingPacket, from peerId: String) {
        // Check if already seen (loop prevention)
        if seenMessages[packet.packetId] != nil {
            NoxLogger.mesh.debug("Dropping duplicate packet \(packet.packetId)")
            stats.duplicatesDropped += 1
            return
        }
        
        // Mark as seen
        seenMessages[packet.packetId] = Date()
        stats.packetsReceived += 1
        
        // Check if we are the destination
        let isForMe = isPacketForMe(packet)
        
        if isForMe {
            deliverLocally(packet: packet, from: peerId)
        }
        
        // Check if we should relay
        if shouldRelay(packet: packet, isForMe: isForMe) {
            relayPacket(packet)
        }
    }
    
    private func isPacketForMe(_ packet: RoutingPacket) -> Bool {
        // Default to .direct if chatType is missing (backward compatibility)
        let chatType = packet.chatType ?? .direct
        
        // Direct message to us
        if chatType == .direct && packet.destinationId == myPeerId {
            return true
        }
        
        // Group message where we are a recipient
        if chatType == .group, let recipientIds = packet.recipientIds {
            return recipientIds.contains(myPeerId)
        }
        
        // Key exchange or announcement directed to us
        if packet.type == .keyExchange && packet.destinationId == myPeerId {
            return true
        }
        
        // Broadcast packets (peer announcements)
        if packet.type == .peerAnnounce {
            return true
        }
        
        return false
    }
    
    private func shouldRelay(packet: RoutingPacket, isForMe: Bool) -> Bool {
        // Only relay if enabled
        guard relayModeEnabled else { return false }
        
        // Don't relay if packet has expired
        guard packet.canRelay else {
            NoxLogger.mesh.debug("Packet \(packet.packetId) TTL expired")
            stats.ttlExpired += 1
            return false
        }
        
        // Don't relay our own packets
        guard packet.sourcePeerId != myPeerId else { return false }
        
        // Relay group messages even if we're a recipient
        // (other recipients might need it)
        if (packet.chatType ?? .direct) == .group {
            return true
        }
        
        // Don't relay direct messages if we're the destination
        if isForMe {
            return false
        }
        
        return true
    }
    
    private func relayPacket(_ packet: RoutingPacket) {
        let relayedPacket = packet.relayed()
        
        sendPacket(relayedPacket)
        
        stats.messagesRelayed += 1
        NoxLogger.mesh.debug("Relayed packet \(packet.packetId) (hop \(relayedPacket.hopCount)/\(relayedPacket.maxHops))")
    }
    
    private func deliverLocally(packet: RoutingPacket, from peerId: String) {
        switch packet.type {
        case .message:
            handleDirectMessage(packet: packet)
            
        case .groupMessage:
            handleGroupMessage(packet: packet)
            
        case .keyExchange:
            handleKeyExchangePacket(packet: packet)
            
        case .peerAnnounce:
            handlePeerAnnouncement(packet: packet)
            
        case .ack:
            handleAck(packet: packet)
            
        case .ping:
            // Ignore pings for now
            break
        }
    }
    
    private func handleDirectMessage(packet: RoutingPacket) {
        do {
            // Decode encrypted payload
            let encryptedPayload = try EncryptedPayload.decode(from: packet.payload)
            
            // Decrypt message
            let content = try encryptionService.decrypt(
                payload: encryptedPayload,
                fromPeerId: packet.sourcePeerId
            )
            
            // Create message model
            let message = Message(
                messageId: packet.packetId,
                senderId: packet.sourcePeerId,
                senderName: packet.sourcePeerName,
                destinationChatId: packet.sourcePeerId, // For direct chat, chatId = senderId
                chatType: .direct,
                hopCount: packet.hopCount,
                maxHops: packet.maxHops,
                timestamp: packet.timestamp,
                encryptedPayload: packet.payload,
                decryptedContent: content,
                status: .delivered,
                isOutgoing: false,
                receivedHopCount: packet.hopCount
            )
            
            stats.messagesReceived += 1
            
            NoxLogger.mesh.info("Received message from \(packet.sourcePeerName) via \(packet.hopCount) hops")
            
            delegate?.meshRouting(self, didReceiveMessage: message, from: packet.sourcePeerId)
            
            // Send acknowledgment
            sendAck(for: packet)
            
        } catch {
            NoxLogger.mesh.error("Failed to decrypt message: \(error.localizedDescription)")
        }
    }
    
    private func handleGroupMessage(packet: RoutingPacket) {
        do {
            // Decode group payload
            let groupPayload = try JSONDecoder().decode(GroupMessagePayload.self, from: packet.payload)
            
            // Find our encrypted payload
            guard let myPayload = groupPayload.encryptedPayloads[myPeerId] else {
                NoxLogger.mesh.warning("No encrypted payload for us in group message")
                return
            }
            
            // Decrypt message
            let content = try encryptionService.decrypt(
                payload: myPayload,
                fromPeerId: packet.sourcePeerId
            )
            
            // Create message model
            let message = Message(
                messageId: packet.packetId,
                senderId: packet.sourcePeerId,
                senderName: packet.sourcePeerName,
                destinationChatId: packet.destinationId, // Group ID
                chatType: .group,
                hopCount: packet.hopCount,
                maxHops: packet.maxHops,
                timestamp: packet.timestamp,
                encryptedPayload: packet.payload,
                decryptedContent: content,
                status: .delivered,
                isOutgoing: false,
                receivedHopCount: packet.hopCount
            )
            
            stats.messagesReceived += 1
            
            NoxLogger.mesh.info("Received group message from \(packet.sourcePeerName)")
            
            delegate?.meshRouting(self, didReceiveMessage: message, from: packet.sourcePeerId)
            
        } catch {
            NoxLogger.mesh.error("Failed to decrypt group message: \(error.localizedDescription)")
        }
    }
    
    private func handleKeyExchangePacket(packet: RoutingPacket) {
        do {
            let keyExchangePayload = try KeyExchangePayload.decode(from: packet.payload)
            
            // Check if we already have the key (to decide if we need to respond)
            let isNewKey = !peerManager.hasExchangedKeys(with: keyExchangePayload.peerId)
            
            peerManager.handleKeyExchange(
                peerId: keyExchangePayload.peerId,
                displayName: keyExchangePayload.displayName,
                publicKeyData: keyExchangePayload.publicKeyData
            )
            
            delegate?.meshRouting(self, didReceiveKeyExchange: keyExchangePayload.peerId)
            
            NoxLogger.mesh.info("Received key exchange from \(keyExchangePayload.displayName)")
            
            // Send our key back if this is a new exchange
            if isNewKey {
                try initiateKeyExchange(with: keyExchangePayload.peerId)
            }
            
        } catch {
            NoxLogger.mesh.error("Failed to handle key exchange: \(error.localizedDescription)")
        }
    }
    
    private func handlePeerAnnouncement(packet: RoutingPacket) {
        do {
            let announcement = try PeerAnnouncePayload.decode(from: packet.payload)
            
            // Update peer info
            peerManager.updatePeerDisplayName(announcement.peerId, name: announcement.displayName)
            
            if let publicKeyData = announcement.publicKeyData {
                peerManager.updatePeerPublicKey(announcement.peerId, publicKeyData: publicKeyData)
            }
            
            NoxLogger.mesh.debug("Received peer announcement from \(announcement.displayName)")
            
        } catch {
            NoxLogger.mesh.error("Failed to handle peer announcement: \(error.localizedDescription)")
        }
    }
    
    private func handleAck(packet: RoutingPacket) {
        do {
            let ack = try AckPayload.decode(from: packet.payload)
            
            // Update pending packet status
            if pendingPackets[ack.originalPacketId] != nil {
                pendingPackets.removeValue(forKey: ack.originalPacketId)
                
                delegate?.meshRouting(self, didSendMessage: ack.originalPacketId, status: .delivered)
                
                NoxLogger.mesh.debug("Received ack for \(ack.originalPacketId)")
            }
            
        } catch {
            NoxLogger.mesh.error("Failed to handle ack: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Packet Transmission
    
    private func sendPacket(_ packet: RoutingPacket) {
        do {
            let data = try packet.encoded()
            bleService.broadcast(data: data)
        } catch {
            NoxLogger.mesh.error("Failed to encode packet: \(error.localizedDescription)")
        }
    }
    
    private func sendAck(for packet: RoutingPacket) {
        guard let identity = encryptionService.getIdentity() else { return }
        
        do {
            let ackPayload = AckPayload(originalPacketId: packet.packetId, status: "delivered")
            
            let ackPacket = RoutingPacket(
                type: .ack,
                sourcePeerId: identity.userId,
                sourcePeerName: identity.displayName,
                destinationId: packet.sourcePeerId,
                maxHops: packet.maxHops,
                payload: try ackPayload.encoded(),
                chatType: .direct
            )
            
            sendPacket(ackPacket)
            
        } catch {
            NoxLogger.mesh.error("Failed to send ack: \(error.localizedDescription)")
        }
    }
    
    private func sendPeerAnnouncement() {
        guard let identity = encryptionService.getIdentity(),
              let keyPair = encryptionService.getKeyPair() else {
            return
        }
        
        do {
            let announcement = PeerAnnouncePayload(
                peerId: identity.userId,
                displayName: identity.displayName,
                publicKeyData: keyPair.publicKeyData,
                relayEnabled: relayModeEnabled
            )
            
            let packet = RoutingPacket(
                type: .peerAnnounce,
                sourcePeerId: identity.userId,
                sourcePeerName: identity.displayName,
                destinationId: "broadcast",
                maxHops: 1,
                payload: try announcement.encoded(),
                chatType: .direct
            )
            
            sendPacket(packet)
            
        } catch {
            NoxLogger.mesh.error("Failed to send announcement: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Cleanup
    
    private func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.cleanupSeenMessages()
            }
        }
    }
    
    private func stopCleanupTimer() {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
    }
    
    private func cleanupSeenMessages() {
        let now = Date()
        seenMessages = seenMessages.filter { (_, timestamp) in
            now.timeIntervalSince(timestamp) < seenMessageTTL
        }
    }
    
    private func startAnnouncements() {
        announceTimer = Timer.scheduledTimer(withTimeInterval: BLEConstants.announceInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sendPeerAnnouncement()
            }
        }
        
        // Send initial announcement
        sendPeerAnnouncement()
    }
    
    private func stopAnnouncements() {
        announceTimer?.invalidate()
        announceTimer = nil
    }
}

// MARK: - BLEServiceDelegate

extension MeshRoutingService: BLEServiceDelegate {
    
    nonisolated func bleService(_ service: BLEService, didDiscoverPeer peer: BLEPeer) {
        // Handled by PeerManager
    }
    
    nonisolated func bleService(_ service: BLEService, didConnectPeer peerId: String) {
        Task { @MainActor in
            // Initiate key exchange on new connection
            do {
                try initiateKeyExchange(with: peerId)
            } catch {
                NoxLogger.mesh.error("Failed to initiate key exchange: \(error.localizedDescription)")
            }
        }
    }
    
    nonisolated func bleService(_ service: BLEService, didDisconnectPeer peerId: String) {
        // Handled by PeerManager
    }
    
    nonisolated func bleService(_ service: BLEService, didReceiveData data: Data, from peerId: String) {
        Task { @MainActor in
            do {
                let packet = try RoutingPacket.decode(from: data)
                handleIncomingPacket(packet, from: peerId)
            } catch {
                if let string = String(data: data, encoding: .utf8) {
                     NoxLogger.mesh.error("Failed to decode incoming packet: \(error.localizedDescription)\nData: \(string)")
                } else {
                     NoxLogger.mesh.error("Failed to decode incoming packet: \(error.localizedDescription)\nData (hex): \(data.map { String(format: "%02hhx", $0) }.joined())")
                }
            }
        }
    }
    
    nonisolated func bleService(_ service: BLEService, didUpdatePowerState state: BLEPowerState) {
        // Could notify UI about Bluetooth state changes
    }
}

// MARK: - PeerManagerDelegate

extension MeshRoutingService: PeerManagerDelegate {
    
    nonisolated func peerManager(_ manager: PeerManager, didDiscoverPeer peer: Peer) {
        // Peer discovery handled
    }
    
    nonisolated func peerManager(_ manager: PeerManager, didConnectPeer peerId: String) {
        // Connection handled in BLEServiceDelegate
    }
    
    nonisolated func peerManager(_ manager: PeerManager, didDisconnectPeer peerId: String) {
        // Disconnection handling
    }
    
    nonisolated func peerManager(_ manager: PeerManager, didReceiveKeyExchange peerId: String, publicKey: Data) {
        Task { @MainActor in
            delegate?.meshRouting(self, didReceiveKeyExchange: peerId)
        }
    }
}

// MARK: - Supporting Types

/// Statistics for mesh routing
struct MeshStats {
    var messagesSent = 0
    var messagesReceived = 0
    var messagesRelayed = 0
    var packetsReceived = 0
    var duplicatesDropped = 0
    var ttlExpired = 0
}

/// Payload for group messages containing per-recipient encrypted data
struct GroupMessagePayload: Codable {
    let encryptedPayloads: [String: EncryptedPayload]
}

/// Mesh routing errors
enum MeshRoutingError: Error, LocalizedError {
    case notInitialized
    case encryptionFailed
    case peerNotFound
    case keyExchangeRequired
    
    var errorDescription: String? {
        switch self {
        case .notInitialized: return "Mesh routing not initialized"
        case .encryptionFailed: return "Failed to encrypt message"
        case .peerNotFound: return "Peer not found"
        case .keyExchangeRequired: return "Key exchange required before messaging"
        }
    }
}
