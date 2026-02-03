import Foundation
import Combine

/// Delegate protocol for peer manager events
protocol PeerManagerDelegate: AnyObject {
    func peerManager(_ manager: PeerManager, didDiscoverPeer peer: Peer)
    func peerManager(_ manager: PeerManager, didConnectPeer peerId: String)
    func peerManager(_ manager: PeerManager, didDisconnectPeer peerId: String)
    func peerManager(_ manager: PeerManager, didReceiveKeyExchange peerId: String, publicKey: Data)
}

/// Manages discovered and connected peers in the mesh network
@MainActor
final class PeerManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var peers: [String: Peer] = [:]
    @Published private(set) var connectedPeerIds: Set<String> = []
    
    // MARK: - Properties
    
    private let bleService: BLEService
    private let encryptionService: EncryptionService
    
    private var cancellables = Set<AnyCancellable>()
    
    weak var delegate: PeerManagerDelegate?
    
    // MARK: - Computed Properties
    
    var allPeers: [Peer] {
        Array(peers.values).sorted { $0.lastSeen > $1.lastSeen }
    }
    
    var connectedPeers: [Peer] {
        peers.values.filter { connectedPeerIds.contains($0.peerId) }
    }
    
    var availablePeers: [Peer] {
        peers.values.filter { $0.isAvailable && !$0.isStale }
    }
    
    // MARK: - Singleton
    
    static let shared = PeerManager()
    
    // MARK: - Initialization
    
    private init() {
        bleService = BLEService.shared
        encryptionService = EncryptionService.shared
    }
    
    // MARK: - Setup
    
    func setup() {
        // Observe BLE discovered peers
        bleService.$discoveredPeers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] blePeers in
                self?.handleDiscoveredPeers(blePeers)
            }
            .store(in: &cancellables)
        
        // Observe connected peer IDs
        bleService.$connectedPeerIds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ids in
                self?.handleConnectedPeerIds(ids)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Peer Operations
    
    /// Gets a peer by ID
    func getPeer(id: String) -> Peer? {
        peers[id]
    }
    
    /// Updates a peer's display name
    func updatePeerDisplayName(_ peerId: String, name: String) {
        if var peer = peers[peerId] {
            peer.displayName = name
            peers[peerId] = peer
        }
    }
    
    /// Updates a peer's public key
    func updatePeerPublicKey(_ peerId: String, publicKeyData: Data) {
        if var peer = peers[peerId] {
            peer.publicKeyData = publicKeyData
            peers[peerId] = peer
            
            // Store in encryption service
            do {
                try encryptionService.storePeerPublicKey(peerId: peerId, publicKeyData: publicKeyData)
                NoxLogger.mesh.info("Stored public key for peer \(peerId)")
            } catch {
                NoxLogger.mesh.error("Failed to store public key: \(error.localizedDescription)")
            }
        }
    }
    
    /// Creates or updates a peer from key exchange
    func handleKeyExchange(peerId: String, displayName: String, publicKeyData: Data) {
        if var peer = peers[peerId] {
            peer.displayName = displayName
            peer.publicKeyData = publicKeyData
            peer.lastSeen = Date()
            peers[peerId] = peer
        } else {
            let peer = Peer(
                peerId: peerId,
                displayName: displayName,
                publicKeyData: publicKeyData,
                lastSeen: Date(),
                isAvailable: true
            )
            peers[peerId] = peer
        }
        
        // Store in encryption service
        do {
            try encryptionService.storePeerPublicKey(peerId: peerId, publicKeyData: publicKeyData)
            NoxLogger.mesh.info("Received key exchange from peer \(peerId)")
            delegate?.peerManager(self, didReceiveKeyExchange: peerId, publicKey: publicKeyData)
        } catch {
            NoxLogger.mesh.error("Failed to store exchanged key: \(error.localizedDescription)")
        }
    }
    
    /// Checks if we have exchanged keys with a peer
    func hasExchangedKeys(with peerId: String) -> Bool {
        if let peer = peers[peerId], peer.hasExchangedKeys {
            return true
        }
        return encryptionService.hasPeerPublicKey(peerId: peerId)
    }
    
    /// Removes a peer
    func removePeer(_ peerId: String) {
        peers.removeValue(forKey: peerId)
    }
    
    /// Clears all peers
    func clearPeers() {
        peers.removeAll()
        connectedPeerIds.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func handleDiscoveredPeers(_ blePeers: [String: BLEPeer]) {
        for (id, blePeer) in blePeers {
            if var peer = peers[id] {
                // Update existing peer
                peer.rssi = blePeer.rssi
                peer.lastSeen = blePeer.lastSeen
                peer.isConnected = blePeer.isConnected
                peer.displayName = blePeer.displayName
                peers[id] = peer
            } else {
                // Create new peer
                let peer = Peer(
                    peerId: id,
                    displayName: blePeer.displayName,
                    rssi: blePeer.rssi,
                    lastSeen: blePeer.lastSeen,
                    isConnected: blePeer.isConnected,
                    isAvailable: true
                )
                peers[id] = peer
                delegate?.peerManager(self, didDiscoverPeer: peer)
            }
        }
    }
    
    private func handleConnectedPeerIds(_ ids: Set<String>) {
        let previouslyConnected = connectedPeerIds
        connectedPeerIds = ids
        
        // Notify about new connections
        for id in ids where !previouslyConnected.contains(id) {
            if var peer = peers[id] {
                peer.isConnected = true
                peers[id] = peer
            }
            delegate?.peerManager(self, didConnectPeer: id)
        }
        
        // Notify about disconnections
        for id in previouslyConnected where !ids.contains(id) {
            if var peer = peers[id] {
                peer.isConnected = false
                peers[id] = peer
            }
            delegate?.peerManager(self, didDisconnectPeer: id)
        }
    }
}
