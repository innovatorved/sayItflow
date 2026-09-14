import XCTest
@testable import SayItFlow

final class SayItFlowErrorTests: XCTestCase {
    func testPermissionsIncompleteDescription() {
        let error = SayItFlowError.permissionsIncomplete
        XCTAssertEqual(error.errorDescription, "Grant microphone, accessibility, and input monitoring in Settings.")
    }

    func testPipelineMessagePassthrough() {
        let error = SayItFlowError.pipeline("Engine timeout")
        XCTAssertEqual(error.errorDescription, "Engine timeout")
    }

    func testEngineUnavailableDescription() {
        XCTAssertEqual(SayItFlowError.engineUnavailable.errorDescription, "Speech models are not ready yet.")
    }
}
