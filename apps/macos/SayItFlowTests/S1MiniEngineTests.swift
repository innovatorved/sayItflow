import XCTest
@testable import SayItFlow

@MainActor
final class S1MiniEngineTests: XCTestCase {
    var engine: S1MiniEngine!

    override func setUp() {
        super.setUp()
        engine = S1MiniEngine.shared
        engine.isEnabled = true
        engine.styling = .semiFormal
        engine.structure = .prose
        engine.context = .general
    }

    func testPromptFormattingIncludesMandatoryThinkingBlock() {
        let input = "send the invoice by friday"
        let prompt = engine.buildPrompt(for: input)

        XCTAssertTrue(prompt.contains("<|im_start|>system"))
        XCTAssertTrue(prompt.contains("You are a text normalizer for speech-to-text transcripts."))
        XCTAssertTrue(prompt.contains("[Styling: semi-formal] [Structure: prose] [Context: general]"))
        XCTAssertTrue(prompt.contains(input))
        // Verify mandatory closed thinking block
        XCTAssertTrue(prompt.contains("<|im_start|>assistant"))
        XCTAssertTrue(prompt.contains("<think>"))
        XCTAssertTrue(prompt.contains("</think>"))
    }

    func testPromptUpdatesWithDifferentControls() {
        engine.styling = .casual
        engine.structure = .lists
        engine.context = .email

        let prompt = engine.buildPrompt(for: "meeting notes")
        XCTAssertTrue(prompt.contains("[Styling: casual] [Structure: lists] [Context: email]"))
    }

    func testNonEnglishLanguageBypassesS1Mini() async {
        let spanishRaw = "hola cómo estás por favor envía el informe"
        let result = await engine.normalize(spanishRaw, language: "es")
        XCTAssertEqual(result, spanishRaw)

        let frenchRaw = "bonjour tout le monde"
        let resultFrench = await engine.normalize(frenchRaw, language: "fr")
        XCTAssertEqual(resultFrench, frenchRaw)
    }

    func testDisabledEngineReturnsRaw() async {
        engine.isEnabled = false
        let raw = "um so like this is raw speech"
        let result = await engine.normalize(raw, language: "en")
        XCTAssertEqual(result, raw)
    }

    func testFillerOnlyReturnsEmpty() async {
        XCTAssertTrue(engine.isFillerOnly("um"))
        XCTAssertTrue(engine.isFillerOnly("uh"))
        XCTAssertTrue(engine.isFillerOnly("um uh ah"))
        XCTAssertTrue(engine.isFillerOnly("erm, uh... ah!"))

        let result = await engine.normalize("um uh ah", language: "en")
        XCTAssertEqual(result, "")
    }

    func testMeaningfulSpeechIsNotFillerOnly() {
        XCTAssertFalse(engine.isFillerOnly("umbrella"))
        XCTAssertFalse(engine.isFillerOnly("so um I need the file"))
        XCTAssertFalse(engine.isFillerOnly("yes"))
    }

    func testRuleBasedNormalizerRemovesDisfluencies() {
        let raw = "um so I need to like submit the report"
        let normalized = engine.ruleBasedNormalize(raw)
        XCTAssertFalse(normalized.lowercased().starts(with: "um "))
        XCTAssertTrue(normalized.prefix(1).allSatisfy { $0.isUppercase })
    }

    func testRuleBasedNormalizerCollapsesStutters() {
        let raw = "I I think the the project is ready"
        let normalized = engine.ruleBasedNormalize(raw)
        XCTAssertTrue(normalized.contains("I think"))
        XCTAssertTrue(normalized.contains("the project"))
        XCTAssertFalse(normalized.contains("the the"))
    }

    func testServerPortMatchesConfiguredConstant() {
        XCTAssertEqual(S1MiniEngine.serverPort, 58231)
    }

    func testFindServerBinary() {
        // Verifies the discovery logic finds llama-server if installed
        if FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/llama-server") {
            XCTAssertNotNil(engine.findServerBinary())
        }
    }
}
