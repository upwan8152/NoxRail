import SwiftUI

/// Row component for displaying a chat in the list
struct ChatRow: View {
    let chat: Chat
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: chat.chatType == .group
                                ? [Color.noxSecondary, Color.noxAccent]
                                : [Color.noxPrimary, Color.noxSecondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                
                if chat.chatType == .group {
                    Image(systemName: "person.3.fill")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                } else {
                    Text(chat.displayName.firstLetter)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                }
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(chat.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if let timestamp = chat.lastMessageTimestamp {
                        Text(timestamp.chatListTimestamp)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                HStack {
                    Text(chat.lastMessagePreview ?? "No messages yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    
                    Spacer()
                    
                    if chat.unreadCount > 0 {
                        Text("\(chat.unreadCount)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.noxPrimary)
                            )
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

#Preview {
    List {
        ChatRow(chat: Chat(
            chatType: .direct,
            displayName: "Alice",
            participantIds: ["alice"],
            lastMessagePreview: "Hey, are you coming to the party?",
            lastMessageTimestamp: Date(),
            unreadCount: 2
        ))
        
        ChatRow(chat: Chat(
            chatType: .group,
            displayName: "Project Team",
            participantIds: ["alice", "bob", "charlie"],
            lastMessagePreview: "Let's meet tomorrow at 3pm",
            lastMessageTimestamp: Date().addingTimeInterval(-3600),
            unreadCount: 0
        ))
        
        ChatRow(chat: Chat(
            chatType: .direct,
            displayName: "Bob",
            participantIds: ["bob"]
        ))
    }
}
