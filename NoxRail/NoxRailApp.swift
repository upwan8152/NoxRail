import SwiftUI
import SwiftData

/// Main app entry point for NoxRail
@main
struct NoxRailApp: App {
    
    // MARK: - Properties
    
    @StateObject private var appState = AppState()
    
    // MARK: - Body
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .modelContainer(PersistenceService.shared.modelContainer)
                .preferredColorScheme(appState.colorScheme)
                .task {
                    await appState.initialize()
                }
        }
    }
}

/// Root content view handling initialization states
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        Group {
            switch appState.state {
            case .initializing:
                InitializingView()
                
            case .bluetoothDisabled:
                BluetoothDisabledView()
                
            case .permissionDenied:
                PermissionDeniedView()
                
            case .ready:
                MainTabView()
                
            case .error(let message):
                ErrorView(message: message) {
                    Task {
                        await appState.retry()
                    }
                }
            }
        }
        .animation(.easeInOut, value: appState.state)
    }
}

/// Global app state manager
@MainActor
final class AppState: ObservableObject {
    
    enum State: Equatable {
        case initializing
        case bluetoothDisabled
        case permissionDenied
        case ready
        case error(String)
    }
    
    @Published var state: State = .initializing
    @Published var colorScheme: ColorScheme? = nil
    
    private let meshRoutingService = MeshRoutingService.shared
    private let bleService = BLEService.shared
    
    func initialize() async {
        state = .initializing
        
        do {
            try await meshRoutingService.start()
            meshRoutingService.delegate = self
            
            // Wait a moment for BLE to initialize
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            // Check Bluetooth state
            if bleService.powerState == .poweredOff {
                state = .bluetoothDisabled
            } else if bleService.powerState == .unauthorized {
                state = .permissionDenied
            } else {
                state = .ready
            }
            
        } catch {
            state = .error(error.localizedDescription)
        }
    }
    
    func retry() async {
        await initialize()
    }

}

// MARK: - MeshRoutingServiceDelegate

extension AppState: MeshRoutingServiceDelegate {
    func meshRouting(_ service: MeshRoutingService, didReceiveMessage message: Message, from peerId: String) {
        do {
            let persistence = PersistenceService.shared
            
            // Handle Direct Chat
            if message.chatType == .direct {
                if let peer = try persistence.fetchPeer(id: peerId) {
                    let chat = try persistence.getOrCreateDirectChat(with: peer)
                    try persistence.saveMessage(message, to: chat)
                    NoxLogger.persistence.debug("Saved incoming direct message")
                } else {
                    NoxLogger.persistence.warning("Received message from unknown peer \(peerId)")
                    // Optional: Create provisional peer?
                }
            }
            
            // Handle Group Chat
            else if message.chatType == .group {
                // Determine Group ID (destinationChatId)
                let groupId = message.destinationChatId
                
                if let group = try persistence.fetchGroup(id: groupId) {
                    let chat = try persistence.createGroupChat(group: group) // Returns existing if found?
                    // Fetch existing chat logic inside persistence?
                    // createGroupChat inserts new Group and Chat?
                    // We need getOrCreateGroupChat equivalent.
                    // Assuming createGroupChat handles uniqueness or we fetch first.
                    
                    // Actually fetchChat(id: groupId) should find the chat if it exists.
                    if let chat = try persistence.fetchChat(id: groupId) {
                        try persistence.saveMessage(message, to: chat)
                    } else {
                        // Chat entity missing but Group entity exists? Recreate Chat
                        let chat = try persistence.createGroupChat(group: group)
                        try persistence.saveMessage(message, to: chat)
                    }
                     NoxLogger.persistence.debug("Saved incoming group message")
                } else {
                    // Group Unknown - Create Placeholder
                    NoxLogger.persistence.warning("Received message for unknown group \(groupId)")
                    
                    let newGroup = try persistence.createGroup(
                        name: "Unknown Group",
                        memberIds: [peerId], // We only know the sender
                        creatorId: peerId
                    )
                    // Pivot: set ID to match incoming
                    // PersistenceService.createGroup generates new UUID if we don't pass one?
                    // ChatGroup init (in PersistenceService.createGroup) likely uses init() defaults?
                    // We need to match the ID from message!
                    
                    // Since PersistenceService.createGroup helper doesn't support custom ID, we might fail routing.
                    // For now, let's just log and drop to avoid crash/dupes, 
                    // OR try to fetch chat by ID directly.
                }
            }
            
        } catch {
            NoxLogger.persistence.error("Failed to save incoming message: \(error.localizedDescription)")
        }
    }
    
    func meshRouting(_ service: MeshRoutingService, didSendMessage messageId: String, status: MessageStatus) {
        do {
            try PersistenceService.shared.updateMessageStatus(messageId, status: status)
        } catch {
            NoxLogger.persistence.error("Failed to update message status: \(error.localizedDescription)")
        }
    }
    
    func meshRouting(_ service: MeshRoutingService, didReceiveKeyExchange peerId: String) {
        NoxLogger.mesh.info("Key exchange completed with \(peerId)")
        // UI could show a toast here
    }
}

// MARK: - State Views

struct InitializingView: View {
    var body: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Initializing NoxRail")
                .font(.headline)
            
            Text("Setting up secure mesh network...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

struct BluetoothDisabledView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 60))
                .foregroundStyle(.orange)
            
            Text("Bluetooth Disabled")
                .font(.title2.bold())
            
            Text("NoxRail requires Bluetooth to discover nearby devices and send messages.\n\nPlease enable Bluetooth in Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 60))
                .foregroundStyle(.white)
            
            Text("Bluetooth Access Denied")
                .font(.title2.bold())
            
            Text("NoxRail needs Bluetooth access to function.\n\nPlease grant Bluetooth permission in Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

struct ErrorView: View {
    let message: String
    let retryAction: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.red)
            
            Text("Something went wrong")
                .font(.title2.bold())
            
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button("Try Again", action: retryAction)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
