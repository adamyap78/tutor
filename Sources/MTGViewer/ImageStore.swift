import AppKit
import ImageIO

enum ImageSize: String {
    case small, normal, large
}

private actor Limiter {
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(_ n: Int) { available = n }
    func acquire() async {
        if available > 0 { available -= 1 } else { await withCheckedContinuation { waiters.append($0) } }
    }
    func release() {
        if waiters.isEmpty { available += 1 } else { waiters.removeFirst().resume() }
    }
}

private actor Inflight {
    private var tasks: [String: Task<Data?, Never>] = [:]
    func task(_ key: String, make: @escaping @Sendable () async -> Data?) -> Task<Data?, Never> {
        if let t = tasks[key] { return t }
        let t = Task { [weak self] () -> Data? in
            let d = await make()
            await self?.finish(key)
            return d
        }
        tasks[key] = t
        return t
    }
    private func finish(_ key: String) { tasks[key] = nil }
}

/// Memory + on-disk cache for card images. Images are fetched lazily from Scryfall's CDN
/// (no rate limit) and never block search or navigation.
final class ImageStore: @unchecked Sendable {
    static let shared = ImageStore()

    enum Priority { case visible, background }

    /// Ceiling for the on-demand (evictable) cache; least-recently-used files go first.
    /// The pinned tier (all `small` images + popular `normal` ones) is never evicted.
    var diskLimit: Int64 {
        let mb = UserDefaults.standard.integer(forKey: "cacheLimitMB")
        return Int64(mb > 0 ? mb : 2048) * 1024 * 1024
    }

    private let mem = NSCache<NSString, NSImage>()
    private let root: URL
    private let pinnedRoot: URL
    private let session: URLSession
    private let fgLimiter = Limiter(6)
    private let bgLimiter = Limiter(12)
    private let inflight = Inflight()
    private let lock = NSLock()
    private var failures: [String: Date] = [:]
    private var writesSinceTrim = 0

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        root = caches.appendingPathComponent("MTGViewer/images", isDirectory: true)
        pinnedRoot = caches.appendingPathComponent("MTGViewer/pinned", isDirectory: true)
        let cfg = URLSessionConfiguration.default
        cfg.urlCache = nil
        cfg.timeoutIntervalForRequest = 20
        cfg.httpMaximumConnectionsPerHost = 18
        cfg.httpAdditionalHeaders = ["User-Agent": Importer.userAgent, "Accept": "image/jpeg,image/*;q=0.8"]
        session = URLSession(configuration: cfg)
        mem.totalCostLimit = 400 * 1024 * 1024
        mem.countLimit = 800
    }

    static func key(_ scryID: String, _ face: Int, _ size: ImageSize) -> String {
        "\(size.rawValue)/\(face)/\(scryID)"
    }

    func memoryImage(_ key: String) -> NSImage? { mem.object(forKey: key as NSString) }

    private func fileURL(_ scryID: String, _ face: Int, _ size: ImageSize, pinned: Bool) -> URL {
        let shard = String(scryID.prefix(2))
        return (pinned ? pinnedRoot : root).appendingPathComponent("\(size.rawValue)/\(shard)/\(scryID)-\(face).jpg")
    }

    private func existingFile(_ scryID: String, _ face: Int, _ size: ImageSize) -> URL? {
        let fm = FileManager.default
        for pinned in [true, false] {
            let u = fileURL(scryID, face, size, pinned: pinned)
            if fm.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    private func remoteURL(_ scryID: String, _ face: Int, _ size: ImageSize) -> URL? {
        guard scryID.count >= 2 else { return nil }
        let a = scryID[scryID.startIndex], b = scryID[scryID.index(after: scryID.startIndex)]
        return URL(string: "https://cards.scryfall.io/\(size.rawValue)/\(face == 0 ? "front" : "back")/\(a)/\(b)/\(scryID).jpg")
    }

    static func decode(_ data: Data) -> NSImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    private func remember(_ img: NSImage, _ key: String) {
        let cost = Int(img.size.width * img.size.height * 4)
        mem.setObject(img, forKey: key as NSString, cost: cost)
    }

    /// Loads from memory, then disk, then network. `debounceMs` lets scrolling grids skip
    /// downloads for cells that were only passed over; the selected card uses 0.
    func load(scryID: String, face: Int, size: ImageSize, network: Bool = true,
              priority: Priority = .visible, debounceMs: UInt64 = 0) async -> NSImage? {
        let key = Self.key(scryID, face, size)
        if let hit = memoryImage(key) { return hit }

        if let url = existingFile(scryID, face, size),
           let data = try? Data(contentsOf: url, options: .mappedIfSafe), let img = Self.decode(data) {
            remember(img, key)
            touch(url)
            return img
        }
        guard network else { return nil }

        if debounceMs > 0 {
            try? await Task.sleep(nanoseconds: debounceMs * 1_000_000)
            if Task.isCancelled { return nil }
        }
        if recentlyFailed(key) { return nil }

        let data = await inflight.task(key) { [self] in
            await download(scryID: scryID, face: face, size: size, key: key, priority: priority, pinned: size == .small)
        }.value
        guard let data, let img = Self.decode(data) else { return nil }
        remember(img, key)
        return img
    }

    func prefetch(scryID: String, face: Int, size: ImageSize) {
        Task.detached(priority: .utility) { [self] in
            _ = await load(scryID: scryID, face: face, size: size, priority: .background)
        }
    }

    /// Downloads straight to the pinned tier without decoding. Returns false when paused/cancelled.
    func warmOne(scryID: String, size: ImageSize) async {
        let k = Self.key(scryID, 0, size)
        if FileManager.default.fileExists(atPath: fileURL(scryID, 0, size, pinned: true).path) { return }
        if existingFile(scryID, 0, size) != nil { return }
        _ = await inflight.task(k) { [self] in
            await download(scryID: scryID, face: 0, size: size, key: k, priority: .background, pinned: true)
        }.value
    }

    private func download(scryID: String, face: Int, size: ImageSize, key: String,
                          priority: Priority, pinned: Bool) async -> Data? {
        guard let remote = remoteURL(scryID, face, size) else { return nil }
        let limiter = priority == .visible ? fgLimiter : bgLimiter
        await limiter.acquire()
        defer { Task { await limiter.release() } }
        do {
            let (data, resp) = try await session.data(from: remote)
            guard (resp as? HTTPURLResponse)?.statusCode == 200, data.count > 1000 else {
                markFailed(key)
                return nil
            }
            let url = fileURL(scryID, face, size, pinned: pinned)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
            if !pinned { noteWrite() }
            return data
        } catch {
            markFailed(key)
            return nil
        }
    }

    /// Removes pinned images for printings that are no longer any card's preview (after a data update).
    func pruneOrphans(keep: Set<String>) {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: pinnedRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return }
        for case let url as URL in en where url.pathExtension == "jpg" {
            let id = String(url.deletingPathExtension().lastPathComponent.dropLast(2))   // strip "-<face>"
            if !keep.contains(id) { try? fm.removeItem(at: url) }
        }
    }

    // MARK: Failure backoff

    private func recentlyFailed(_ key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if let t = failures[key], Date().timeIntervalSince(t) < 3 { return true }
        return false
    }

    private func markFailed(_ key: String) {
        lock.lock(); failures[key] = Date(); lock.unlock()
    }

    // MARK: Disk housekeeping

    private func touch(_ url: URL) {
        let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        if let d = vals?.contentModificationDate, Date().timeIntervalSince(d) < 6 * 3600 { return }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }

    private func noteWrite() {
        lock.lock()
        writesSinceTrim += 1
        let due = writesSinceTrim >= 300
        if due { writesSinceTrim = 0 }
        lock.unlock()
        if due { trimDisk() }
    }

    /// Evicts least-recently-used images until the cache is under 90 % of the limit.
    func trimDisk() {
        let limit = diskLimit
        DispatchQueue.global(qos: .background).async { [root] in
            let fm = FileManager.default
            guard let en = fm.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                                         options: [.skipsHiddenFiles]) else { return }
            var files: [(URL, Int64, Date)] = []
            var total: Int64 = 0
            for case let url as URL in en {
                guard let v = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { continue }
                let size = Int64(v.fileSize ?? 0)
                total += size
                files.append((url, size, v.contentModificationDate ?? .distantPast))
            }
            guard total > limit else { return }
            files.sort { $0.2 < $1.2 }
            let target = Int64(Double(limit) * 0.9)
            for f in files where total > target {
                try? fm.removeItem(at: f.0)
                total -= f.1
            }
        }
    }
}
