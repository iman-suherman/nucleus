import Foundation

enum NotificationUserInfo {
    static func accountID(from userInfo: [AnyHashable: Any]?) -> UUID? {
        guard let userInfo else { return nil }
        if let id = userInfo["accountID"] as? UUID { return id }
        if let id = userInfo["accountID"] as? NSUUID { return id as UUID }
        if let raw = userInfo["accountID"] as? String { return UUID(uuidString: raw) }
        return nil
    }

    static func unreadCount(from userInfo: [AnyHashable: Any]?) -> Int? {
        guard let userInfo else { return nil }
        if let count = userInfo["count"] as? Int { return count }
        if let count = userInfo["count"] as? NSNumber { return count.intValue }
        return nil
    }

    static func mailUnreadPayload(accountID: UUID, count: Int) -> [String: Any] {
        [
            "accountID": accountID.uuidString,
            "count": count,
        ]
    }
}
