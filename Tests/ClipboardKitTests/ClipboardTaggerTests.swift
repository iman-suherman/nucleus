import XCTest
import NucleusKit
@testable import ClipboardKit

final class ClipboardTaggerTests: XCTestCase {
    func testInfersDockerTag() {
        let tags = ClipboardTagger.inferTags(from: "docker compose up")
        XCTAssertTrue(tags.contains("docker"))
    }

    func testSearchRanksPinnedHigher() {
        let entries = [
            ClipboardEntry(content: "kubectl get pods", isPinned: false),
            ClipboardEntry(content: "kubectl logs deploy", isPinned: true),
        ]
        let ranked = ClipboardSearch.rank(entries, query: "kubectl")
        XCTAssertEqual(ranked.first?.isPinned, true)
    }
}
