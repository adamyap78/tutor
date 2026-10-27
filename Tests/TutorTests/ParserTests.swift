import Testing
@testable import Tutor

/// Renders a parsed query as a compact string so tree shapes are easy to assert.
private func shape(_ raw: String) -> String {
    var p = QParser(raw)
    guard let n = p.parse() else { return "nil" }
    return describe(n)
}

private func describe(_ n: QNode) -> String {
    switch n {
    case .term(let t):
        let v = t.quoted ? "\"\(t.value)\"" : t.value
        return (t.field ?? "") + (t.field == nil ? "" : t.op) + v
    case .and(let ps): return "and(" + ps.map(describe).joined(separator: ", ") + ")"
    case .or(let ps): return "or(" + ps.map(describe).joined(separator: ", ") + ")"
    case .not(let c): return "not(" + describe(c) + ")"
    }
}

@Suite struct ParserTests {
    @Test func bareWordsAreNameTerms() {
        #expect(shape("bolt") == "bolt")
        #expect(shape("lightning bolt") == "and(lightning, bolt)")
    }

    @Test func filtersCarryFieldAndOperator() {
        #expect(shape("t:creature") == "t:creature")
        #expect(shape("mv<=3") == "mv<=3")
        #expect(shape("pow>=4") == "pow>=4")
        #expect(shape("mv!=2") == "mv!=2")
        #expect(shape("id=wu") == "id=wu")
    }

    @Test func quotedPhrasesStayTogether() {
        #expect(shape("\"lightning bolt\"") == "\"lightning bolt\"")
        #expect(shape("o:\"draw a card\"") == "o:\"draw a card\"")
    }

    @Test func exactNameBang() {
        var p = QParser("!\"Lightning Bolt\"")
        guard case .term(let t)? = p.parse() else { Issue.record("expected a term"); return }
        #expect(t.field == "!")
        #expect(t.value == "Lightning Bolt")
    }

    @Test func negation() {
        #expect(shape("-t:creature") == "not(t:creature)")
        #expect(shape("-\"foo bar\"") == "not(\"foo bar\")")
        #expect(shape("a - b") == "and(a, b)")
    }

    @Test func orBindsLooserThanAnd() {
        #expect(shape("a or b") == "or(a, b)")
        #expect(shape("a b or c") == "or(and(a, b), c)")
        #expect(shape("a OR b") == "or(a, b)")
    }

    @Test func wordsStartingWithOrAreNotTheKeyword() {
        #expect(shape("orc") == "orc")
        #expect(shape("a order:cmc") == "and(a, order:cmc)")
    }

    @Test func parenthesesGroup() {
        #expect(shape("(c:r or c:g) t:creature") == "and(or(c:r, c:g), t:creature)")
        #expect(shape("-(a or b)") == "not(or(a, b))")
    }

    @Test func emptyAndBlankInput() {
        #expect(shape("") == "nil")
        #expect(shape("   ") == "nil")
    }

    @Test(arguments: ["(", ")", "((a", "a)", "-", "-(", "\"unterminated", "t:", ":", "or", "()"])
    func malformedInputNeverCrashes(_ raw: String) {
        _ = shape(raw)
        _ = QueryCompiler.compile(raw)
    }
}
