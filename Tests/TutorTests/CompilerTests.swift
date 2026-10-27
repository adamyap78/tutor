import Foundation
import Testing
@testable import Tutor

/// Runs compiled queries against a small in-memory database that uses the importer's real schema.
final class Fixture {
    let db: SQLiteConn

    struct Card {
        var id: Int64
        var name: String
        var cost: String
        var cmc: Double
        var type: String
        var text = ""
        var keywords = ""
        var colors = ""
        var produced = ""
        var pow: Double? = nil
        var tou: Double? = nil
        var rarity = "common"
        var modern = false
        var pop: Int64? = nil
    }

    private static func mask(_ letters: String) -> Int64 {
        Int64(letters.reduce(0) { $0 | (Colors.bits[$1] ?? 0) })
    }

    init() throws {
        db = try SQLiteConn(path: ":memory:", readOnly: false)
        try db.exec("""
        CREATE TABLE cards(
          id INTEGER PRIMARY KEY, oracle_id TEXT NOT NULL, name TEXT NOT NULL, name_norm TEXT NOT NULL,
          mana_cost TEXT NOT NULL, cmc REAL NOT NULL, type_line TEXT NOT NULL, type_lc TEXT NOT NULL,
          text_lc TEXT NOT NULL, keywords_lc TEXT NOT NULL, colors INT NOT NULL, ci INT NOT NULL,
          produced INT NOT NULL, pow REAL, tou REAL, loy REAL, legal INT NOT NULL, restricted INT NOT NULL,
          banned INT NOT NULL, rarities INT NOT NULL, layout TEXT NOT NULL, flags INT NOT NULL,
          year_min INT, year_max INT, usd_min REAL, usd_max REAL, edhrec INT, pop INT NOT NULL,
          printing_id INT NOT NULL, scry_id TEXT NOT NULL, set_code TEXT NOT NULL, rarity INT NOT NULL,
          has_image INT NOT NULL);
        CREATE TABLE printings(
          id INTEGER PRIMARY KEY, card_id INT NOT NULL, scry_id TEXT NOT NULL, set_code TEXT NOT NULL,
          set_name TEXT NOT NULL, cn TEXT NOT NULL, rarity INT NOT NULL, released TEXT NOT NULL,
          usd REAL, usd_foil REAL, usd_etched REAL, has_image INT NOT NULL,
          set_type TEXT NOT NULL, attrs INT NOT NULL);
        """)
        let cards = [
            Card(id: 1, name: "Lightning Bolt", cost: "{R}", cmc: 1, type: "Instant", text: "Lightning Bolt deals 3 damage to any target.", colors: "r", modern: true),
            Card(id: 2, name: "Llanowar Elves", cost: "{G}", cmc: 1, type: "Creature — Elf Druid", text: "{T}: Add {G}.", colors: "g", produced: "g", pow: 1, tou: 1, modern: true),
            Card(id: 3, name: "Serra Angel", cost: "{3}{W}{W}", cmc: 5, type: "Creature — Angel", text: "Flying, vigilance", keywords: "flying vigilance", colors: "w", pow: 4, tou: 4, rarity: "uncommon", modern: true),
            Card(id: 4, name: "Counterspell", cost: "{U}{U}", cmc: 2, type: "Instant", text: "Counter target spell.", colors: "u", rarity: "uncommon", modern: true),
            Card(id: 5, name: "Niv-Mizzet, Parun", cost: "{3}{U}{R}", cmc: 6, type: "Legendary Creature — Dragon Wizard", text: "Flying", keywords: "flying", colors: "ur", pow: 5, tou: 5, rarity: "mythic"),
            Card(id: 6, name: "Sol Ring", cost: "{1}", cmc: 1, type: "Artifact", text: "{T}: Add {C}{C}.", rarity: "uncommon"),
            Card(id: 7, name: "Chain Lightning", cost: "{R}", cmc: 1, type: "Sorcery", text: "Chain Lightning deals 3 damage to any target.", colors: "r", rarity: "uncommon", pop: 0),
        ]
        let ins = try db.prepare("INSERT INTO cards VALUES(\(Array(repeating: "?", count: 33).joined(separator: ",")))")
        for c in cards {
            let m = Fixture.mask(c.colors)
            let rarityBit = Int64(1 << Rarity.index(c.rarity)!)
            let modernBit = Int64(1 << Formats.keys.firstIndex(of: "modern")!)
            ins.reset()
            ins.bind([
                .int(c.id), .text("oracle\(c.id)"), .text(c.name), .text(TextNorm.normName(c.name)),
                .text(c.cost), .double(c.cmc), .text(c.type), .text(c.type.lowercased()),
                .text(c.text.lowercased()), .text(c.keywords), .int(m), .int(m),
                .int(Fixture.mask(c.produced)), c.pow.map { .double($0) } ?? .null, c.tou.map { .double($0) } ?? .null, .null,
                .int(c.modern ? modernBit : 0), .int(0),
                .int(0), .int(rarityBit), .text("normal"), .int(0),
                .null, .null, .null, .null, .null, .int(c.pop ?? c.id),
                .int(c.id), .text("scry\(c.id)"), .text("lea"), .int(0),
                .int(0),
            ])
            try ins.run()
        }
        let prt = try db.prepare("INSERT INTO printings VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)")
        for (pid, cardID, set) in [(1, 1, "lea"), (2, 1, "m10"), (3, 3, "lea"), (4, 6, "lea")] as [(Int64, Int64, String)] {
            prt.reset()
            prt.bind([.int(pid), .int(cardID), .text("p\(pid)"), .text(set), .text(set), .text("1"), .int(0), .text("1993-08-05"),
                      .null, .null, .null, .int(0), .text("core"), .int(0)])
            try prt.run()
        }
    }

    /// Card names matched by `query`, in the order the app would show them.
    func names(_ query: String) throws -> [String] {
        let q = QueryCompiler.compile(query)
        let st = try db.prepare(q.sql)
        st.bind(q.binds)
        let lookup = try db.prepare("SELECT name FROM cards WHERE id = ?")
        var out: [String] = []
        while st.step() {
            lookup.reset()
            lookup.bind(1, .int(st.int64(0)))
            lookup.step()
            out.append(lookup.text(0))
        }
        return out
    }
}

@Suite struct CompilerTests {
    let fx: Fixture
    init() throws { fx = try Fixture() }

    private func match(_ query: String) throws -> Set<String> { Set(try fx.names(query)) }

    // MARK: Names

    @Test func nameSubstringIsCaseAndAccentInsensitive() throws {
        #expect(try match("BOLT") == ["Lightning Bolt"])
        #expect(try match("niv mizzet") == ["Niv-Mizzet, Parun"])
        #expect(try match("lightning bolt") == ["Lightning Bolt"])
    }

    @Test func exactNameMatch() throws {
        #expect(try match("!\"lightning bolt\"") == ["Lightning Bolt"])
        #expect(try match("!lightning") == [])
    }

    @Test func prefixMatchesRankAboveSubstringMatches() throws {
        // Chain Lightning is more popular, but "Lightning Bolt" starts with the query.
        #expect(try fx.names("lightning") == ["Lightning Bolt", "Chain Lightning"])
    }

    @Test func blankQueryReturnsEverythingByPopularity() throws {
        let all = try fx.names("")
        #expect(all.count == 7)
        #expect(all.first == "Chain Lightning")
        #expect(QueryCompiler.compile("  ").isBlank)
    }

    // MARK: Fields

    @Test func typeAndOracleText() throws {
        #expect(try match("t:creature") == ["Llanowar Elves", "Serra Angel", "Niv-Mizzet, Parun"])
        #expect(try match("t:legendary t:creature") == ["Niv-Mizzet, Parun"])
        #expect(try match("o:\"deals 3 damage\"") == ["Lightning Bolt", "Chain Lightning"])
        #expect(try match("kw:flying") == ["Serra Angel", "Niv-Mizzet, Parun"])
    }

    @Test func manaValue() throws {
        #expect(try match("mv>=5") == ["Serra Angel", "Niv-Mizzet, Parun"])
        #expect(try match("t:creature mv<=1") == ["Llanowar Elves"])
        #expect(try match("mv:even") == ["Counterspell", "Niv-Mizzet, Parun"])
        #expect(try match("mv=2") == ["Counterspell"])
    }

    @Test func powerAndToughness() throws {
        #expect(try match("pow>=4") == ["Serra Angel", "Niv-Mizzet, Parun"])
        #expect(try match("pow=tou") == ["Llanowar Elves", "Serra Angel", "Niv-Mizzet, Parun"])
        #expect(try match("pow>tou") == [])
        // Noncreatures have no power, so they never match a numeric comparison.
        #expect(try match("pow<10").contains("Sol Ring") == false)
    }

    @Test func colours() throws {
        #expect(try match("c:r") == ["Lightning Bolt", "Niv-Mizzet, Parun", "Chain Lightning"])
        #expect(try match("c=r") == ["Lightning Bolt", "Chain Lightning"])
        #expect(try match("c:ur") == ["Niv-Mizzet, Parun"])
        #expect(try match("c:izzet") == ["Niv-Mizzet, Parun"])
        #expect(try match("c:c") == ["Sol Ring"])
        #expect(try match("c:m") == ["Niv-Mizzet, Parun"])
        #expect(try match("c<=r") == ["Lightning Bolt", "Chain Lightning", "Sol Ring"])
    }

    @Test func colourIdentityDefaultsToSubset() throws {
        #expect(try match("id:ur") == ["Lightning Bolt", "Counterspell", "Niv-Mizzet, Parun", "Sol Ring", "Chain Lightning"])
        #expect(try match("id>=ur") == ["Niv-Mizzet, Parun"])
    }

    @Test func rarityComparisons() throws {
        #expect(try match("r:mythic") == ["Niv-Mizzet, Parun"])
        #expect(try match("r:common") == ["Lightning Bolt", "Llanowar Elves"])
        #expect(try match("r>=uncommon").count == 5)
        #expect(try match("r<uncommon") == ["Lightning Bolt", "Llanowar Elves"])
    }

    @Test func setsAndManaCost() throws {
        #expect(try match("s:lea") == ["Lightning Bolt", "Serra Angel", "Sol Ring"])
        #expect(try match("s:m10") == ["Lightning Bolt"])
        #expect(try match("-s:lea").contains("Lightning Bolt") == false)
        #expect(try match("m:r") == ["Lightning Bolt", "Niv-Mizzet, Parun", "Chain Lightning"])
        #expect(try match("m:{3}{W}") == ["Serra Angel"])
    }

    @Test func formatsAndProduces() throws {
        #expect(try match("f:modern") == ["Lightning Bolt", "Llanowar Elves", "Serra Angel", "Counterspell"])
        #expect(try match("produces:g") == ["Llanowar Elves"])
    }

    // MARK: Boolean logic

    @Test func negationIncludesCardsWithNullFields() throws {
        #expect(try match("-t:creature") == ["Lightning Bolt", "Counterspell", "Sol Ring", "Chain Lightning"])
        #expect(try match("-pow>=4").contains("Lightning Bolt"))
    }

    @Test func orAndGrouping() throws {
        #expect(try match("(c:g or c:w) t:creature") == ["Llanowar Elves", "Serra Angel"])
        #expect(try match("bolt or elves") == ["Lightning Bolt", "Llanowar Elves"])
        #expect(try match("t:instant -c:u") == ["Lightning Bolt"])
    }

    // MARK: Warnings

    @Test func problemsProduceWarningsInsteadOfFailing() {
        #expect(!QueryCompiler.compile("mv>big").warnings.isEmpty)
        #expect(!QueryCompiler.compile("c:xyz").warnings.isEmpty)
        #expect(!QueryCompiler.compile("r:legendary").warnings.isEmpty)
        #expect(!QueryCompiler.compile("f:nonsense").warnings.isEmpty)
        #expect(!QueryCompiler.compile("xyz:1").warnings.isEmpty)
        #expect(QueryCompiler.compile("t:creature mv<=3").warnings.isEmpty)
    }

    @Test func unknownFilterIsIgnoredNotFatal() throws {
        // The bad term drops out; the rest of the query still applies.
        #expect(try match("xyz:1 t:instant") == ["Lightning Bolt", "Counterspell"])
    }

    @Test(arguments: ["t:creature", "c:rg mv<=3", "(a or b) -c", "r>=rare s:lea", "pow>tou", "!\"x\"", "m:{2}{R}", "year<=1995", "usd>=100"])
    func compiledSQLAlwaysPrepares(_ raw: String) throws {
        let q = QueryCompiler.compile(raw)
        let st = try fx.db.prepare(q.sql)
        st.bind(q.binds)
        _ = st.step()
    }
}
