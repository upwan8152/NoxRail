import Foundation
import SwiftData

/// Represents the type of chat
enum ChatType: String, Codable, Sendable {
    case direct
    case group
}

/// Represents the delivery status of a message
enum MessageStatus: String, Codable, Sendable {
    case sending
    case sent
    case delivered
    case failed
}

/// Core message model for mesh communication
@Model
final class Message {
    /// Unique identifier for the message
    @Attribute(.unique) var messageId: String
    
    /// ID of the sender
    var senderId: String
    
    /// Display name of the sender (cached for UI)
    var senderName: String
    
    /// Destination chat ID (peer ID for direct, group ID for group)
    var destinationChatId: String
    
    /// Type of chat this message belongs to
    var chatType: ChatType
    
    /// Current hop count (incremented at each relay)
    var hopCount: Int
    
    /// Maximum allowed hops (TTL)
    var maxHops: Int
    
    /// Message creation timestamp
    var timestamp: Date
    
    /// Encrypted message payload (ciphertext)
    var encryptedPayload: Data
    
    /// Decrypted content (stored locally after decryption, never transmitted)
    var decryptedContent: String?
    
    /// Current delivery status
    var status: MessageStatus
    
    /// Whether this message was sent by the local user
    var isOutgoing: Bool
    
    /// Number of hops the message took to reach us (for incoming messages)
    var receivedHopCount: Int?
    
    /// Reference to the chat this message belongs to
    var chat: Chat?
    
    init(
        messageId: String = UUID().uuidString,
        senderId: String,
        senderName: String,
        destinationChatId: String,
        chatType: ChatType,
        hopCount: Int = 0,
        maxHops: Int = 5,
        timestamp: Date = Date(),
        encryptedPayload: Data,
        decryptedContent: String? = nil,
        status: MessageStatus = .sending,
        isOutgoing: Bool,
        receivedHopCount: Int? = nil
    ) {
        self.messageId = messageId
        self.senderId = senderId
        self.senderName = senderName
        self.destinationChatId = destinationChatId
        self.chatType = chatType
        self.hopCount = hopCount
        self.maxHops = maxHops
        self.timestamp = timestamp
        self.encryptedPayload = encryptedPayload
        self.decryptedContent = decryptedContent
        self.status = status
        self.isOutgoing = isOutgoing
        self.receivedHopCount = receivedHopCount
    }
}

// MARK: - Message Extensions

extension Message {
    /// Creates a system message (e.g., "User joined the group")
    static func systemMessage(
        chatId: String,
        chatType: ChatType,
        content: String
    ) -> Message {
        Message(
            senderId: "system",
            senderName: "System",
            destinationChatId: chatId,
            chatType: chatType,
            encryptedPayload: Data(),
            decryptedContent: content,
            status: .delivered,
            isOutgoing: false
        )
    }
    
    /// Human-readable hop description
    var hopDescription: String? {
        guard let hops = receivedHopCount, hops > 0 else { return nil }
        return hops == 1 ? "via 1 hop" : "via \(hops) hops"
    }
}
