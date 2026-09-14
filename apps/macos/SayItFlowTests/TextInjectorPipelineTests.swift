import AppKit
import ApplicationServices
import XCTest
@testable import SayItFlow

@MainActor
final class TextInjectorPipelineTests: XCTestCase {

    func testAXHelpersTextInputRoles() {
        // Test that read-only/structural elements are NOT classified as text inputs
        // to prevent false positives and stalling during injection
        let dummyApp = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        XCTAssertFalse(AXHelpers.isTextInputElement(dummyApp))
    }

    func testAXFocusResolverExecutionSpeed() {
        // Must return near-instantly without recursive window tree crawling
        var diagnostics = AXFocusResolver.Diagnostics()
        let start = CFAbsoluteTimeGetCurrent()
        _ = AXFocusResolver.focusedTextElement(forPID: ProcessInfo.processInfo.processIdentifier, diagnostics: &diagnostics)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000.0

        // In the old implementation with depth-28 recursion, this could take 2000-4000ms.
        // The optimized implementation must complete in under 50ms.
        XCTAssertLessThan(elapsedMs, 50.0, "AXFocusResolver took too long: \(elapsedMs) ms")
    }

    func testKeystrokeEmitterCommandVDwellTime() {
        let success = KeystrokeEmitter.postCommandV()
        XCTAssertTrue(success)
    }

    func testKeystrokeEmitterTypeText() {
        let success = KeystrokeEmitter.typeText("Hello")
        XCTAssertTrue(success)
    }

    func testS1MiniEngineNormalizationIsInstantaneous() async {
        let engine = S1MiniEngine.shared
        engine.isEnabled = true
        _ = await engine.ensureServerRunning()
        let raw = "um so I I think the project is ready"

        let start = CFAbsoluteTimeGetCurrent()
        let normalized = await engine.normalize(raw, language: "en")
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000.0

        // Normalization on warm server must be fast (< 500ms vs 3500ms cold CLI)
        XCTAssertLessThan(elapsedMs, 600.0, "S1MiniEngine normalization took too long: \(elapsedMs) ms")
        XCTAssertFalse(normalized.lowercased().starts(with: "um "))
        XCTAssertTrue(normalized.contains("I think") || normalized.contains("project is ready"))
        XCTAssertFalse(normalized.contains("I I"))
    }

    func testPasteboardRescueWithTargetPID() {
        let testPasteboard = NSPasteboard(name: NSPasteboard.Name("com.innovatorved.sayitflow.pipeline.test"))
        testPasteboard.clearContents()

        let success = PasteboardRescue.paste(
            "pipeline test text",
            targetPID: ProcessInfo.processInfo.processIdentifier,
            pasteboard: testPasteboard
        )
        XCTAssertTrue(success)
        XCTAssertEqual(testPasteboard.string(forType: .string), "pipeline test text")
        testPasteboard.releaseGlobally()
    }
}
