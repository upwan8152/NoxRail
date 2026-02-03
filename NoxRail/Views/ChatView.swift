import SwiftUI

/// Chat conversation view
struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    @FocusState private var isInputFocused: Bool
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages, id: \.messageId) { message in
                            MessageBubble(
                                message: message,
                                isGroupChat: viewModel.isGroupChat,
                                onRetry: {
                                    viewModel.retrySend(message)
                                }
                            )
                            .id(message.messageId)
                        }
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: viewModel.messages.count) { _, _ in
                    if let lastMessage = viewModel.messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.messageId, anchor: .bottom)
                        }
                    }
                }
            }
            
            Divider()
            
            // Input bar
            inputBar
        }
        .navigationTitle(viewModel.chatTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if viewModel.isGroupChat {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(viewModel.participantCount) members")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
    
    // MARK: - Input Bar
    
    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Message", text: $viewModel.messageText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .lineLimit(1...5)
                .focused($isInputFocused)
            
            Button {
                viewModel.sendMessage()
                isInputFocused = false
            } label: {
                Image(systemName: viewModel.isSending ? "ellipsis" : "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(viewModel.canSend ? Color.noxPrimary : .secondary)
                    .symbolEffect(.pulse, isActive: viewModel.isSending)
            }
            .disabled(!viewModel.canSend)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
}

#Preview {
    NavigationStack {
        ChatView(viewModel: ChatViewModel(chat: Chat(
            chatType: .direct,
            displayName: "Alice",
            participantIds: ["alice-id"]
        )))
    }
}
