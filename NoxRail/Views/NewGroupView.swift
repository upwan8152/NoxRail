import SwiftUI

/// View for creating a new group
struct NewGroupView: View {
    @ObservedObject var viewModel: ChatListViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var groupName = ""
    @State private var selectedPeerIds: Set<String> = []
    
    @StateObject private var peersViewModel = PeersViewModel()
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Group Name", text: $groupName)
                } header: {
                    Text("Group Info")
                }
                
                Section {
                    if peersViewModel.connectedPeers.isEmpty {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary)
                            Text("Connect with peers first to add them to a group")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(peersViewModel.connectedPeers, id: \.peerId) { peer in
                            HStack {
                                // Avatar
                                ZStack {
                                    Circle()
                                        .fill(Color.noxSecondary.opacity(0.2))
                                        .frame(width: 36, height: 36)
                                    
                                    Text(peer.displayName.firstLetter)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(Color.noxSecondary)
                                }
                                
                                Text(peer.displayName)
                                
                                Spacer()
                                
                                if selectedPeerIds.contains(peer.peerId) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.noxPrimary)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                toggleSelection(peer.peerId)
                            }
                        }
                    }
                } header: {
                    Text("Select Members (\(selectedPeerIds.count) selected)")
                }
            }
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") {
                        createGroup()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canCreate)
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private var canCreate: Bool {
        !groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !selectedPeerIds.isEmpty
    }
    
    private func toggleSelection(_ peerId: String) {
        if selectedPeerIds.contains(peerId) {
            selectedPeerIds.remove(peerId)
        } else {
            selectedPeerIds.insert(peerId)
        }
    }
    
    private func createGroup() {
        viewModel.createGroup(
            name: groupName.trimmingCharacters(in: .whitespacesAndNewlines),
            memberIds: Array(selectedPeerIds)
        )
    }
}

#Preview {
    NewGroupView(viewModel: ChatListViewModel())
}
