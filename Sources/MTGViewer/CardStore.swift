import Foundation

struct SearchOutput {
    var ids: [Int64]
    var warnings: [String]
    var ms: Double
}

/// Read-only access to the card database.
/// `search` must be called from a single queue; `row` / `full` from the main thread.
final class CardStore {
    static let schemaVersion = 1

    let path: String
    private let searchConn: SQLiteConn
    private let lookupConn: SQLiteConn
    private let rowStmt: Statement
    private let fullStmt: Statement
    private let printingsStmt: Statement

    init(path: String) throws {
        self.path = path
        searchConn = try SQLiteConn(path: path, readOnly: true)
        lookupConn = try SQLiteConn(path: path, readOnly: true)
        for c in [searchConn, lookupConn] {
            try c.exec("PRAGMA mmap_size = 536870912; PRAGMA cache_size = -65536; PRAGMA temp_store = MEMORY;")
        }
        guard searchConn.scalarText("SELECT value FROM meta WHERE key='schema'") == String(Self.schemaVersion) else {
            throw DBError(message: "Database schema is out of date")
        }
        rowStmt = try lookupConn.prepare(
            "SELECT id,name,mana_cost,type_line,set_code,rarity,scry_id,has_image,flags FROM cards WHERE id=?")
        fullStmt = try lookupConn.prepare(
            "SELECT c.oracle_id,c.legal,c.restricted,c.banned,c.edhrec,c.printing_id,d.json FROM cards c JOIN detail d ON d.card_id=c.id WHERE c.id=?")
        printingsStmt = try lookupConn.prepare(
            "SELECT id,scry_id,set_code,set_name,cn,rarity,released,usd,usd_foil,usd_etched,has_image FROM printings WHERE card_id=? ORDER BY released DESC, id")
    }

    /// Printing ids of every card that has artwork, most popular first (for cache warming).
    func imageIDs() -> [String] {
        guard let st = try? lookupConn.prepare("SELECT scry_id FROM cards WHERE has_image=1 ORDER BY pop, id") else { return [] }
        var out: [String] = []
        out.reserveCapacity(36_000)
        while st.step() { out.append(st.text(0)) }
        return out
    }

    func meta(_ key: String) -> String? {
        lookupConn.scalarText("SELECT value FROM meta WHERE key='\(key)'")
    }

    var cardCount: Int { Int(meta("cards") ?? "") ?? 0 }

    func search(_ query: String) -> SearchOutput {
        let t0 = DispatchTime.now().uptimeNanoseconds
        let compiled = QueryCompiler.compile(query)
        var ids: [Int64] = []
        var warnings = compiled.warnings
        do {
            let st = try searchConn.prepare(compiled.sql)
            st.bind(compiled.binds)
            while st.step() { ids.append(st.int64(0)) }
        } catch {
            warnings.append("Query error: \(error.localizedDescription)")
        }
        let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
        return SearchOutput(ids: ids, warnings: warnings, ms: ms)
    }

    func row(id: Int64) -> CardRow? {
        rowStmt.reset()
        rowStmt.bind(1, .int(id))
        guard rowStmt.step() else { return nil }
        let flags = rowStmt.int(8)
        return CardRow(
            id: rowStmt.int64(0), name: rowStmt.text(1), manaCost: rowStmt.text(2),
            typeLine: rowStmt.text(3), setCode: rowStmt.text(4), rarity: rowStmt.int(5),
            scryID: rowStmt.text(6), hasImage: rowStmt.int(7) != 0,
            hasBack: flags & (1 << CardFlag.dfc.rawValue) != 0)
    }

    func full(id: Int64) -> CardFull? {
        guard let row = row(id: id) else { return nil }
        fullStmt.reset()
        fullStmt.bind(1, .int(id))
        guard fullStmt.step() else { return nil }
        let repID = fullStmt.int64(5)
        let json = fullStmt.text(6)
        guard let blob = try? JSONDecoder().decode(DetailBlob.self, from: Data(json.utf8)) else { return nil }
        let oracleID = fullStmt.text(0)
        let legal = fullStmt.int(1), restricted = fullStmt.int(2), banned = fullStmt.int(3)
        let edh: Int? = fullStmt.int(4) > 0 ? fullStmt.int(4) : nil

        var printings: [Printing] = []
        var repIndex = 0
        printingsStmt.reset()
        printingsStmt.bind(1, .int(id))
        while printingsStmt.step() {
            let p = Printing(
                id: printingsStmt.int64(0), scryID: printingsStmt.text(1), setCode: printingsStmt.text(2),
                setName: printingsStmt.text(3), collector: printingsStmt.text(4), rarity: printingsStmt.int(5),
                released: printingsStmt.text(6), usd: printingsStmt.optDouble(7), usdFoil: printingsStmt.optDouble(8),
                usdEtched: printingsStmt.optDouble(9), hasImage: printingsStmt.int(10) != 0)
            if p.id == repID { repIndex = printings.count }
            printings.append(p)
        }
        return CardFull(
            row: row, oracleID: oracleID, layout: blob.layout, faces: blob.faces, keywords: blob.keywords,
            legal: legal, restricted: restricted, banned: banned, edhrec: edh,
            printings: printings, repIndex: repIndex)
    }
}
