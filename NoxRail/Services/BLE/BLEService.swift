import Foundation
import CoreBluetooth
import Combine

/// Delegate protocol for BLE service events
protocol BLEServiceDelegate: AnyObject {
    func bleService(_ service: BLEService, didDiscoverPeer peer: BLEPeer)
    func bleService(_ service: BLEService, didConnectPeer peerId: String)
    func bleService(_ service: BLEService, didDisconnectPeer peerId: String)
    func bleService(_ service: BLEService, didReceiveData data: Data, from peerId: String)
    func bleService(_ service: BLEService, didUpdatePowerState state: BLEPowerState)
}

/// Unified BLE service that coordinates Central and Peripheral managers
@MainActor
final class BLEService: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var powerState: BLEPowerState = .unknown
    @Published private(set) var isActive = false
    @Published private(set) var discoveredPeers: [String: BLEPeer] = [:]
    @Published private(set) var connectedPeerIds: Set<String> = []
    
    // MARK: - Properties
    
    private let centralManager: BLECentralManager
    private let peripheralManager: BLEPeripheralManager
    
    private var staleCleanupTimer: Timer?
    private var announceTimer: Timer?
    
    weak var delegate: BLEServiceDelegate?
    
    var localName: String {
        get { peripheralManager.localName }
        set { peripheralManager.localName = newValue }
    }
    
    // MARK: - Singleton
    
    static let shared = BLEService()
    
    // MARK: - Initialization
    
    private init() {
        centralManager = BLECentralManager()
        peripheralManager = BLEPeripheralManager()
        
        centralManager.delegate = self
        peripheralManager.delegate = self
    }
    
    // MARK: - Lifecycle
    
    /// Starts the BLE service
    func start() {
        guard !isActive else { return }
        
        NoxLogger.ble.info("Starting BLE service")
        
        centralManager.start()
        peripheralManager.start()
        
        isActive = true
        
        startStaleCleanup()
    }
    
    /// Stops the BLE service
    func stop() {
        guard isActive else { return }
        
        NoxLogger.ble.info("Stopping BLE service")
        
        stopStaleCleanup()
        
        centralManager.stop()
        peripheralManager.stop()
        
        discoveredPeers.removeAll()
        connectedPeerIds.removeAll()
        
        isActive = false
    }
    
    // MARK: - Connection Management
    
    /// Connects to a peer
    func connect(peerId: String) {
        centralManager.connect(peerId: peerId)
    }
    
    /// Disconnects from a peer
    func disconnect(peerId: String) {
        centralManager.disconnect(peerId: peerId)
    }
    
    /// Checks if a peer is connected
    func isConnected(peerId: String) -> Bool {
        connectedPeerIds.contains(peerId)
    }
    
    // MARK: - Data Transmission
    
    /// Sends data to a specific peer
    func send(data: Data, to peerId: String) -> Bool {
        // Try central first (as a scanner, we write to peripherals)
        if centralManager.sendData(data, to: peerId) {
            return true
        }
        
        // Try peripheral (as an advertiser, we notify centrals)
        peripheralManager.sendToCentral(centralId: peerId, data: data)
        return true
    }
    
    /// Broadcasts data to all connected peers
    func broadcast(data: Data) {
        // Send via central to all connected peripherals
        centralManager.sendToAllConnected(data: data)
        
        // Send via peripheral to all subscribed centrals
        peripheralManager.sendToAllCentrals(data: data)
    }
    
    // MARK: - Peer Management
    
    /// Gets all currently visible peers
    func getAllPeers() -> [BLEPeer] {
        Array(discoveredPeers.values)
    }
    
    /// Gets a specific peer
    func getPeer(id: String) -> BLEPeer? {
        discoveredPeers[id]
    }
    
    /// Gets only connected peers
    func getConnectedPeers() -> [BLEPeer] {
        discoveredPeers.values.filter { connectedPeerIds.contains($0.id) }
    }
    
    // MARK: - Private Methods
    
    private func startStaleCleanup() {
        staleCleanupTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.cleanupStalePeers()
            }
        }
    }
    
    private func stopStaleCleanup() {
        staleCleanupTimer?.invalidate()
        staleCleanupTimer = nil
    }
    
    private func cleanupStalePeers() {
        let now = Date()
        let staleTimeout = BLEConstants.peerStaleTimeout
        
        var peersToRemove: [String] = []
        
        for (id, peer) in discoveredPeers {
            if !connectedPeerIds.contains(id) {
                let timeSinceLastSeen = now.timeIntervalSince(peer.lastSeen)
                if timeSinceLastSeen > staleTimeout {
                    peersToRemove.append(id)
                }
            }
        }
        
        for id in peersToRemove {
            discoveredPeers.removeValue(forKey: id)
            NoxLogger.ble.debug("Removed stale peer: \(id)")
        }
    }
}

// MARK: - BLECentralManagerDelegate

extension BLEService: BLECentralManagerDelegate {
    
    nonisolated func centralManager(_ manager: BLECentralManager, didDiscoverPeer peer: BLEPeer) {
        Task { @MainActor in
            var updatedPeer = peer
            
            // Preserve connected state if already connected
            if let existingPeer = discoveredPeers[peer.id] {
                updatedPeer.connectionState = existingPeer.connectionState
            }
            
            discoveredPeers[peer.id] = updatedPeer
            delegate?.bleService(self, didDiscoverPeer: updatedPeer)
        }
    }
    
    nonisolated func centralManager(_ manager: BLECentralManager, didConnectPeer peerId: String) {
        Task { @MainActor in
            connectedPeerIds.insert(peerId)
            
            if var peer = discoveredPeers[peerId] {
                peer.connectionState = .connected
                discoveredPeers[peerId] = peer
            }
            
            delegate?.bleService(self, didConnectPeer: peerId)
        }
    }
    
    nonisolated func centralManager(_ manager: BLECentralManager, didDisconnectPeer peerId: String) {
        Task { @MainActor in
            connectedPeerIds.remove(peerId)
            
            if var peer = discoveredPeers[peerId] {
                peer.connectionState = .disconnected
                discoveredPeers[peerId] = peer
            }
            
            delegate?.bleService(self, didDisconnectPeer: peerId)
        }
    }
    
    nonisolated func centralManager(_ manager: BLECentralManager, didReceiveData data: Data, from peerId: String) {
        Task { @MainActor in
            delegate?.bleService(self, didReceiveData: data, from: peerId)
        }
    }
    
    nonisolated func centralManagerDidUpdateState(_ manager: BLECentralManager, state: BLEPowerState) {
        Task { @MainActor in
            powerState = state
            delegate?.bleService(self, didUpdatePowerState: state)
        }
    }
}

// MARK: - BLEPeripheralManagerDelegate

extension BLEService: BLEPeripheralManagerDelegate {
    
    nonisolated func peripheralManager(_ manager: BLEPeripheralManager, didReceiveData data: Data, from centralId: String) {
        Task { @MainActor in
            delegate?.bleService(self, didReceiveData: data, from: centralId)
        }
    }
    
    nonisolated func peripheralManager(_ manager: BLEPeripheralManager, centralDidConnect centralId: String) {
        Task { @MainActor in
            connectedPeerIds.insert(centralId)
            
            // Create a peer entry for the central if it doesn't exist
            if discoveredPeers[centralId] == nil {
                let peer = BLEPeer(
                    id: centralId,
                    displayName: "Central-\(centralId.prefix(4))",
                    connectionState: .connected
                )
                discoveredPeers[centralId] = peer
            }
            
            delegate?.bleService(self, didConnectPeer: centralId)
        }
    }
    
    nonisolated func peripheralManager(_ manager: BLEPeripheralManager, centralDidDisconnect centralId: String) {
        Task { @MainActor in
            connectedPeerIds.remove(centralId)
            
            if var peer = discoveredPeers[centralId] {
                peer.connectionState = .disconnected
                discoveredPeers[centralId] = peer
            }
            
            delegate?.bleService(self, didDisconnectPeer: centralId)
        }
    }
    
    nonisolated func peripheralManagerDidUpdateState(_ manager: BLEPeripheralManager, state: BLEPowerState) {
        Task { @MainActor in
            if powerState != .poweredOn {
                powerState = state
            }
            delegate?.bleService(self, didUpdatePowerState: state)
        }
    }
}
