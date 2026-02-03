import Foundation
import Combine

/// ViewModel for individual chat conversations
@MainActor
final class ChatViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var messages: [Message] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSending = false
    @Published var messageText = ""
    @Published var errorMessage: String? = nil
    
    // MARK: - Properties
    
    let chat: Chat
    
    private let persistenceService: PersistenceService
    private let meshRoutingService: MeshRoutingService
    private let encryptionService: EncryptionService
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Computed Properties
    
    var canSend: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }
    
    var chatTitle: String {
        chat.displayName
    }
    
    var participantCount: Int {
        chat.participantIds.count
    }
    
    var isGroupChat: Bool {
        chat.chatType == .group
    }
    
    var myUserId: String {
        encryptionService.getIdentity()?.userId ?? ""
    }
    
    // MARK: - Initialization
    
    init(chat: Chat) {
        self.chat = chat
        self.persistenceService = PersistenceService.shared
        self.meshRoutingService = MeshRoutingService.shared
        self.encryptionService = EncryptionService.shared
        
        setupObservers()
        loadMessages()
        markAsRead()
    }
    
    // MARK: - Setup
    
    private func setupObservers() {
        // Listen for new messages
        meshRoutingService.delegate = self
    }
    
    // MARK: - Data Loading
    
    /// Loads messages from persistence
    func loadMessages() {
        isLoading = true
        
        do {
            messages = try persistenceService.fetchMessages(for: chat.chatId)
        } catch {
            errorMessage = "Failed to load messages: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    /// Marks the chat as read
    func markAsRead() {
        do {
            try persistenceService.markChatAsRead(chat)
        } catch {
            NoxLogger.ui.error("Failed to mark chat as read: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Sending Messages
    
    /// Sends the current message
    func sendMessage() {
        let content = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        
        isSending = true
        messageText = ""
        
        Task {
            do {
                let message: Message
                
                if chat.chatType == .direct {
                    guard let recipientId = chat.participantIds.first else {
                        throw ChatError.noRecipient
                    }
                    
                    message = try await meshRoutingService.sendDirectMessage(
                        content: content,
                        to: recipientId,
                        chatId: chat.chatId
                    )
                } else {
                    // Filter out self from recipients
                    let recipientIds = chat.participantIds.filter { $0 != myUserId }
                    
                    message = try await meshRoutingService.sendGroupMessage(
                        content: content,
                        to: chat.chatId,
                        recipientIds: recipientIds
                    )
                }
                
                // Save to persistence
                try persistenceService.saveMessage(message, to: chat)
                
                // Update local list
                messages.append(message)
                
                isSending = false
                
            } catch {
                isSending = false
                errorMessage = "Failed to send: \(error.localizedDescription)"
                
                // Restore message text on failure
                messageText = content
            }
        }
    }
    
    /// Retries sending a failed message
    func retrySend(_ message: Message) {
        guard let content = message.decryptedContent else { return }
        
        // Remove failed message
        if let index = messages.firstIndex(where: { $0.messageId == message.messageId }) {
            messages.remove(at: index)
        }
        
        do {
            try persistenceService.deleteMessage(message)
        } catch {
            NoxLogger.ui.error("Failed to delete message: \(error.localizedDescription)")
        }
        
        // Resend
        messageText = content
        sendMessage()
    }
    
    /// Deletes a message
    func deleteMessage(_ message: Message) {
        do {
            try persistenceService.deleteMessage(message)
            messages.removeAll { $0.messageId == message.messageId }
        } catch {
            errorMessage = "Failed to delete message: \(error.localizedDescription)"
        }
    }
}

// MARK: - MeshRoutingServiceDelegate

extension ChatViewModel: MeshRoutingServiceDelegate {
    
    nonisolated func meshRouting(_ service: MeshRoutingService, didReceiveMessage message: Message, from peerId: String) {
        Task { @MainActor in
            // Only add if this message is for our chat
            if message.destinationChatId == chat.chatId || 
               (chat.chatType == .direct && message.senderId == chat.chatId) {
                
                // Save to persistence
                do {
                    try persistenceService.saveMessage(message, to: chat)
                } catch {
                    NoxLogger.ui.error("Failed to save message: \(error.localizedDescription)")
                }
                
                // Update local list
                if !messages.contains(where: { $0.messageId == message.messageId }) {
                    messages.append(message)
                }
            }
        }
    }
    
    nonisolated func meshRouting(_ service: MeshRoutingService, didSendMessage messageId: String, status: MessageStatus) {
        Task { @MainActor in
            // Update message status
            if let index = messages.firstIndex(where: { $0.messageId == messageId }) {
                messages[index].status = status
            }
            
            do {
                try persistenceService.updateMessageStatus(messageId, status: status)
            } catch {
                NoxLogger.ui.error("Failed to update message status: \(error.localizedDescription)")
            }
        }
    }
    
    nonisolated func meshRouting(_ service: MeshRoutingService, didReceiveKeyExchange peerId: String) {
        // Handle in PeersViewModel
    }
}

// MARK: - Chat Errors

enum ChatError: Error, LocalizedError {
    case noRecipient
    case encryptionFailed
    
    var errorDescription: String? {
        switch self {
        case .noRecipient: return "No recipient specified"
        case .encryptionFailed: return "Failed to encrypt message"
        }
    }
}
