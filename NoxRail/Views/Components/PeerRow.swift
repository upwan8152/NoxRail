import SwiftUI

/// Row component for displaying a peer in a list
struct PeerRow: View {
    let peer: Peer
    let isConnected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.noxPrimary.opacity(0.7), Color.noxSecondary.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                
                Text(peer.displayName.firstLetter)
                    .font(.headline.bold())
                    .foregroundStyle(.white)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(peer.displayName)
                        .font(.headline)
                    
                    if peer.hasExchangedKeys {
                        Image(systemName: "key.fill")
                            .font(.caption)
                            .foregroundStyle(Color.noxSuccess)
                    }
                }
                
                HStack(spacing: 8) {
                    // Connection status
                    HStack(spacing: 4) {
                        Circle()
                            .fill(isConnected ? .green : .orange)
                            .frame(width: 6, height: 6)
                        
                        Text(isConnected ? "Connected" : "Available")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    // Signal strength
                    HStack(spacing: 2) {
                        Image(systemName: signalIcon)
                            .font(.caption2)
                        Text("\(peer.rssi) dBm")
                            .font(.caption)
                    }
                    .foregroundStyle(signalColor)
                }
            }
            
            Spacer()
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
    
    private var signalIcon: String {
        peer.signalStrength.icon
    }
    
    private var signalColor: Color {
        switch peer.signalStrength {
        case .excellent: return .green
        case .good: return .blue
        case .fair: return .orange
        case .weak: return .red
        }
    }
}

#Preview {
    List {
        PeerRow(
            peer: Peer(
                peerId: "test-1",
                displayName: "Alice",
                publicKeyData: Data([1, 2, 3]),
                rssi: -45,
                isConnected: true
            ),
            isConnected: true
        )
        
        PeerRow(
            peer: Peer(
                peerId: "test-2",
                displayName: "Bob",
                rssi: -70,
                isConnected: false
            ),
            isConnected: false
        )
    }
}
