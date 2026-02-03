import SwiftUI

/// View displaying nearby BLE peers
struct NearbyPeersView: View {
    @ObservedObject var viewModel: PeersViewModel
    @State private var selectedPeer: Peer? = nil
    @State private var showingChatSheet = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                if viewModel.peers.isEmpty {
                    emptyStateView
                } else {
                    peerListView
                }
            }
            .navigationTitle("Nearby")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NetworkStatusBanner(
                        bluetoothState: viewModel.bluetoothState,
                        connectedCount: viewModel.connectedPeers.count
                    )
                }
            }
            .sheet(item: $selectedPeer) { peer in
                PeerDetailSheet(
                    peer: peer,
                    viewModel: viewModel,
                    onStartChat: { chat in
                        selectedPeer = nil
                        showingChatSheet = true
                    }
                )
                .presentationDetents([.medium])
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }
    
    // MARK: - Subviews
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("No Nearby Devices")
                .font(.title2.bold())
            
            Text("Make sure other NoxRail users are nearby with Bluetooth enabled.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            if viewModel.isScanning {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Scanning...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var peerListView: some View {
        List {
            if !viewModel.connectedPeers.isEmpty {
                Section {
                    ForEach(viewModel.connectedPeers, id: \.peerId) { peer in
                        PeerRow(peer: peer, isConnected: true)
                            .onTapGesture {
                                selectedPeer = peer
                            }
                    }
                } header: {
                    Text("Connected")
                }
            }
            
            if !viewModel.availablePeers.isEmpty {
                Section {
                    ForEach(viewModel.availablePeers, id: \.peerId) { peer in
                        PeerRow(peer: peer, isConnected: false)
                            .onTapGesture {
                                selectedPeer = peer
                            }
                    }
                } header: {
                    HStack {
                        Text("Available")
                        if viewModel.isScanning {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            // Refresh is handled automatically by BLE scanning
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
}

/// Detail sheet for a peer
struct PeerDetailSheet: View {
    let peer: Peer
    @ObservedObject var viewModel: PeersViewModel
    let onStartChat: (Chat) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.noxPrimary, Color.noxSecondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                    
                    Text(peer.displayName.firstLetter)
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                }
                
                // Name and status
                VStack(spacing: 4) {
                    Text(peer.displayName)
                        .font(.title2.bold())
                    
                    HStack(spacing: 8) {
                        Circle()
                            .fill(peer.isConnected ? .green : .orange)
                            .frame(width: 8, height: 8)
                        
                        Text(peer.isConnected ? "Connected" : "Available")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Signal strength
                HStack {
                    Image(systemName: peer.signalStrength.icon)
                        .foregroundStyle(signalColor)
                    Text("Signal: \(peer.signalStrength.rawValue.capitalized)")
                        .font(.subheadline)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .clipShape(Capsule())
                
                Spacer()
                
                // Actions
                VStack(spacing: 12) {
                    if !peer.isConnected {
                        Button {
                            viewModel.connect(to: peer)
                        } label: {
                            Label("Connect", systemImage: "link")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        if !viewModel.hasExchangedKeys(with: peer) {
                            Button {
                                viewModel.exchangeKeys(with: peer)
                            } label: {
                                Label("Exchange Keys", systemImage: "key.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button {
                                if let chat = viewModel.startChat(with: peer) {
                                    onStartChat(chat)
                                }
                            } label: {
                                Label("Start Chat", systemImage: "bubble.left.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        
                        Button(role: .destructive) {
                            viewModel.disconnect(from: peer)
                            dismiss()
                        } label: {
                            Label("Disconnect", systemImage: "xmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal)
            }
            .padding()
            .navigationTitle("Peer Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
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
    NearbyPeersView(viewModel: PeersViewModel())
}
