import Foundation
import Combine

/// ViewModel for the nearby peers screen
@MainActor
final class PeersViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var peers: [Peer] = []
    @Published private(set) var isScanning = false
    @Published private(set) var bluetoothState: BLEPowerState = .unknown
    @Published var showingPeerDetail: Peer? = nil
    @Published var errorMessage: String? = nil
    
    // MARK: - Properties
    
    private let peerManager: PeerManager
    private let meshRoutingService: MeshRoutingService
    private let bleService: BLEService
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Computed Properties
    
    var connectedPeers: [Peer] {
        peers.filter { $0.isConnected }
    }
    
    var availablePeers: [Peer] {
        peers.filter { !$0.isConnected && $0.isAvailable }
    }
    
    var isBluetoothReady: Bool {
        bluetoothState.isReady
    }
    
    // MARK: - Initialization
    
    init() {
        peerManager = PeerManager.shared
        meshRoutingService = MeshRoutingService.shared
        bleService = BLEService.shared
        
        setupObservers()
    }
    
    // MARK: - Setup
    
    private func setupObservers() {
        // Observe peers
        peerManager.$peers
            .receive(on: DispatchQueue.main)
            .map { Array($0.values).sorted { $0.rssi > $1.rssi } }
            .assign(to: &$peers)
        
        // Observe Bluetooth state
        bleService.$powerState
            .receive(on: DispatchQueue.main)
            .assign(to: &$bluetoothState)
        
        // Observe scanning state
        bleService.$isActive
            .receive(on: DispatchQueue.main)
            .assign(to: &$isScanning)
    }
    
    // MARK: - Actions
    
    /// Connects to a peer
    func connect(to peer: Peer) {
        bleService.connect(peerId: peer.peerId)
    }
    
    /// Disconnects from a peer
    func disconnect(from peer: Peer) {
        bleService.disconnect(peerId: peer.peerId)
    }
    
    /// Initiates key exchange with a peer
    func exchangeKeys(with peer: Peer) {
        do {
            try meshRoutingService.initiateKeyExchange(with: peer.peerId)
        } catch {
            errorMessage = "Failed to exchange keys: \(error.localizedDescription)"
        }
    }
    
    /// Checks if keys have been exchanged with a peer
    func hasExchangedKeys(with peer: Peer) -> Bool {
        peerManager.hasExchangedKeys(with: peer.peerId)
    }
    
    /// Starts a chat with a peer
    func startChat(with peer: Peer) -> Chat? {
        do {
            let persistenceService = PersistenceService.shared
            return try persistenceService.getOrCreateDirectChat(with: peer)
        } catch {
            errorMessage = "Failed to create chat: \(error.localizedDescription)"
            return nil
        }
    }
}
