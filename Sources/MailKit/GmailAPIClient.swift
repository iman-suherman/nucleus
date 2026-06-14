import Foundation
import NucleusKit

public enum GmailAPIClient {
    public static func unreadCount(accessToken: String) async throws -> Int {
        var request = URLRequest(url: URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/labels/INBOX")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["messagesUnread"] as? Int ?? 0
    }

    public static func fetchRecentMessages(accessToken: String, maxResults: Int = 20) async throws -> [[String: Any]] {
        var listRequest = URLRequest(
            url: URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages?maxResults=\(maxResults)&labelIds=INBOX")!
        )
        listRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (listData, listResponse) = try await URLSession.shared.data(for: listRequest)
        guard let listHTTP = listResponse as? HTTPURLResponse, (200..<300).contains(listHTTP.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let listJSON = try JSONSerialization.jsonObject(with: listData) as? [String: Any]
        guard let messages = listJSON?["messages"] as? [[String: Any]] else {
            return []
        }

        var results: [[String: Any]] = []
        for message in messages.prefix(maxResults) {
            guard let id = message["id"] as? String else { continue }
            var detailRequest = URLRequest(
                url: URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)?format=metadata&metadataHeaders=From&metadataHeaders=Subject&metadataHeaders=Date")!
            )
            detailRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let (detailData, detailResponse) = try await URLSession.shared.data(for: detailRequest)
            guard let detailHTTP = detailResponse as? HTTPURLResponse, (200..<300).contains(detailHTTP.statusCode) else {
                continue
            }
            if let detailJSON = try JSONSerialization.jsonObject(with: detailData) as? [String: Any] {
                results.append(detailJSON)
            }
        }
        return results
    }

    public static func sendReply(
        accessToken: String,
        threadID: String,
        to: String,
        subject: String,
        body: String
    ) async throws {
        let rawMessage = """
        To: \(to)
        Subject: \(subject)
        Content-Type: text/plain; charset=UTF-8

        \(body)
        """
        let encoded = Data(rawMessage.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        var request = URLRequest(url: URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/send")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "raw": encoded,
            "threadId": threadID,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    public static func markRead(accessToken: String, messageID: String) async throws {
        var request = URLRequest(
            url: URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(messageID)/modify")!
        )
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["removeLabelIds": ["UNREAD"]])

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}

public enum MailMessageParser {
    public static func parse(_ payload: [String: Any], accountID: UUID) -> MailMessageSummary? {
        guard
            let id = payload["id"] as? String,
            let threadID = payload["threadId"] as? String
        else {
            return nil
        }

        let labelIDs = payload["labelIds"] as? [String] ?? []
        let isUnread = labelIDs.contains("UNREAD")
        let snippet = payload["snippet"] as? String ?? ""

        var fromName = "Unknown"
        var fromEmail = ""
        var subject = "(No subject)"
        var receivedAt = Date()

        if let headers = payload["payload"] as? [String: Any],
           let headerItems = headers["headers"] as? [[String: Any]] {
            for header in headerItems {
                guard let name = header["name"] as? String, let value = header["value"] as? String else { continue }
                switch name.lowercased() {
                case "from":
                    if let match = value.range(of: "<(.*)>", options: .regularExpression) {
                        fromEmail = String(value[match]).trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
                        fromName = value.replacingOccurrences(of: "<\(fromEmail)>", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        fromEmail = value
                        fromName = value
                    }
                case "subject":
                    subject = value
                case "date":
                    receivedAt = MailDateParser.parse(value) ?? receivedAt
                default:
                    break
                }
            }
        }

        if let internalDate = payload["internalDate"] as? String,
           let millis = Double(internalDate) {
            receivedAt = Date(timeIntervalSince1970: millis / 1000)
        }

        return MailMessageSummary(
            id: id,
            accountID: accountID,
            threadID: threadID,
            fromName: fromName,
            fromEmail: fromEmail,
            subject: subject,
            snippet: snippet,
            receivedAt: receivedAt,
            isUnread: isUnread
        )
    }
}

enum MailDateParser {
    static func parse(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.date(from: value)
    }
}

public struct MailSyncResult: Sendable {
    public var unreadByAccount: [UUID: Int]
    public var messages: [MailMessageSummary]
    public var newMessages: [MailMessageSummary]

    public init(unreadByAccount: [UUID: Int], messages: [MailMessageSummary], newMessages: [MailMessageSummary]) {
        self.unreadByAccount = unreadByAccount
        self.messages = messages
        self.newMessages = newMessages
    }

    public var totalUnread: Int {
        unreadByAccount.values.reduce(0, +)
    }
}

public enum MailSyncEngine {
    public static func sync(
        accounts: [GoogleAccount],
        knownMessageIDs: Set<String>,
        accessTokenProvider: @escaping (UUID) async throws -> String
    ) async -> MailSyncResult {
        var unreadByAccount: [UUID: Int] = [:]
        var messages: [MailMessageSummary] = []
        var newMessages: [MailMessageSummary] = []

        await withTaskGroup(of: (UUID, Int, [MailMessageSummary]).self) { group in
            for account in accounts {
                group.addTask {
                    do {
                        let token = try await accessTokenProvider(account.id)
                        async let unread = GmailAPIClient.unreadCount(accessToken: token)
                        async let payloads = GmailAPIClient.fetchRecentMessages(accessToken: token)
                        let count = try await unread
                        let parsed = try await payloads.compactMap { MailMessageParser.parse($0, accountID: account.id) }
                        return (account.id, count, parsed)
                    } catch {
                        return (account.id, 0, [])
                    }
                }
            }

            for await (accountID, unread, accountMessages) in group {
                unreadByAccount[accountID] = unread
                messages.append(contentsOf: accountMessages)
                newMessages.append(contentsOf: accountMessages.filter { !knownMessageIDs.contains($0.id) && $0.isUnread })
            }
        }

        return MailSyncResult(
            unreadByAccount: unreadByAccount,
            messages: messages.sorted { $0.receivedAt > $1.receivedAt },
            newMessages: newMessages.sorted { $0.receivedAt > $1.receivedAt }
        )
    }
}
