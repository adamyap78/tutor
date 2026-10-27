import Foundation

/// Monotonic counter safe to bump from any thread; all state is guarded by `lock`.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var v = 0
    func next() -> Int { lock.lock(); defer { lock.unlock() }; v += 1; return v }
    var value: Int { lock.lock(); defer { lock.unlock() }; return v }
}

/// Rate limiter for progress callbacks that arrive on background threads; all state is guarded by `lock`.
final class Throttle: @unchecked Sendable {
    private let lock = NSLock()
    private var last = Date.distantPast
    private let minInterval: TimeInterval = 0.08
    func ready(force: Bool) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        if force || now.timeIntervalSince(last) > minInterval { last = now; return true }
        return false
    }
}
