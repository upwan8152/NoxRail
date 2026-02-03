import Foundation
import SwiftData

/// Service for persisting messages, chats, and groups using SwiftData
@MainActor
final class PersistenceService: ObservableObject {
    
    // MARK: - Properties
    
    let modelContainer: ModelContainer
    let modelContext: ModelContext
    
    // MARK: - Singleton
    
    static let shared: PersistenceService = {
        do {
            return try PersistenceService()
        } catch {
            fatalError("Failed to initialize PersistenceService: \(error)")
        }
    }()
    
    // MARK: - Initialization
    
    init() throws {
        let schema = Schema([
            Message.self,
            Chat.self,
            Peer.self,
            ChatGroup.self
        ])
        
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )
        
        modelContainer = try ModelContainer(
            for: schema,
            configurations: [modelConfiguration]
        )
        
        modelContext = modelContainer.mainContext
        
        NoxLogger.persistence.info("PersistenceService initialized")
    }
    
    // MARK: - Chat Operations
    
    /// Fetches all chats sorted by last message time
    func fetchAllChats() throws -> [Chat] {
        let descriptor = FetchDescriptor<Chat>(
            sortBy: [SortDescriptor(\.lastMessageTimestamp, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    /// Fetches a chat by ID
    func fetchChat(id: String) throws -> Chat? {
        let descriptor = FetchDescriptor<Chat>(
            predicate: #Predicate { $0.chatId == id }
        )
        return try modelContext.fetch(descriptor).first
    }
    
    /// Creates or fetches a direct chat with a peer
    func getOrCreateDirectChat(with peer: Peer) throws -> Chat {
        if let existingChat = try fetchChat(id: peer.peerId) {
            return existingChat
        }
        
        let chat = Chat.directChat(with: peer)
        modelContext.insert(chat)
        try save()
        
        return chat
    }
    
    /// Creates a group chat
    func createGroupChat(group: ChatGroup) throws -> Chat {
        let chat = Chat.groupChat(group: group)
        modelContext.insert(group)
        modelContext.insert(chat)
        try save()
        
        return chat
    }
    
    /// Deletes a chat and its messages
    func deleteChat(_ chat: Chat) throws {
        modelContext.delete(chat)
        try save()
    }
    
    /// Updates chat with latest message info
    func updateChatWithMessage(_ chat: Chat, message: Message) throws {
        chat.lastMessagePreview = message.decryptedContent ?? "Encrypted message"
        chat.lastMessageTimestamp = message.timestamp
        
        if !message.isOutgoing {
            chat.unreadCount += 1
        }
        
        try save()
    }
    
    /// Marks a chat as read
    func markChatAsRead(_ chat: Chat) throws {
        chat.unreadCount = 0
        try save()
    }
    
    // MARK: - Message Operations
    
    /// Fetches messages for a chat
    func fetchMessages(for chatId: String) throws -> [Message] {
        let descriptor = FetchDescriptor<Message>(
            predicate: #Predicate { $0.destinationChatId == chatId },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    /// Saves a new message
    func saveMessage(_ message: Message, to chat: Chat) throws {
        message.chat = chat
        chat.messages.append(message)
        
        modelContext.insert(message)
        try updateChatWithMessage(chat, message: message)
    }
    
    /// Updates message status
    func updateMessageStatus(_ messageId: String, status: MessageStatus) throws {
        let descriptor = FetchDescriptor<Message>(
            predicate: #Predicate { $0.messageId == messageId }
        )
        
        if let message = try modelContext.fetch(descriptor).first {
            message.status = status
            try save()
        }
    }
    
    /// Deletes a message
    func deleteMessage(_ message: Message) throws {
        modelContext.delete(message)
        try save()
    }
    
    // MARK: - Group Operations
    
    /// Fetches all groups
    func fetchAllGroups() throws -> [ChatGroup] {
        let descriptor = FetchDescriptor<ChatGroup>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    /// Fetches a group by ID
    func fetchGroup(id: String) throws -> ChatGroup? {
        let descriptor = FetchDescriptor<ChatGroup>(
            predicate: #Predicate { $0.groupId == id }
        )
        return try modelContext.fetch(descriptor).first
    }
    
    /// Creates a new group
    func createGroup(name: String, memberIds: [String], creatorId: String, id: String? = nil) throws -> ChatGroup {
        let group = ChatGroup(
            groupId: id ?? UUID().uuidString,
            groupName: name,
            memberIds: memberIds,
            creatorId: creatorId
        )
        
        modelContext.insert(group)
        try save()
        
        return group
    }
    
    /// Updates a group
    func updateGroup(_ group: ChatGroup) throws {
        try save()
    }
    
    /// Deletes a group
    func deleteGroup(_ group: ChatGroup) throws {
        modelContext.delete(group)
        try save()
    }
    
    // MARK: - Peer Operations
    
    /// Fetches all cached peers
    func fetchAllPeers() throws -> [Peer] {
        let descriptor = FetchDescriptor<Peer>(
            sortBy: [SortDescriptor(\.lastSeen, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    /// Fetches a peer by ID
    func fetchPeer(id: String) throws -> Peer? {
        let descriptor = FetchDescriptor<Peer>(
            predicate: #Predicate { $0.peerId == id }
        )
        return try modelContext.fetch(descriptor).first
    }
    
    /// Saves or updates a peer
    func savePeer(_ peer: Peer) throws {
        if try fetchPeer(id: peer.peerId) == nil {
            modelContext.insert(peer)
        }
        try save()
    }
    
    /// Deletes a peer
    func deletePeer(_ peer: Peer) throws {
        modelContext.delete(peer)
        try save()
    }
    
    // MARK: - General Operations
    
    /// Saves changes to the context
    func save() throws {
        if modelContext.hasChanges {
            try modelContext.save()
        }
    }
    
    /// Clears all data (for testing/reset)
    func clearAllData() throws {
        try modelContext.delete(model: Message.self)
        try modelContext.delete(model: Chat.self)
        try modelContext.delete(model: ChatGroup.self)
        try modelContext.delete(model: Peer.self)
        try save()
        
        NoxLogger.persistence.info("All data cleared")
    }
}
