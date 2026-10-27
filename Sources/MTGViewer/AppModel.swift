import AppKit
import Observation

enum LayoutMode: String { case list, grid }
enum ViewMode { case browse, detail }
enum DataState { case loading, needsData, ready }
enum Arrow { case up, down, left, right }

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var v = 0
    func next() -> Int { lock.lock(); defer { lock.unlock() }; v += 1; return v }
    var value: Int { lock.lock(); defer { lock.unlock() }; return v }
}

private final class Throttle: @unchecked Sendable {
    private let lock = NSLock()
    private var last = Date.distantPast
    func ready(force: Bool) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        if force || now.timeIntervalSince(last) > 0.08 { last = now; return true }
        return false
    }
}

@MainActor @Observable
final class AppModel {
    // MARK: Observable state
    private(set) var query = ""
    private(set) var ids: [Int64] = []
    private(set) var warnings: [String] = []
    private(set) var searchMS = 0.0
    private(set) var selection = 0
    private(set) var resultsVersion = 0
    private(set) var mode: ViewMode = .browse
    private(set) var face = 0
    private(set) var printingIndex: Int?
    var gridColumns = 4
    private(set) var showText = UserDefaults.standard.bool(forKey: "showText")
    private(set) var layout: LayoutMode = LayoutMode(rawValue: UserDefaults.standard.string(forKey: "layout") ?? "") ?? .list

    private(set) var dataState: DataState = .loading
    private(set) var progress: ImportProgress?
    private(set) var importError: String?
    private(set) var updateStatus: String?
    private(set) var bulkDate: Date?
    private(set) var toast: String?
    private(set) var cardTotal = 0
    private(set) var warmStatus: String?
    private(set) var warmEnabled = UserDefaults.standard.object(forKey: "warmCache") as? Bool ?? true
    private(set) var cacheLimitMB: Int = {
        let v = UserDefaults.standard.integer(forKey: "cacheLimitMB")
        return v > 0 ? v : 2048
    }()

    // MARK: Internals
    @ObservationIgnored private var store: CardStore?
    @ObservationIgnored private var importer = Importer(dataDir: Importer.defaultDataDir())
    @ObservationIgnored private var rowCache: [Int64: CardRow] = [:]
    @ObservationIgnored private var fullCache: CardFull?
    @ObservationIgnored weak var searchField: NSTextField?
    @ObservationIgnored private let searchQueue = DispatchQueue(label: "mtg.search", qos: .userInteractive)
    @ObservationIgnored private let gen = Counter()
    @ObservationIgnored private var prefetchTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var importing = false
    @ObservationIgnored private var warmTask: Task<Void, Never>?
    @ObservationIgnored private var lastDelta = 1

    // MARK: Startup

    func start() {
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.focusSearch() }
        }
        ImageStore.shared.trimDisk()
        if let s = try? CardStore(path: importer.dbURL.path), s.cardCount > 0 {
            install(s)
            let last = UserDefaults.standard.double(forKey: "lastUpdateCheck")
            if Date().timeIntervalSince1970 - last > 24 * 3600 {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    self.refreshData(force: false, silent: true)
                }
            }
        } else {
            dataState = .needsData
            refreshData(force: true, silent: false)
        }
    }

    private func install(_ s: CardStore) {
        store = s
        cardTotal = s.cardCount
        if let d = s.meta("bulk_updated_at") {
            bulkDate = ISO8601DateFormatter.withFractional.date(from: d) ?? ISO8601DateFormatter().date(from: d)
        }
        rowCache.removeAll()
        fullCache = nil
        dataState = .ready
        runSearch()
        startWarming(after: 5)
    }

    // MARK: Data refresh

    func refreshData(force: Bool, silent: Bool) {
        guard !importing else { return }
        importing = true
        importError = nil
        if !silent { progress = ImportProgress(phase: .checking, fraction: 0, detail: "Preparing…") }
        if dataState == .ready { updateStatus = "Checking for updates…" }
        let throttle = Throttle()
        let installed = store?.meta("bulk_updated_at")
        let estimate = Int(store?.meta("printings") ?? "") ?? 120_000
        let firstRun = dataState != .ready

        Task { @MainActor in
            do {
                let url = try await importer.run(force: force, installedBulkDate: installed, estimatedLines: estimate) { p in
                    guard throttle.ready(force: p.fraction >= 1) else { return }
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            self.progress = p
                            if self.dataState == .ready {
                                self.updateStatus = p.phase == .downloading
                                    ? "Downloading update \(Int(p.fraction * 100))%"
                                    : "Updating card data \(Int(p.fraction * 100))%"
                            }
                        }
                    }
                }
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastUpdateCheck")
                if let url {
                    let s = try CardStore(path: url.path)
                    guard s.cardCount > 20_000 else { throw ImportError(message: "The updated database was incomplete.") }
                    install(s)
                    selectionReset()
                    flash(firstRun ? "Card database ready" : "Card data updated")
                } else if !silent {
                    flash("Card data is already up to date")
                }
                updateStatus = nil
                progress = nil
            } catch {
                if firstRun {
                    importError = error.localizedDescription
                } else {
                    flash("Update failed — still using your existing card data")
                }
                updateStatus = nil
                progress = nil
            }
            importing = false
        }
    }

    // MARK: Search

    func setQuery(_ q: String) {
        guard q != query else { return }
        query = q
        mode = .browse
        runSearch()
    }

    private func runSearch() {
        guard let store else { return }
        let q = query
        let g = gen.next()
        let counter = gen
        searchQueue.async {
            guard counter.value == g else { return }
            let out = store.search(q)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.apply(out, generation: g) }
            }
        }
    }

    private func apply(_ out: SearchOutput, generation: Int) {
        guard generation == gen.value else { return }
        ids = out.ids
        warnings = out.warnings
        searchMS = out.ms
        if rowCache.count > 4000 { rowCache.removeAll() }
        selection = 0
        lastDelta = 1
        resultsVersion += 1
        selectionReset()
        for i in 0..<min(24, ids.count) {
            if let r = row(at: i), r.hasImage { ImageStore.shared.prefetch(scryID: r.scryID, face: 0, size: .small) }
        }
    }

    private func selectionReset() {
        face = 0
        printingIndex = nil
        fullCache = nil
        schedulePrefetch()
    }

    // MARK: Accessors for views

    var count: Int { ids.count }

    func row(at i: Int) -> CardRow? {
        guard ids.indices.contains(i) else { return nil }
        let id = ids[i]
        if let r = rowCache[id] { return r }
        guard let r = store?.row(id: id) else { return nil }
        rowCache[id] = r
        return r
    }

    var current: CardRow? { row(at: selection) }

    var full: CardFull? {
        guard let cur = current else { return nil }
        if let f = fullCache, f.row.id == cur.id { return f }
        fullCache = store?.full(id: cur.id)
        return fullCache
    }

    var printing: Printing? {
        guard let f = full, !f.printings.isEmpty else { return nil }
        let i = min(max(printingIndex ?? f.repIndex, 0), f.printings.count - 1)
        return f.printings[i]
    }

    var selectedPrintingIndex: Int { printingIndex ?? full?.repIndex ?? 0 }

    var priceAge: String? {
        guard let d = bulkDate else { return nil }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }

    var handlesHorizontal: Bool { mode == .detail || layout == .grid }

    // MARK: Navigation

    func select(_ i: Int, fromUser: Bool = true) {
        guard !ids.isEmpty else { return }
        let c = min(max(i, 0), ids.count - 1)
        guard c != selection else { return }
        lastDelta = c > selection ? 1 : -1
        selection = c
        selectionReset()
    }

    func arrow(_ a: Arrow) {
        if mode == .detail {
            switch a {
            case .up: stepPrinting(-1)
            case .down: stepPrinting(1)
            case .left: select(selection - 1)
            case .right: select(selection + 1)
            }
            return
        }
        switch (layout, a) {
        case (.list, .up): select(selection - 1)
        case (.list, .down): select(selection + 1)
        case (.grid, .up): select(selection - gridColumns)
        case (.grid, .down): select(selection + gridColumns)
        case (.grid, .left): select(selection - 1)
        case (.grid, .right): select(selection + 1)
        default: break
        }
    }

    func page(_ dir: Int) {
        select(selection + dir * (layout == .grid ? gridColumns * 3 : 10))
    }

    func first() { select(0) }
    func last() { select(ids.count - 1) }

    func stepPrinting(_ d: Int) {
        guard let f = full, f.printings.count > 1 else { return }
        printingIndex = min(max(selectedPrintingIndex + d, 0), f.printings.count - 1)
        face = 0
    }

    func selectPrinting(_ i: Int) { printingIndex = i; face = 0 }

    func enter() {
        if mode == .detail { mode = .browse } else if current != nil { mode = .detail }
    }

    func escape() {
        if mode == .detail {
            mode = .browse
        } else if !query.isEmpty {
            searchField?.stringValue = ""
            setQuery("")
        }
    }

    func flip() {
        guard let f = full, f.row.hasBack else { return }
        face = face == 0 ? 1 : 0
    }

    func toggleText() {
        showText.toggle()
        UserDefaults.standard.set(showText, forKey: "showText")
    }

    func toggleLayout() {
        layout = layout == .list ? .grid : .list
        UserDefaults.standard.set(layout.rawValue, forKey: "layout")
        resultsVersion += 1
    }

    func focusSearch(selectAll: Bool = false) {
        guard let f = searchField, let w = f.window else { return }
        if w.firstResponder !== f.currentEditor() {
            w.makeFirstResponder(f)
        }
        if selectAll { f.currentEditor()?.selectAll(nil) }
    }

    // MARK: Prefetch

    private func schedulePrefetch() {
        prefetchTask?.cancel()
        let sel = selection
        let d = lastDelta
        let size: ImageSize = layout == .grid ? .small : .large
        prefetchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 40_000_000)
            guard !Task.isCancelled else { return }
            for off in [d, 2 * d, -d, 3 * d, 4 * d] {
                guard let r = row(at: sel + off), r.hasImage else { continue }
                ImageStore.shared.prefetch(scryID: r.scryID, face: 0, size: size)
            }
        }
    }

    // MARK: Image cache

    /// Downloads `small` images for every card (pinned, ~0.4 GB) and `normal` for the most popular
    /// few thousand, in the background at low priority. Resumable: files already on disk are skipped.
    func startWarming(after delay: Double = 0) {
        warmTask?.cancel()
        warmStatus = nil
        guard warmEnabled, let store else { return }
        let ids = store.imageIDs()
        let normalCount = min(3000, ids.count)
        let total = ids.count + normalCount
        warmTask = Task.detached(priority: .background) { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            var done = 0
            let chunk = 96
            for (size, list) in [(ImageSize.small, ids), (ImageSize.normal, Array(ids.prefix(normalCount)))] {
                var i = 0
                while i < list.count {
                    if Task.isCancelled { return }
                    if ProcessInfo.processInfo.isLowPowerModeEnabled {
                        await MainActor.run { self?.warmStatus = "Image caching paused (Low Power Mode)" }
                        try? await Task.sleep(nanoseconds: 30_000_000_000)
                        continue
                    }
                    let slice = list[i..<min(i + chunk, list.count)]
                    await withTaskGroup(of: Void.self) { g in
                        for id in slice { g.addTask { await ImageStore.shared.warmOne(scryID: id, size: size) } }
                    }
                    i += chunk
                    done += slice.count
                    let pct = Int(Double(done) / Double(total) * 100)
                    await MainActor.run { self?.warmStatus = "Caching images \(pct)%" }
                }
            }
            ImageStore.shared.pruneOrphans(keep: Set(ids))
            await MainActor.run { self?.warmStatus = nil }
        }
    }

    func setWarm(_ on: Bool) {
        warmEnabled = on
        UserDefaults.standard.set(on, forKey: "warmCache")
        if on { startWarming() } else { warmTask?.cancel(); warmStatus = nil }
    }

    func setCacheLimit(_ mb: Int) {
        cacheLimitMB = mb
        UserDefaults.standard.set(mb, forKey: "cacheLimitMB")
        ImageStore.shared.trimDisk()
    }

    // MARK: Clipboard & links

    func copyOrName() {
        if let tv = NSApp.keyWindow?.firstResponder as? NSTextView, tv.selectedRange().length > 0 {
            tv.copy(nil)
        } else {
            copyName()
        }
    }

    func copyName() {
        guard let c = current else { return }
        put(c.name)
        flash("Copied “\(c.name)”")
    }

    func copyDetails() {
        guard let f = full, let p = printing else { return }
        var lines: [String] = []
        for face in f.faces {
            lines.append(face.manaCost.isEmpty ? face.name : "\(face.name)  \(face.manaCost)")
            lines.append(face.typeLine)
            if !face.oracleText.isEmpty { lines.append(face.oracleText) }
            if let pt = face.powerToughness { lines.append(pt) }
            if let l = face.loyalty { lines.append("Loyalty: \(l)") }
            if let d = face.defense { lines.append("Defense: \(d)") }
            lines.append("")
        }
        lines.append("\(p.setName) (\(p.setCode.uppercased())) #\(p.collector) · \(Rarity.names[p.rarity].capitalized)")
        lines.append("Modern: \(f.status("modern").label)")
        if let usd = p.usd { lines.append("USD \(usd.usdString)") }
        if let url = scryfallURL { lines.append(url.absoluteString) }
        put(lines.joined(separator: "\n"))
        flash("Copied card details")
    }

    var scryfallURL: URL? {
        guard let p = printing else { return nil }
        var c = URLComponents()
        c.scheme = "https"
        c.host = "scryfall.com"
        c.path = "/card/\(p.setCode)/\(p.collector)"
        return c.url
    }

    func openScryfall() {
        if let u = scryfallURL { NSWorkspace.shared.open(u) }
    }

    private func put(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    func flash(_ s: String) {
        toast = s
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if !Task.isCancelled { toast = nil }
        }
    }
}

extension ISO8601DateFormatter {
    static let withFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
