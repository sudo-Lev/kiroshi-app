import AppKit
import XCTest
@testable import Tokiri

@MainActor
final class ClipboardCoordinatorTests: XCTestCase {
    func testActionPasteRestoresAllPreviousPasteboardTypes() {
        let pasteboard = NSPasteboard(name: .init("ai.qwixit.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let customType = NSPasteboard.PasteboardType("ai.qwixit.tests.binary")
        let item = NSPasteboardItem()
        item.setString("original", forType: .string)
        item.setData(Data([0, 1, 2]), forType: customType)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])

        let archive = PasteboardArchive(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("temporary", forType: .string)
        archive.finishPaste(
            to: pasteboard,
            ifChangeCountAtMost: pasteboard.changeCount,
            clipboardAfterPaste: .restorePrevious,
            replacementWritten: true
        )

        XCTAssertEqual(pasteboard.string(forType: .string), "original")
        XCTAssertEqual(pasteboard.data(forType: customType), Data([0, 1, 2]))
    }

    func testArchiveDoesNotOverwriteNewerClipboardContent() {
        let pasteboard = NSPasteboard(name: .init("ai.qwixit.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("original", forType: .string)
        let archive = PasteboardArchive(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("temporary", forType: .string)
        let injectedChangeCount = pasteboard.changeCount
        pasteboard.clearContents()
        pasteboard.setString("newer copy", forType: .string)
        archive.finishPaste(
            to: pasteboard,
            ifChangeCountAtMost: injectedChangeCount,
            clipboardAfterPaste: .restorePrevious,
            replacementWritten: true
        )

        XCTAssertEqual(pasteboard.string(forType: .string), "newer copy")
    }

    func testFixKeepsReplacementForManualCommandV() {
        let pasteboard = NSPasteboard(name: .init("ai.qwixit.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("original", forType: .string)
        let archive = PasteboardArchive(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("fresh correction", forType: .string)
        archive.finishPaste(
            to: pasteboard,
            ifChangeCountAtMost: pasteboard.changeCount,
            clipboardAfterPaste: .keepReplacement,
            replacementWritten: true
        )

        XCTAssertEqual(pasteboard.string(forType: .string), "fresh correction")
    }

    func testPasteFailureBeforeClipboardWriteRestoresOriginal() {
        let pasteboard = NSPasteboard(name: .init("ai.qwixit.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("original", forType: .string)
        let archive = PasteboardArchive(pasteboard)

        pasteboard.clearContents()
        archive.finishPaste(
            to: pasteboard,
            ifChangeCountAtMost: pasteboard.changeCount,
            clipboardAfterPaste: .keepReplacement,
            replacementWritten: false
        )

        XCTAssertEqual(pasteboard.string(forType: .string), "original")
    }

    func testFixDoesNotOverwriteANewerClipboardChange() {
        let pasteboard = NSPasteboard(name: .init("ai.qwixit.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("original", forType: .string)
        let archive = PasteboardArchive(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("fresh correction", forType: .string)
        let replacementChangeCount = pasteboard.changeCount
        pasteboard.clearContents()
        pasteboard.setString("newer copy", forType: .string)
        archive.finishPaste(
            to: pasteboard,
            ifChangeCountAtMost: replacementChangeCount,
            clipboardAfterPaste: .keepReplacement,
            replacementWritten: true
        )

        XCTAssertEqual(pasteboard.string(forType: .string), "newer copy")
    }

    func testCopyReadbackAcceptsMultipleWritesAndRestoresOriginalClipboard() {
        let pasteboard = NSPasteboard(name: .init("ai.qwixit.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("original", forType: .string)
        let archive = PasteboardArchive(pasteboard)

        pasteboard.clearContents()
        let clearedCount = pasteboard.changeCount
        XCTAssertNil(ClipboardCopyReadback.text(from: pasteboard, after: clearedCount))

        pasteboard.declareTypes([.rtf], owner: nil)
        pasteboard.setData(Data([1, 2, 3]), forType: .rtf)
        XCTAssertNil(ClipboardCopyReadback.text(from: pasteboard, after: clearedCount))
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("selected", forType: .string)
        XCTAssertGreaterThan(pasteboard.changeCount, clearedCount + 1)
        XCTAssertEqual(ClipboardCopyReadback.text(from: pasteboard, after: clearedCount), "selected")

        archive.restore(to: pasteboard, ifChangeCountAtMost: pasteboard.changeCount)
        XCTAssertEqual(pasteboard.string(forType: .string), "original")
    }

}
