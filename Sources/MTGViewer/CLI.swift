import Foundation

/// Developer entry points: `MTGViewer --import`, `--bench`. Returns true when handled.
enum CLI {
    static func handle(_ args: [String]) -> Bool {
        if args.contains("--import") { runImport(force: true); return true }
        if args.contains("--bench") { bench(); return true }
        return false
    }

    static func runImport(force: Bool) {
        let imp = Importer(dataDir: Importer.defaultDataDir())
        let sem = DispatchSemaphore(value: 0)
        Task {
            let t0 = Date()
            var lastPrint = Date.distantPast
            do {
                let url = try await imp.run(force: force, installedBulkDate: nil, estimatedLines: 112_000) { p in
                    if Date().timeIntervalSince(lastPrint) > 1 {
                        lastPrint = Date()
                        print(String(format: "%3.0f%%  %@", p.fraction * 100, p.detail))
                    }
                }
                print("Installed \(url?.path ?? "-") in \(String(format: "%.1f", Date().timeIntervalSince(t0))) s")
            } catch {
                print("Import failed: \(error.localizedDescription)")
            }
            sem.signal()
        }
        sem.wait()
    }

    static func bench() {
        let path = Importer(dataDir: Importer.defaultDataDir()).dbURL.path
        guard let store = try? CardStore(path: path) else { print("No database at \(path)"); return }
        print("cards: \(store.cardCount), printings: \(store.meta("printings") ?? "?"), bulk: \(store.meta("bulk_updated_at") ?? "?")")
        let queries = [
            "", "j", "ja", "jace", "lightning bolt", "bolt", "the", "e", "t:creature", "t:creature mv<=3",
            "c:b", "c:rg t:creature", "id<=wu", "f:modern", "f:modern o:draw", "o:draw", "o:\"draw a card\"",
            "o:destroy t:instant c:r", "mv>=7", "r:mythic s:mh3", "t:legendary t:creature id:bg",
            "(c:r or c:g) t:creature pow>=5", "-t:creature t:artifact", "kw:flying kw:lifelink", "m:rr",
            "is:mdfc", "year<=1995", "usd>=100", "!\"Lightning Bolt\"", "pow>tou", "order:cmc", "xyz:1",
            "t:land produces:g", "banned:modern", "is:commander id:g", "s:lea r:rare",
        ]
        print(String(format: "%-38@ %8@ %9@ %9@", "query" as NSString, "results" as NSString, "median" as NSString, "max" as NSString))
        var worst = 0.0
        for q in queries {
            var times: [Double] = []
            var count = 0
            var warn = ""
            for _ in 0..<15 {
                let out = store.search(q)
                times.append(out.ms); count = out.ids.count
                warn = out.warnings.joined(separator: "; ")
            }
            times.sort()
            worst = max(worst, times[times.count / 2])
            print(String(format: "%-38@ %8d %7.2fms %7.2fms %@", q as NSString, count, times[times.count / 2], times.last!, warn as NSString))
        }
        print(String(format: "worst median: %.2f ms", worst))
        // Row + detail lookup latency
        let ids = store.search("t:creature").ids
        let t0 = DispatchTime.now().uptimeNanoseconds
        for id in ids.prefix(2000) { _ = store.row(id: id) }
        let rowUS = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1000 / Double(min(2000, ids.count))
        let t1 = DispatchTime.now().uptimeNanoseconds
        for id in ids.prefix(500) { _ = store.full(id: id) }
        let fullUS = Double(DispatchTime.now().uptimeNanoseconds - t1) / 1000 / Double(min(500, ids.count))
        print(String(format: "row lookup: %.1f µs, full card lookup: %.1f µs", rowUS, fullUS))
    }
}
