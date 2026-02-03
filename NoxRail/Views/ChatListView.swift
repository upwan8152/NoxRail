import SwiftUI

/// View displaying list of chats
struct ChatListView: View {
    @ObservedObject var viewModel: ChatListViewModel
    @State private var selectedChat: Chat? = nil
    
    var body: some View {
        NavigationStack {
            ZStack {
                if viewModel.chats.isEmpty {
                    emptyStateView
                } else {
                    chatListView
                }
            }
            .navigationTitle("Chats")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.showingNewGroupSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
            }
            .navigationDestination(item: $selectedChat) { chat in
                ChatView(viewModel: ChatViewModel(chat: chat))
            }
            .sheet(isPresented: $viewModel.showingNewGroupSheet) {
                NewGroupView(viewModel: viewModel)
            }
            .refreshable {
                viewModel.refresh()
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
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("No Chats Yet")
                .font(.title2.bold())
            
            Text("Connect with nearby peers to start chatting, or create a group.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button {
                viewModel.showingNewGroupSheet = true
            } label: {
                Label("Create Group", systemImage: "person.3.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var chatListView: some View {
        List {
            if !viewModel.directChats.isEmpty {
                Section {
                    ForEach(viewModel.directChats, id: \.chatId) { chat in
                        ChatRow(chat: chat)
                            .onTapGesture {
                                selectedChat = chat
                            }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            viewModel.deleteChat(viewModel.directChats[index])
                        }
                    }
                } header: {
                    Text("Direct Messages")
                }
            }
            
            if !viewModel.groupChats.isEmpty {
                Section {
                    ForEach(viewModel.groupChats, id: \.chatId) { chat in
                        ChatRow(chat: chat)
                            .onTapGesture {
                                selectedChat = chat
                            }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            viewModel.deleteChat(viewModel.groupChats[index])
                        }
                    }
                } header: {
                    Text("Groups")
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

#Preview {
    ChatListView(viewModel: ChatListViewModel())
}
