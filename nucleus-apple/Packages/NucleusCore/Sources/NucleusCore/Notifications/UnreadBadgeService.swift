import Foundation
import NucleusKit

/// Phase 2: Gmail API unread counts and badge updates.
@MainActor
public final class UnreadBadgeService: ObservableObject {
    @Published public private(set) var unreadByAccount: [UUID: Int] = [:]
    @Published public private(set) var totalUnread = 0

    public init() {}

    public func updateUnread(accountID: UUID, count: Int) {
        unreadByAccount[accountID] = count
        totalUnread = unreadByAccount.values.reduce(0, +)
    }

    public func removeUnread(accountID: UUID) {
        unreadByAccount.removeValue(forKey: accountID)
        totalUnread = unreadByAccount.values.reduce(0, +)
    }

    public func reset() {
        unreadByAccount = [:]
        totalUnread = 0
    }
}
