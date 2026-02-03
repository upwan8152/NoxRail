import Foundation
import Combine

/// ViewModel for settings screen
@MainActor
final class SettingsViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var displayName: String = ""
    @Published var relayModeEnabled: Bool = false
    @Published private(set) var userId: String = ""
    @Published private(set) var publicKeyPreview: String = ""
    @Published private(set) var stats: MeshStats = MeshStats()
    @Published private(set) var bluetoothState: BLEPowerState = .unknown
    @Published private(set) var connectedPeerCount: Int = 0
    @Published private(set) var discoveredPeerCount: Int = 0
    @Published var showingResetConfirmation = false
    @Published var errorMessage: String? = nil
    
    // MARK: - Properties
    
    private let encryptionService: EncryptionService
    private let meshRoutingService: MeshRoutingService
    private let bleService: BLEService
    private let peerManager: PeerManager
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Computed Properties
    
    var isBluetoothReady: Bool {
        bluetoothState.isReady
    }
    
    var isMeshActive: Bool {
        meshRoutingService.isActive
    }
    
    // MARK: - Initialization
    
    init() {
        encryptionService = EncryptionService.shared
        meshRoutingService = MeshRoutingService.shared
        bleService = BLEService.shared
        peerManager = PeerManager.shared
        
        loadIdentity()
        setupObservers()
    }
    
    // MARK: - Setup
    
    private func loadIdentity() {
        if let identity = encryptionService.getIdentity() {
            displayName = identity.displayName
            userId = identity.userId
            publicKeyPreview = identity.publicKeyData.prefix(16).hexString + "..."
        }
    }
    
    private func setupObservers() {
        // Observe relay mode
        meshRoutingService.$relayModeEnabled
            .receive(on: DispatchQueue.main)
            .assign(to: &$relayModeEnabled)
        
        // Observe stats
        meshRoutingService.$stats
            .receive(on: DispatchQueue.main)
            .assign(to: &$stats)
        
        // Observe Bluetooth state
        bleService.$powerState
            .receive(on: DispatchQueue.main)
            .assign(to: &$bluetoothState)
        
        // Observe connected peers
        bleService.$connectedPeerIds
            .receive(on: DispatchQueue.main)
            .map { $0.count }
            .assign(to: &$connectedPeerCount)
        
        // Observe discovered peers
        peerManager.$peers
            .receive(on: DispatchQueue.main)
            .map { $0.count }
            .assign(to: &$discoveredPeerCount)
    }
    
    // MARK: - Actions
    
    /// Updates the display name
    func updateDisplayName() {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Display name cannot be empty"
            return
        }
        
        do {
            try encryptionService.updateDisplayName(trimmedName)
            bleService.localName = "\(BLEConstants.localNamePrefix)-\(trimmedName)"
        } catch {
            errorMessage = "Failed to update name: \(error.localizedDescription)"
        }
    }
    
    /// Toggles relay mode
    func toggleRelayMode() {
        meshRoutingService.setRelayMode(!relayModeEnabled)
    }
    
    /// Resets all data and identity
    func resetAllData() {
        do {
            try encryptionService.reset()
            try PersistenceService.shared.clearAllData()
            
            // Reinitialize
            Task {
                do {
                    _ = try await encryptionService.initialize()
                    loadIdentity()
                } catch {
                    errorMessage = "Failed to reinitialize: \(error.localizedDescription)"
                }
            }
        } catch {
            errorMessage = "Failed to reset: \(error.localizedDescription)"
        }
        
        showingResetConfirmation = false
    }
    
    /// Copies user ID to clipboard
    func copyUserId() {
        UIPasteboard.general.string = userId
    }
    
    /// Copies public key to clipboard
    func copyPublicKey() {
        if let identity = encryptionService.getIdentity() {
            UIPasteboard.general.string = identity.publicKeyBase64
        }
    }
}

// MARK: - UIPasteboard import
import UIKit
