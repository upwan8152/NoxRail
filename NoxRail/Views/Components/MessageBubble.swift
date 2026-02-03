import SwiftUI

/// Message bubble component for chat view
struct MessageBubble: View {
    let message: Message
    let isGroupChat: Bool
    let onRetry: () -> Void
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isOutgoing {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: 4) {
                // Sender name for group chats
                if isGroupChat && !message.isOutgoing {
                    Text(message.senderName)
                        .font(.caption.bold())
                        .foregroundStyle(Color.noxSecondary)
                }
                
                // Message content
                VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: 4) {
                    Text(message.decryptedContent ?? "Encrypted message")
                        .font(.body)
                    
                    // Metadata row
                    HStack(spacing: 6) {
                        // Timestamp
                        Text(message.timestamp.messageTimestamp)
                            .font(.caption2)
                        
                        // Hop indicator
                        if let hopDescription = message.hopDescription {
                            Text("•")
                            Text(hopDescription)
                                .font(.caption2)
                        }
                        
                        // Status indicator for outgoing messages
                        if message.isOutgoing {
                            statusIcon
                        }
                    }
                    .foregroundStyle(message.isOutgoing ? .white.opacity(0.7) : .secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    message.isOutgoing
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: [Color.noxPrimary, Color.noxSecondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        : AnyShapeStyle(Color(.secondarySystemBackground))
                )
                .foregroundStyle(message.isOutgoing ? .white : .primary)
                .clipShape(
                    RoundedRectangle(cornerRadius: 18)
                )
                .contextMenu {
                    if message.status == .failed {
                        Button {
                            onRetry()
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                        }
                    }
                    
                    Button {
                        UIPasteboard.general.string = message.decryptedContent
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
            }
            
            if !message.isOutgoing {
                Spacer(minLength: 60)
            }
        }
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch message.status {
        case .sending:
            Image(systemName: "clock")
                .font(.caption2)
        case .sent:
            Image(systemName: "checkmark")
                .font(.caption2)
        case .delivered:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        MessageBubble(
            message: Message(
                senderId: "me",
                senderName: "Me",
                destinationChatId: "alice",
                chatType: .direct,
                encryptedPayload: Data(),
                decryptedContent: "Hello! How are you?",
                status: .delivered,
                isOutgoing: true
            ),
            isGroupChat: false,
            onRetry: {}
        )
        
        MessageBubble(
            message: Message(
                senderId: "alice",
                senderName: "Alice",
                destinationChatId: "me",
                chatType: .direct,
                encryptedPayload: Data(),
                decryptedContent: "I'm doing great, thanks for asking! 🎉",
                status: .delivered,
                isOutgoing: false,
                receivedHopCount: 2
            ),
            isGroupChat: false,
            onRetry: {}
        )
        
        MessageBubble(
            message: Message(
                senderId: "me",
                senderName: "Me",
                destinationChatId: "alice",
                chatType: .direct,
                encryptedPayload: Data(),
                decryptedContent: "Failed to send",
                status: .failed,
                isOutgoing: true
            ),
            isGroupChat: false,
            onRetry: {}
        )
    }
    .padding()
}
