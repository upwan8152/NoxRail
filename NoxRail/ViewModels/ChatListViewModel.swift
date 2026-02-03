import Foundation
import Combine
import SwiftData

/// ViewModel for the chat list screen
@MainActor
final class ChatListViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var chats: [Chat] = []
    @Published private(set) var directChats: [Chat] = []
    @Published private(set) var groupChats: [Chat] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String? = nil
    @Published var showingNewGroupSheet = false
    
    // MARK: - Properties
    
    private let persistenceService: PersistenceService
    private let meshRoutingService: MeshRoutingService
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Computed Properties
    
    var totalUnreadCount: Int {
        chats.reduce(0) { $0 + $1.unreadCount }
    }
    
    var hasChats: Bool {
        !chats.isEmpty
    }
    
    // MARK: - Initialization
    
    init() {
        persistenceService = PersistenceService.shared
        meshRoutingService = MeshRoutingService.shared
        
        loadChats()
    }
    
    // MARK: - Data Loading
    
    /// Loads all chats from persistence
    func loadChats() {
        isLoading = true
        
        do {
            chats = try persistenceService.fetchAllChats()
            directChats = chats.filter { $0.chatType == .direct }
            groupChats = chats.filter { $0.chatType == .group }
        } catch {
            errorMessage = "Failed to load chats: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    /// Refreshes chat list
    func refresh() {
        loadChats()
    }
    
    // MARK: - Chat Operations
    
    /// Deletes a chat
    func deleteChat(_ chat: Chat) {
        do {
            try persistenceService.deleteChat(chat)
            loadChats()
        } catch {
            errorMessage = "Failed to delete chat: \(error.localizedDescription)"
        }
    }
    
    /// Marks a chat as read
    func markAsRead(_ chat: Chat) {
        do {
            try persistenceService.markChatAsRead(chat)
            loadChats()
        } catch {
            errorMessage = "Failed to mark chat as read: \(error.localizedDescription)"
        }
    }
    
    /// Creates a new group chat
    func createGroup(name: String, memberIds: [String]) {
        do {
            guard let identity = EncryptionService.shared.getIdentity() else {
                errorMessage = "Not initialized"
                return
            }
            
            // Include self in member list
            var allMembers = memberIds
            if !allMembers.contains(identity.userId) {
                allMembers.insert(identity.userId, at: 0)
            }
            
            let group = try persistenceService.createGroup(
                name: name,
                memberIds: allMembers,
                creatorId: identity.userId
            )
            
            _ = try persistenceService.createGroupChat(group: group)
            loadChats()
            
            showingNewGroupSheet = false
        } catch {
            errorMessage = "Failed to create group: \(error.localizedDescription)"
        }
    }
    
    /// Gets or creates a chat for a peer
    func getOrCreateChat(for peer: Peer) -> Chat? {
        do {
            let chat = try persistenceService.getOrCreateDirectChat(with: peer)
            loadChats()
            return chat
        } catch {
            errorMessage = "Failed to create chat: \(error.localizedDescription)"
            return nil
        }
    }
}
