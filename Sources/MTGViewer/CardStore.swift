import Foundation

struct SearchOutput {
    var ids: [Int64]
    var warnings: [String]
    var ms: Double
}

/// Read-only access to the card database.
/// `search` must be called from a single queue; `row` / `full` from the main thread.
final class CardStore {
    static let schemaVersion = 2

    let path: String
    private let searchConn: SQLiteConn
    private let lookupConn: SQLiteConn
    /// Used only by the preferences queue (overlay computation, set catalog).
    private let adminConn: SQLiteConn
    private let overlayLock = NSLock()
    private var _overlay: Overlay?
    private let rowStmt: Statement
    private let fullStmt: Statement
    private let printingsStmt: Statement

    init(path: String) throws {
        self.path = path
        searchConn = try SQLiteConn(path: path, readOnly: true)
        lookupConn = try SQLiteConn(path: path, readOnly: true)
        adminConn = try SQLiteConn(path: path, readOnly: true)
        for c in [searchConn, lookupConn, adminConn] {
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
            "SELECT id,scry_id,set_code,set_name,cn,rarity,released,usd,usd_foil,usd_etched,has_image,set_type,attrs FROM printings WHERE card_id=? ORDER BY released DESC, id")
    }

    var overlay: Overlay? {
        overlayLock.lock(); defer { overlayLock.unlock() }
        return _overlay
    }

    func setOverlay(_ o: Overlay?) {
        overlayLock.lock(); _overlay = o; overlayLock.unlock()
    }

    /// Printing ids of every visible card that has artwork, most popular first (for cache warming).
    func imageIDs() -> [String] {
        guard let st = try? lookupConn.prepare("SELECT id,scry_id,has_image FROM cards ORDER BY pop, id") else { return [] }
        let o = overlay
        var out: [String] = []
        out.reserveCapacity(36_000)
        while st.step() {
            if let o {
                let id = st.int64(0)
                if o.hidden.contains(id) { continue }
                if let r = o.reps[id] {
                    if r.hasImage { out.append(r.scryID) }
                    continue
                }
            }
            if st.int(2) != 0 { out.append(st.text(1)) }
        }
        return out
    }

    // MARK: Preferences (call from a single background queue)

    /// Applies the user's preferences to every printing. Nil when they match what the database already encodes.
    func computeOverlay(_ prefs: Preferences) -> Overlay? {
        if prefs.isStandard { return nil }
        guard let st = try? adminConn.prepare(
            "SELECT card_id,id,scry_id,set_code,rarity,released,has_image,set_type,attrs FROM printings ORDER BY card_id, id")
        else { return nil }
        var reps = [Int64: RepInfo](minimumCapacity: 40_000)
        var hidden = Set<Int64>()
        var current: Int64 = -1
        var best: (key: (Int, String), info: RepInfo)?

        func flush() {
            guard current >= 0 else { return }
            if let best { reps[current] = best.info } else { hidden.insert(current) }
        }
        while st.step() {
            let card = st.int64(0)
            if card != current { flush(); current = card; best = nil }
            let meta = PrintingMeta(
                setCode: st.text(3), setType: st.text(7), released: st.text(5), attrs: st.int(8), hasImage: st.int(6) != 0)
            if Representative.excluded(meta, prefs.exclude) { continue }
            let key = Representative.key(meta, prefs.art)
            if best == nil || key > best!.key {
                best = (key, RepInfo(printingID: st.int64(1), scryID: st.text(2), setCode: meta.setCode,
                                     rarity: st.int(4), hasImage: meta.hasImage))
            }
        }
        flush()
        return Overlay(reps: reps, hidden: hidden, exclude: prefs.exclude)
    }

    func setCatalog() -> [SetInfo] {
        guard let st = try? adminConn.prepare("""
            SELECT set_code, set_name, set_type, MIN(released), COUNT(*) FROM printings
            GROUP BY set_code ORDER BY MIN(released) DESC, set_name
            """) else { return [] }
        var out: [SetInfo] = []
        while st.step() {
            out.append(SetInfo(code: st.text(0), name: st.text(1), type: st.text(2), released: st.text(3), count: st.int(4)))
        }
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
        if let hidden = overlay?.hidden, !hidden.isEmpty { ids.removeAll { hidden.contains($0) } }
        let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
        return SearchOutput(ids: ids, warnings: warnings, ms: ms)
    }

    func row(id: Int64) -> CardRow? {
        rowStmt.reset()
        rowStmt.bind(1, .int(id))
        guard rowStmt.step() else { return nil }
        let flags = rowStmt.int(8)
        let rep = overlay?.reps[id]
        return CardRow(
            id: rowStmt.int64(0), name: rowStmt.text(1), manaCost: rowStmt.text(2),
            typeLine: rowStmt.text(3), setCode: rep?.setCode ?? rowStmt.text(4), rarity: rep?.rarity ?? rowStmt.int(5),
            scryID: rep?.scryID ?? rowStmt.text(6), hasImage: rep?.hasImage ?? (rowStmt.int(7) != 0),
            hasBack: flags & (1 << CardFlag.dfc.rawValue) != 0)
    }

    func full(id: Int64) -> CardFull? {
        guard let row = row(id: id) else { return nil }
        fullStmt.reset()
        fullStmt.bind(1, .int(id))
        guard fullStmt.step() else { return nil }
        let o = overlay
        let repID = o?.reps[id]?.printingID ?? fullStmt.int64(5)
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
            if let ex = o?.exclude, !ex.isEmpty,
               Representative.excluded(PrintingMeta(setCode: p.setCode, setType: printingsStmt.text(11),
                                                    released: p.released, attrs: printingsStmt.int(12),
                                                    hasImage: p.hasImage), ex) { continue }
            if p.id == repID { repIndex = printings.count }
            printings.append(p)
        }
        return CardFull(
            row: row, oracleID: oracleID, layout: blob.layout, faces: blob.faces, keywords: blob.keywords,
            legal: legal, restricted: restricted, banned: banned, edhrec: edh,
            printings: printings, repIndex: repIndex)
    }
}
