import CloudKit
import Foundation

enum CloudKitErrorDescriber {
    static func describe(_ error: Error) -> String {
        if let ckError = error as? CKError {
            return describe(ckError)
        }

        let nsError = error as NSError
        if nsError.domain == CKError.errorDomain,
           let code = CKError.Code(rawValue: nsError.code) {
            return describe(CKError(_nsError: nsError))
        }

        let nested = nestedCloudKitMessages(for: nsError)
        if !nested.isEmpty {
            return nested.joined(separator: " — ")
        }

        return error.localizedDescription
    }

    static func describe(_ ckError: CKError) -> String {
        var parts = [headline(for: ckError.code)]

        let description = ckError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !description.isEmpty, description != "(null)" {
            parts.append(description)
        }

        let partial = partialErrors(from: ckError)
        if ckError.code == .partialFailure, !partial.isEmpty {
            let details = partial.prefix(6).map { recordID, itemError in
                let id = recordID as? CKRecord.ID
                let name = id?.recordName.isEmpty == false ? id!.recordName : (id?.zoneID.zoneName ?? String(describing: recordID))
                return "\(name): \(describe(itemError))"
            }
            parts.append("Failed records — \(details.joined(separator: "; "))")
        } else if ckError.code == .partialFailure {
            parts.append(
                "Core Data did not expose which records failed. Common causes: iCloud storage full, stale local sync metadata, or account needs attention in System Settings → Apple ID → iCloud."
            )
        }

        if let retry = ckError.retryAfterSeconds, retry > 0 {
            parts.append("Retry after \(Int(retry))s")
        }

        return parts.joined(separator: " — ")
    }

    static func userFacingUploadFailure(_ error: Error) -> String {
        guard let ckError = error as? CKError else {
            return "iCloud upload failed: \(error.localizedDescription)"
        }

        switch ckError.code {
        case .quotaExceeded:
            return "iCloud upload failed: iCloud storage is full. Free space in System Settings → Apple ID → iCloud, then try again."
        case .notAuthenticated, .badContainer:
            return "iCloud upload failed: sign in to iCloud and confirm Nucleus has iCloud access in System Settings."
        case .partialFailure:
            let detail = describe(ckError)
            if detail.localizedCaseInsensitiveContains("schema")
                || detail.localizedCaseInsensitiveContains("unknown field")
                || detail.localizedCaseInsensitiveContains("production") {
                return "iCloud upload failed: CloudKit schema may not be deployed to Production. Open CloudKit Console for iCloud.net.suherman.nucleus and deploy schema to Production."
            }
            return "iCloud upload failed: \(detail)"
        default:
            return "iCloud upload failed: \(describe(ckError))"
        }
    }

    private static func partialErrors(from ckError: CKError) -> [AnyHashable: Error] {
        if let partial = ckError.partialErrorsByItemID, !partial.isEmpty {
            return partial
        }
        if let partial = ckError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error], !partial.isEmpty {
            return partial
        }
        if let partial = ckError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: NSError], !partial.isEmpty {
            return partial.mapValues { $0 as Error }
        }
        return [:]
    }

    private static func nestedCloudKitMessages(for error: NSError, depth: Int = 0) -> [String] {
        guard depth < 4 else { return [] }

        var messages: [String] = []
        if error.domain == CKError.errorDomain,
           let code = CKError.Code(rawValue: error.code) {
            messages.append(headline(for: code))
            let ckError = CKError(_nsError: error)
            let partial = partialErrors(from: ckError)
            for (_, itemError) in partial.prefix(6) {
                messages.append(describe(itemError))
            }
        }

        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            messages.append(contentsOf: nestedCloudKitMessages(for: underlying, depth: depth + 1))
        }

        return messages
    }

    private static func headline(for code: CKError.Code) -> String {
        switch code {
        case .partialFailure:
            return "CKError partialFailure (code 2)"
        case .quotaExceeded:
            return "CKError quotaExceeded (code 12)"
        case .notAuthenticated:
            return "CKError notAuthenticated (code 9)"
        case .networkUnavailable:
            return "CKError networkUnavailable (code 3)"
        case .serviceUnavailable:
            return "CKError serviceUnavailable (code 6)"
        case .requestRateLimited:
            return "CKError requestRateLimited (code 7)"
        case .zoneNotFound:
            return "CKError zoneNotFound (code 26)"
        case .userDeletedZone:
            return "CKError userDeletedZone (code 28)"
        case .serverRecordChanged:
            return "CKError serverRecordChanged (code 14)"
        case .unknownItem:
            return "CKError unknownItem (code 11)"
        default:
            return "CKError code \(code.rawValue)"
        }
    }
}
