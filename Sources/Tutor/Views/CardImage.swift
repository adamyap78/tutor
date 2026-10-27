import SwiftUI

final class ImageBox: ObservableObject {
    var key: String?
    var image: NSImage?
    func set(_ k: String, _ i: NSImage) {
        key = k
        image = i
        objectWillChange.send()
    }
    func refresh() { objectWillChange.send() }
}

struct CardImageView: View {
    let scryID: String
    let hasImage: Bool
    let face: Int
    let size: ImageSize
    let title: String
    let subtitle: String
    let text: String
    var shadow = true
    var textOverlay: CardFull? = nil

    @StateObject private var box = ImageBox()

    private var key: String { ImageStore.key(scryID, face, size) }

    private func current() -> NSImage? {
        if box.key == key, let img = box.image { return img }
        let store = ImageStore.shared
        if let m = store.memoryImage(key) { return m }
        // Show a smaller cached version while the sharp one loads.
        if size == .large {
            return store.memoryImage(ImageStore.key(scryID, face, .normal)) ?? store.memoryImage(ImageStore.key(scryID, face, .small))
        }
        return nil
    }

    var body: some View {
        GeometryReader { geo in
            let w = min(geo.size.width, geo.size.height * Style.cardAspect)
            let h = w / Style.cardAspect
            ZStack {
                if let img = current() {
                    Image(nsImage: img).resizable().interpolation(.high)
                } else {
                    CardPlaceholder(title: title, subtitle: subtitle, text: text, width: w)
                }
                if let full = textOverlay {
                    CardTextOverlay(full: full, face: face, width: w)
                }
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: w * 0.048, style: .continuous))
            .shadow(color: .black.opacity(shadow ? 0.28 : 0.12), radius: shadow ? 14 : 3, y: shadow ? 6 : 1)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .task(id: key) {
            guard hasImage else { return }
            let store = ImageStore.shared
            if let hit = store.memoryImage(key) {
                // Landed in the cache (e.g. prefetch) after this view first rendered.
                box.set(key, hit)
                return
            }
            if size == .large {
                // Paint something sharp-ish immediately while the large image loads.
                Task {
                    let hit = await store.load(scryID: scryID, face: face, size: .normal, network: false)
                    if hit == nil { _ = await store.load(scryID: scryID, face: face, size: .small) }
                    box.refresh()
                }
            }
            let delays: [Double] = [0.4, 1.5, 4, 10]
            for attempt in 0...delays.count {
                if let img = await store.load(scryID: scryID, face: face, size: size, debounceMs: size == .small ? 50 : 0) {
                    box.set(key, img)
                    return
                }
                if Task.isCancelled || attempt == delays.count { return }
                try? await Task.sleep(nanoseconds: UInt64(delays[attempt] * 1_000_000_000))
            }
        }
    }
}

/// Shown instantly from local data while (or if) the artwork is unavailable.
struct CardPlaceholder: View {
    let title: String
    let subtitle: String
    let text: String
    let width: CGFloat

    var body: some View {
        let s = width / 300
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: width * 0.048, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
            RoundedRectangle(cornerRadius: width * 0.048, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
            VStack(alignment: .leading, spacing: 6 * s) {
                Text(title).font(.system(size: max(9, 17 * s), weight: .semibold)).lineLimit(3)
                if width > 150 {
                    Text(subtitle).font(.system(size: 12 * s)).foregroundStyle(.secondary).lineLimit(2)
                    if !text.isEmpty {
                        Text(text).font(.system(size: 11.5 * s)).foregroundStyle(.secondary).lineLimit(9)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(width * 0.07)
        }
    }
}
