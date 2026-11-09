import XCTest
@testable import Harbor

@MainActor
final class QueueManagerTests: XCTestCase {

    override func setUp() async throws {
        QueueManager.shared.clear()
    }

    override func tearDown() async throws {
        QueueManager.shared.clear()
    }

    func testAddAndClearItems() {
        let manager = QueueManager.shared
        XCTAssertTrue(manager.items.isEmpty)

        let urls = [
            URL(fileURLWithPath: "/tmp/sample1.png"),
            URL(fileURLWithPath: "/tmp/sample2.pdf")
        ]

        manager.add(urls: urls)
        XCTAssertEqual(manager.items.count, 2)

        // Duplicate addition should be ignored
        manager.add(urls: [URL(fileURLWithPath: "/tmp/sample1.png")])
        XCTAssertEqual(manager.items.count, 2)

        manager.clear()
        XCTAssertTrue(manager.items.isEmpty)
    }

    func testBatchDestinationTransitions() {
        let manager = QueueManager.shared

        let urls = [
            URL(fileURLWithPath: "/tmp/doc1.pdf"),
            URL(fileURLWithPath: "/tmp/doc2.pdf")
        ]
        manager.add(urls: urls)

        // Initially both are .auto
        XCTAssertEqual(manager.batchDestinationState, .uniform(.auto))

        // Set all to Files app
        manager.setDestinationForAll(.filesApp)
        XCTAssertEqual(manager.batchDestinationState, .uniform(.filesApp))

        // Change single item to custom app Documents
        if let first = manager.items.first {
            manager.setDestination(.appDocuments(bundleId: "com.test.app"), for: first.id)
            XCTAssertEqual(manager.batchDestinationState, .mixed)
        }

        // Set all back to auto
        manager.setDestinationForAll(.auto)
        XCTAssertEqual(manager.batchDestinationState, .uniform(.auto))
    }

    func testRemoveItem() {
        let manager = QueueManager.shared
        let url = URL(fileURLWithPath: "/tmp/test.png")
        manager.add(urls: [url])

        XCTAssertEqual(manager.items.count, 1)
        guard let item = manager.items.first else {
            XCTFail("Item should exist")
            return
        }

        manager.remove(id: item.id)
        XCTAssertTrue(manager.items.isEmpty)
    }
}
