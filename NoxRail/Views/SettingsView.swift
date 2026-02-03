import SwiftUI

/// Settings view
struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    
    var body: some View {
        NavigationStack {
            Form {
                // Identity Section
                Section {
                    HStack {
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
                                .frame(width: 60, height: 60)
                            
                            Text(viewModel.displayName.firstLetter)
                                .font(.title.bold())
                                .foregroundStyle(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Display Name", text: $viewModel.displayName)
                                .font(.headline)
                                .submitLabel(.done)
                                .onSubmit {
                                    viewModel.updateDisplayName()
                                }
                            
                            Text("ID: \(viewModel.userId.prefix(8))...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 8)
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Identity")
                } footer: {
                    Text("Your identity is stored securely on this device.")
                }
                
                // Network Section
                Section {
                    NavigationLink {
                        // TODO: Bluetooth Diagnostics
                    } label: {
                        HStack {
                            Label("Bluetooth", systemImage: "antenna.radiowaves.left.and.right")
                            Spacer()
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(viewModel.isBluetoothReady ? .green : .orange)
                                    .frame(width: 8, height: 8)
                                Text(viewModel.bluetoothState.displayMessage)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    HStack {
                        Label("Connected Peers", systemImage: "link")
                        Spacer()
                        Text("\(viewModel.connectedPeerCount)")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Label("Discovered Peers", systemImage: "antenna.radiowaves.left.and.right")
                        Spacer()
                        Text("\(viewModel.discoveredPeerCount)")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Network Status")
                }
                
                // Relay Section
                Section {
                    Toggle(isOn: $viewModel.relayModeEnabled) {
                        Label("Relay Mode", systemImage: "arrow.triangle.branch")
                    }
                    .onChange(of: viewModel.relayModeEnabled) { _, _ in
                        viewModel.toggleRelayMode()
                    }
                } header: {
                    Text("Mesh Network")
                } footer: {
                    Text("When enabled, your device helps relay messages for other users. This uses more battery but extends the mesh network range.")
                }
                
                // Stats Section
                Section {
                    StatRow(label: "Messages Sent", value: "\(viewModel.stats.messagesSent)")
                    StatRow(label: "Messages Received", value: "\(viewModel.stats.messagesReceived)")
                    StatRow(label: "Messages Relayed", value: "\(viewModel.stats.messagesRelayed)")
                    StatRow(label: "Duplicates Dropped", value: "\(viewModel.stats.duplicatesDropped)")
                } header: {
                    Text("Statistics")
                }
                
                // Security Section
                Section {
                    Button {
                        viewModel.copyUserId()
                    } label: {
                        Label("Copy User ID", systemImage: "doc.on.doc")
                    }
                    
                    Button {
                        viewModel.copyPublicKey()
                    } label: {
                        Label("Copy Public Key", systemImage: "key")
                    }
                } header: {
                    Text("Security")
                }
                
                // Danger Zone
                Section {
                    Button(role: .destructive) {
                        viewModel.showingResetConfirmation = true
                    } label: {
                        Label("Reset All Data", systemImage: "trash")
                    }
                } header: {
                    Text("Danger Zone")
                } footer: {
                    Text("This will delete all messages, chats, and generate a new identity.")
                }
                
                // About Section
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("Build")
                        Spacer()
                        Text("1")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog(
                "Reset All Data?",
                isPresented: $viewModel.showingResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset", role: .destructive) {
                    viewModel.resetAllData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete all your messages, chats, and create a new identity. This cannot be undone.")
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
}

struct StatRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

#Preview {
    SettingsView(viewModel: SettingsViewModel())
}
