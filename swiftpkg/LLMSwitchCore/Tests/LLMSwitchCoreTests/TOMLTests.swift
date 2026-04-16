import Foundation
import Testing
@testable import LLMSwitchCore

@Test func tomlParserSupportsQuotedKeysAndComments() throws {
    let source = """
    [enabledModels]
    "gpt-4.1" = true # keep enabled

    [activeBindings."gpt-4.1"]
    provider = "openai"
    upstreamModel = "gpt-4.1"
    """

    let document = try TOMLParser.parse(source)
    #expect(document.table(at: ["enabledModels"])?["gpt-4.1"] == .bool(true))
    #expect(document.table(at: ["activeBindings", "gpt-4.1"])?["provider"] == .string("openai"))
}
