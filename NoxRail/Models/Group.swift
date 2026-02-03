import Foundation
import SwiftData

/// Represents a group chat in the mesh network
/// Named ChatGroup to avoid conflict with SwiftUI.Group
@Model
final class ChatGroup {
    /// Unique identifier for the group
    @Attribute(.unique) var groupId: String
    
    /// Display name of the group
    var groupName: String
    
    /// IDs of group members
    var memberIds: [String]
    
    /// ID of the group creator
    var creatorId: String
    
    /// Group creation timestamp
    var createdAt: Date
    
    /// Group description (optional)
    var groupDescription: String?
    
    /// Reference to the associated chat
    @Relationship(inverse: \Chat.group)
    var chat: Chat?
    
    init(
        groupId: String = UUID().uuidString,
        groupName: String,
        memberIds: [String],
        creatorId: String,
        createdAt: Date = Date(),
        groupDescription: String? = nil
    ) {
        self.groupId = groupId
        self.groupName = groupName
        self.memberIds = memberIds
        self.creatorId = creatorId
        self.createdAt = createdAt
        self.groupDescription = groupDescription
    }
}

// MARK: - ChatGroup Extensions

extension ChatGroup {
    /// Number of members in the group
    var memberCount: Int {
        memberIds.count
    }
    
    /// Whether a user is a member
    func isMember(_ userId: String) -> Bool {
        memberIds.contains(userId)
    }
    
    /// Whether a user is the creator
    func isCreator(_ userId: String) -> Bool {
        creatorId == userId
    }
    
    /// Adds a member to the group
    func addMember(_ userId: String) {
        guard !memberIds.contains(userId) else { return }
        memberIds.append(userId)
    }
    
    /// Removes a member from the group
    func removeMember(_ userId: String) {
        memberIds.removeAll { $0 == userId }
    }
}
