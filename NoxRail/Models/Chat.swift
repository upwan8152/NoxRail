import Foundation
import SwiftData

/// Represents a chat session (direct or group)
@Model
final class Chat {
    /// Unique identifier for the chat
    @Attribute(.unique) var chatId: String
    
    /// Type of chat (direct or group)
    var chatType: ChatType
    
    /// Display name for the chat
    var displayName: String
    
    /// List of participant IDs
    var participantIds: [String]
    
    /// Last message preview text
    var lastMessagePreview: String?
    
    /// Timestamp of the last message
    var lastMessageTimestamp: Date?
    
    /// Number of unread messages
    var unreadCount: Int
    
    /// Whether the chat is muted
    var isMuted: Bool
    
    /// Chat creation timestamp
    var createdAt: Date
    
    /// Messages in this chat
    @Relationship(deleteRule: .cascade, inverse: \Message.chat)
    var messages: [Message]
    
    /// Associated group (if group chat)
    var group: ChatGroup?
    
    init(
        chatId: String = UUID().uuidString,
        chatType: ChatType,
        displayName: String,
        participantIds: [String],
        lastMessagePreview: String? = nil,
        lastMessageTimestamp: Date? = nil,
        unreadCount: Int = 0,
        isMuted: Bool = false,
        createdAt: Date = Date(),
        messages: [Message] = []
    ) {
        self.chatId = chatId
        self.chatType = chatType
        self.displayName = displayName
        self.participantIds = participantIds
        self.lastMessagePreview = lastMessagePreview
        self.lastMessageTimestamp = lastMessageTimestamp
        self.unreadCount = unreadCount
        self.isMuted = isMuted
        self.createdAt = createdAt
        self.messages = messages
    }
}

// MARK: - Chat Extensions

extension Chat {
    /// Creates a direct chat with a peer
    static func directChat(with peer: Peer) -> Chat {
        Chat(
            chatId: peer.peerId,
            chatType: .direct,
            displayName: peer.displayName,
            participantIds: [peer.peerId]
        )
    }
    
    /// Creates a group chat
    static func groupChat(group: ChatGroup) -> Chat {
        let chat = Chat(
            chatId: group.groupId,
            chatType: .group,
            displayName: group.groupName,
            participantIds: group.memberIds
        )
        chat.group = group
        return chat
    }
    
    /// Returns the other participant ID for direct chats
    func otherParticipantId(excluding myId: String) -> String? {
        guard chatType == .direct else { return nil }
        return participantIds.first { $0 != myId }
    }
    
    /// Sorted messages by timestamp
    var sortedMessages: [Message] {
        messages.sorted { $0.timestamp < $1.timestamp }
    }
}
