import Testing
@testable import TranslationCore

@Test(arguments: ["\n", "\r\n", "\r", "\u{0085}", "\u{2028}", "\u{2029}", "\u{000B}", "\u{000C}"])
func translationKeepsSourceSeparatorsBlankLinesAndFinalNewline(separator: String) throws {
    let source = separator + "日本語" + separator + separator + " \t" + separator + "😀次の行" + separator
    let layout = TranslationLayout(source)
    #expect(layout.lines == ["日本語", "😀次の行"])
    let result = try layout.applying(["\nFirst\r\nline\n", "Second line"])
    #expect(result == separator + "First line" + separator + separator + " \t" + separator + "Second line" + separator)
}

@Test(arguments: ["\nHello\r\nworld\n", "Hello\n\nworld", "\tHello\u{2028}world\t", "Hello\rworld"])
func aSingleSourceLineCannotGainNewLines(translated: String) throws {
    let layout = TranslationLayout("こんにちは。")
    #expect(try layout.applying([translated]) == "Hello world")
}

@Test func extraBlankLinesInTranslationDoNotCreateNewParagraphs() throws {
    let layout = TranslationLayout("こんにちは。いい天気です。\nそうですね。\n明日は雨です。\n今日は散歩しましょう。")
    #expect(layout.lines == ["こんにちは。いい天気です。", "そうですね。", "明日は雨です。", "今日は散歩しましょう。"])
    #expect(try layout.applying(["Hello, nice weather.\n", "Yes, it is.\n\n", "It will rain tomorrow.\n\n", "Let's take a walk today.\n"]) ==
            "Hello, nice weather.\nYes, it is.\nIt will rain tomorrow.\nLet's take a walk today.")
}

@Test func existingParagraphBreaksAreKept() throws {
    let source = "こんにちは。いい天気です。\nそうですね。\n\n明日は雨です。\n\n今日は散歩しましょう。\n"
    let layout = TranslationLayout(source)
    let translated = ["Hello, nice weather.", "Yes, it is.", "It will rain tomorrow.", "Let's take a walk today."]
    #expect(try layout.applying(translated.map { "\n" + $0 + "\n\n" }) ==
            "Hello, nice weather.\nYes, it is.\n\nIt will rain tomorrow.\n\nLet's take a walk today.\n")
}

@Test func translationKeepsMixedSourceLineBreaksAndInternalSpaces() throws {
    let layout = TranslationLayout("一\r\n\r\n二\n \t\r三\r\n")
    #expect(layout.lines == ["一", "二", "三"])
    let result = try layout.applying(["  One  words\nnext  ", "Two", "Three"])
    #expect(result == "One  words next\r\n\r\nTwo\n \t\rThree\r\n")
}

@Test(arguments: ["", " \t", "\n \t\r\n\r"])
func emptySourceLinesAreNotSentForTranslation(source: String) throws {
    let layout = TranslationLayout(source)
    #expect(layout.lines.isEmpty)
    #expect(try layout.applying([]) == source)
}

@Test(arguments: ["", "\n \t\r\n"])
func emptyTranslatedLineFailsTheEntireTranslation(translated: String) {
    let layout = TranslationLayout("最初\n二番目\n最後")
    #expect(throws: InputError.emptyTranslation) {
        try layout.applying(["First", translated, "Last"])
    }
}

@Test(arguments: [[String](), ["First"], ["First", "Second", "Extra"]])
func incompleteOrExtraTranslatedLinesAreRejected(translated: [String]) {
    let layout = TranslationLayout("最初\n次の行")
    #expect(throws: InputError.emptyTranslation) { try layout.applying(translated) }
}
