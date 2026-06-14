import XCTest
import SwiftData
import NucleusKit
@testable import DatabaseKit

final class DatabaseKitTests: XCTestCase {
    func testAccountRepositoryUpsert() throws {
        let container = try NucleusDatabase.makeContainer(inMemory: true)
        let context = ModelContext(container)

        let account = GoogleAccount(email: "personal@gmail.com", displayName: "Personal", isPrimary: true)
        try AccountRepository.upsert(account, context: context)

        let fetched = try AccountRepository.fetchAll(context: context)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.email, "personal@gmail.com")
    }
}
