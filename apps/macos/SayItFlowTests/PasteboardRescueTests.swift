import AppKit
import XCTest
@testable import SayItFlow

final class PasteboardRescueTests: XCTestCase {
    private var pasteboard: NSPasteboard!

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard(name: NSPasteboard.Name("com.innovatorved.sayitflow.tests"))
        pasteboard.clearContents()
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        pasteboard = nil
        super.tearDown()
    }

    /// The bug: restore only ever carried `.string`, so pasting while an image or file
    /// was on the clipboard destroyed it.
    func testRestoreRoundTripsEveryType() {
        let tiff = NSPasteboard.PasteboardType.tiff
        let imageData = Data([0x4D, 0x4D, 0x00, 0x2A])

        let item = NSPasteboardItem()
        item.setString("original text", forType: .string)
        item.setData(imageData, forType: tiff)
        pasteboard.writeObjects([item])

        let saved = PasteboardRescue.snapshot(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("dictated text", forType: .string)
        XCTAssertNil(pasteboard.data(forType: tiff))

        PasteboardRescue.restore(saved, to: pasteboard)

        XCTAssertEqual(pasteboard.string(forType: .string), "original text")
        XCTAssertEqual(pasteboard.data(forType: tiff), imageData)
    }

    func testRestoringAnEmptySnapshotLeavesPasteboardEmpty() {
        let saved = PasteboardRescue.snapshot(pasteboard)
        XCTAssertTrue(saved.isEmpty)

        pasteboard.clearContents()
        pasteboard.setString("dictated text", forType: .string)

        PasteboardRescue.restore(saved, to: pasteboard)
        XCTAssertNil(pasteboard.string(forType: .string))
    }

    func testSnapshotIsDetachedFromLaterMutations() {
        pasteboard.clearContents()
        pasteboard.setString("first", forType: .string)
        let saved = PasteboardRescue.snapshot(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("second", forType: .string)

        PasteboardRescue.restore(saved, to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), "first")
    }

    func testRestoreIfUnchangedSkipsRestoreWhenUserCopiedSomethingNew() {
        pasteboard.clearContents()
        pasteboard.setString("original", forType: .string)
        let saved = PasteboardRescue.snapshot(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("dictated", forType: .string)
        let expectedCount = pasteboard.changeCount

        // User copies something new before restoreDelay fires
        pasteboard.clearContents()
        pasteboard.setString("user new copy", forType: .string)

        let restored = PasteboardRescue.restoreIfUnchanged(
            saved,
            expectedChangeCount: expectedCount,
            to: pasteboard
        )
        XCTAssertFalse(restored)
        XCTAssertEqual(pasteboard.string(forType: .string), "user new copy")
    }

    func testRestoreIfUnchangedRestoresWhenUnmodified() {
        pasteboard.clearContents()
        pasteboard.setString("original", forType: .string)
        let saved = PasteboardRescue.snapshot(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("dictated", forType: .string)
        let expectedCount = pasteboard.changeCount

        let restored = PasteboardRescue.restoreIfUnchanged(
            saved,
            expectedChangeCount: expectedCount,
            to: pasteboard
        )
        XCTAssertTrue(restored)
        XCTAssertEqual(pasteboard.string(forType: .string), "original")
    }
}
