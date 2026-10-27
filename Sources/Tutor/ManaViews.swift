import SwiftUI

// Native rendering of mana symbols — no network or bundled assets.

enum ManaToken: Hashable {
    case symbol(String)
    case text(String)
}

enum ManaParser {
    static func tokens(_ s: String) -> [ManaToken] {
        var out: [ManaToken] = []
        var buf = ""
        var i = s.startIndex
        while i < s.endIndex {
            let ch = s[i]
            if ch == "{", let close = s[i...].firstIndex(of: "}") {
                if !buf.isEmpty { out.append(.text(buf)); buf = "" }
                let sym = String(s[s.index(after: i)..<close])
                out.append(.symbol(sym))
                i = s.index(after: close)
            } else {
                buf.append(ch)
                i = s.index(after: i)
            }
        }
        if !buf.isEmpty { out.append(.text(buf)) }
        return out
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

struct ManaSymbolView: View {
    let symbol: String
    let size: CGFloat

    private static let colors: [String: UInt32] = [
        "W": 0xF8F4DA, "U": 0x5AA9E6, "B": 0x6B5B63, "R": 0xE5604A, "G": 0x3FA06A, "C": 0xCFCBC7, "S": 0xBFE3F0,
    ]

    private var parts: [String] { symbol.split(separator: "/").map(String.init) }

    private func color(_ p: String) -> Color? {
        Self.colors[p].map(Color.init(hex:))
    }

    private var fill: AnyShapeStyle {
        let ps = parts
        let cs = ps.compactMap { $0 == "P" ? nil : color($0) }
        if cs.count >= 2 {
            return AnyShapeStyle(LinearGradient(stops: [
                .init(color: cs[0], location: 0), .init(color: cs[0], location: 0.48),
                .init(color: cs[1], location: 0.52), .init(color: cs[1], location: 1),
            ], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        if let c = cs.first { return AnyShapeStyle(c) }
        switch symbol {
        case "T", "Q": return AnyShapeStyle(Color(hex: 0x2B2B2E))
        case "E": return AnyShapeStyle(Color(hex: 0xE8C547))
        default: return AnyShapeStyle(Color(hex: 0xCFCBC7))
        }
    }

    private var label: String {
        let ps = parts
        switch symbol {
        case "T": return "↷"
        case "Q": return "↶"
        case "E": return "⚡︎"
        case "S": return "❄︎"
        case "CHAOS": return "?"
        default: break
        }
        if ps.count == 1 { return ps[0] }
        if ps.last == "P" { return "Φ" }
        if ps.first.map({ Int($0) != nil }) == true { return ps[0] }   // {2/W}
        return ""
    }

    private var labelColor: Color {
        switch symbol {
        case "T", "Q": return .white
        case "B": return .white
        default: return Color.black.opacity(0.78)
        }
    }

    var body: some View {
        ZStack {
            Circle().fill(fill)
            Circle().strokeBorder(Color.black.opacity(0.28), lineWidth: max(0.5, size / 28))
            let l = label
            if !l.isEmpty {
                Text(l)
                    .font(.system(size: size * (l.count > 1 ? 0.46 : 0.62), weight: .bold, design: .rounded))
                    .foregroundStyle(labelColor)
                    .minimumScaleFactor(0.5)
            }
        }
        .frame(width: size, height: size)
    }
}

/// A row of mana symbols, e.g. "{2}{R}{R}" or "{1}{R} // {1}{W}".
struct ManaCostView: View {
    let cost: String
    var size: CGFloat = 14

    var body: some View {
        HStack(spacing: size * 0.1) {
            ForEach(Array(ManaParser.tokens(cost).enumerated()), id: \.offset) { _, t in
                switch t {
                case .symbol(let s): ManaSymbolView(symbol: s, size: size)
                case .text(let s): Text(s).font(.system(size: size * 0.8)).foregroundStyle(.secondary)
                }
            }
        }
    }
}

@MainActor
enum SymbolImages {
    private static var cache: [String: Image] = [:]

    static func image(_ symbol: String, size: CGFloat) -> Image {
        let key = "\(symbol)@\(size)"
        if let i = cache[key] { return i }
        let r = ImageRenderer(content: ManaSymbolView(symbol: symbol, size: size))
        r.scale = 3
        let img = r.nsImage.map { Image(nsImage: $0) } ?? Image(systemName: "circle")
        cache[key] = img
        return img
    }
}

/// Oracle text with inline mana symbols and italic reminder text.
struct OracleText: View {
    let text: String
    var size: CGFloat = 13

    var body: some View {
        VStack(alignment: .leading, spacing: size * 0.5) {
            ForEach(Array(text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, line in
                if String(line) == "//" {
                    Divider().padding(.vertical, 2)
                } else {
                    Self.line(String(line), size: size).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    static func line(_ s: String, size: CGFloat) -> Text {
        var result = Text("")
        var italic = false
        for tok in ManaParser.tokens(s) {
            switch tok {
            case .symbol(let sym):
                result = result + Text(SymbolImages.image(sym, size: size * 1.05)).baselineOffset(-size * 0.14)
            case .text(let t):
                // Toggle italics across parentheses (reminder text).
                var chunk = ""
                func flush() {
                    guard !chunk.isEmpty else { return }
                    var seg = Text(chunk).font(.system(size: size))
                    if italic { seg = seg.italic().foregroundColor(.secondary) }
                    result = result + seg
                    chunk = ""
                }
                for ch in t {
                    if ch == "(" { flush(); italic = true; chunk.append(ch) }
                    else if ch == ")" { chunk.append(ch); flush(); italic = false }
                    else { chunk.append(ch) }
                }
                flush()
            }
        }
        return result
    }
}
