import XCTest
@testable import Harbor

final class QueueItemTests: XCTestCase {

    func testQueueItemKindClassification() {
        let appURL = URL(fileURLWithPath: "/tmp/MyApp.app")
        XCTAssertEqual(QueueItemKind(url: appURL), .app)

        let photoURL = URL(fileURLWithPath: "/tmp/sample.png")
        XCTAssertEqual(QueueItemKind(url: photoURL), .photo)

        let videoURL = URL(fileURLWithPath: "/tmp/demo.mov")
        XCTAssertEqual(QueueItemKind(url: videoURL), .video)

        let contactURL = URL(fileURLWithPath: "/tmp/john.vcf")
        XCTAssertEqual(QueueItemKind(url: contactURL), .contact)

        let apnsURL = URL(fileURLWithPath: "/tmp/push.apns")
        XCTAssertEqual(QueueItemKind(url: apnsURL), .apnsPayload)

        let weblocURL = URL(fileURLWithPath: "/tmp/link.webloc")
        XCTAssertEqual(QueueItemKind(url: weblocURL), .link)

        let webURL = URL(string: "https://apple.com")!
        XCTAssertEqual(QueueItemKind(url: webURL), .link)

        let docURL = URL(fileURLWithPath: "/tmp/report.pdf")
        XCTAssertEqual(QueueItemKind(url: docURL), .generalDocument)
    }

    func testPriorityOrdering() {
        let app = QueueItemKind.app
        let photo = QueueItemKind.photo
        let apns = QueueItemKind.apnsPayload
        let link = QueueItemKind.link

        XCTAssertLessThan(app.priorityOrder, photo.priorityOrder)
        XCTAssertLessThan(photo.priorityOrder, apns.priorityOrder)
        XCTAssertLessThan(apns.priorityOrder, link.priorityOrder)
    }

    func testSupportsDestinationOverride() {
        let appItem = QueueItem(url: URL(fileURLWithPath: "/tmp/Test.app"))
        XCTAssertFalse(appItem.supportsDestinationOverride)

        let linkItem = QueueItem(url: URL(string: "myapp://test")!)
        XCTAssertFalse(linkItem.supportsDestinationOverride)

        let apnsItem = QueueItem(url: URL(fileURLWithPath: "/tmp/test.apns"))
        XCTAssertFalse(apnsItem.supportsDestinationOverride)

        let docItem = QueueItem(url: URL(fileURLWithPath: "/tmp/test.pdf"))
        XCTAssertTrue(docItem.supportsDestinationOverride)

        let photoItem = QueueItem(url: URL(fileURLWithPath: "/tmp/test.jpg"))
        XCTAssertTrue(photoItem.supportsDestinationOverride)
    }

    func testContextualIconSystemNames() {
        let swiftItem = QueueItem(url: URL(fileURLWithPath: "/tmp/TestView.swift"))
        XCTAssertEqual(swiftItem.iconSystemName, "chevron.left.forwardslash.chevron.right")

        let pdfItem = QueueItem(url: URL(fileURLWithPath: "/tmp/doc.pdf"))
        XCTAssertEqual(pdfItem.iconSystemName, "doc.richtext.fill")

        let txtItem = QueueItem(url: URL(fileURLWithPath: "/tmp/notes.txt"))
        XCTAssertEqual(txtItem.iconSystemName, "doc.plaintext.fill")

        let zipItem = QueueItem(url: URL(fileURLWithPath: "/tmp/archive.zip"))
        XCTAssertEqual(zipItem.iconSystemName, "doc.zipper")

        let photoItem = QueueItem(url: URL(fileURLWithPath: "/tmp/pic.png"))
        XCTAssertEqual(photoItem.iconSystemName, "photo.fill")
    }
}
