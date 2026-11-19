import XCTest
@testable import SayItFlow

final class VocabularyStoreTests: XCTestCase {
    private var previous: Vocabulary!

    override func setUp() {
        super.setUp()
        previous = VocabularyStore.load()
    }

    override func tearDown() {
        VocabularyStore.save(previous)
        super.tearDown()
    }

    func testCachedCaseCorrectionsApplyAndInvalidateOnSave() {
        VocabularyStore.save(Vocabulary(terms: ["SayItFlow", "SwiftUI", "PostgreSQL"]))
        let first = VocabularyStore.applyCaseCorrections(to: "I love sayitflow and swiftui with postgresql.")
        XCTAssertEqual(first, "I love SayItFlow and SwiftUI with PostgreSQL.")

        // Update vocabulary and verify cache invalidates immediately
        VocabularyStore.save(Vocabulary(terms: ["Xcode"]))
        let second = VocabularyStore.applyCaseCorrections(to: "Open xcode and sayitflow.")
        XCTAssertEqual(second, "Open Xcode and sayitflow.")
    }
}
