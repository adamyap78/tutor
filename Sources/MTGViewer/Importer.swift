import Foundation

// Downloads Scryfall's "Default Cards" bulk file (every English printing, ~80 MB gzipped),
// folds it into a compact SQLite database (one row per Oracle card + one row per printing),
// validates it, and atomically swaps it into place. The existing database is never touched
// until the new one has been fully built and verified.

struct ImportProgress {
    enum Phase { case checking, downloading, parsing, building, finishing }
    var phase: Phase
    var fraction: Double
    var detail: String
}

struct ImportError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct BulkInfo {
    var updatedAt: String
    var url: URL
    var size: Int64
}

final class Importer {
    static let userAgent = "MTGViewer/1.0"
    nonisolated(unsafe) private static var savedResumeData: Data?

    let dataDir: URL
    var dbURL: URL { dataDir.appendingPathComponent("cards.sqlite") }

    init(dataDir: URL) { self.dataDir = dataDir }

    static func defaultDataDir() -> URL {
        if let override = ProcessInfo.processInfo.environment["MTG_DATA_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MTGViewer", isDirectory: true)
    }

    // MARK: Entry point

    /// Returns the installed database URL, or nil when `installedBulkDate` is already current.
    func run(force: Bool, installedBulkDate: String?, estimatedLines: Int,
             progress: @escaping (ImportProgress) -> Void) async throws -> URL? {
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        progress(.init(phase: .checking, fraction: 0, detail: "Checking for the latest card data…"))
        let info = try await Self.fetchBulkInfo()
        if !force, let installed = installedBulkDate, installed == info.updatedAt { return nil }

        let gz = dataDir.appendingPathComponent("default-cards.jsonl.gz.download")
        try? FileManager.default.removeItem(at: gz)
        try await Self.download(info.url, to: gz, expected: info.size) { got, total in
            let t = total > 0 ? total : info.size
            let f = t > 0 ? Double(got) / Double(t) : 0
            let mb = { (b: Int64) in String(format: "%.0f", Double(b) / 1_048_576) }
            progress(.init(phase: .downloading, fraction: f, detail: "Downloading card data — \(mb(got)) of \(mb(t)) MB"))
        }
        defer { try? FileManager.default.removeItem(at: gz) }

        let tmp = dataDir.appendingPathComponent("cards.sqlite.building")
        let dbURL = self.dbURL
        try await Task.detached(priority: .utility) {
            try Self.build(gz: gz, out: tmp, bulkDate: info.updatedAt, estimatedLines: estimatedLines, progress: progress)
        }.value

        progress(.init(phase: .finishing, fraction: 1, detail: "Installing…"))
        guard rename(tmp.path, dbURL.path) == 0 else {
            try? FileManager.default.removeItem(at: tmp)
            throw ImportError(message: "Could not install the new database (\(String(cString: strerror(errno)))).")
        }
        return dbURL
    }

    // MARK: Network

    private static func request(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url)
        r.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        r.setValue("application/json;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        r.timeoutInterval = 30
        return r
    }

    static func fetchBulkInfo() async throws -> BulkInfo {
        let (data, resp) = try await URLSession.shared.data(for: request(URL(string: "https://api.scryfall.com/bulk-data/default-cards")!))
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let updated = o["updated_at"] as? String,
              let uri = (o["jsonl_download_uri"] as? String) ?? (o["download_uri"] as? String),
              let url = URL(string: uri)
        else { throw ImportError(message: "Scryfall returned an unexpected response.") }
        let size = (o["compressed_size"] as? NSNumber)?.int64Value ?? (o["size"] as? NSNumber)?.int64Value ?? 0
        return BulkInfo(updatedAt: updated, url: url, size: size)
    }

    static func download(_ url: URL, to dest: URL, expected: Int64, progress: @escaping (Int64, Int64) -> Void) async throws {
        let d = FileDownloader(dest: dest, progress: progress)
        let resume = savedResumeData
        savedResumeData = nil
        do {
            try await d.start(request: request(url), resumeData: resume)
        } catch {
            savedResumeData = d.resumeData
            throw error
        }
    }

    // MARK: Build

    private struct PrintingRec {
        var scryID, setCode, setName, cn: String
        var rarity: Int
        var released: String
        var usd, usdFoil, usdEtched: Double?
        var hasImage: Bool
        var setType: String
        var attrs: Int
    }

    private struct Agg {
        var rep: Parsed
        var repKey: (Int, String)
        var printings: [PrintingRec] = []
        var rarities = 0
        var yearMin = 9999, yearMax = 0
        var usdMin: Double?, usdMax: Double?
    }

    fileprivate struct Parsed {
        var scryID = "", oracleID = "", name = "", layout = "", manaCost = "", typeLine = "", oracleText = ""
        var cmc = 0.0
        var colors = 0, ci = 0, produced = 0
        var keywords: [String] = []
        var pow: Double?, tou: Double?, loy: Double?
        var legal = 0, restricted = 0, banned = 0
        var edhrec: Int?
        var setCode = "", setName = "", cn = "", released = "", setType = ""
        var attrs = 0
        var rarity = 0
        var hasImage = false, hasBack = false
        var reserved = false, gameChanger = false, funny = false
        var usd: Double?, usdFoil: Double?, usdEtched: Double?
        var faces: [Face] = []
        var repKey: (Int, String) = (0, "")
    }

    private static func build(gz: URL, out: URL, bulkDate: String, estimatedLines: Int,
                              progress: @escaping (ImportProgress) -> Void) throws {
        try? FileManager.default.removeItem(at: out)

        // 1. Stream-decompress and parse in parallel batches.
        var aggs = [String: Agg](minimumCapacity: 40_000)
        var lines = 0
        var batch: [Data] = []
        batch.reserveCapacity(4000)

        func flush() {
            guard !batch.isEmpty else { return }
            let n = batch.count
            let slices = min(8, n)
            var parts = [[Parsed]](repeating: [], count: slices)
            let lock = NSLock()
            DispatchQueue.concurrentPerform(iterations: slices) { s in
                var local: [Parsed] = []
                let lo = n * s / slices, hi = n * (s + 1) / slices
                for k in lo..<hi { if let p = parse(batch[k]) { local.append(p) } }
                lock.lock(); parts[s] = local; lock.unlock()
            }
            for part in parts { for p in part { merge(&aggs, p) } }
            lines += n
            batch.removeAll(keepingCapacity: true)
            let f = min(0.97, Double(lines) / Double(max(estimatedLines, 1)))
            progress(.init(phase: .parsing, fraction: f, detail: "Reading cards — \(lines.formatted()) printings"))
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
        proc.arguments = ["-c", gz.path]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        try proc.run()
        let fh = pipe.fileHandleForReading
        var carry = Data()
        while let chunk = try fh.read(upToCount: 1 << 22), !chunk.isEmpty {
            carry.append(chunk)
            var start = carry.startIndex
            while let nl = carry[start...].firstIndex(of: 10) {
                if nl > start { batch.append(carry[start..<nl]) }
                start = carry.index(after: nl)
                if batch.count >= 4000 { flush() }
            }
            carry = Data(carry[start...])
        }
        if !carry.isEmpty { batch.append(carry) }
        flush()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { throw ImportError(message: "The downloaded file was corrupt. Please try again.") }
        guard aggs.count > 20_000 else { throw ImportError(message: "The card data looked incomplete (\(aggs.count) cards).") }

        // 2. Write the database.
        progress(.init(phase: .building, fraction: 0, detail: "Building search index…"))
        let db = try SQLiteConn(path: out.path, readOnly: false)
        try db.exec("""
        PRAGMA journal_mode=OFF; PRAGMA synchronous=OFF; PRAGMA locking_mode=EXCLUSIVE;
        CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
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
        CREATE TABLE detail(card_id INTEGER PRIMARY KEY, json TEXT NOT NULL);
        BEGIN;
        """)

        let insCard = try db.prepare("INSERT INTO cards VALUES(\(Array(repeating: "?", count: 33).joined(separator: ",")))")
        let insPrinting = try db.prepare("INSERT INTO printings VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)")
        let insDetail = try db.prepare("INSERT INTO detail VALUES(?,?)")
        let encoder = JSONEncoder()

        var sorted = Array(aggs.values)
        aggs.removeAll()
        let keyed = sorted.map { ($0, TextNorm.normName($0.rep.name)) }
        sorted = keyed.sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.rep.name < $1.0.rep.name }.map { $0.0 }

        var printingID: Int64 = 0
        var printingCount = 0
        for (idx, var a) in sorted.enumerated() {
            let cardID = Int64(idx + 1)
            let r = a.rep
            a.printings.sort { $0.released != $1.released ? $0.released > $1.released : $0.scryID < $1.scryID }
            var repPrinting: Int64 = 0
            for p in a.printings {
                printingID += 1
                if p.scryID == r.scryID { repPrinting = printingID }
                insPrinting.reset()
                insPrinting.bind([
                    .int(printingID), .int(cardID), .text(p.scryID), .text(p.setCode), .text(p.setName), .text(p.cn),
                    .int(Int64(p.rarity)), .text(p.released), opt(p.usd), opt(p.usdFoil), opt(p.usdEtched),
                    .int(p.hasImage ? 1 : 0), .text(p.setType), .int(Int64(p.attrs)),
                ])
                try insPrinting.run()
            }
            printingCount += a.printings.count

            let typeLC = r.typeLine.lowercased()
            let flags = computeFlags(r, typeLC: typeLC, printings: a.printings.count)
            insCard.reset()
            insCard.bind([
                .int(cardID), .text(r.oracleID), .text(r.name), .text(TextNorm.normName(r.name)),
                .text(r.manaCost), .double(r.cmc), .text(r.typeLine), .text(typeLC),
                .text(r.oracleText.lowercased()), .text("|" + r.keywords.map { $0.lowercased() }.joined(separator: "|") + "|"),
                .int(Int64(r.colors)), .int(Int64(r.ci)), .int(Int64(r.produced)),
                opt(r.pow), opt(r.tou), opt(r.loy),
                .int(Int64(r.legal)), .int(Int64(r.restricted)), .int(Int64(r.banned)),
                .int(Int64(a.rarities)), .text(r.layout), .int(Int64(flags)),
                .int(Int64(a.yearMin)), .int(Int64(a.yearMax)), opt(a.usdMin), opt(a.usdMax),
                r.edhrec.map { .int(Int64($0)) } ?? .null, .int(Int64(r.edhrec ?? 1_000_000)),
                .int(repPrinting), .text(r.scryID), .text(r.setCode), .int(Int64(r.rarity)),
                .int(r.hasImage ? 1 : 0),
            ])
            try insCard.run()

            let blob = DetailBlob(layout: r.layout, faces: r.faces, keywords: r.keywords)
            insDetail.reset()
            insDetail.bind([.int(cardID), .text(String(decoding: try encoder.encode(blob), as: UTF8.self))])
            try insDetail.run()

            if idx % 1500 == 0 {
                progress(.init(phase: .building, fraction: Double(idx) / Double(sorted.count), detail: "Building search index…"))
            }
        }

        let insMeta = try db.prepare("INSERT INTO meta VALUES(?,?)")
        for (k, v) in [
            ("schema", String(CardStore.schemaVersion)), ("bulk_updated_at", bulkDate),
            ("imported_at", ISO8601DateFormatter().string(from: Date())),
            ("cards", String(sorted.count)), ("printings", String(printingCount)),
        ] {
            insMeta.reset()
            insMeta.bind([.text(k), .text(v)])
            try insMeta.run()
        }
        try db.exec("""
        COMMIT;
        CREATE INDEX printings_card ON printings(card_id);
        CREATE INDEX printings_set ON printings(set_code, card_id);
        CREATE INDEX printings_cn ON printings(cn);
        """)
        progress(.init(phase: .building, fraction: 1, detail: "Verifying…"))
        guard db.scalarText("PRAGMA quick_check") == "ok" else {
            throw ImportError(message: "The new database failed verification; keeping the existing one.")
        }
        try db.exec("PRAGMA locking_mode=NORMAL; SELECT count(*) FROM meta;")
    }

    private static func opt(_ d: Double?) -> Bind { d.map { .double($0) } ?? .null }

    private static func computeFlags(_ r: Parsed, typeLC: String, printings: Int) -> Int {
        var f = 0
        func set(_ flag: CardFlag, _ on: Bool) { if on { f |= 1 << flag.rawValue } }
        let front = typeLC.components(separatedBy: " // ").first ?? typeLC
        let legendary = typeLC.contains("legendary")
        set(.dfc, r.hasBack)
        set(.mdfc, r.layout == "modal_dfc")
        set(.transform, r.layout == "transform")
        set(.split, r.layout == "split")
        set(.flip, r.layout == "flip")
        set(.adventure, r.layout == "adventure")
        set(.meld, r.layout == "meld")
        set(.leveler, r.layout == "leveler")
        set(.reversible, r.layout == "reversible_card")
        set(.saga, typeLC.contains("saga"))
        set(.classCard, typeLC.contains(" class"))
        set(.battle, typeLC.contains("battle"))
        set(.reserved, r.reserved)
        set(.gamechanger, r.gameChanger)
        set(.funny, r.funny)
        set(.legendary, legendary)
        set(.creature, typeLC.contains("creature"))
        set(.planeswalker, typeLC.contains("planeswalker"))
        set(.commander, (legendary && front.contains("creature")) || r.oracleText.lowercased().contains("can be your commander"))
        let spell = front.contains("instant") || front.contains("sorcery")
        set(.spell, spell)
        set(.permanent, !spell && !front.contains("plane ") && !front.contains("scheme") && !front.contains("vanguard"))
        set(.vanilla, front.contains("creature") && r.oracleText.isEmpty)
        set(.historic, legendary || typeLC.contains("artifact") || typeLC.contains("saga"))
        set(.reprint, printings > 1)
        return f
    }

    private static func merge(_ aggs: inout [String: Agg], _ p: Parsed) {
        let rec = PrintingRec(
            scryID: p.scryID, setCode: p.setCode, setName: p.setName, cn: p.cn, rarity: p.rarity,
            released: p.released, usd: p.usd, usdFoil: p.usdFoil, usdEtched: p.usdEtched, hasImage: p.hasImage,
            setType: p.setType, attrs: p.attrs)
        let year = Int(p.released.prefix(4)) ?? 0
        if var a = aggs[p.oracleID] {
            a.printings.append(rec)
            a.rarities |= 1 << p.rarity
            if year > 0 { a.yearMin = min(a.yearMin, year); a.yearMax = max(a.yearMax, year) }
            for price in [p.usd, p.usdFoil, p.usdEtched].compactMap({ $0 }) {
                a.usdMin = min(a.usdMin ?? price, price)
                a.usdMax = max(a.usdMax ?? price, price)
            }
            if (p.repKey.0, p.repKey.1) > (a.repKey.0, a.repKey.1) { a.rep = p; a.repKey = p.repKey }
            aggs[p.oracleID] = a
        } else {
            var a = Agg(rep: p, repKey: p.repKey)
            a.printings = [rec]
            a.rarities = 1 << p.rarity
            if year > 0 { a.yearMin = year; a.yearMax = year }
            for price in [p.usd, p.usdFoil, p.usdEtched].compactMap({ $0 }) {
                a.usdMin = min(a.usdMin ?? price, price)
                a.usdMax = max(a.usdMax ?? price, price)
            }
            aggs[p.oracleID] = a
        }
    }

    // MARK: JSON parsing

    private static let skipLayouts: Set<String> = ["token", "double_faced_token", "emblem", "art_series"]
    private static let rarityIndex: [String: Int] = ["common": 0, "uncommon": 1, "rare": 2, "mythic": 3, "special": 4, "bonus": 5]

    private static func mask(_ arr: Any?, letters: String = "WUBRG") -> Int {
        guard let a = arr as? [String] else { return 0 }
        var m = 0
        for s in a { if let i = letters.firstIndex(of: Character(s.uppercased())) { m |= 1 << letters.distance(from: letters.startIndex, to: i) } }
        return m
    }

    private static func number(_ s: String?) -> Double? {
        guard let s else { return nil }
        if let d = Double(s) { return d }
        return s.contains("*") ? 0 : nil
    }

    private static func parse(_ data: Data) -> Parsed? {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let layout = o["layout"] as? String ?? "normal"
        if skipLayouts.contains(layout) { return nil }
        guard let id = o["id"] as? String else { return nil }
        let faceObjs = (o["card_faces"] as? [[String: Any]]) ?? []
        guard let oracleID = (o["oracle_id"] as? String) ?? (faceObjs.first?["oracle_id"] as? String) else { return nil }

        func face(_ f: [String: Any]) -> Face {
            Face(name: f["name"] as? String ?? "", manaCost: f["mana_cost"] as? String ?? "",
                 typeLine: f["type_line"] as? String ?? "", oracleText: f["oracle_text"] as? String ?? "",
                 power: f["power"] as? String, toughness: f["toughness"] as? String,
                 loyalty: f["loyalty"] as? String, defense: f["defense"] as? String,
                 flavor: f["flavor_text"] as? String)
        }

        var p = Parsed()
        p.scryID = id
        p.oracleID = oracleID
        p.layout = layout
        p.name = o["name"] as? String ?? ""
        p.faces = faceObjs.isEmpty ? [face(o)] : faceObjs.map(face)
        p.hasBack = faceObjs.count > 1 && faceObjs[0]["image_uris"] != nil
        p.manaCost = (o["mana_cost"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? p.faces.first?.manaCost ?? ""
        p.typeLine = (o["type_line"] as? String) ?? p.faces.map(\.typeLine).joined(separator: " // ")
        p.oracleText = (o["oracle_text"] as? String) ?? p.faces.map(\.oracleText).joined(separator: "\n//\n")
        p.cmc = (o["cmc"] as? NSNumber)?.doubleValue ?? 0
        p.colors = mask(o["colors"] ?? faceObjs.first?["colors"])
        p.ci = mask(o["color_identity"])
        p.produced = mask(o["produced_mana"], letters: "WUBRGC")
        p.keywords = (o["keywords"] as? [String]) ?? []
        let f0 = p.faces[0]
        p.pow = number(f0.power); p.tou = number(f0.toughness); p.loy = number(f0.loyalty ?? f0.defense)
        p.edhrec = (o["edhrec_rank"] as? NSNumber)?.intValue
        p.reserved = o["reserved"] as? Bool ?? false
        p.gameChanger = o["game_changer"] as? Bool ?? false

        if let leg = o["legalities"] as? [String: String] {
            for (k, v) in leg {
                guard let bit = Formats.keys.firstIndex(of: k) else { continue }
                switch v {
                case "legal": p.legal |= 1 << bit
                case "restricted": p.legal |= 1 << bit; p.restricted |= 1 << bit
                case "banned": p.banned |= 1 << bit
                default: break
                }
            }
        }

        p.setCode = o["set"] as? String ?? ""
        p.setName = o["set_name"] as? String ?? ""
        p.cn = (o["collector_number"] as? String ?? "").lowercased()
        p.released = o["released_at"] as? String ?? ""
        p.rarity = rarityIndex[o["rarity"] as? String ?? ""] ?? 0
        let status = o["image_status"] as? String ?? "missing"
        p.hasImage = status == "highres_scan" || status == "lowres"
        let setType = o["set_type"] as? String ?? ""
        p.funny = setType == "funny"

        if let prices = o["prices"] as? [String: Any] {
            func price(_ k: String) -> Double? { (prices[k] as? String).flatMap(Double.init) }
            p.usd = price("usd"); p.usdFoil = price("usd_foil"); p.usdEtched = price("usd_etched")
        }

        // Which printing best represents the card by default. The same ranking is re-run at runtime
        // from the stored per-printing attributes when the user changes their art preferences.
        let games = (o["games"] as? [String]) ?? []
        let effects = (o["frame_effects"] as? [String]) ?? []
        let promoTypes = (o["promo_types"] as? [String]) ?? []
        let plain = effects.isEmpty && promoTypes.isEmpty && !(o["full_art"] as? Bool ?? false)
            && (o["border_color"] as? String) != "borderless"
        var attrs = 0
        if (o["lang"] as? String) == "en" { attrs |= PrintingAttr.english }
        if o["digital"] as? Bool ?? false { attrs |= PrintingAttr.digital }
        if o["promo"] as? Bool ?? false { attrs |= PrintingAttr.promo }
        if o["oversized"] as? Bool ?? false { attrs |= PrintingAttr.oversized }
        if plain { attrs |= PrintingAttr.plain }
        if games.contains("paper") { attrs |= PrintingAttr.paper }
        if games.contains("mtgo") { attrs |= PrintingAttr.mtgo }
        if games.contains("arena") { attrs |= PrintingAttr.arena }
        p.setType = setType
        p.attrs = attrs
        p.repKey = Representative.key(
            PrintingMeta(setCode: p.setCode, setType: setType, released: p.released, attrs: attrs, hasImage: p.hasImage),
            ArtPreferences())
        return p
    }
}

// MARK: - Download delegate

final class FileDownloader: NSObject, URLSessionDownloadDelegate {
    private let dest: URL
    private let progress: (Int64, Int64) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private var moveError: Error?
    private var session: URLSession?
    private(set) var resumeData: Data?

    init(dest: URL, progress: @escaping (Int64, Int64) -> Void) {
        self.dest = dest
        self.progress = progress
    }

    func start(request: URLRequest, resumeData: Data?) async throws {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        cfg.waitsForConnectivity = false
        let s = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
        session = s
        defer { s.finishTasksAndInvalidate() }
        let task = resumeData.map { s.downloadTask(withResumeData: $0) } ?? s.downloadTask(with: request)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                continuation = c
                task.resume()
            }
        } onCancel: { task.cancel() }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
            moveError = ImportError(message: "Scryfall responded with HTTP \(http.statusCode).")
            return
        }
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: location, to: dest)
        } catch { moveError = error }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let c = continuation
        continuation = nil
        if let error {
            resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
            c?.resume(throwing: error)
        } else if let moveError {
            c?.resume(throwing: moveError)
        } else {
            c?.resume()
        }
    }
}
